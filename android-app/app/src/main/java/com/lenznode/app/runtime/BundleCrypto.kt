package com.lenznode.app.runtime

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object BundleCrypto {

    private const val EXPECTED_PACKAGE = "com.lenznode.app"
    private const val KEY_SUFFIX = ":LenzNode-APK-Bundle-v1"

    fun verifyPackageName(packageName: String) {
        if (packageName != EXPECTED_PACKAGE) {
            throw SecurityException("Verifikasi paket gagal: $packageName")
        }
    }

    fun deriveKey(packageName: String): ByteArray {
        val seed = "$packageName$KEY_SUFFIX".toByteArray(Charsets.UTF_8)
        return MessageDigest.getInstance("SHA-256").digest(seed)
    }

    fun transformXor(data: ByteArray, key: ByteArray, offset: Int = 0): ByteArray {
        val out = ByteArray(data.size)
        for (i in data.indices) {
            val mask = key[(offset + i) % key.size].toInt() and 0xFF
            out[i] = ((data[i].toInt() and 0xFF) xor mask).toByte()
        }
        return out
    }

    fun xorUnmaskStream(input: InputStream, key: ByteArray): InputStream {
        return object : FilterInputStream(input) {
            private var position = 0

            override fun read(): Int {
                val b = super.read()
                if (b == -1) return -1
                val mask = key[position % key.size].toInt() and 0xFF
                position++
                return (b xor mask) and 0xFF
            }

            override fun read(b: ByteArray, off: Int, len: Int): Int {
                val count = super.read(b, off, len)
                if (count <= 0) return count
                for (i in 0 until count) {
                    val mask = key[position % key.size].toInt() and 0xFF
                    b[off + i] = ((b[off + i].toInt() and 0xFF) xor mask).toByte()
                    position++
                }
                return count
            }
        }
    }

    fun extractXorZip(encryptedStream: InputStream, destDir: File, key: ByteArray): Int {
        if (!destDir.exists()) {
            destDir.mkdirs()
        }
        val baseCanonical = destDir.canonicalPath
        val basePrefix = if (baseCanonical.endsWith(File.separator)) baseCanonical else baseCanonical + File.separator
        var extractedFiles = 0

        ZipInputStream(xorUnmaskStream(encryptedStream, key)).use { zis ->
            var entry: ZipEntry?
            val buffer = ByteArray(16 * 1024)
            while (zis.nextEntry.also { entry = it } != null) {
                val current = entry ?: continue
                var relName = current.name.replace('\\', '/').trimStart('/')
                if (relName.startsWith("./")) {
                    relName = relName.removePrefix("./")
                }
                if (relName.startsWith("lenznode-bundle/")) {
                    relName = relName.removePrefix("lenznode-bundle/")
                }
                if (relName.isBlank()) {
                    zis.closeEntry()
                    continue
                }

                val targetFile = File(destDir, relName)
                val targetCanonical = targetFile.canonicalPath
                if (targetCanonical != baseCanonical && !targetCanonical.startsWith(basePrefix)) {
                    throw SecurityException("Entri ZIP tidak sah (path traversal): ${current.name}")
                }

                if (current.isDirectory) {
                    targetFile.mkdirs()
                } else {
                    targetFile.parentFile?.mkdirs()
                    FileOutputStream(targetFile).use { fos ->
                        while (true) {
                            val read = zis.read(buffer)
                            if (read <= 0) break
                            fos.write(buffer, 0, read)
                        }
                    }
                    extractedFiles++
                }
                zis.closeEntry()
            }
        }
        return extractedFiles
    }

    fun packXorZipForTest(entries: Map<String, ByteArray>, packageName: String = EXPECTED_PACKAGE): ByteArray {
        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zos ->
            for ((path, content) in entries) {
                zos.putNextEntry(ZipEntry(path))
                zos.write(content)
                zos.closeEntry()
            }
        }
        val key = deriveKey(packageName)
        return transformXor(baos.toByteArray(), key)
    }

    private val PRESERVED_PANEL_FILES = setOf(
        "panel/auth-config.json",
        "panel/vps-config.json",
        "panel/sessions.json",
        "panel/state.json",
        "panel/root-config.json"
    )

    fun extractVersionFromJson(jsonText: String): String? {
        val match = Regex("\"version\"\\s*:\\s*\"([^\"]+)\"").find(jsonText) ?: return null
        return match.groupValues[1].trim().takeIf { it.isNotEmpty() }
    }

    fun compareSemver(a: String, b: String): Int {
        val pa = a.trim().removePrefix("v").split('.').map { it.takeWhile(Char::isDigit).toIntOrNull() ?: 0 }
        val pb = b.trim().removePrefix("v").split('.').map { it.takeWhile(Char::isDigit).toIntOrNull() ?: 0 }
        val maxLen = maxOf(pa.size, pb.size)
        for (i in 0 until maxLen) {
            val va = pa.getOrElse(i) { 0 }
            val vb = pb.getOrElse(i) { 0 }
            if (va != vb) return va.compareTo(vb)
        }
        return 0
    }

    fun syncBundleIfNewer(bundleDir: File, targetAppDir: File, fallbackBundleVersion: String): Boolean {
        val bundlePanel = File(bundleDir, "panel/server.js")
        val targetPanel = File(targetAppDir, "panel/server.js")
        if (!bundlePanel.exists() || !targetPanel.exists()) return false

        val bundleVersion = File(bundleDir, "version.json").takeIf { it.exists() }
            ?.let { extractVersionFromJson(it.readText()) }
            ?: fallbackBundleVersion

        val installedVersion = File(targetAppDir, "version.json").takeIf { it.exists() }
            ?.let { extractVersionFromJson(it.readText()) }
            ?: "0.0.0"

        if (compareSemver(bundleVersion, installedVersion) <= 0) {
            return false
        }

        val itemsToCopy = listOf("panel", "apps", "scripts", "version.json", "CHANGELOG.md")
        for (item in itemsToCopy) {
            val src = File(bundleDir, item)
            if (!src.exists()) continue
            copyPreservingConfigs(src, File(targetAppDir, item), item)
        }
        return true
    }

    private fun copyPreservingConfigs(src: File, dest: File, relPath: String) {
        val normalizedRel = relPath.replace('\\', '/')
        if (src.isDirectory) {
            if (!dest.exists()) dest.mkdirs()
            src.listFiles()?.forEach { child ->
                copyPreservingConfigs(child, File(dest, child.name), "$normalizedRel/${child.name}")
            }
            return
        }
        if (normalizedRel in PRESERVED_PANEL_FILES && dest.exists()) {
            return
        }
        dest.parentFile?.mkdirs()
        src.copyTo(dest, overwrite = true)
        if (dest.name.endsWith(".sh")) {
            dest.setExecutable(true, false)
        }
    }
}
