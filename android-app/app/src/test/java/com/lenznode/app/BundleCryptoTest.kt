package com.lenznode.app

import com.lenznode.app.runtime.BundleCrypto
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

class BundleCryptoTest {

    @Test
    fun `extracts xor-masked zip bundle accurately`() {
        val tempDir = Files.createTempDirectory("lenz-bundle-test").toFile()
        try {
            val sampleFiles = linkedMapOf(
                "panel/server.js" to "console.log('lenznode');".toByteArray(Charsets.UTF_8),
                "panel/public/index.html" to "<html><body>OK</body></html>".toByteArray(Charsets.UTF_8),
                "version.json" to "{\"version\":\"2.2.8\"}".toByteArray(Charsets.UTF_8)
            )
            val encrypted = BundleCrypto.packXorZipForTest(sampleFiles)
            val key = BundleCrypto.deriveKey("com.lenznode.app")

            val count = BundleCrypto.extractXorZip(ByteArrayInputStream(encrypted), tempDir, key)
            assertEquals(3, count)
            assertEquals("console.log('lenznode');", File(tempDir, "panel/server.js").readText())
            assertEquals("<html><body>OK</body></html>", File(tempDir, "panel/public/index.html").readText())
            assertEquals("{\"version\":\"2.2.8\"}", File(tempDir, "version.json").readText())
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test(expected = SecurityException::class)
    fun `rejects unexpected package name`() {
        BundleCrypto.verifyPackageName("com.fake.clone")
    }

    @Test(expected = SecurityException::class)
    fun `rejects zip path traversal entries`() {
        val tempDir = Files.createTempDirectory("lenz-bundle-traversal").toFile()
        try {
            val malicious = BundleCrypto.packXorZipForTest(
                mapOf("../../evil.txt" to "bad".toByteArray(Charsets.UTF_8))
            )
            val key = BundleCrypto.deriveKey("com.lenznode.app")
            BundleCrypto.extractXorZip(ByteArrayInputStream(malicious), tempDir, key)
        } finally {
            tempDir.deleteRecursively()
            assertTrue(true)
        }
    }

    @Test
    fun `syncs newer apk bundle without wiping auth-config and preserves newer ota version`() {
        val root = Files.createTempDirectory("lenz-sync-test").toFile()
        try {
            val bundleDir = File(root, "bundle").apply { mkdirs() }
            val targetDir = File(root, "rootfs-app").apply { mkdirs() }

            File(bundleDir, "panel").mkdirs()
            File(bundleDir, "panel/server.js").writeText("// v2.2.9")
            File(bundleDir, "panel/auth-config.json").writeText("{\"accessToken\":\"lnz_default\"}")
            File(bundleDir, "version.json").writeText("{\"version\":\"2.2.9\"}")

            File(targetDir, "panel").mkdirs()
            File(targetDir, "panel/server.js").writeText("// v2.2.8")
            File(targetDir, "panel/auth-config.json").writeText("{\"accessToken\":\"lnz_user_secret\"}")
            File(targetDir, "version.json").writeText("{\"version\":\"2.2.8\"}")

            // Newer APK bundle upgrades server.js and version.json, preserving auth-config.json
            val upgraded = BundleCrypto.syncBundleIfNewer(bundleDir, targetDir, "2.2.9")
            assertTrue(upgraded)
            assertEquals("// v2.2.9", File(targetDir, "panel/server.js").readText())
            assertEquals("{\"accessToken\":\"lnz_user_secret\"}", File(targetDir, "panel/auth-config.json").readText())
            assertEquals("{\"version\":\"2.2.9\"}", File(targetDir, "version.json").readText())

            // Simulate OTA update on device to 2.3.0 -> older 2.2.9 APK bundle must NOT overwrite it
            File(targetDir, "version.json").writeText("{\"version\":\"2.3.0\"}")
            File(targetDir, "panel/server.js").writeText("// v2.3.0-ota")
            val downgraded = BundleCrypto.syncBundleIfNewer(bundleDir, targetDir, "2.2.9")
            assertEquals(false, downgraded)
            assertEquals("// v2.3.0-ota", File(targetDir, "panel/server.js").readText())
        } finally {
            root.deleteRecursively()
        }
    }
}
