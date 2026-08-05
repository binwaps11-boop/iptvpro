package com.binwaps.cardmanager.mikrotik

import com.binwaps.cardmanager.model.ActiveUser
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.HotspotProfile
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.model.RouterStatus
import com.binwaps.cardmanager.model.SessionEntry
import com.binwaps.cardmanager.model.UploadTarget
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import me.legrange.mikrotik.ApiConnection

/**
 * عميل RouterOS API — يدعم الهوتسبوت واليوزر منجر (v6 و v7)،
 * الجلسات النشطة وسجلها، الباقات، والكروت المنتهية.
 */
object MikrotikClient {

    // ===== الاتصال =====

    private fun open(r: RouterProfile): ApiConnection = openWith(r, r.useSsl)

    // مهلة **الأوامر** (نقل النتائج) مستقلة عن مهلة **الاتصال** (فتح المقبس).
    // كانت مربوطة بمهلة الاتصال (١٢ث افتراضاً) عبر setTimeout، فجلب قائمة كبيرة
    // (كل الكروت/الباقات) يرمي «Command timed out» على راوتر فيه آلاف الكروت عن
    // بُعد — وهو السبب الجذري لـ«لا بيانات/تعليق» بالكميات الكبيرة. الآن مهلة
    // سخيّة، وتُضبط لكل عملية في onRouter (أطول للأمامية، أقصر للخلفية).
    private const val CMD_TIMEOUT_DEFAULT_MS = 60_000
    private const val CMD_TIMEOUT_FG_MS = 90_000   // عملية المستخدم: تُكمل نقل القوائم الكبيرة
    private const val CMD_TIMEOUT_BG_MS = 30_000    // مزامنة خلفية: تفشل بسرعة وتفسح القفل

    private fun openWith(r: RouterProfile, ssl: Boolean): ApiConnection {
        val timeoutMs = (r.timeoutSec.coerceIn(3, 120)) * 1000
        val factory = if (ssl) trustAllSocketFactory() else javax.net.SocketFactory.getDefault()
        val con = ApiConnection.connect(factory, r.host.trim(), r.port, timeoutMs)
        // فشل الدخول بعد نجاح فتح المقبس كان يترك المقبس وخيوط المكتبة مفتوحة —
        // ومع تجربة النوع الخاطئ عمداً صار ذلك مساراً معتاداً لا حالة نادرة
        try {
            con.setTimeout(CMD_TIMEOUT_DEFAULT_MS)
            con.login(r.username, r.password)
        } catch (e: Throwable) {
            runCatching { con.close() }
            throw e
        }
        return con
    }

    /**
     * فحص وصول خام: هل المنفذ مفتوح أصلاً؟ يفصل «العنوان/المنفذ مغلق» عن
     * «مفتوح لكن نوع التشفير خاطئ» — بدل رسالة مهلة عامة لا تدل على شيء.
     */
    private fun portReachable(host: String, port: Int, timeoutMs: Int): Boolean = runCatching {
        // فحص خفيف بمهلة قصيرة: ميزانية الاتصال الكلية يجب ألا تُستهلك هنا
        val probeMs = timeoutMs.coerceAtMost(5000)
        java.net.Socket().use { s ->
            s.connect(java.net.InetSocketAddress(host.trim(), port), probeMs)
            true
        }
    }.getOrDefault(false)

    /**
     * راوترات مايكروتك تستخدم شهادة موقّعة ذاتياً افتراضياً، فلا يمكن التحقق منها
     * عبر سلسلة ثقة عامة. نقبلها لأن الاتصال موجّه لعنوان يحدده المستخدم بنفسه.
     */
    private fun trustAllSocketFactory(): javax.net.SocketFactory {
        val trustAll = arrayOf<javax.net.ssl.TrustManager>(object : javax.net.ssl.X509TrustManager {
            override fun checkClientTrusted(chain: Array<java.security.cert.X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<java.security.cert.X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = arrayOf()
        })
        val ctx = javax.net.ssl.SSLContext.getInstance("TLS")
        ctx.init(null, trustAll, java.security.SecureRandom())
        return ctx.socketFactory
    }

    // ===== جلسة دائمة =====
    //
    // فتح اتصال جديد لكل عملية (TCP + دخول) كان يكلف ثواني عن بعد وفي كل
    // تحديث دوري. نُبقي جلسة واحدة حية ونعيد استخدامها، وإن ماتت نعيد فتحها
    // تلقائياً ونكرر العملية مرة واحدة — المستخدم لا يرى إلا السرعة.

    @Volatile private var session: ApiConnection? = null
    @Volatile private var sessionKey: String? = null
    // إصدار اليوزر منجر مكتشفاً مرة واحدة لكل جلسة — كان يُكتشف بجولة شبكة في
    // ٦ مواضع كل مرة، وبطريقة غير متسقة (موضع كان ينقل القائمة كاملة). يُصفّر
    // حرفياً مع sessionKey فيرتبط بالجلسة نفسها؛ راوتر جديد ⇒ كشف جديد.
    @Volatile private var umVariant: UmVariant? = null
    private val sessionLock = Mutex()

    // عدّاد العمليات الأمامية (رفع/توليد بضغطة المستخدم). المزامنة الدورية
    // تتنحّى عن القفل ما دام أكبر من صفر، فلا يقف رفع المستخدم في طابور خلف
    // دورة مزامنة تجلب كل الكروت — كان هذا سبب بقاء الشريط على «0 من N».
    private val foregroundOps = java.util.concurrent.atomic.AtomicInteger(0)

    /** هل هناك عملية أمامية جارية؟ تفحصها المزامنة لتتنحّى عن القفل */
    fun foregroundActive(): Boolean = foregroundOps.get() > 0

    // بصمة كلمة المرور ضمن المفتاح — تغييرها يجب أن يفتح جلسة جديدة لا يعاد
    // استخدام جلسة قديمة سجّلت بكلمة سابقة فيبدو الاتصال ناجحاً زوراً
    private fun keyOf(r: RouterProfile) =
        "${r.host.trim()}:${r.port}:${r.username}:${r.useSsl}:${r.password.hashCode()}"

    private fun obtain(r: RouterProfile): ApiConnection {
        val k = keyOf(r)
        session?.let { if (sessionKey == k && it.isConnected) return it }
        runCatching { session?.close() }
        return open(r).also { session = it; sessionKey = k }
    }

    private fun invalidateSession() {
        runCatching { session?.close() }
        session = null
        sessionKey = null
        umVariant = null
    }

    /**
     * فشل منطقي (رفض من الراوتر أو نتيجة فارغة) — الجلسة سليمة، ولا يجوز
     * أن تُعيد onRouter تنفيذ العملية كاملة بسببه.
     */
    internal class RouterLogicException(message: String, cause: Throwable? = null) :
        Exception(message, cause)

    /** خطأ أمرٍ ردّه الراوتر (trap) — الجلسة سليمة ولا معنى لإعادة الاتصال */
    private fun isCommandError(t: Throwable): Boolean {
        var c: Throwable? = t
        while (c != null) {
            if (c is RouterLogicException) return true
            if (c.javaClass.name.endsWith("ApiCommandException")) return true
            c = c.cause
        }
        return false
    }

    /**
     * ينفّذ عملية على الراوتر عبر الجلسة الدائمة ويحوّل الأخطاء إلى رسائل عربية.
     * القفل يمنع تداخل الكتابة على نفس المقبس من شاشتين في آن واحد.
     */
    internal suspend fun <T> onRouter(
        r: RouterProfile?,
        // عملية بدأها المستخدم (رفع/توليد/جلب بضغطة): تُعلِّم نفسها أمامية فور
        // استدعائها — قبل انتظار القفل — فتتنحّى المزامنة الدورية وتفسح القفل
        foreground: Boolean = false,
        block: (ApiConnection) -> T,
    ): Result<T> =
        withContext(Dispatchers.IO) {
            if (r == null) return@withContext Result.failure(Exception("لا يوجد راوتر محفوظ — اتصل أولاً"))
            if (foreground) foregroundOps.incrementAndGet()
            try {
                runCatching {
                    // اكتساب القفل بسقف زمني بدل انتظار لا نهائي: دورة المزامنة قد
                    // تحتجز القفل وهي تجلب كل الكروت على راوتر كبير أو بعيد، فيبقى
                    // «جاري الجلب» عالقاً بلا نهاية عند المستخدم. نمنح مهلة معقولة
                    // (أطول للعمليات الأمامية) ثم نرمي خطأً عربياً مفهوماً. لا نلمس
                    // المقبس أبداً قبل امتلاك القفل، فلا خطر تداخل على الجلسة.
                    // ميزانية اكتساب القفل: الأمامية تفوق أقصى زمن يحبس فيه القفل
                    // في الخلفية (CMD_TIMEOUT_BG_MS=30ث) فلا يفشل رفع المستخدم زوراً
                    // بـ«الراوتر مشغول» بينما مزامنة خلفية تجلب.
                    val acquireBudgetMs = if (foreground) 45_000L else 15_000L
                    if (!acquireSessionWithin(acquireBudgetMs)) {
                        throw RouterLogicException(
                            "الراوتر مشغول بعملية أخرى (مزامنة أو رفع) — أعد المحاولة بعد ثوانٍ",
                        )
                    }
                    // مهلة الأمر حسب نوع العملية: عملية المستخدم تأخذ ٩٠ث لتُكمل نقل
                    // القوائم الكبيرة، والخلفية ٣٠ث لتفشل بسرعة وتفسح القفل فوراً
                    val cmdTimeout = if (foreground) CMD_TIMEOUT_FG_MS else CMD_TIMEOUT_BG_MS
                    try {
                        try {
                            block(obtain(r).also { runCatching { it.setTimeout(cmdTimeout) } })
                        } catch (e: Exception) {
                            if (isCommandError(e)) throw e
                            // الجلسة القديمة ماتت غالباً — اتصال جديد ومحاولة أخيرة
                            invalidateSession()
                            block(obtain(r).also { runCatching { it.setTimeout(cmdTimeout) } })
                        }
                    } finally {
                        sessionLock.unlock()
                    }
                }.recoverCatching { throw Exception(arabicError(it), it) }
            } finally {
                if (foreground) foregroundOps.decrementAndGet()
            }
        }

    /**
     * يحاول امتلاك قفل الجلسة خلال ميزانية زمنية. يعود true إن نجح (وعندها على
     * المستدعي فكّه)، أو false إن نفدت المهلة والقفل ما زال مشغولاً. آمن تماماً:
     * لا يمسّ الجلسة إلا بعد الامتلاك.
     */
    private suspend fun acquireSessionWithin(budgetMs: Long): Boolean {
        if (sessionLock.tryLock()) return true
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < budgetMs) {
            delay(150)
            if (sessionLock.tryLock()) return true
        }
        return false
    }

    private val clientScope =
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)

    /**
     * يغلق الجلسة الدائمة — عند تغيير الراوتر أو قطع الاتصال يدوياً.
     * الإغلاق تحت القفل نفسه حتى لا يسحب المقبس من تحت عملية جارية.
     */
    fun disconnect() {
        clientScope.launch {
            // القفل إن توفّر فوراً؛ وإلا نُسقط المرجع بلا انتظار — عملية عالقة
            // قد تحتجز القفل دقيقة كاملة، ولا يصح أن يتعطّل القطع بسببها
            if (sessionLock.tryLock()) {
                try { invalidateSession() } finally { sessionLock.unlock() }
            } else {
                val old = session
                session = null
                sessionKey = null
                umVariant = null
                runCatching { old?.close() }
            }
        }
    }

    private fun arabicError(t: Throwable): String {
        val raw = (t.message ?: t.toString())
        return when {
            raw.contains("timed out", true) || raw.contains("timeout", true) ->
                "انتهت مهلة الاتصال — تأكد من العنوان والمنفذ، أو زد المهلة من شاشة الاتصال"
            raw.contains("ECONNREFUSED", true) || raw.contains("refused", true) ->
                "الراوتر رفض الاتصال — تأكد أن خدمة API مفعّلة: IP → Services → api"
            raw.contains("UnknownHost", true) || raw.contains("Unable to resolve", true) ->
                "تعذّر العثور على العنوان — تحقق من الدومين أو الـ IP"
            raw.contains("cannot log in", true) || raw.contains("invalid user", true) ||
                raw.contains("password", true) ->
                "اسم المستخدم أو كلمة المرور غير صحيحة"
            raw.contains("not enough permissions", true) || raw.contains("policy", true) ->
                "هذا المستخدم لا يملك صلاحية — أعطه صلاحيات api و read و write على الراوتر"
            raw.contains("no such command", true) || raw.contains("unknown command", true) ->
                "هذا الأمر غير موجود على الراوتر — قد تكون حزمة اليوزر منجر غير مثبّتة"
            raw.contains("SSL", true) || raw.contains("handshake", true) ->
                "فشل الاتصال المشفّر — جرّب إيقاف api-ssl أو تأكد من المنفذ 8729"
            else -> raw
        }
    }

    /**
     * يلفّ القيمة بعلامتي تنصيص — محلّل المكتبة يقطع القيمة عند المسافة أو
     * الرموز (= ! < > ،) إن لم تكن مقتبسة، فباقة اسمها "شهري 10 جيجا" كانت
     * تتحول إلى ثلاث كلمات يرفضها الراوتر. القيمة الفارغة تخرج "" فتُقبل.
     */
    internal fun q(v: String): String {
        val clean = v.replace('\n', ' ').replace('\r', ' ')
        return when {
            !clean.contains('"') -> "\"$clean\""
            !clean.contains('\'') -> "'$clean'"
            // لا يمكن تمثيل قيمة فيها النوعان معاً — نحذف المزدوجة
            else -> "\"${clean.replace("\"", "")}\""
        }
    }

    // ===== كشف إصدار اليوزر منجر (موحّد ومخزّن) =====

    /**
     * v7 على المسار `/user-manager`، v6 على `/tool/user-manager`، وNONE إن لم
     * تُثبّت الحزمة. الكشف مرة واحدة لكل جلسة (`umVariant`)، وكل الأوامر تبني
     * مسارها عبر [umPath] فلا تكرار ولا تناقض بين المواضع.
     */
    internal enum class UmVariant { V7, V6, NONE }

    /** جذر مسار جدول يوزر منجر حسب الإصدار — دالة نقية قابلة للاختبار */
    internal fun umPath(v: UmVariant, table: String): String {
        val base = when (v) {
            UmVariant.V7 -> "/user-manager"
            // NONE نادر (الحزمة غير مثبّتة) — نبني مسار v6 ليعطي خطأ «لا أمر»
            // مفهوماً بدل مسارٍ فارغ
            else -> "/tool/user-manager"
        }
        return "$base/$table"
    }

    /**
     * يكتشف الإصدار مرة واحدة ويخزّنه للجلسة. **count-only دائماً** (لا ينقل
     * القائمة كاملة). يجرّب v7 ثم v6؛ إن فشلا فالحزمة غير مثبّتة (NONE).
     */
    private fun userManagerVariant(con: ApiConnection): UmVariant {
        // لا نُخزّن NONE: فشل الكشف قد يكون عابراً (الراوتر مشغول لحظتها)، وتخزينه
        // كان يخفي كل كروت اليوزر منجر طوال الجلسة على راوتر v7 حقيقي. نخزّن
        // V6/V7 فقط ونعيد الكشف في الاستدعاء التالي طالما لم يُثبَّت إصدار.
        umVariant?.let { if (it != UmVariant.NONE) return it }
        val detected = when {
            runCatching { con.execute("/user-manager/user/print count-only") }.isSuccess -> UmVariant.V7
            runCatching { con.execute("/tool/user-manager/user/print count-only") }.isSuccess -> UmVariant.V6
            else -> UmVariant.NONE
        }
        if (detected != UmVariant.NONE) umVariant = detected
        return detected
    }

    /**
     * تنفيذ متدفق: يرسل كل الأوامر دفعة واحدة على نفس الاتصال ويجمع الردود
     * وهي تتقاطر — بدل انتظار ردٍّ لكل أمر قبل إرسال التالي.
     * عن بُعد (دومين/كلاود) هذا الفرق بين دقائق وثوانٍ للدفعات الكبيرة.
     */
    internal fun ApiConnection.pipeline(
        cmds: List<String>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onDone: (index: Int, success: Boolean) -> Unit = { _, _ -> },
        /**
         * أخطاء تُعد نجاحاً — «already have user» عند إعادة رفع دفعة انقطعت
         * يعني أن الكرت موجود فعلاً: إعادة التشغيل متكررة النتيجة بلا تكرار كروت
         */
        treatErrorAsOk: (String) -> Boolean = { false },
        /**
         * عدد الأوامر المعلّقة في وقت واحد. الهوتسبوت خفيف فيتحمّل نافذة واسعة،
         * أما يوزر منجر v6 فكل إضافة فيه تكتب في قاعدة بياناته — نافذة واسعة
         * تخنقه فيتوقف عن الرد وتتجمّد الدفعة.
         */
        window: Int = 128,
    ): BulkResult {
        if (cmds.isEmpty()) return BulkResult(0, 0)
        firstPipelineError.set(null)
        val total = cmds.size
        val succeeded = java.util.concurrent.atomic.AtomicInteger(0)
        val progressed = java.util.concurrent.atomic.AtomicInteger(0)

        // جولات: الدفعة كاملة، ثم إعادة صامتة لما فشل فقط — «صفر أخطاء» عملياً
        // دون أن يرى المستخدم فشلاً عابراً أو يعيد شيئاً بنفسه
        val retries = 2
        var pending: List<Int> = cmds.indices.toList()
        var round = 0
        while (pending.isNotEmpty() && round <= retries) {
            val lastRound = round == retries
            val failedNow = java.util.Collections.synchronizedList(mutableListOf<Int>())
            val latch = java.util.concurrent.CountDownLatch(pending.size)
            // نافذة تُبقي الأنبوب ممتلئاً فوق زمن الذهاب والإياب —
            // أساس هدف «آلاف الكروت في أقل من دقيقة» حتى على دومين بعيد
            val inFlight = java.util.concurrent.Semaphore(window.coerceIn(1, 256))
            // يُغلق عند انقضاء مهلة الجولة — أي ردّ متأخر بعده يُتجاهل تماماً
            // فلا يعدّل عدّادات جولةٍ تالية ولا يستدعي onDone خارج مسار الاكتمال
            val roundClosed = java.util.concurrent.atomic.AtomicBoolean(false)

            // الأوامر التي لم تُرسَل لأن الراوتر توقف عن الرد — تُحسب فاشلة
            val notSent = mutableListOf<Int>()
            var stalled = false
            // الفهارس التي وصلت نتيجتها فعلاً — ما ليس فيها لم يأتِه ردّ
            val reported = java.util.concurrent.ConcurrentHashMap.newKeySet<Int>()
            // إجهاض مبكر: إن فشلت أوامر الجولة الأولى بنفس الخطأ ولم ينجح أيٌّ
            // منها، فالخطأ منهجي (صيغة أمر خاطئة، عميل يوزر منجر غير موجود، حزمة
            // غير مثبّتة) لا عابر — نوقف فوراً ونُظهر السبب، بدل إبقاء الشريط على
            // صفر عبر ثلاث جولات صامتة فيبدو التطبيق متجمّداً (شكوى المستخدم)
            val firstRound = round == 0
            val earlyAbort = java.util.concurrent.atomic.AtomicBoolean(false)
            val systematicFails = java.util.concurrent.atomic.AtomicInteger(0)
            val earlyAbortAt = minOf(pending.size, maxOf(8, window))
            for (index in pending) {
                if (stalled || earlyAbort.get()) { notSent.add(index); continue }
                // مهلة على انتظار مكان في النافذة: acquire() بلا مهلة كان يتجمّد
                // للأبد إن توقف الراوتر عن الرد بعد امتلاء النافذة. وقبل أن ينجح
                // أي أمر لم يُثبت الأنبوب أنه يعمل، فنُقصّر المهلة إلى ٣٠ث ليظهر
                // التجمّد بسرعة بدل ٩٠ث من شريط فارغ؛ وبعد أول نجاح نُطيلها
                val ackTimeout = if (succeeded.get() == 0 && reported.isEmpty()) 30L else 90L
                if (!inFlight.tryAcquire(ackTimeout, java.util.concurrent.TimeUnit.SECONDS)) {
                    stalled = true
                    notSent.add(index)
                    if (firstPipelineError.get() == null) {
                        firstPipelineError.set(
                            Exception("الراوتر لا يستجيب لأوامر الرفع — قد يكون محمّلاً أو الاتصال ضعيفاً")
                        )
                    }
                    continue
                }
                val listener = object : me.legrange.mikrotik.ResultListener {
                    private val finished = java.util.concurrent.atomic.AtomicBoolean(false)
                    private fun finish(success: Boolean) {
                        if (!finished.compareAndSet(false, true)) return
                        if (roundClosed.get()) { inFlight.release(); return }
                        reported.add(index)
                        if (success) {
                            succeeded.incrementAndGet()
                            onDone(index, true)
                            onProgress(progressed.incrementAndGet().coerceAtMost(total), total)
                        } else {
                            failedNow.add(index)
                            if (lastRound) {
                                onDone(index, false)
                                onProgress(progressed.incrementAndGet().coerceAtMost(total), total)
                            }
                        }
                        inFlight.release()
                        latch.countDown()
                    }
                    override fun receive(result: Map<String, String>) {}
                    override fun error(ex: me.legrange.mikrotik.MikrotikApiException) {
                        if (treatErrorAsOk(ex.message ?: "")) {
                            finish(true)
                            return
                        }
                        if (firstPipelineError.get() == null) firstPipelineError.set(ex)
                        // فشل منهجي في الجولة الأولى: نفس رسالة الخطأ، وبلا أي نجاح.
                        // بلوغ العتبة يوقف بقية الدفعة فوراً ويُظهر السبب خلال ثوانٍ
                        // بدل طحن ثلاث جولات بشريط صفر (تجربة «متجمّد»)
                        if (firstRound && succeeded.get() == 0 &&
                            (ex.message ?: "") == (firstPipelineError.get()?.message ?: "") &&
                            systematicFails.incrementAndGet() >= earlyAbortAt
                        ) {
                            earlyAbort.set(true)
                        }
                        finish(false)
                    }
                    override fun completed() = finish(true)
                }
                runCatching { execute(cmds[index], listener) }.onFailure {
                    // فشل الإرسال نفسه — المستمع لن يُستدعى
                    if (firstPipelineError.get() == null) firstPipelineError.set(it)
                    reported.add(index)
                    failedNow.add(index)
                    if (lastRound) {
                        onDone(index, false)
                        onProgress(progressed.incrementAndGet().coerceAtMost(total), total)
                    }
                    inFlight.release()
                    latch.countDown()
                }
            }
            // ما لم يُرسَل لن يأتيه ردّ — نُنزل عدّاد الانتظار بعدده وإلا انتظرنا
            // المهلة كاملة بلا داعٍ، ونُعيده في الجولة التالية فهو لم يُنفَّذ أصلاً
            repeat(notSent.size) { latch.countDown() }
            // مهلة متناسبة مع الحجم لكن مسقوفة بعشر دقائق للجولة: الصيغة القديمة
            // كانت تبلغ ساعات لدفعة 100000 فيبدو التطبيق معلقاً بلا نهاية
            val roundTimeout = (60_000L + pending.size * 150L).coerceAtMost(600_000L)
            // انتظار بخطوات قصيرة ليُكسر فوراً عند الإجهاض المبكر بدل انتظار المهلة
            var waited = 0L
            while (waited < roundTimeout && !earlyAbort.get()) {
                if (latch.await(250, java.util.concurrent.TimeUnit.MILLISECONDS)) break
                waited += 250
            }
            roundClosed.set(true)
            // إجهاض مبكر مؤكد (فشل منهجي): نخرج بلا جولات إعادة عقيمة. الشريط
            // يكتمل عبر الذيل، والمستدعي يرمي الخطأ الحقيقي لأن ok==0
            if (earlyAbort.get()) break
            // أوامر أُرسلت ولم يأتِها ردّ قبل المهلة: كانت تُسقط تماماً — لا تُعاد
            // ولا يُبلَّغ عنها، فتضيع صامتة. إعادتها آمنة لأن «موجود مسبقاً»
            // يُحسب نجاحاً، فالعملية متكررة النتيجة بلا تكرار كروت
            val unanswered = pending.filter { it !in reported && it !in notSent }
            if (lastRound) {
                // الجولة الأخيرة: نُبلّغ عن غير المُرسَل وغير المُجاب كفاشل ليكتمل التقدم
                (notSent + unanswered).forEach { i ->
                    onDone(i, false)
                    onProgress(progressed.incrementAndGet().coerceAtMost(total), total)
                }
            }
            pending = if (lastRound) emptyList()
            else (failedNow + notSent + unanswered).distinct().sorted()
            round++
        }
        // في الجولة الأخيرة نُكمل شريط التقدم للنهاية حتى لو تجمّد بعض الأوامر
        // دون ردّ قبل المهلة — العدّاد لا يتجاوز الإجمالي أبداً
        if (progressed.get() < total) onProgress(total, total)
        val ok = succeeded.get()
        com.binwaps.cardmanager.data.EventLog.log(
            "رفع",
            "نجح $ok من $total" + if (ok < total) " — أول خطأ: ${firstPipelineError.get()?.message?.take(140)}" else "",
            ok = ok == total,
        )
        return BulkResult(ok, total - ok)
    }

    /** أول خطأ في آخر عملية متدفقة — لعرض سببٍ مفهوم عند فشل الكل */
    internal val firstPipelineError =
        java.util.concurrent.atomic.AtomicReference<Throwable?>(null)

    /** ينفّذ أمراً ويعيد قائمة فارغة بدل الانهيار إن لم يكن الأمر مدعوماً */
    internal fun ApiConnection.tryList(vararg commands: String): List<Map<String, String>> {
        for (cmd in commands) {
            val result = runCatching { execute(cmd) }.getOrNull()
            if (result != null) return result
        }
        return emptyList()
    }

    /**
     * جلب خفيف: يطلب الحقول المطلوبة فقط بدل كل شيء —
     * الفرق هائل مع قوائم بعشرات آلاف المستخدمين على شبكة بطيئة.
     */
    internal fun ApiConnection.printLight(path: String, props: String): List<Map<String, String>> =
        runCatching { execute("$path/print return $props") }
            .getOrElse { e ->
                // لا نصعّد إلى print الكامل (الأثقل) عند انتهاء المهلة — كان يضاعف
                // الانتظار ثم يفشل ثانيةً. التصعيد فقط لأخطاء الأمر (راوتر قديم لا
                // يدعم صيغة return props).
                val msg = e.message ?: ""
                if (msg.contains("timed out", true) || msg.contains("timeout", true)) throw e
                execute("$path/print")
            }

    internal fun ApiConnection.tryPrintLight(props: String, vararg paths: String): List<Map<String, String>> {
        for (p in paths) {
            val r = runCatching { printLight(p, props) }.getOrNull()
            if (r != null) return r
        }
        return emptyList()
    }

    /**
     * عدّ فوري على الراوتر دون نقل أي صفوف: `count-only` يجعل الراوتر يعيد
     * الرقم وحده في حقل `ret` — على دومين بعيد هذا الفرق بين تعليقٍ لدقائق
     * (نقل عشرات آلاف المستخدمين) ورقمٍ يصل في أجزاء من الثانية.
     */
    internal fun ApiConnection.countOnly(path: String, where: String = ""): Int? =
        runCatching {
            val cmd = "$path/print count-only" + if (where.isBlank()) "" else " where $where"
            execute(cmd)?.firstOrNull()?.get("ret")?.trim()?.toIntOrNull()
        }.getOrNull()

    internal fun ApiConnection.tryCountOnly(where: String = "", vararg paths: String): Int? {
        for (p in paths) {
            val c = countOnly(p, where)
            if (c != null) return c
        }
        return null
    }

    // ===== PPP / PPPoE =====

    data class PppSecret(
        val id: String,
        val name: String,
        val password: String,
        val profile: String,
        val service: String,
        val comment: String,
        val disabled: Boolean,
        val lastLoggedOut: String,
        val active: Boolean = false,
        val activeAddress: String = "",
        val activeUptime: String = "",
    )

    /** حسابات PPPoE مع حالة اتصال كل حساب الآن */
    suspend fun fetchPppSecrets(r: RouterProfile?): Result<List<PppSecret>> = onRouter(r) { con ->
        val actives = con.tryPrintLight("name,address,uptime", "/ppp/active")
            .associateBy { it["name"].orEmpty() }
        con.printLight(
            "/ppp/secret",
            ".id,name,password,profile,service,comment,disabled,last-logged-out",
        ).map { row ->
            val name = row["name"].orEmpty()
            val a = actives[name]
            PppSecret(
                id = row[".id"].orEmpty(),
                name = name,
                password = row["password"].orEmpty(),
                profile = row["profile"].orEmpty(),
                service = row["service"].orEmpty(),
                comment = row["comment"].orEmpty(),
                disabled = row["disabled"] == "true",
                lastLoggedOut = row["last-logged-out"].orEmpty(),
                active = a != null,
                activeAddress = a?.get("address").orEmpty(),
                activeUptime = a?.get("uptime").orEmpty(),
            )
        }
    }

    /** باقات PPP — لاختيارها عند رفع الكروت كحسابات PPPoE */
    suspend fun fetchPppProfiles(r: RouterProfile?): Result<List<String>> = onRouter(r) { con ->
        con.tryList("/ppp/profile/print").mapNotNull { it["name"] }
    }

    /**
     * رفع كروت كحسابات PPPoE — متدفق بنفس محرك الهوتسبوت:
     * نافذة 128، إعادة صامتة، والموجود مسبقاً يُحسب نجاحاً لا تكراراً.
     */
    suspend fun createPppSecrets(
        r: RouterProfile?,
        users: List<UserEntry>,
        profile: String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onCreated: (UserEntry) -> Unit = {},
    ): Result<Int> = onRouter(r, foreground = true) { con ->
        val cmds = users.map { pppAddCommand(it, profile) }
        val result = con.pipeline(
            cmds, onProgress,
            treatErrorAsOk = { it.contains("already have", true) || it.contains("already exists", true) },
            onDone = { index, success -> if (success) onCreated(users[index]) },
        )
        if (result.ok == 0 && users.isNotEmpty()) {
            throw RouterLogicException(
                "رفض الراوتر إنشاء حسابات PPPoE: ${firstPipelineError.get()?.message ?: "تأكد من اسم الباقة"}",
                firstPipelineError.get(),
            )
        }
        result.ok
    }

    suspend fun setPppSecretDisabled(r: RouterProfile?, id: String, disabled: Boolean): Result<Unit> =
        onRouter(r) { con ->
            con.execute("/ppp/secret/set .id=$id disabled=${if (disabled) "yes" else "no"}")
            Unit
        }

    suspend fun removePppSecret(r: RouterProfile?, id: String): Result<Unit> = onRouter(r) { con ->
        con.execute("/ppp/secret/remove .id=$id")
        Unit
    }

    /** فصل جلسة PPPoE نشطة باسم المستخدم */
    suspend fun disconnectPppActive(r: RouterProfile?, name: String): Result<Unit> = onRouter(r) { con ->
        con.tryPrintLight(".id,name", "/ppp/active")
            .filter { it["name"] == name }
            .forEach { row -> row[".id"]?.let { con.execute("/ppp/active/remove .id=$it") } }
        Unit
    }

    // ===== التشخيص =====

    data class DiagLine(val label: String, val value: String, val ok: Boolean)

    /**
     * فحص شامل يجري أوامر خام على الراوتر ويعرض ردّه الحقيقي على كلٍّ منها —
     * حين «تظهر أصفار» يكشف هذا أين الكروت فعلاً وأي أمرٍ يفشل ولماذا.
     */
    suspend fun diagnose(r: RouterProfile?): Result<List<DiagLine>> = onRouter(r) { con ->
        val out = mutableListOf<DiagLine>()
        fun probe(label: String, cmd: String, render: (List<Map<String, String>>) -> String) {
            runCatching { con.execute(cmd) ?: emptyList() }
                .onSuccess { out.add(DiagLine(label, render(it), true)) }
                .onFailure { out.add(DiagLine(label, it.message?.take(140) ?: "فشل", false)) }
        }
        fun ret(rows: List<Map<String, String>>) = rows.firstOrNull()?.get("ret") ?: "بدون ret"
        fun names(rows: List<Map<String, String>>) =
            "${rows.size} إجمالاً" + if (rows.isEmpty()) "" else " — أولها: " +
                rows.take(5).mapNotNull { it["name"] ?: it["username"] }.joinToString("، ")

        probe("هوية الراوتر", "/system/identity/print") { it.firstOrNull()?.get("name") ?: "؟" }
        probe("الإصدار واللوحة", "/system/resource/print") {
            "${it.firstOrNull()?.get("version") ?: "؟"} — ${it.firstOrNull()?.get("board-name").orEmpty()}"
        }
        probe("خوادم الهوتسبوت", "/ip/hotspot/print") { rows ->
            if (rows.isEmpty()) "لا يوجد أي سيرفر هوتسبوت على هذا الراوتر"
            else rows.mapNotNull { it["name"] }.joinToString("، ")
        }
        probe("عدّ مستخدمي الهوتسبوت (count-only)", "/ip/hotspot/user/print count-only", ::ret)
        probe("مستخدمو الهوتسبوت (قائمة)", "/ip/hotspot/user/print return name", ::names)
        probe("فحص استعلام الاستثناء (where)", "/ip/hotspot/user/print count-only where name!=default-trial", ::ret)
        probe("باقات الهوتسبوت", "/ip/hotspot/user/profile/print") { rows ->
            "${rows.size} باقة" + if (rows.isEmpty()) "" else " — " + rows.take(6).mapNotNull { it["name"] }.joinToString("، ")
        }
        probe("عملاء اليوزر منجر v6", "/tool/user-manager/customer/print") { rows ->
            if (rows.isEmpty()) "لا يوجد عملاء" else rows.take(5).mapNotNull { it["login"] }.joinToString("، ")
        }
        probe("اليوزر منجر v6 (count-only)", "/tool/user-manager/user/print count-only", ::ret)
        probe("اليوزر منجر v6 (قائمة)", "/tool/user-manager/user/print return name,username", ::names)
        probe("باقات اليوزر منجر v6", "/tool/user-manager/profile/print") { rows -> "${rows.size} باقة" }
        probe("اليوزر منجر v7 (count-only)", "/user-manager/user/print count-only", ::ret)
        probe("المتصلون الآن", "/ip/hotspot/active/print count-only", ::ret)
        probe("حسابات PPPoE (count-only)", "/ppp/secret/print count-only", ::ret)
        probe("جلسات PPPoE النشطة", "/ppp/active/print count-only", ::ret)
        out
    }

    // ===== الحالة =====

    /**
     * اتصال سريع: حالة النظام وعدد المتصلين فقط.
     * لا يمسح قوائم المستخدمين — تلك تُجلب عند الطلب عبر [fetchCardStats].
     */
    /** نتيجة الاتصال الذكي: الحالة + الإعداد الذي نجح فعلاً */
    data class SmartConnect(val status: RouterStatus, val useSsl: Boolean, val note: String)

    /**
     * ينفّذ الاتصال الذكي على نطاق مستقل عن الواجهة.
     *
     * السبب: العمل الشبكي المُعطِّل (blocking) لا يستجيب للإلغاء، فلو كان
     * ابناً للواجهة لبقيت مهلة الشاشة تنتظره فعلياً وتعلّق على «جاري الاتصال».
     * بجعله مستقلاً تعود الواجهة في موعدها ويُكمل هو تنظيف نفسه في الخلفية.
     */
    fun smartConnectAsync(
        r: RouterProfile,
        onStage: (String) -> Unit = {},
    ): kotlinx.coroutines.Deferred<Result<SmartConnect>> =
        clientScope.async { smartConnect(r, onStage) }

    /**
     * اتصال ذكي: لا يفشل لمجرد أن خانة «مشفّر» مضبوطة خطأ.
     * يفحص أن المنفذ مفتوح أصلاً، ثم يجرّب النوع المطلوب، وإن فشل يجرّب
     * النوع الآخر تلقائياً ويخبرنا أيهما نجح لنحفظه.
     *
     * سبب وجوده: منفذ API عادي (مثل 8728 أو منفذ مخصّص) مع تفعيل api-ssl
     * يجعل مصافحة TLS تعلّق حتى انتهاء المهلة بلا سبب مفهوم للمستخدم.
     */
    suspend fun smartConnect(
        r: RouterProfile,
        onStage: (String) -> Unit = {},
    ): Result<SmartConnect> = withContext(Dispatchers.IO) {
        val timeoutMs = (r.timeoutSec.coerceIn(3, 120)) * 1000
        onStage("فحص المنفذ ${r.port}…")
        com.binwaps.cardmanager.data.EventLog.log(
            "اتصال",
            "محاولة ${r.host.trim()}:${r.port} مستخدم=${r.username} مشفّر=${if (r.useSsl) "نعم" else "لا"} مهلة=${r.timeoutSec}ث",
        )
        // الفحص استرشادي فقط لتحسين رسالة الخطأ — لا يُجهض الاتصال.
        // شبكة بطيئة (VPN) قد تتجاوز مهلة الفحص القصيرة بينما الاتصال نفسه ينجح.
        val reachable = portReachable(r.host, r.port, timeoutMs)
        com.binwaps.cardmanager.data.EventLog.log(
            "اتصال",
            if (reachable) "المنفذ ${r.port} مفتوح" else "فحص المنفذ ${r.port} لم ينجح — نتابع المحاولة",
            reachable,
        )
        // المنفذ مفتوح — المشكلة إن وُجدت في نوع التشفير أو بيانات الدخول.
        // كل العمل الشبكي خارج قفل الجلسة: لو كانت دورة مزامنة عالقة تحتجز
        // القفل، لا يقف اتصال المستخدم في الطابور حتى تنتهي مهلته.
        val order = listOf(r.useSsl, !r.useSsl)
        var lastError: Throwable? = null
        for (ssl in order) {
            var probe: ApiConnection? = null
            onStage(if (ssl) "تجربة الاتصال المشفّر (api-ssl)…" else "تجربة الاتصال العادي (api)…")
            val attempt = runCatching {
                val con = openWith(r, ssl)
                probe = con
                onStage("تسجيل الدخول وقراءة حالة الراوتر…")
                readStatus(con)
            }
            attempt.onSuccess { status ->
                // تثبيت الجلسة إن كان القفل متاحاً فوراً؛ وإلا نغلق النسخة
                // المؤقتة ويفتح obtain() جلسة جديدة عند أول عملية — بلا انتظار
                if (sessionLock.tryLock()) {
                    try {
                        invalidateSession()
                        session = probe
                        sessionKey = keyOf(r.copy(useSsl = ssl))
                    } finally {
                        sessionLock.unlock()
                    }
                } else {
                    runCatching { probe?.close() }
                }
                val note = when {
                    ssl == r.useSsl -> ""
                    ssl -> "تم الاتصال بالوضع المشفّر (api-ssl) — فُعِّل تلقائياً"
                    else -> "المنفذ ${r.port} غير مشفّر — أُطفئ خيار api-ssl تلقائياً ونجح الاتصال"
                }
                com.binwaps.cardmanager.data.EventLog.log(
                    "اتصال",
                    "نجح (${if (ssl) "مشفّر" else "عادي"}) — ${status.identity.ifBlank { "بلا اسم" }} ${status.version}",
                )
                return@withContext Result.success(SmartConnect(status, ssl, note))
            }
            runCatching { probe?.close() }
            lastError = attempt.exceptionOrNull()
            com.binwaps.cardmanager.data.EventLog.log(
                "اتصال",
                "فشل (${if (ssl) "مشفّر" else "عادي"}): ${lastError?.message?.take(160)}",
                ok = false,
            )
            // بيانات دخول خاطئة: لا فائدة من تجربة النوع الآخر
            val msg = lastError?.message.orEmpty()
            if (msg.contains("cannot log in", true) || msg.contains("invalid user", true)) break
        }
        // فشل المحاولتان — إن كان المنفذ نفسه غير قابل للوصول فذاك السبب الأرجح
        val reason = if (!reachable) {
            "لا يمكن الوصول إلى ${r.host.trim()}:${r.port} — المنفذ مغلق أو العنوان خاطئ. " +
                "تأكد أن خدمة API مفعّلة على الراوتر وأن المنفذ مفتوح من الخارج (Port Forward) للاتصال البعيد."
        } else {
            arabicError(lastError ?: Exception("تعذّر الاتصال"))
        }
        Result.failure(Exception(reason, lastError))
    }

    private fun readStatus(con: ApiConnection): RouterStatus {
        val res = con.execute("/system/resource/print").firstOrNull() ?: emptyMap()
        val identity = runCatching { con.execute("/system/identity/print").firstOrNull()?.get("name") }
            .getOrNull().orEmpty()
        val active = con.countOnly("/ip/hotspot/active") ?: -1
        return RouterStatus(
            identity = identity,
            version = res["version"].orEmpty(),
            board = res["board-name"].orEmpty(),
            uptime = res["uptime"].orEmpty(),
            cpuLoad = res["cpu-load"].orEmpty(),
            freeMemory = res["free-memory"].orEmpty(),
            totalMemory = res["total-memory"].orEmpty(),
            activeUsers = active,
            hotspotUsers = -1,
            userManagerUsers = -1,
            usedUsers = -1,
        )
    }

    suspend fun connect(r: RouterProfile): Result<RouterStatus> = onRouter(r) { con ->
        val res = con.execute("/system/resource/print").firstOrNull() ?: emptyMap()
        val identity = runCatching { con.execute("/system/identity/print").firstOrNull()?.get("name") }
            .getOrNull().orEmpty()
        // count-only بدل نقل صفٍّ لكل جلسة نشطة لمجرد عدّها — يتكرر كل دورة مزامنة
        val active = con.countOnly("/ip/hotspot/active") ?: -1

        RouterStatus(
            identity = identity,
            version = res["version"].orEmpty(),
            board = res["board-name"].orEmpty(),
            uptime = res["uptime"].orEmpty(),
            cpuLoad = res["cpu-load"].orEmpty(),
            freeMemory = res["free-memory"].orEmpty(),
            totalMemory = res["total-memory"].orEmpty(),
            activeUsers = active,
            hotspotUsers = -1,
            userManagerUsers = -1,
            usedUsers = -1,
        )
    }

    /**
     * عدادات الكروت — بـ count-only يعيد الراوتر الأرقام فوراً دون نقل صف واحد،
     * فتظهر العدادات في أقل من ثانية حتى على دومين بعيد ببطء عالٍ.
     */
    suspend fun fetchCardStats(r: RouterProfile?): Result<RouterStatus> = onRouter(r) { con ->
        val hs = "/ip/hotspot/user"
        // العدّ الصريح أولاً — استعلام الاستثناء قد يتصرف بغرابة على بعض إصدارات v6
        // فلا نأتمنه على الإجمالي؛ خصم default-trial هامشي ولا يستحق المجازفة
        val total = con.countOnly(hs)
        if (total != null) {
            // المستعملة: دخلت ولو مرة (uptime > 0) أو معلّمة منتهية بأسلوب MIKHMON
            // (limit-uptime=1s) أو معطّلة — نفس منطق classify لكن يعدّه الراوتر بنفسه
            // القيم المنطقية في الـ API تُكتب true/false لا yes/no
            val used = con.countOnly(hs, "uptime>0s or limit-uptime=1s or disabled=true")
                ?: con.countOnly(hs, "uptime>0s")
            // إن فشل عدّ اليوزر منجر لا نعرض صفراً كاذباً — نجرب عدّ القائمة الخفيفة
            val um = con.tryCountOnly("", "/user-manager/user", "/tool/user-manager/user")
                ?: con.tryPrintLight(".id", "/user-manager/user", "/tool/user-manager/user").size
            RouterStatus(
                activeUsers = con.countOnly("/ip/hotspot/active") ?: -1,
                hotspotUsers = total,
                userManagerUsers = um,
                usedUsers = used ?: -1,
            )
        } else {
            // راوتر قديم جداً لا يدعم count-only — الطريقة الكاملة كخطة أخيرة
            val hotspotRows = con
                .printLight(hs, "name,limit-uptime,uptime,limit-bytes-total,bytes-in,bytes-out,disabled,comment")
                .filter { (it["name"] ?: "") != "default-trial" }
            val used = hotspotRows.count { classify(it) != CardStatus.UNUSED }
            val umCount = con.tryPrintLight("name", "/user-manager/user", "/tool/user-manager/user").size
            RouterStatus(
                activeUsers = -1,
                hotspotUsers = hotspotRows.size,
                userManagerUsers = umCount,
                usedUsers = used,
            )
        }
    }

    // ===== تصنيف حالة الكرت =====

    /**
     * تصنيف كرت الهوتسبوت — يدعم اصطلاح MIKHMON المنتشر إضافة للحدود الأصلية:
     *
     * - MIKHMON يضع `limit-uptime=1s` علامةً على الانتهاء
     * - ويكتب في الملاحظة `vc-` أو `up-` للكرت الذي لم يُستخدم بعد
     * - وعند أول دخول يستبدلها بتاريخ الانتهاء "25/Jul/2026 14:30:00"
     */
    fun classify(row: Map<String, String>): CardStatus {
        if (row["disabled"] == "true") return CardStatus.DISABLED

        val limitUptimeRaw = row["limit-uptime"].orEmpty()
        // علامة MIKHMON للكرت المنتهي
        if (limitUptimeRaw.trim() == "1s") return CardStatus.EXPIRED

        val limitUptime = parseUptime(limitUptimeRaw)
        val uptime = parseUptime(row["uptime"].orEmpty())
        if (limitUptime > 0 && uptime >= limitUptime) return CardStatus.EXPIRED

        val limitBytes = row["limit-bytes-total"]?.toLongOrNull() ?: 0
        val usedBytes = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0)
        if (limitBytes > 0 && usedBytes >= limitBytes) return CardStatus.EXPIRED

        // ملاحظة MIKHMON: تاريخ انتهاء مكتوب عند أول دخول
        val comment = row["comment"].orEmpty()
        val expiry = parseCommentExpiry(comment)
        if (expiry != null) {
            return if (expiry < System.currentTimeMillis()) CardStatus.EXPIRED else CardStatus.IN_USE
        }
        val untouched = comment.startsWith("vc-") || comment.startsWith("up-")

        return when {
            uptime > 0 || usedBytes > 0 -> CardStatus.IN_USE
            untouched || comment.isBlank() -> CardStatus.UNUSED
            else -> CardStatus.UNUSED
        }
    }

    /** تاريخ انتهاء بصيغة MIKHMON: 25/Jul/2026 14:30:00 */
    fun parseCommentExpiry(comment: String): Long? {
        if (comment.length < 11 || comment[2] != '/' || comment[6] != '/') return null
        return runCatching {
            java.text.SimpleDateFormat("dd/MMM/yyyy HH:mm:ss", java.util.Locale.ENGLISH)
                .parse(comment.trim())?.time
        }.getOrNull()
    }

    // ===== الكروت =====

    private const val HOTSPOT_PROPS =
        ".id,name,password,profile,limit-uptime,uptime,limit-bytes-total,bytes-in,bytes-out,disabled,comment"

    /** كروت الهوتسبوت مع حالتها */
    suspend fun fetchHotspotUsers(r: RouterProfile?, foreground: Boolean = false): Result<List<UserEntry>> = onRouter(r, foreground = foreground) { con ->
        con.printLight("/ip/hotspot/user", HOTSPOT_PROPS).mapNotNull { row ->
            val name = row["name"] ?: return@mapNotNull null
            if (name == "default-trial") return@mapNotNull null
            UserEntry(
                username = name,
                password = row["password"].orEmpty(),
                profile = row["profile"].orEmpty(),
                validity = row["limit-uptime"].orEmpty(),
                comment = row["comment"].orEmpty(),
                routerId = row[".id"].orEmpty(),
                source = CardSource.HOTSPOT,
                status = classify(row),
                uptime = row["uptime"].orEmpty(),
                bytesUsed = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0),
                disabled = row["disabled"] == "true",
            )
        }
    }

    /**
     * مستخدمو اليوزر منجر — v7 ثم v6.
     *
     * في v7 لا توجد الصلاحية على سجل المستخدم، بل في جدول منفصل
     * `/user-manager/user-profile` يحمل (user, profile, end-time, state).
     * في v6 تكون العدادات على السجل نفسه (uptime-used, download-used…).
     */
    private fun readUserManager(con: ApiConnection): List<UserEntry> {
        val variant = userManagerVariant(con)
        // proplist v7 يضمّ حقول العدّاد المحتملة على user-profile؛ نقرأ ما يوجد
        val rows = con.tryPrintLight(
            ".id,name,username,customer,password,group,actual-profile,comment,disabled,uptime-used,download-used,upload-used",
            umPath(variant, "user"),
        )
        if (rows.isEmpty()) return emptyList()

        // جدول الصلاحيات/العدّادات — في v7 هنا يعيش state/end-time والاستهلاك
        val userProfiles = con.tryPrintLight(
            "user,profile,end-time,state,uptime,download,upload,total-bytes",
            umPath(variant, "user-profile"),
        ).associateBy { it["user"].orEmpty() }

        val now = System.currentTimeMillis()
        return rows.mapNotNull { row ->
            val name = row["name"] ?: row["username"] ?: return@mapNotNull null
            val up = userProfiles[name]
            UserEntry(
                username = name,
                password = row["password"].orEmpty(),
                profile = up?.get("profile") ?: row["group"] ?: row["actual-profile"] ?: row["profile"].orEmpty(),
                comment = row["comment"].orEmpty(),
                routerId = row[".id"].orEmpty(),
                source = CardSource.USER_MANAGER,
                status = classifyUm(variant, row, up, now),
                uptime = umUptimeUsed(variant, row, up),
                bytesUsed = umBytesUsed(variant, row, up),
                disabled = row["disabled"] == "true",
                expiryText = up?.get("end-time").orEmpty(),
            )
        }
    }

    // ===== تصنيف اليوزر منجر (دوال نقية قابلة للاختبار) =====
    //
    // في v6 العدّادات على سجل المستخدم (uptime-used/download-used/upload-used).
    // في v7 ليست هناك، بل الحالة والاستهلاك في جدول user-profile — قراءتها
    // بأسماء v6 كانت تعطي صفراً فيظهر كرت مستهلك على أنه UNUSED.

    /** بايتات الاستهلاك حسب الإصدار — تقرأ الحقول المتاحة بأمان */
    internal fun umBytesUsed(
        variant: UmVariant,
        userRow: Map<String, String>,
        profileRow: Map<String, String>?,
    ): Long = if (variant == UmVariant.V7) {
        (profileRow?.get("download")?.toLongOrNull() ?: 0L) +
            (profileRow?.get("upload")?.toLongOrNull() ?: 0L) +
            (profileRow?.get("total-bytes")?.toLongOrNull() ?: 0L)
    } else {
        (userRow["download-used"]?.toLongOrNull() ?: 0L) +
            (userRow["upload-used"]?.toLongOrNull() ?: 0L)
    }

    /** نص وقت الاستخدام حسب الإصدار */
    internal fun umUptimeUsed(
        variant: UmVariant,
        userRow: Map<String, String>,
        profileRow: Map<String, String>?,
    ): String = if (variant == UmVariant.V7) profileRow?.get("uptime").orEmpty()
    else userRow["uptime-used"].orEmpty()

    /** حالة الكرت من صفَّي المستخدم والصلاحية — نقية بلا اتصال ولا وقت ضمني */
    internal fun classifyUm(
        variant: UmVariant,
        userRow: Map<String, String>,
        profileRow: Map<String, String>?,
        now: Long,
    ): CardStatus {
        if (userRow["disabled"] == "true") return CardStatus.DISABLED
        val state = profileRow?.get("state").orEmpty()
        val endTime = profileRow?.get("end-time").orEmpty()
        val expiredByTime = endTime.isNotBlank() && !endTime.equals("unlimited", true) &&
            (parseRouterTime(endTime)?.let { it < now } == true)
        val usedUptime = umUptimeUsed(variant, userRow, profileRow)
        val usedBytes = umBytesUsed(variant, userRow, profileRow)
        return when {
            state.equals("used", true) -> CardStatus.EXPIRED
            expiredByTime -> CardStatus.EXPIRED
            state.equals("running", true) -> CardStatus.IN_USE
            usedUptime.isNotBlank() && parseUptime(usedUptime) > 0 -> CardStatus.IN_USE
            usedBytes > 0 -> CardStatus.IN_USE
            else -> CardStatus.UNUSED
        }
    }

    suspend fun fetchUserManagerUsers(r: RouterProfile?, foreground: Boolean = false): Result<List<UserEntry>> = onRouter(r, foreground = foreground) { con ->
        val list = readUserManager(con)
        if (list.isEmpty()) {
            throw RouterLogicException("لم يُعثر على مستخدمين في اليوزر منجر — تأكد أن الحزمة مثبّتة ومفعّلة على الراوتر")
        }
        list
    }

    /** تحويل وقت الراوتر (jul/25/2026 14:30:00 أو 2026-07-25 14:30:00) إلى ميلي ثانية */
    fun parseRouterTime(value: String): Long? {
        val v = value.trim()
        val formats = listOf(
            "MMM/dd/yyyy HH:mm:ss", "dd/MMM/yyyy HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss",
        )
        for (f in formats) {
            val t = runCatching {
                java.text.SimpleDateFormat(f, java.util.Locale.ENGLISH).parse(v)?.time
            }.getOrNull()
            if (t != null) return t
        }
        return null
    }

    /** كل الكروت من المصدرين معاً */
    suspend fun fetchAllCards(r: RouterProfile?, foreground: Boolean = false): Result<List<UserEntry>> = onRouter(r, foreground = foreground) { con ->
        // فشل الهوتسبوت خطأ حقيقي يظهر للمستخدم — كان يتحول إلى "0 كرت" بنجاح زائف
        val hotspot = con.printLight("/ip/hotspot/user", HOTSPOT_PROPS)
            .filter { (it["name"] ?: "") != "default-trial" }
            .mapNotNull { row ->
                val name = row["name"] ?: return@mapNotNull null
                UserEntry(
                    username = name,
                    password = row["password"].orEmpty(),
                    profile = row["profile"].orEmpty(),
                    validity = row["limit-uptime"].orEmpty(),
                    comment = row["comment"].orEmpty(),
                    routerId = row[".id"].orEmpty(),
                    source = CardSource.HOTSPOT,
                    status = classify(row),
                    uptime = row["uptime"].orEmpty(),
                    bytesUsed = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0),
                    disabled = row["disabled"] == "true",
                    limitUptime = row["limit-uptime"].orEmpty(),
                    batchTag = row["comment"].orEmpty().takeIf { it.startsWith("vc-") || it.startsWith("b-") }.orEmpty(),
                    limitBytes = row["limit-bytes-total"]?.toLongOrNull() ?: 0,
                    expiryText = parseCommentExpiry(row["comment"].orEmpty())
                        ?.let { java.text.SimpleDateFormat("yyyy/MM/dd HH:mm", java.util.Locale.US).format(java.util.Date(it)) }
                        .orEmpty(),
                )
            }
        // دمج المصدرين لا يجب أن يسقط بفشل اليوزر منجر، لكن لا نبتلعه صامتاً:
        // نسجّله في السجل ليعرف المستخدم أن مصدراً لم يُجلب (كان يظهر كأن لا كروت)
        val um = runCatching { readUserManager(con) }.getOrElse { e ->
            com.binwaps.cardmanager.data.EventLog.log(
                "جلب",
                "تعذّر جلب اليوزر منجر: ${e.message?.take(120) ?: "سبب غير معروف"}",
                ok = false,
            )
            emptyList()
        }
        hotspot + um
    }

    // ===== الجلسات =====

    /** الجلسات النشطة الآن */
    suspend fun fetchActiveSessions(r: RouterProfile?): Result<List<SessionEntry>> = onRouter(r) { con ->
        con.execute("/ip/hotspot/active/print").map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["user"].orEmpty(),
                address = row["address"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                uptime = row["uptime"].orEmpty(),
                bytesIn = row["bytes-in"]?.toLongOrNull() ?: 0,
                bytesOut = row["bytes-out"]?.toLongOrNull() ?: 0,
                startedAt = row["login-by"].orEmpty(),
                active = true,
            )
        }
    }

    /** سجل الجلسات السابقة — من اليوزر منجر إن وُجد، وإلا من كوكيز الهوتسبوت */
    suspend fun fetchSessionHistory(r: RouterProfile?, foreground: Boolean = false): Result<List<SessionEntry>> = onRouter(r, foreground = foreground) { con ->
        val umSessions = con.tryList("/user-manager/session/print", "/tool/user-manager/session/print")
        if (umSessions.isNotEmpty()) {
            return@onRouter umSessions.map { row ->
                SessionEntry(
                    id = row[".id"].orEmpty(),
                    username = row["user"] ?: row["username"].orEmpty(),
                    address = row["nas-ip-address"] ?: row["address"].orEmpty(),
                    macAddress = row["calling-station-id"] ?: row["mac-address"].orEmpty(),
                    uptime = row["session-time"] ?: row["uptime"].orEmpty(),
                    bytesIn = row["download"]?.toLongOrNull() ?: row["bytes-in"]?.toLongOrNull() ?: 0,
                    bytesOut = row["upload"]?.toLongOrNull() ?: row["bytes-out"]?.toLongOrNull() ?: 0,
                    startedAt = row["started"] ?: row["from-time"].orEmpty(),
                    endedAt = row["ended"] ?: row["till-time"].orEmpty(),
                    active = false,
                )
            }
        }
        // بديل: الكوكيز تحفظ آخر دخول لكل مستخدم
        con.tryList("/ip/hotspot/cookie/print").map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["user"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                uptime = row["expires-in"].orEmpty(),
                active = false,
            )
        }
    }

    suspend fun disconnectActive(r: RouterProfile?, id: String): Result<Unit> = onRouter(r) { con ->
        con.execute("/ip/hotspot/active/remove .id=$id")
        Unit
    }

    // ===== الباقات =====

    /**
     * باقات الهوتسبوت واليوزر منجر معاً، مع عدد الكروت في كل باقة.
     * جداول الباقات صغيرة فتصل فوراً، وعدّ كروت كل باقة يتم على الراوتر
     * نفسه بـ count-only — لا يُنقل أي مستخدم عبر الشبكة إطلاقاً.
     */
    suspend fun fetchProfiles(r: RouterProfile?, foreground: Boolean = false): Result<List<HotspotProfile>> = onRouter(r, foreground = foreground) { con ->
        // عدّ الكروت لكل باقة بجولة **تجميع واحدة لكل مصدر** بدل جولة count-only
        // منفصلة لكل باقة (كانت N جولة تسلسلية على راوتر بعيد = ثوانٍ تجمّد شاشة
        // الباقات في كل بناء وبعد كل رفع). نجلب حقل الباقة لكل مستخدم مرة واحدة
        // متدفقاً ونجمّعه محلياً — يهبط الإجمالي إلى جولتين مهما كثُرت الباقات.
        val hsCounts: Map<String, Int> = runCatching {
            con.printLight("/ip/hotspot/user", "profile")
                .groupingBy { it["profile"].orEmpty() }.eachCount()
        }.getOrDefault(emptyMap())

        // كشف الإصدار مرة واحدة، ثم قراءة الجدول الصحيح حسب النكهة:
        // v7 الباقة الفعلية في جدول user-profile، وv6 في actual-profile على المستخدم
        val umV = userManagerVariant(con)
        val umCounts: Map<String, Int> = runCatching {
            when (umV) {
                UmVariant.V7 -> con.printLight(umPath(umV, "user-profile"), "profile")
                    .groupingBy { it["profile"].orEmpty() }.eachCount()
                UmVariant.V6 -> con.printLight(umPath(umV, "user"), "actual-profile")
                    .groupingBy { it["actual-profile"].orEmpty() }.eachCount()
                else -> emptyMap()
            }
        }.getOrDefault(emptyMap())

        val hotspotProfiles = con.tryList("/ip/hotspot/user/profile/print").map { row ->
            val name = row["name"].orEmpty()
            HotspotProfile(
                id = row[".id"].orEmpty(),
                name = name,
                rateLimit = row["rate-limit"].orEmpty(),
                sessionTimeout = row["session-timeout"].orEmpty(),
                sharedUsers = row["shared-users"] ?: "1",
                source = CardSource.HOTSPOT,
                userCount = hsCounts[name] ?: 0,
            )
        }

        // اليوزر منجر v7 يسميها profile، و v6 يسميها profile أيضاً لكن بمسار مختلف
        val umProfiles = con.tryList("/user-manager/profile/print", "/tool/user-manager/profile/print")
            .map { row ->
                val name = row["name"].orEmpty()
                HotspotProfile(
                    id = row[".id"].orEmpty(),
                    name = name,
                    rateLimit = row["rate-limit"] ?: row["rate-limit-rx"].orEmpty(),
                    sessionTimeout = row["validity"] ?: row["session-timeout"].orEmpty(),
                    sharedUsers = row["shared-users"] ?: "1",
                    source = CardSource.USER_MANAGER,
                    userCount = umCounts[name] ?: 0,
                )
            }

        val all = hotspotProfiles + umProfiles
        if (all.isEmpty()) throw RouterLogicException("لا توجد باقات على الراوتر — أنشئ باقة من الهوتسبوت أو اليوزر منجر أولاً")
        all
    }

    suspend fun createProfile(r: RouterProfile?, p: HotspotProfile): Result<Unit> = onRouter(r) { con ->
        val cmd = buildString {
            append("/ip/hotspot/user/profile/add name=${q(p.name)}")
            if (p.rateLimit.isNotBlank()) append(" rate-limit=${q(p.rateLimit)}")
            if (p.sessionTimeout.isNotBlank()) append(" session-timeout=${q(p.sessionTimeout)}")
            if (p.sharedUsers.isNotBlank()) append(" shared-users=${q(p.sharedUsers)}")
        }
        con.execute(cmd)
        Unit
    }

    // ===== الرفع والحذف =====

    suspend fun createHotspotUsers(
        r: RouterProfile?,
        users: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onCreated: (UserEntry) -> Unit = {},
    ): Result<Int> = onRouter(r, foreground = true) { con ->
        // إرسال متدفق: كل أوامر الإنشاء تنطلق معاً وتُجمع الردود وهي تصل —
        // على دومين بعيد هذا أسرع بعشرات المرات من أمرٍ بعد أمر
        val cmds = users.map { hotspotAddCommand(it) }
        val result = con.pipeline(
            cmds, onProgress,
            treatErrorAsOk = { it.contains("already have", true) || it.contains("already exists", true) },
            onDone = { index, success ->
                if (success) onCreated(users[index])
            },
        )
        if (result.ok == 0 && users.isNotEmpty()) {
            throw RouterLogicException("رفض الراوتر إنشاء الكروت: ${firstPipelineError.get()?.message ?: "سبب غير معروف"}", firstPipelineError.get())
        }
        result.ok
    }

    // ===== بناء الأوامر (دوال صافية قابلة للاختبار) =====
    //
    // فُصلت عن دوال الاتصال عمداً: أخطاء صيغة الأوامر (مثل name بدل username
    // في v6) كانت تُفشل الرفع كله ولا تُكتشف إلا على جهاز المستخدم. الآن
    // تغطيها اختبارات وحدة تعمل في كل بناء.

    /** أمر إنشاء كرت هوتسبوت */
    internal fun hotspotAddCommand(u: UserEntry): String = buildString {
        append("/ip/hotspot/user/add name=${q(u.username)}")
        if (u.password.isNotBlank()) append(" password=${q(u.password)}")
        if (u.profile.isNotBlank()) append(" profile=${q(u.profile)}")
        if (u.validity.isNotBlank()) append(" limit-uptime=${q(u.validity)}")
        val tag = u.batchTag.ifBlank { u.comment }
        if (tag.isNotBlank()) append(" comment=${q(tag)}")
    }

    /**
     * أمر إنشاء مستخدم يوزر منجر.
     * v6 (/tool/user-manager): حقل الدخول `username` و`customer` إلزامي.
     * v7 (/user-manager): حقل الدخول `name` والباقة في `group`.
     */
    internal fun umAddCommand(isV7: Boolean, customer: String, u: UserEntry): String {
        val base = if (isV7) "/user-manager" else "/tool/user-manager"
        return buildString {
            append("$base/user/add ${if (isV7) "name" else "username"}=${q(u.username)}")
            if (u.password.isNotBlank()) append(" password=${q(u.password)}")
            // v7: لا نرسل group= هنا. ربط الباقة يتم حصراً عبر جدول user-profile
            // في umLinkProfileCommand — إرسالها في الموضعين كان ازدواجاً قد
            // يُنشئ تخصيصاً مكرّراً أو متعارضاً. v6 يحتاج customer إلزامياً.
            if (!isV7) append(" customer=${q(customer)}")
            if (u.comment.isNotBlank()) append(" comment=${q(u.comment)}")
        }
    }

    /** أمر ربط الباقة بالمستخدم بعد إنشائه */
    internal fun umLinkProfileCommand(isV7: Boolean, customer: String, username: String, profile: String): String =
        if (isV7) "/user-manager/user-profile/add user=${q(username)} profile=${q(profile)}"
        else "/tool/user-manager/user/create-and-activate-profile customer=${q(customer)} " +
            "numbers=${q(username)} profile=${q(profile)}"

    /** أمر إنشاء حساب PPPoE */
    internal fun pppAddCommand(u: UserEntry, profile: String): String = buildString {
        append("/ppp/secret/add name=${q(u.username)} service=pppoe")
        if (u.password.isNotBlank()) append(" password=${q(u.password)}")
        val p = profile.ifBlank { u.profile }
        if (p.isNotBlank()) append(" profile=${q(p)}")
        val tag = u.batchTag.ifBlank { u.comment }
        if (tag.isNotBlank()) append(" comment=${q(tag)}")
    }

    /**
     * أول عميل معرّف في يوزر منجر v6 — أوامر الإضافة والتفعيل تتطلب customer
     * موجوداً فعلاً، وافتراض admin كان يُفشل الرفع عند من سمّاه غير ذلك.
     */
    private fun umCustomer(con: ApiConnection): String =
        runCatching {
            con.execute("/tool/user-manager/customer/print")?.firstOrNull()?.get("login")
        }.getOrNull().takeUnless { it.isNullOrBlank() } ?: "admin"

    /**
     * إنشاء المستخدمين في اليوزر منجر.
     * v7: يُنشأ المستخدم ثم تُربط به الباقة في جدول user-profile.
     * v6: أمر واحد create-and-activate-profile، وإلا إضافة عادية.
     */
    suspend fun createUserManagerUsers(
        r: RouterProfile?,
        users: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onCreated: (UserEntry) -> Unit = {},
    ): Result<Int> = onRouter(r, foreground = true) { con ->
        // كشف موحّد مخزّن للجلسة — count-only، لا يتكرر عبر المواضع
        val isV7 = userManagerVariant(con) == UmVariant.V7
        val base = if (isV7) "/user-manager" else "/tool/user-manager"
        val customer = if (isV7) "" else umCustomer(con)
        com.binwaps.cardmanager.data.EventLog.log(
            "رفع",
            "يوزر منجر ${if (isV7) "v7" else "v6"} — المسار $base" +
                (if (isV7) "" else "، العميل «$customer»") + "، ${users.size} كرت",
        )

        // الرفع بموجتين (إنشاء ثم ربط الباقة) = عملياتٌ ضِعف عدد الكروت. نقود
        // الشريط بوحدة عمل واحدة لكل عملية عبر الموجتين معاً ونسقُطها على عدد
        // الكروت، فيتحرّك بسلاسة من البداية للنهاية بدل التجمّد بين الموجتين
        val total = users.size.coerceAtLeast(1)
        val willLink = users.count { it.profile.isNotBlank() }
        val grand = (users.size + willLink).coerceAtLeast(1)
        val work = java.util.concurrent.atomic.AtomicInteger(0)
        fun bump() {
            val scaled = (work.incrementAndGet().toLong() * total / grand).toInt().coerceAtMost(total)
            onProgress(scaled, total)
        }

        // الموجة الأولى (متدفقة): إنشاء المستخدمين كلهم.
        // v6 يسمي حقل الدخول username لا name — استعمال name كان يُفشل كل الرفع
        val addCmds = users.map { umAddCommand(isV7, customer, it) }
        val created = java.util.Collections.synchronizedList(mutableListOf<UserEntry>())
        // نافذة v6 صغيرة عمداً: كل add يكتب في قاعدة يوزر منجر تسلسلياً، ونافذة
        // ١٦ كانت تُغرقه فيتأخر أول ردّ !done جداً فلا يُسجَّل أي نجاح مبكّر
        // ويبقى الشريط «٠ من N» بينما العمل يجري — شكوى المستخدم بالضبط.
        // ٤ تكفي لإخفاء زمن الذهاب/الإياب دون خنق يوزر منجر.
        val umWindow = if (isV7) 48 else 4
        val addResult = con.pipeline(
            addCmds,
            treatErrorAsOk = { it.contains("already have", true) || it.contains("already exists", true) },
            onDone = { index, success ->
                if (success) {
                    created.add(users[index])
                    onCreated(users[index])
                }
                bump()
            },
            window = umWindow,
        )
        if (addResult.ok == 0 && users.isNotEmpty()) {
            throw RouterLogicException(
                "تعذّر إنشاء أي مستخدم: ${firstPipelineError.get()?.message ?: "تأكد من تثبيت حزمة اليوزر منجر ومن الصلاحيات"}",
                firstPipelineError.get(),
            )
        }

        // الموجة الثانية (متدفقة): ربط الباقة بمن نجح إنشاؤهم.
        // نسخة ثابتة — مستمع متأخر من مهلة منتهية قد يضيف أثناء القراءة
        val createdSafe = synchronized(created) { created.toList() }
        val linkCmds = createdSafe.filter { it.profile.isNotBlank() }
            .map { umLinkProfileCommand(isV7, customer, it.username, it.profile) }
        // نتيجة ربط الباقة كانت مُهمَلة تماماً: كرت أُنشئ بلا باقة كان يُحسب
        // نجاحاً كاملاً، فيبدو الرفع سليماً والكرت لا يعمل على الشبكة
        if (linkCmds.isNotEmpty()) {
            val addError = firstPipelineError.get()
            val link = con.pipeline(
                linkCmds,
                // الموجة الثانية كانت بلا تقدّم إطلاقاً فيتجمّد الشريط عند
                // نهايتها — الآن كل ربط يحرّك نفس العدّاد المشترك
                onDone = { _, _ -> bump() },
                treatErrorAsOk = { it.contains("already", true) },
                window = umWindow,
            )
            com.binwaps.cardmanager.data.EventLog.log(
                "رفع",
                "ربط الباقة: نجح ${link.ok} من ${linkCmds.size}",
                ok = link.failed == 0,
            )
            if (link.ok == 0) {
                throw RouterLogicException(
                    "أُنشئ ${addResult.ok} مستخدماً لكن تعذّر ربط الباقة بأي منهم — " +
                        "تأكد أن الباقة «${createdSafe.firstOrNull { it.profile.isNotBlank() }?.profile}» " +
                        "موجودة في اليوزر منجر: ${firstPipelineError.get()?.message?.take(120) ?: ""}",
                    firstPipelineError.get(),
                )
            }
            // لا نُخفي سبب فشل الإضافة إن كان موجوداً قبل موجة الربط
            if (addError != null) firstPipelineError.set(addError)
        }
        // إكمال الشريط للنهاية: تقدير grand قد يفوق العمل الفعلي إن فشل إنشاء
        // بعض الكروت فقلّ عدد الروابط، فلا يبلغ العدّاد النهاية وحده
        onProgress(total, total)
        addResult.ok
    }

    /** تفعيل أو تعطيل كرت على الراوتر */
    suspend fun setUserEnabled(r: RouterProfile?, user: UserEntry, enabled: Boolean): Result<Unit> =
        onRouter(r) { con ->
            if (user.routerId.isBlank()) throw RouterLogicException("هذا الكرت غير موجود على الراوتر")
            val path = when (user.source) {
                CardSource.USER_MANAGER -> umPath(userManagerVariant(con), "user")
                else -> "/ip/hotspot/user"
            }
            con.execute("$path/set .id=${user.routerId} disabled=${!enabled}")
            Unit
        }

    // ===== العمليات الجماعية =====

    /** نتيجة عملية جماعية */
    data class BulkResult(val ok: Int, val failed: Int) {
        val total: Int get() = ok + failed
    }

    private fun ApiConnection.hotspotPath() = "/ip/hotspot/user"

    private fun ApiConnection.userPathFor(source: CardSource): String = when (source) {
        // كان يستعمل print بلا count-only فينقل القائمة كاملة لمجرد كشف المسار —
        // الآن الكشف الموحّد المخزّن (count-only)
        CardSource.USER_MANAGER -> umPath(userManagerVariant(this), "user")
        else -> "/ip/hotspot/user"
    }

    /** تنفيذ أمر على مجموعة كروت مع تقرير تقدم */
    private fun ApiConnection.bulk(
        cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit,
        command: (UserEntry, String) -> String?,
    ): BulkResult {
        // نحسب مسار كل مصدر مرة واحدة بدل مرة لكل كرت
        val paths = cards.map { it.source }.distinct().associateWith { userPathFor(it) }
        var skipped = 0
        val cmds = cards.mapNotNull { u ->
            val cmd = command(u, paths[u.source] ?: "/ip/hotspot/user")
            if (cmd == null) { skipped++; null } else cmd
        }
        // إرسال متدفق — العمليات الجماعية على مئات الكروت تكتمل في ثوانٍ
        val r = pipeline(cmds, { d, _ -> onProgress(skipped + d, cards.size) })
        return BulkResult(r.ok, r.failed + skipped)
    }

    /** تفعيل أو تعطيل مجموعة كروت */
    suspend fun bulkSetEnabled(
        r: RouterProfile?, cards: List<UserEntry>, enabled: Boolean,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        con.bulk(cards, onProgress) { u, path ->
            if (u.routerId.isBlank()) null else "$path/set .id=${u.routerId} disabled=${!enabled}"
        }
    }

    /** حذف مجموعة كروت — يفصل جلساتها النشطة أولاً */
    suspend fun bulkDelete(
        r: RouterProfile?, cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        val names = cards.map { it.username }.toSet()
        runCatching {
            con.printLight("/ip/hotspot/active", ".id,user")
                .filter { it["user"] in names }
                .forEach { row ->
                    row[".id"]?.let { runCatching { con.execute("/ip/hotspot/active/remove .id=$it") } }
                }
        }
        con.bulk(cards, onProgress) { u, path ->
            if (u.routerId.isBlank()) null else "$path/remove .id=${u.routerId}"
        }
    }

    /**
     * تغيير باقة مجموعة كروت — إرسال **متدفّق** (pipeline) لا أمراً-بعد-أمر.
     * كانت هذه العملية الجماعية الوحيدة التسلسلية: تغيير باقة ٥٠٠ كرت على راوتر
     * بعيد كان يستغرق دقائق (٥٠٠ × زمن الذهاب والإياب). الآن ثوانٍ.
     * التقدّم يُسقَط دائماً على cards.size حتى يصل الشريط للنهاية.
     */
    suspend fun bulkSetProfile(
        r: RouterProfile?, cards: List<UserEntry>, profile: String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        val (um, hotspot) = cards.partition { it.source == CardSource.USER_MANAGER }
        val grand = cards.size
        var ok = 0
        var failed = 0
        var done = 0

        // الهوتسبوت — نافذة واسعة (128) كبقية عملياته الجماعية
        if (hotspot.isNotEmpty()) {
            val hs = hotspot.filter { it.routerId.isNotBlank() }
            failed += hotspot.size - hs.size
            if (hs.isNotEmpty()) {
                val base = done
                val cmds = hs.map { "/ip/hotspot/user/set .id=${it.routerId} profile=${q(profile)}" }
                val res = con.pipeline(cmds, onProgress = { d, _ -> onProgress((base + d).coerceAtMost(grand), grand) })
                ok += res.ok; failed += res.failed
            }
            done += hotspot.size
            onProgress(done.coerceAtMost(grand), grand)
        }

        if (um.isNotEmpty()) {
            val isV7 = userManagerVariant(con) == UmVariant.V7
            if (isV7) {
                // صفوف الصلاحيات الحالية مرة واحدة — إعادة الربط تحتاج حذف القديم؛
                // مجرد set group لا يغيّر الباقة الفعلية في v7
                val existing = runCatching {
                    con.printLight("/user-manager/user-profile", ".id,user")
                }.getOrDefault(emptyList())
                // المرحلة A (أفضل-جهد، متدفّقة وحاصرة): set group + حذف صفوف الباقة
                // القديمة — تكتمل كلها قبل أي إضافة فلا يتداخل remove/add لنفس المستخدم
                val phaseA = buildList {
                    um.forEach { u ->
                        if (u.routerId.isNotBlank()) add("/user-manager/user/set .id=${u.routerId} group=${q(profile)}")
                        existing.filter { it["user"] == u.username }.forEach { row ->
                            row[".id"]?.let { add("/user-manager/user-profile/remove .id=$it") }
                        }
                    }
                }
                if (phaseA.isNotEmpty()) con.pipeline(phaseA, window = 48)
                // المرحلة B: ربط الباقة عبر user-profile — نجاحها هو نجاح الكرت في v7
                val base = done
                val addCmds = um.map { "/user-manager/user-profile/add user=${q(it.username)} profile=${q(profile)}" }
                val res = con.pipeline(
                    addCmds,
                    onProgress = { d, _ -> onProgress((base + d).coerceAtMost(grand), grand) },
                    treatErrorAsOk = { it.contains("already", true) },
                    window = 48,
                )
                ok += res.ok; failed += res.failed
            } else {
                // v6: create-and-activate بنافذة ضيقة (٤) فلا نخنق قاعدة UM؛
                // العميل يُحسب مرة واحدة لا لكل كرت (كان استعلاماً مكرراً لكل كرت)
                val customer = umCustomer(con)
                val base = done
                val v6Cmds = um.map {
                    "/tool/user-manager/user/create-and-activate-profile customer=${q(customer)} " +
                        "numbers=${q(it.username)} profile=${q(profile)}"
                }
                val res = con.pipeline(
                    v6Cmds,
                    onProgress = { d, _ -> onProgress((base + d).coerceAtMost(grand), grand) },
                    treatErrorAsOk = { it.contains("already", true) },
                    window = 4,
                )
                ok += res.ok; failed += res.failed
            }
            done += um.size
            onProgress(done.coerceAtMost(grand), grand)
        }
        BulkResult(ok, failed)
    }

    /** تصفير عدادات مجموعة كروت */
    suspend fun bulkResetCounters(
        r: RouterProfile?, cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        con.bulk(cards.filter { it.source != CardSource.USER_MANAGER }, onProgress) { u, _ ->
            if (u.routerId.isBlank()) null else "/ip/hotspot/user/reset-counters .id=${u.routerId}"
        }
    }

    /**
     * إرجاع الكروت غير مستهلكة: تصفير العدادات، ومسح علامة MIKHMON،
     * وإعادة الصلاحية الأصلية بدل صفر، وحذف الكوكيز حتى لا يعود الجهاز بجلسته القديمة.
     */
    suspend fun bulkResetToUnused(
        r: RouterProfile?, cards: List<UserEntry>, restoreValidity: String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        val names = cards.map { it.username }.toSet()
        runCatching {
            con.printLight("/ip/hotspot/cookie", ".id,user")
                .filter { it["user"] in names }
                .forEach { row -> row[".id"]?.let { runCatching { con.execute("/ip/hotspot/cookie/remove .id=$it") } } }
        }
        con.bulk(cards.filter { it.source != CardSource.USER_MANAGER }, onProgress) { u, _ ->
            if (u.routerId.isBlank()) return@bulk null
            runCatching { con.execute("/ip/hotspot/user/reset-counters .id=${u.routerId}") }
            // نُعيد الصلاحية المطلوبة: المحددة، أو الأصلية للكرت إن لم تكن علامة انتهاء
            val validity = restoreValidity.ifBlank {
                u.limitUptime.takeIf { it.isNotBlank() && it.trim() != "1s" } ?: ""
            }
            buildString {
                append("/ip/hotspot/user/set .id=${u.routerId} comment=\"\"")
                if (validity.isNotBlank()) append(" limit-uptime=${q(validity)}")
            }
        }
    }

    /** تغيير كلمة المرور لمجموعة كروت */
    suspend fun bulkSetPassword(
        r: RouterProfile?, cards: List<UserEntry>, password: (UserEntry) -> String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        con.bulk(cards, onProgress) { u, path ->
            if (u.routerId.isBlank()) null else "$path/set .id=${u.routerId} password=${q(password(u))}"
        }
    }

    /** تمديد صلاحية مجموعة كروت بإضافة مدة إلى الحد الحالي */
    suspend fun bulkExtendValidity(
        r: RouterProfile?, cards: List<UserEntry>, addSeconds: Long,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r, foreground = true) { con ->
        con.bulk(cards.filter { it.source != CardSource.USER_MANAGER }, onProgress) { u, _ ->
            if (u.routerId.isBlank()) null else {
                val current = parseUptime(u.limitUptime.takeIf { it.trim() != "1s" }.orEmpty())
                val next = formatUptime(current + addSeconds)
                "/ip/hotspot/user/set .id=${u.routerId} limit-uptime=${q(next)}"
            }
        }
    }

    /** تحويل ثوانٍ إلى صيغة مايكروتك 1d2h3m4s */
    fun formatUptime(seconds: Long): String {
        if (seconds <= 0) return "0s"
        val d = seconds / 86400
        val h = (seconds % 86400) / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return buildString {
            if (d > 0) append("${d}d")
            if (h > 0) append("${h}h")
            if (m > 0) append("${m}m")
            if (s > 0 || isEmpty()) append("${s}s")
        }
    }

    /** تصفير عدادات كرت واحد وإرجاعه غير مستهلك */
    suspend fun resetCard(r: RouterProfile?, user: UserEntry): Result<Unit> =
        bulkResetToUnused(r, listOf(user), "").mapCatching {
            if (it.failed > 0) error("رفض الراوتر إرجاع الكرت")
        }

    /** سجل الجلسات من سجل الراوتر (يحتاج تفعيل تسجيل الهوتسبوت) */
    suspend fun fetchLogHistory(r: RouterProfile?): Result<List<SessionEntry>> = onRouter(r) { con ->
        val rows = runCatching { con.execute("/log/print") }.getOrDefault(emptyList())
        rows.filter { (it["topics"] ?: "").contains("hotspot") }
            .mapNotNull { row ->
                val msg = row["message"] ?: return@mapNotNull null
                // "user1 (10.5.50.2): logged in" / "logged out: session-timeout, 1h2m3s, 45.6MiB, 12.3MiB"
                val name = msg.substringBefore(" (").takeIf { it.isNotBlank() && !it.contains(":") }
                    ?: return@mapNotNull null
                SessionEntry(
                    username = name,
                    address = msg.substringAfter("(", "").substringBefore(")", ""),
                    uptime = Regex("(\\d+[wdhms])+").find(msg.substringAfter("logged out", ""))?.value.orEmpty(),
                    startedAt = row["time"].orEmpty(),
                    endedAt = if (msg.contains("logged out")) row["time"].orEmpty() else "",
                    active = false,
                )
            }
            .reversed()
    }

    /** تفعيل حفظ سجل الهوتسبوت على الراوتر ليعمل سجل الجلسات */
    suspend fun enableHotspotLogging(r: RouterProfile?): Result<Unit> = onRouter(r) { con ->
        con.execute("/system/logging/add topics=hotspot action=disk")
        Unit
    }

    /** الأجهزة المتصلة: عملاء الواي فاي وحجوزات DHCP */
    suspend fun fetchConnectedDevices(r: RouterProfile?, foreground: Boolean = false): Result<List<SessionEntry>> = onRouter(r, foreground = foreground) { con ->
        val wireless = con.tryList(
            "/interface/wireless/registration-table/print",
            "/interface/wifi/registration-table/print",
        ).map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["interface"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                uptime = row["uptime"].orEmpty(),
                bytesIn = row["bytes"]?.substringBefore(",")?.toLongOrNull() ?: 0,
                startedAt = row["signal-strength"] ?: row["signal"].orEmpty(),
                active = true,
            )
        }
        val leases = con.tryList("/ip/dhcp-server/lease/print").map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["host-name"] ?: row["comment"].orEmpty(),
                address = row["address"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                startedAt = row["status"].orEmpty(),
                active = row["status"] == "bound",
            )
        }
        wireless + leases
    }

    /** حذف الكروت المنتهية أو المعطّلة من الهوتسبوت */
    suspend fun removeExpiredUsers(r: RouterProfile?): Result<Int> = onRouter(r, foreground = true) { con ->
        var removed = 0
        for (row in con.execute("/ip/hotspot/user/print")) {
            val id = row[".id"] ?: continue
            if ((row["name"] ?: "") == "default-trial") continue
            if (classify(row) == CardStatus.EXPIRED) {
                runCatching { con.execute("/ip/hotspot/user/remove .id=$id") }.onSuccess { removed++ }
            }
        }
        removed
    }

    /** حذف كرت واحد من الراوتر */
    suspend fun removeUser(r: RouterProfile?, user: UserEntry): Result<Unit> = onRouter(r) { con ->
        if (user.routerId.isBlank()) throw RouterLogicException("هذا الكرت غير موجود على الراوتر")
        val path = if (user.source == CardSource.USER_MANAGER) {
            umPath(userManagerVariant(con), "user") + "/remove"
        } else "/ip/hotspot/user/remove"
        con.execute("$path .id=${user.routerId}")
        Unit
    }

    /** حذف دفعة كاملة حسب وسم الملاحظة الذي كُتب عند التوليد */
    suspend fun removeBatchByComment(r: RouterProfile?, tag: String): Result<Int> = onRouter(r, foreground = true) { con ->
        var removed = 0
        for (row in con.execute("/ip/hotspot/user/print")) {
            if ((row["comment"] ?: "") != tag) continue
            val id = row[".id"] ?: continue
            runCatching { con.execute("/ip/hotspot/user/remove .id=$id") }.onSuccess { removed++ }
        }
        removed
    }

    /** تحويل صيغة مايكروتك للوقت (1w2d3h4m5s) إلى ثوانٍ */
    fun parseUptime(v: String): Long {
        if (v.isBlank()) return 0
        val re = Regex("(\\d+)([wdhms])")
        var total = 0L
        for (m in re.findAll(v)) {
            val n = m.groupValues[1].toLongOrNull() ?: 0
            total += when (m.groupValues[2]) {
                "w" -> n * 604800
                "d" -> n * 86400
                "h" -> n * 3600
                "m" -> n * 60
                else -> n
            }
        }
        // صيغة 00:15:32
        if (total == 0L && v.contains(":")) {
            val parts = v.split(":").mapNotNull { it.toLongOrNull() }
            if (parts.size == 3) total = parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return total
    }

    /** جلب المستخدمين المتصلين بصيغة ActiveUser (للوحة التحكم) */
    suspend fun fetchActiveUsers(r: RouterProfile?): Result<List<ActiveUser>> =
        fetchActiveSessions(r).map { list ->
            list.map {
                ActiveUser(
                    id = it.id, username = it.username, address = it.address,
                    macAddress = it.macAddress, uptime = it.uptime,
                    bytesIn = it.bytesIn, bytesOut = it.bytesOut,
                )
            }
        }

    // ===== إدارة الراوتر =====

    /** تعديل كرت واحد على الراوتر: كلمة المرور، الباقة، الملاحظة، والتعطيل */
    suspend fun updateCard(
        r: RouterProfile?,
        user: UserEntry,
        password: String? = null,
        profile: String? = null,
        comment: String? = null,
        limitUptime: String? = null,
    ): Result<Unit> = onRouter(r) { con ->
        if (user.routerId.isBlank()) error("لا يمكن تعديل هذا الكرت — لم يُجلب من الراوتر")
        if (user.source == CardSource.USER_MANAGER) {
            // اليوزر منجر: الحقول تختلف — group بدل profile، ولا يوجد limit-uptime
            val isV7 = userManagerVariant(con) == UmVariant.V7
            val path = umPath(if (isV7) UmVariant.V7 else UmVariant.V6, "user")
            val sets = buildString {
                password?.let { append(" password=${q(it)}") }
                comment?.let { append(" comment=${q(it)}") }
                if (isV7) profile?.takeIf { it.isNotBlank() }?.let { append(" group=${q(it)}") }
            }
            if (sets.isNotBlank()) con.execute("$path/set .id=${user.routerId}$sets")
            // تغيير الباقة الفعلية
            profile?.takeIf { it.isNotBlank() }?.let { p ->
                runCatching {
                    if (isV7) {
                        con.printLight("/user-manager/user-profile", ".id,user")
                            .filter { it["user"] == user.username }
                            .forEach { row -> row[".id"]?.let { con.execute("/user-manager/user-profile/remove .id=$it") } }
                        con.execute("/user-manager/user-profile/add user=${q(user.username)} profile=${q(p)}")
                    } else {
                        con.execute(
                            "/tool/user-manager/user/create-and-activate-profile customer=${q(umCustomer(con))} " +
                                "numbers=${q(user.username)} profile=${q(p)}"
                        )
                    }
                }
            }
        } else {
            val sets = buildString {
                password?.let { append(" password=${q(it)}") }
                profile?.let { append(" profile=${q(it)}") }
                comment?.let { append(" comment=${q(it)}") }
                limitUptime?.let { append(" limit-uptime=${q(it)}") }
            }
            if (sets.isNotBlank()) con.execute("/ip/hotspot/user/set .id=${user.routerId}$sets")
        }
    }

    /** قائمة عناوين DHCP الممنوحة — تكشف الأجهزة الموجودة على الشبكة */
    suspend fun fetchDhcpLeases(r: RouterProfile?): Result<List<DhcpLease>> = onRouter(r) { con ->
        con.tryPrintLight(
            ".id,address,mac-address,host-name,status,expires-after,dynamic,comment",
            "/ip/dhcp-server/lease",
        ).map { row ->
            DhcpLease(
                id = row[".id"].orEmpty(),
                address = row["address"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                hostName = row["host-name"].orEmpty(),
                status = row["status"].orEmpty(),
                expiresAfter = row["expires-after"].orEmpty(),
                dynamic = row["dynamic"] == "true",
                comment = row["comment"].orEmpty(),
            )
        }
    }

    /** المنافذ وحركة البيانات عليها */
    suspend fun fetchInterfaces(r: RouterProfile?): Result<List<InterfaceStat>> = onRouter(r) { con ->
        con.tryPrintLight(
            ".id,name,type,running,disabled,rx-byte,tx-byte",
            "/interface",
        ).map { row ->
            InterfaceStat(
                name = row["name"].orEmpty(),
                type = row["type"].orEmpty(),
                running = row["running"] == "true",
                disabled = row["disabled"] == "true",
                rxBytes = row["rx-byte"]?.toLongOrNull() ?: 0,
                txBytes = row["tx-byte"]?.toLongOrNull() ?: 0,
            )
        }
    }

    /** أجهزة محجوبة أو مثبّتة في الهوتسبوت (ip-binding) */
    suspend fun fetchIpBindings(r: RouterProfile?): Result<List<IpBinding>> = onRouter(r) { con ->
        con.tryPrintLight(
            ".id,mac-address,address,to-address,type,comment,disabled",
            "/ip/hotspot/ip-binding",
        ).map { row ->
            IpBinding(
                id = row[".id"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                address = row["address"].orEmpty(),
                type = row["type"].orEmpty(),
                comment = row["comment"].orEmpty(),
                disabled = row["disabled"] == "true",
            )
        }
    }

    /** حجب جهاز عن الشبكة بعنوانه الفيزيائي */
    suspend fun blockMac(r: RouterProfile?, mac: String, note: String = ""): Result<Unit> = onRouter(r) { con ->
        val comment = if (note.isBlank()) "" else " comment=${q(note)}"
        con.execute("/ip/hotspot/ip-binding/add mac-address=${q(mac)} type=blocked$comment")
        Unit
    }

    /** السماح لجهاز بالمرور بدون كرت */
    suspend fun bypassMac(r: RouterProfile?, mac: String, note: String = ""): Result<Unit> = onRouter(r) { con ->
        val comment = if (note.isBlank()) "" else " comment=${q(note)}"
        con.execute("/ip/hotspot/ip-binding/add mac-address=${q(mac)} type=bypassed$comment")
        Unit
    }

    suspend fun removeIpBinding(r: RouterProfile?, id: String): Result<Unit> = onRouter(r) { con ->
        con.execute("/ip/hotspot/ip-binding/remove .id=$id")
        Unit
    }

    /** حفظ نسخة احتياطية على ذاكرة الراوتر */
    suspend fun backupRouter(r: RouterProfile?, name: String): Result<String> = onRouter(r) { con ->
        con.execute("/system/backup/save name=${q(name)}")
        "$name.backup"
    }

    /** تصدير الإعدادات نصياً — يعيد الأسطر كما يرسلها الراوتر */
    suspend fun exportConfig(r: RouterProfile?): Result<String> = onRouter(r) { con ->
        val rows = runCatching { con.execute("/export") }.getOrElse { emptyList() }
        rows.joinToString("\n") { row -> row.values.joinToString(" ") }
    }

    /** إعادة تشغيل الراوتر */
    suspend fun rebootRouter(r: RouterProfile?): Result<Unit> = onRouter(r) { con ->
        runCatching { con.execute("/system/reboot") }
        Unit
    }

    /**
     * ربط الكرت بأول جهاز يستخدمه.
     *
     * الراوتر لا يفعل ذلك من نفسه، فنكتب سكربت on-login على بروفايل سيرفر الهوتسبوت:
     * عند أول دخول يُخزَّن عنوان الجهاز في الكرت، فلا يعمل الكرت على جهاز آخر بعدها.
     */
    /** علامة تُذيَّل بها السكربت لنعرف أنه من هذا التطبيق. تعليق في آخر السطر */
    private const val BIND_MARKER = "# cardmanager-bind-first"

    /**
     * سطر واحد لأن مُحلِّل مكتبة الـ API لا يقبل سطراً جديداً داخل قيمة.
     * ونتجنّب علامة التنصيص المفردة لأنها هي التي تُغلِّف القيمة.
     */
    private val bindScript: String = ":local usr ${'$'}user; " +
        ":local mac ${'$'}\"mac-address\"; " +
        ":if ([:len [/ip hotspot user find name=${'$'}usr]] > 0) do={ " +
        ":if ([:len [/ip hotspot user get [find name=${'$'}usr] mac-address]] = 0) do={ " +
        "/ip hotspot user set [find name=${'$'}usr] mac-address=${'$'}mac } }; " +
        BIND_MARKER

    /** نتيجة تشغيل الربط: كم بروفايل تغيّر وكم تُرك لأن عليه سكربت خاص */
    data class BindResult(val changed: Int, val skipped: Int, val total: Int)

    /** هل سكربت الربط مثبَّت على أي بروفايل سيرفر هوتسبوت؟ */
    suspend fun isBindFirstDeviceOn(r: RouterProfile?): Result<Boolean> = onRouter(r) { con ->
        con.tryPrintLight(".id,name,on-login", "/ip/hotspot/profile")
            .any { (it["on-login"] ?: "").contains(BIND_MARKER) }
    }

    /**
     * تشغيل أو إيقاف ربط الكرت بأول جهاز على بروفايلات سيرفر الهوتسبوت.
     * لا نلمس بروفايلاً عليه سكربت on-login من عندك — نتركه ونخبرك بعددها.
     */
    suspend fun setBindFirstDevice(r: RouterProfile?, enabled: Boolean): Result<BindResult> =
        onRouter(r) { con ->
            val profiles = con.tryPrintLight(".id,name,on-login", "/ip/hotspot/profile")
            if (profiles.isEmpty()) error("لا يوجد بروفايل سيرفر هوتسبوت على هذا الراوتر")
            var changed = 0
            var skipped = 0
            profiles.forEach { p ->
                val id = p[".id"].orEmpty()
                if (id.isBlank()) return@forEach
                val current = p["on-login"].orEmpty().trim()
                val hasOurs = current.contains(BIND_MARKER)
                val next: String? = when {
                    enabled && hasOurs -> null
                    enabled && current.isEmpty() -> bindScript
                    enabled -> { skipped++; null }   // عليه سكربت خاص — لا نمسحه
                    hasOurs -> ""
                    else -> null
                }
                if (next != null) {
                    val ok = runCatching {
                        con.execute("/ip/hotspot/profile/set .id=$id on-login='$next'")
                    }.isSuccess
                    if (ok) changed++
                }
            }
            BindResult(changed, skipped, profiles.size)
        }

    /** فك ربط الكروت المحددة بأجهزتها حتى تعمل على جهاز آخر */
    suspend fun clearBoundDevice(
        r: RouterProfile?,
        cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> = onRouter(r, foreground = true) { con ->
        var ok = 0
        cards.forEachIndexed { i, c ->
            if (c.routerId.isNotBlank()) {
                val done = runCatching {
                    con.execute("/ip/hotspot/user/set .id=${c.routerId} mac-address=\"\"")
                }.isSuccess
                if (done) ok++
            }
            onProgress(i + 1, cards.size)
        }
        ok
    }

    /** الخدمات المفعّلة (api، www، ssh…) — لتشخيص مشاكل الاتصال */
    suspend fun fetchServices(r: RouterProfile?): Result<List<Triple<String, String, Boolean>>> =
        onRouter(r) { con ->
            con.tryPrintLight("name,port,disabled", "/ip/service").map { row ->
                Triple(row["name"].orEmpty(), row["port"].orEmpty(), row["disabled"] != "true")
            }
        }

    /**
     * نقل كروت بين الهوتسبوت واليوزر منجر.
     * يُنشئ الكروت في الوجهة ثم يحذفها من المصدر إن طُلب ذلك.
     */
    suspend fun moveCards(
        r: RouterProfile?,
        cards: List<UserEntry>,
        to: UploadTarget,
        deleteFromSource: Boolean,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> {
        if (cards.isEmpty()) return Result.success(0)
        val created = java.util.Collections.synchronizedList(mutableListOf<UserEntry>())
        val create = when (to) {
            UploadTarget.HOTSPOT ->
                createHotspotUsers(r, cards, { d, t -> onProgress(d, t) }) { created.add(it) }
            UploadTarget.USER_MANAGER ->
                createUserManagerUsers(r, cards, { d, t -> onProgress(d, t) }) { created.add(it) }
        }
        create.onFailure { return Result.failure(it) }
        // لا نحذف من المصدر إلا ما نجح إنشاؤه فعلاً في الوجهة —
        // النسخة القديمة كانت تحذف الكل حتى الكروت التي فشل نقلها
        if (!deleteFromSource) return Result.success(created.size)
        var removed = 0
        created.forEach { c -> if (removeUser(r, c).isSuccess) removed++ }
        return Result.success(removed)
    }
}

/** عنوان DHCP ممنوح لجهاز */
data class DhcpLease(
    val id: String = "",
    val address: String = "",
    val macAddress: String = "",
    val hostName: String = "",
    val status: String = "",
    val expiresAfter: String = "",
    val dynamic: Boolean = true,
    val comment: String = "",
)

/** منفذ على الراوتر وحركة البيانات عليه */
data class InterfaceStat(
    val name: String = "",
    val type: String = "",
    val running: Boolean = false,
    val disabled: Boolean = false,
    val rxBytes: Long = 0,
    val txBytes: Long = 0,
)

/** ربط عنوان فيزيائي في الهوتسبوت — محجوب أو مسموح بدون كرت */
data class IpBinding(
    val id: String = "",
    val macAddress: String = "",
    val address: String = "",
    val type: String = "",
    val comment: String = "",
    val disabled: Boolean = false,
)
