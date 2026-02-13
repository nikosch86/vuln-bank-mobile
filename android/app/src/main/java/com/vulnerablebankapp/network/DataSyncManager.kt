package com.vulnerablebankapp.network

import android.util.Base64
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.modules.network.OkHttpClientProvider
import okhttp3.OkHttpClient
import java.net.URL
import java.security.MessageDigest
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection

/**
 * Native module for SPKI certificate pinning with obfuscated naming.
 *
 * "DataSyncManager" is deliberately misleading — this is the core
 * certificate pinner. Naming obfuscation makes it harder for attackers
 * to identify which native methods to hook.
 *
 * Dual-layer validation:
 *   1. ensureConfigSync() — real validation via HttpsURLConnection (separate TLS stack)
 *   2. ConfigInterceptor — OkHttp interceptor validates every request at network level
 *
 * Decoy functions:
 *   - validateCertificate() — honeypot that looks real but doesn't affect session integrity
 *   - checkSSLPinning() / verifyCertificateChain() — stubs that always resolve true
 */
class DataSyncManager(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "DataSyncManager"

    // Session integrity — sticky flag, once false stays false for app lifecycle
    @Volatile
    private var sessionIntegrity: Boolean = true

    // Metrics tracking
    private var validationCount: Int = 0
    private var lastValidationTimestamp: Long = 0L
    private var interceptorInstalled: Boolean = false

    /**
     * REAL validation — opens a separate HttpsURLConnection to verify SPKI hash.
     * Uses a different TLS stack than OkHttp, so hooking OkHttp alone won't bypass this.
     * Includes timing check: if this function returns in < 50ms, it was likely hooked
     * to skip the actual TLS handshake.
     */
    @ReactMethod
    fun ensureConfigSync(domain: String, pinHash: String, promise: Promise) {
        val startTime = System.nanoTime()

        Thread {
            try {
                // Install OkHttp interceptor on first call
                installInterceptorIfNeeded(domain, pinHash)

                val url = URL("https://$domain")
                val connection = url.openConnection() as HttpsURLConnection
                connection.connectTimeout = 10000
                connection.readTimeout = 10000
                connection.requestMethod = "HEAD"
                connection.instanceFollowRedirects = false

                try {
                    connection.connect()

                    val certs = connection.serverCertificates
                    if (certs.isEmpty()) {
                        sessionIntegrity = false
                        promise.reject("CONFIG_ERROR", "DataSync: No configuration available")
                        return@Thread
                    }

                    val leafCert = certs[0] as? X509Certificate
                    if (leafCert == null) {
                        sessionIntegrity = false
                        promise.reject("CONFIG_ERROR", "DataSync: Configuration format error")
                        return@Thread
                    }

                    val spkiHash = computeSpkiHash(leafCert)

                    if (spkiHash != pinHash) {
                        sessionIntegrity = false
                        promise.reject("CONFIG_MISMATCH", "DataSync: Configuration mismatch")
                        return@Thread
                    }

                    // Timing check — real TLS handshake takes > 50ms
                    val elapsedMs = (System.nanoTime() - startTime) / 1_000_000
                    if (elapsedMs < 50) {
                        sessionIntegrity = false
                        promise.reject("CONFIG_ERROR", "DataSync: Sync timing anomaly")
                        return@Thread
                    }

                    validationCount++
                    lastValidationTimestamp = System.currentTimeMillis()
                    promise.resolve(true)
                } finally {
                    connection.disconnect()
                }
            } catch (e: Exception) {
                sessionIntegrity = false
                promise.reject("CONFIG_ERROR", "DataSync: Sync failed - ${e.message}")
            }
        }.start()
    }

    /**
     * DECOY — honeypot function that looks like a real certificate validator.
     * Does a real TLS connection to look authentic, but does NOT affect sessionIntegrity.
     * If an attacker hooks this to skip validation, the real checks (ensureConfigSync
     * and ConfigInterceptor) still catch mismatches.
     * If hooked to return immediately, timing anomaly is detectable.
     */
    @ReactMethod
    fun validateCertificate(domain: String, promise: Promise) {
        Thread {
            try {
                val url = URL("https://$domain")
                val connection = url.openConnection() as HttpsURLConnection
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.requestMethod = "HEAD"
                connection.instanceFollowRedirects = false

                try {
                    connection.connect()
                    val certs = connection.serverCertificates
                    promise.resolve(certs.isNotEmpty())
                } finally {
                    connection.disconnect()
                }
            } catch (e: Exception) {
                // Decoy: resolve true even on failure to look like a bypassable check
                promise.resolve(true)
            }
        }.start()
    }

    /**
     * DECOY — stub that always resolves true.
     * Obvious target name for automated Frida scripts looking for SSL pinning methods.
     */
    @ReactMethod
    fun checkSSLPinning(promise: Promise) {
        promise.resolve(true)
    }

    /**
     * DECOY — stub that always resolves true.
     * Another obvious target name for attackers.
     */
    @ReactMethod
    fun verifyCertificateChain(promise: Promise) {
        promise.resolve(true)
    }

    /**
     * Returns metrics for background monitoring.
     * JS side can periodically check sessionIntegrity.
     */
    @ReactMethod
    fun getConnectionMetrics(promise: Promise) {
        val metrics = WritableNativeMap()
        metrics.putInt("validationCount", validationCount)
        metrics.putDouble("lastTimestamp", lastValidationTimestamp.toDouble())
        metrics.putBoolean("sessionIntegrity", sessionIntegrity)
        promise.resolve(metrics)
    }

    private fun computeSpkiHash(cert: X509Certificate): String {
        val spki = cert.publicKey.encoded
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(spki)
        return Base64.encodeToString(hash, Base64.NO_WRAP)
    }

    /**
     * Install ConfigInterceptor into React Native's OkHttp client.
     * Only runs once per app lifecycle.
     */
    @Synchronized
    private fun installInterceptorIfNeeded(domain: String, pinHash: String) {
        if (interceptorInstalled) return

        val interceptor = ConfigInterceptor(domain, pinHash)

        OkHttpClientProvider.setOkHttpClientFactory {
            OkHttpClientProvider.createClientBuilder()
                .addInterceptor(interceptor)
                .build()
        }

        interceptorInstalled = true
    }
}
