package com.binwaps.cardmanager.license

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64

/** Device proof keys cannot be exported from Android Keystore. */
object DeviceIdentity {
    private const val ALIAS = "cardmanager.device.v2"
    @Synchronized private fun store(): KeyStore {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(ALIAS)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256).build())
            }.generateKeyPair()
        }
        return ks
    }
    fun publicKey(): String = Base64.getEncoder().encodeToString(store().getCertificate(ALIAS).publicKey.encoded)
    fun envelope(path: String, body: JSONObject): JSONObject {
        val ks = store()
        body.put("path", path).put("timestamp", System.currentTimeMillis())
        if (!body.has("nonce")) body.put("nonce", java.util.UUID.randomUUID().toString())
        val bytes = body.toString().toByteArray(Charsets.UTF_8)
        val signature = Signature.getInstance("SHA256withECDSA").apply {
            initSign(ks.getKey(ALIAS, null) as PrivateKey)
            update(bytes)
        }.sign()
        return JSONObject().put("payload", Base64.getEncoder().encodeToString(bytes))
            .put("signature", Base64.getEncoder().encodeToString(signature))
            .put("publicKey", Base64.getEncoder().encodeToString(ks.getCertificate(ALIAS).publicKey.encoded))
    }
}
