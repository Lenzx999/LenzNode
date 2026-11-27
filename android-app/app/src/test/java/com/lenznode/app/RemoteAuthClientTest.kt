package com.lenznode.app

import com.lenznode.app.runtime.RemoteAuthClient
import com.lenznode.app.runtime.RemoteAuthHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

class RemoteAuthClientTest {

    @Test
    fun `normalizes LAN IPv4, localhost, custom ports, and HTTPS tunnel URLs`() {
        assertEquals("http://192.168.1.25:8080", RemoteAuthHelper.normalizeBaseUrl("192.168.1.25"))
        assertEquals("http://192.168.1.25:8080", RemoteAuthHelper.normalizeBaseUrl("http://192.168.1.25/"))
        assertEquals("http://192.168.1.25:9090", RemoteAuthHelper.normalizeBaseUrl("192.168.1.25:9090/"))
        assertEquals("http://localhost:8080", RemoteAuthHelper.normalizeBaseUrl("localhost"))
        assertEquals("https://agent.lenznity.my.id", RemoteAuthHelper.normalizeBaseUrl("agent.lenznity.my.id/"))
        assertEquals("https://demo-tunnel.trycloudflare.com", RemoteAuthHelper.normalizeBaseUrl("https://demo-tunnel.trycloudflare.com/"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rejects empty URL`() {
        RemoteAuthHelper.normalizeBaseUrl("   ")
    }

    @Test
    fun `parses lenz_session cookie from Set-Cookie headers`() {
        val parsed = RemoteAuthHelper.parseSessionCookie(
            listOf(
                "other=abc; Path=/",
                "lenz_session=sess_1234567890abcdef; Path=/; HttpOnly; SameSite=Lax"
            )
        )
        assertNotNull(parsed)
        assertEquals("lenz_session", parsed!!.first)
        assertEquals("sess_1234567890abcdef", parsed.second)

        assertNull(RemoteAuthHelper.parseSessionCookie(listOf("other=abc; Path=/")))
    }

    @Test
    fun `authenticates against local HTTP server and captures session cookie`() {
        val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        val port = server.localPort
        val serverThread = thread(isDaemon = true) {
            for (i in 0 until 2) {
                val client = server.accept()
                client.use { sock ->
                    val reader = BufferedReader(InputStreamReader(sock.getInputStream(), Charsets.UTF_8))
                    var contentLen = 0
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (line.isEmpty()) break
                        if (line.startsWith("Content-Length:", ignoreCase = true)) {
                            contentLen = line.substringAfter(':').trim().toIntOrNull() ?: 0
                        }
                    }
                    val bodyChars = CharArray(contentLen)
                    var readTotal = 0
                    while (readTotal < contentLen) {
                        val r = reader.read(bodyChars, readTotal, contentLen - readTotal)
                        if (r <= 0) break
                        readTotal += r
                    }
                    val reqBody = String(bodyChars, 0, readTotal)
                    val out = sock.getOutputStream()
                    if (reqBody.contains("lnz_validtoken123")) {
                        val resp = "{\"ok\":true,\"message\":\"Login berhasil\"}"
                        val headers = "HTTP/1.1 200 OK\r\n" +
                            "Content-Type: application/json\r\n" +
                            "Set-Cookie: lenz_session=tok_abc987; Path=/; HttpOnly\r\n" +
                            "Content-Length: ${resp.toByteArray().size}\r\n" +
                            "Connection: close\r\n\r\n"
                        out.write(headers.toByteArray(Charsets.US_ASCII))
                        out.write(resp.toByteArray(Charsets.UTF_8))
                    } else {
                        val resp = "{\"ok\":false,\"message\":\"Token salah\"}"
                        val headers = "HTTP/1.1 401 Unauthorized\r\n" +
                            "Content-Type: application/json\r\n" +
                            "Content-Length: ${resp.toByteArray().size}\r\n" +
                            "Connection: close\r\n\r\n"
                        out.write(headers.toByteArray(Charsets.US_ASCII))
                        out.write(resp.toByteArray(Charsets.UTF_8))
                    }
                    out.flush()
                }
            }
        }

        try {
            val client = RemoteAuthClient()

            val okRes = client.authenticate("127.0.0.1:$port", "lnz_validtoken123")
            assertTrue(okRes.ok)
            assertEquals("http://127.0.0.1:$port", okRes.normalizedUrl)
            assertEquals("lenz_session", okRes.sessionCookieName)
            assertEquals("tok_abc987", okRes.sessionCookieValue)
            assertEquals("lenz_session=tok_abc987; Path=/", okRes.webViewCookieHeader())

            val badRes = client.authenticate("http://127.0.0.1:$port", "lnz_wrong")
            assertFalse(badRes.ok)
            assertEquals(401, badRes.httpStatus)
            assertEquals("Token salah", badRes.message)

            val emptyTokenRes = client.authenticate("http://127.0.0.1:$port", "   ")
            assertFalse(emptyTokenRes.ok)
        } finally {
            server.close()
            serverThread.join(1000)
        }
    }
}
