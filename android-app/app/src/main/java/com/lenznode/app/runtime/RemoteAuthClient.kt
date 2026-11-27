package com.lenznode.app.runtime

import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI

data class RemoteAuthResult(
    val ok: Boolean,
    val normalizedUrl: String,
    val sessionCookieName: String? = null,
    val sessionCookieValue: String? = null,
    val rawSetCookie: String? = null,
    val message: String = "",
    val httpStatus: Int = 0
) {
    fun webViewCookieHeader(): String? {
        if (sessionCookieName.isNullOrBlank() || sessionCookieValue.isNullOrBlank()) return null
        return "$sessionCookieName=$sessionCookieValue; Path=/"
    }
}

object RemoteAuthHelper {

    private val IPV4_REGEX = Regex("^\\d{1,3}(?:\\.\\d{1,3}){3}$")

    fun normalizeBaseUrl(rawInput: String): String {
        val trimmed = rawInput.trim()
        if (trimmed.isEmpty()) {
            throw IllegalArgumentException("Alamat server tidak boleh kosong.")
        }

        val withScheme = if (trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true)
        ) {
            trimmed
        } else {
            val hostPart = trimmed.substringBefore('/').substringBefore(':')
            val isLocalHost = isLocalAddress(hostPart) || trimmed.substringBefore('/').contains(':')
            if (isLocalHost) "http://$trimmed" else "https://$trimmed"
        }

        val parsed = try {
            URI(withScheme)
        } catch (e: Exception) {
            throw IllegalArgumentException("Format URL server tidak valid: ${e.message}")
        }

        val scheme = (parsed.scheme ?: "").lowercase()
        if (scheme != "http" && scheme != "https") {
            throw IllegalArgumentException("Skema URL harus http:// atau https://")
        }

        val host = parsed.host?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Host atau IP server tidak valid.")

        val port = parsed.port
        val resolvedPort = if (port == -1 && scheme == "http" && isLocalAddress(host)) {
            8080
        } else {
            port
        }

        val authority = if (resolvedPort != -1) "$host:$resolvedPort" else host
        val cleanPath = (parsed.rawPath ?: "").trimEnd('/')
        return "$scheme://$authority$cleanPath"
    }

    fun isLocalAddress(host: String): Boolean {
        val lower = host.trim().lowercase()
        if (lower == "localhost" || lower.endsWith(".local")) return true
        if (IPV4_REGEX.matches(lower)) return true
        return false
    }

    fun parseSessionCookie(
        setCookieHeaders: List<String>,
        expectedCookieName: String = "lenz_session"
    ): Pair<String, String>? {
        for (header in setCookieHeaders) {
            val firstSegment = header.substringBefore(';').trim()
            val eqIdx = firstSegment.indexOf('=')
            if (eqIdx <= 0) continue
            val name = firstSegment.substring(0, eqIdx).trim()
            val value = firstSegment.substring(eqIdx + 1).trim()
            if (name == expectedCookieName && value.isNotEmpty()) {
                return name to value
            }
        }
        return null
    }

    fun buildTokenPayload(token: String): String {
        val escaped = NativeBridgeJson.escapeJson(token.trim())
        return "{\"token\":\"$escaped\"}"
    }
}

class RemoteAuthClient {

    fun connect(rawUrl: String, rawToken: String): RemoteAuthResult = authenticate(rawUrl, rawToken)

    fun authenticate(rawUrl: String, rawToken: String): RemoteAuthResult {
        val token = rawToken.trim()
        if (token.isEmpty()) {
            return RemoteAuthResult(
                ok = false,
                normalizedUrl = rawUrl.trim(),
                message = "Token akses wajib diisi."
            )
        }

        val baseUrl = try {
            RemoteAuthHelper.normalizeBaseUrl(rawUrl)
        } catch (e: IllegalArgumentException) {
            return RemoteAuthResult(
                ok = false,
                normalizedUrl = rawUrl.trim(),
                message = e.message ?: "Alamat server tidak valid."
            )
        }

        val endpoint = "$baseUrl/api/auth/token"
        var conn: HttpURLConnection? = null
        return try {
            conn = (URI.create(endpoint).toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                instanceFollowRedirects = false
                connectTimeout = 10_000
                readTimeout = 12_000
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("X-Lenz-Token", token)
            }

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(RemoteAuthHelper.buildTokenPayload(token))
                writer.flush()
            }

            val status = conn.responseCode
            val stream = if (status in 200..399) conn.inputStream else conn.errorStream
            val bodyText = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()

            val setCookieHeaders = mutableListOf<String>()
            for ((headerName, values) in conn.headerFields) {
                if (headerName != null && headerName.equals("Set-Cookie", ignoreCase = true)) {
                    setCookieHeaders.addAll(values)
                }
            }
            val parsedCookie = RemoteAuthHelper.parseSessionCookie(setCookieHeaders)

            val jsonMap = NativeBridgeJson.parseJsonParams(bodyText)
            val serverOk = when (jsonMap["ok"]?.lowercase()) {
                "true" -> true
                "false" -> false
                else -> status in 200..299
            }
            val serverMsg = jsonMap["message"]?.takeIf { it.isNotBlank() }
                ?: jsonMap["error"]?.takeIf { it.isNotBlank() }

            if (status in 200..299 && serverOk && parsedCookie != null) {
                RemoteAuthResult(
                    ok = true,
                    normalizedUrl = baseUrl,
                    sessionCookieName = parsedCookie.first,
                    sessionCookieValue = parsedCookie.second,
                    rawSetCookie = "${parsedCookie.first}=${parsedCookie.second}; Path=/",
                    message = serverMsg ?: "Terhubung ke server LenzNode.",
                    httpStatus = status
                )
            } else {
                val friendlyError = when {
                    status == 401 || status == 403 -> serverMsg ?: "Token akses tidak valid atau sudah diperbarui."
                    status == 429 -> serverMsg ?: "Terlalu banyak percobaan login. Coba lagi sebentar."
                    status in 200..299 && parsedCookie == null -> "Server tidak mengembalikan cookie sesi."
                    else -> serverMsg ?: "Gagal terhubung ke server (HTTP $status)."
                }
                RemoteAuthResult(
                    ok = false,
                    normalizedUrl = baseUrl,
                    message = friendlyError,
                    httpStatus = status
                )
            }
        } catch (e: Exception) {
            RemoteAuthResult(
                ok = false,
                normalizedUrl = baseUrl,
                message = "Tidak dapat menjangkau server ($baseUrl): ${e.message ?: "koneksi gagal"}"
            )
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }
}
