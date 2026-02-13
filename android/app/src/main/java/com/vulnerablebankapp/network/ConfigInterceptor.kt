package com.vulnerablebankapp.network

import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException
import java.security.MessageDigest
import java.security.cert.X509Certificate
import android.util.Base64

/**
 * OkHttp interceptor that validates SPKI pin on every request.
 * Acts as second validation layer — even if JS-side check is hooked,
 * this interceptor runs at the network level inside OkHttp.
 *
 * Obfuscated as "ConfigInterceptor" to avoid obvious naming.
 */
class ConfigInterceptor(
    private val pinnedDomain: String,
    private val pinnedHash: String
) : Interceptor {

    @Throws(IOException::class)
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val host = request.url.host

        // Only validate requests to the pinned domain
        if (!host.equals(pinnedDomain, ignoreCase = true)) {
            return chain.proceed(request)
        }

        // Proceed with the request to establish TLS handshake
        val response = chain.proceed(request)

        // Extract the leaf certificate from the TLS handshake
        val handshake = response.handshake
            ?: throw IOException("DataSync: Configuration unavailable")

        val certs = handshake.peerCertificates
        if (certs.isEmpty()) {
            throw IOException("DataSync: Configuration missing")
        }

        val leafCert = certs[0] as? X509Certificate
            ?: throw IOException("DataSync: Configuration format error")

        // Compute SPKI hash of the leaf certificate
        val spkiHash = computeSpkiHash(leafCert)

        if (spkiHash != pinnedHash) {
            // Close the response body to prevent resource leak
            response.body?.close()
            throw IOException("DataSync: Configuration mismatch")
        }

        return response
    }

    private fun computeSpkiHash(cert: X509Certificate): String {
        val spki = cert.publicKey.encoded
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(spki)
        return Base64.encodeToString(hash, Base64.NO_WRAP)
    }
}
