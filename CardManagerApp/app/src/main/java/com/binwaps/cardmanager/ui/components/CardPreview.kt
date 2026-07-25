package com.binwaps.cardmanager.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
import com.binwaps.cardmanager.ui.theme.Panel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

val sampleUser = UserEntry(
    username = "user1234",
    password = "8642",
    profile = "شهري 10 جيجا",
    price = "500",
    validity = "30d",
    serial = "0001",
)

/**
 * معاينة الكرت — تُرسم في خيط خلفي (لا تجمّد الواجهة ولا تُسقط التطبيق).
 * تعرض إطاراً فارغاً بنسبة الكرت حتى تجهز الصورة.
 */
@Composable
fun CardPreview(
    template: CardTemplate,
    user: UserEntry = sampleUser,
    widthPx: Int = 800,
    modifier: Modifier = Modifier,
) {
    val settings = Store.settings.value
    val bitmap by produceState<ImageBitmap?>(null, template, user, widthPx, settings) {
        value = withContext(Dispatchers.Default) {
            runCatching { CardRenderer.renderSafe(template, user, settings, widthPx).asImageBitmap() }.getOrNull()
        }
    }

    val ratio = (template.widthMm.coerceAtLeast(1f) / template.heightMm.coerceAtLeast(1f))
    val bmp = bitmap
    if (bmp != null) {
        Image(
            bitmap = bmp,
            contentDescription = null,
            modifier = modifier.fillMaxWidth(),
            contentScale = ContentScale.FillWidth,
        )
    } else {
        Box(
            modifier
                .fillMaxWidth()
                .aspectRatio(ratio)
                .background(Panel, RoundedCornerShape(8.dp)),
        )
    }
}
