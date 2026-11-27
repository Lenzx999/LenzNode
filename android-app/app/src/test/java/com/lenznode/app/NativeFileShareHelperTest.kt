package com.lenznode.app

import com.lenznode.app.runtime.NativeFileShareHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipFile

class NativeFileShareHelperTest {

    @Test
    fun `maps server paths safely into rootfs and blocks traversal`() {
        val base = Files.createTempDirectory("lenz-share-path-test").toFile()
        try {
            val filesDir = File(base, "files").apply { mkdirs() }
            val workspace = File(filesDir, "rootfs/root/workspace").apply { mkdirs() }
            val sample = File(workspace, "hello.txt").apply { writeText("halo") }

            val resolvedAbs = NativeFileShareHelper.resolveServerPath(filesDir, "/root/workspace/hello.txt")
            assertEquals(sample.canonicalPath, resolvedAbs.canonicalPath)

            val resolvedHome = NativeFileShareHelper.resolveServerPath(filesDir, "~/workspace/hello.txt")
            assertEquals(sample.canonicalPath, resolvedHome.canonicalPath)

            val sdcardDir = File(base, "sdcard").apply { mkdirs() }
            val sdFile = File(sdcardDir, "Download/doc.pdf").apply {
                parentFile?.mkdirs()
                writeText("pdf")
            }
            val resolvedSd = NativeFileShareHelper.resolveServerPath(
                filesDir,
                "/sdcard/Download/doc.pdf",
                externalStorageDir = sdcardDir
            )
            assertEquals(sdFile.canonicalPath, resolvedSd.canonicalPath)
        } finally {
            base.deleteRecursively()
        }
    }

    @Test(expected = SecurityException::class)
    fun `rejects traversal outside sdcard`() {
        val base = Files.createTempDirectory("lenz-share-sd-traversal-test").toFile()
        try {
            val filesDir = File(base, "files").apply { mkdirs() }
            val sdcardDir = File(base, "sdcard").apply { mkdirs() }
            NativeFileShareHelper.resolveServerPath(
                filesDir,
                "/sdcard/../../secret.txt",
                externalStorageDir = sdcardDir
            )
        } finally {
            base.deleteRecursively()
        }
    }

    @Test(expected = SecurityException::class)
    fun `rejects traversal outside rootfs`() {
        val base = Files.createTempDirectory("lenz-share-traversal-test").toFile()
        try {
            val filesDir = File(base, "files").apply { mkdirs() }
            File(filesDir, "rootfs").mkdirs()
            NativeFileShareHelper.resolveServerPath(filesDir, "/root/../../secret.txt")
        } finally {
            base.deleteRecursively()
        }
    }

    @Test
    fun `prepares file directly and zips directory into shared-exports`() {
        val base = Files.createTempDirectory("lenz-share-zip-test").toFile()
        try {
            val filesDir = File(base, "files").apply { mkdirs() }
            val cacheDir = File(base, "cache").apply { mkdirs() }
            val projectDir = File(filesDir, "rootfs/root/workspace/my-app").apply { mkdirs() }
            File(projectDir, "index.js").writeText("console.log(1);")
            File(projectDir, "sub").mkdirs()
            File(projectDir, "sub/readme.md").writeText("# App")

            val (fileTarget, fileMime) = NativeFileShareHelper.prepareSharePayload(
                filesDir,
                cacheDir,
                "/root/workspace/my-app/index.js"
            )
            assertEquals("index.js", fileTarget.name)
            assertEquals("text/javascript", fileMime)

            val (zipTarget, zipMime) = NativeFileShareHelper.prepareSharePayload(
                filesDir,
                cacheDir,
                "/root/workspace/my-app"
            )
            assertEquals("my-app.zip", zipTarget.name)
            assertEquals("application/zip", zipMime)
            assertTrue(zipTarget.exists())

            ZipFile(zipTarget).use { zf ->
                val names = zf.entries().toList().map { it.name }
                assertTrue(names.contains("index.js"))
                assertTrue(names.contains("sub/readme.md"))
            }
        } finally {
            base.deleteRecursively()
        }
    }
}
