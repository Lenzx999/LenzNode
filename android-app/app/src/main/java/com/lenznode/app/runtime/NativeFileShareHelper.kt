package com.lenznode.app.runtime

import android.app.Activity
import android.content.Intent
import android.os.Environment
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object NativeFileShareHelper {

    fun resolveServerPath(
        filesDir: File,
        rawServerPath: String,
        externalStorageDir: File? = Environment.getExternalStorageDirectory()
    ): File {
        val trimmed = rawServerPath.trim()
        if (trimmed.isEmpty()) {
            throw SecurityException("Path berkas tidak boleh kosong.")
        }

        val normalizedInput = trimmed.replace('\\', '/')
        if (normalizedInput == "/sdcard" || normalizedInput.startsWith("/sdcard/")) {
            val sdRoot = externalStorageDir?.canonicalFile
                ?: throw SecurityException("Direktori penyimpanan eksternal tidak tersedia.")
            val relSd = normalizedInput.removePrefix("/sdcard").trimStart('/')
            val candidate = if (relSd.isEmpty()) sdRoot else File(sdRoot, relSd)
            val canonicalTarget = candidate.canonicalFile
            val sdPath = sdRoot.path
            val targetPath = canonicalTarget.path
            val sdPrefix = if (sdPath.endsWith(File.separator)) sdPath else sdPath + File.separator
            if (targetPath != sdPath && !targetPath.startsWith(sdPrefix)) {
                throw SecurityException("Akses path di luar penyimpanan eksternal ditolak: $rawServerPath")
            }
            return canonicalTarget
        }

        val rootfsDir = File(filesDir, "rootfs").canonicalFile
        val relative = when {
            normalizedInput == "/" -> ""
            normalizedInput.startsWith("/") -> normalizedInput.trimStart('/')
            normalizedInput.startsWith("~/") -> "root/" + normalizedInput.removePrefix("~/")
            normalizedInput == "~" -> "root"
            else -> "root/$normalizedInput"
        }

        val candidate = if (relative.isEmpty()) rootfsDir else File(rootfsDir, relative)
        val canonicalTarget = candidate.canonicalFile
        val rootPath = rootfsDir.path
        val targetPath = canonicalTarget.path
        val rootPrefix = if (rootPath.endsWith(File.separator)) rootPath else rootPath + File.separator
        if (targetPath != rootPath && !targetPath.startsWith(rootPrefix)) {
            throw SecurityException("Akses path di luar rootfs ditolak: $rawServerPath")
        }
        return canonicalTarget
    }

    fun detectMimeType(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase(Locale.US)
        if (ext.isEmpty()) return "application/octet-stream"
        return when (ext) {
            "txt", "log", "md", "sh", "conf", "yml", "yaml", "ini", "env" -> "text/plain"
            "json" -> "application/json"
            "js", "mjs", "cjs" -> "text/javascript"
            "html", "htm" -> "text/html"
            "css" -> "text/css"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "webp" -> "image/webp"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mpeg"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        }
    }

    fun prepareSharePayload(filesDir: File, cacheDir: File, rawServerPath: String): Pair<File, String> {
        val target = resolveServerPath(filesDir, rawServerPath)
        if (!target.exists()) {
            throw IllegalArgumentException("Berkas atau folder tidak ditemukan: ${target.name}")
        }

        val exportDir = File(cacheDir, "shared-exports").apply {
            if (!exists()) mkdirs()
        }
        cleanupOldExports(exportDir)

        return if (target.isDirectory) {
            val safeName = target.name.ifBlank { "folder" }.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val zipFile = File(exportDir, "$safeName.zip")
            if (zipFile.exists()) zipFile.delete()
            zipDirectory(target, zipFile)
            zipFile to "application/zip"
        } else {
            val mime = detectMimeType(target.name)
            target to mime
        }
    }

    fun shareServerPath(activity: Activity, rawServerPath: String): Result<String> {
        return try {
            val (shareFile, mimeType) = prepareSharePayload(
                filesDir = activity.filesDir,
                cacheDir = activity.cacheDir,
                rawServerPath = rawServerPath
            )
            val authority = "${activity.packageName}.fileprovider"
            val uri = FileProvider.getUriForFile(activity, authority, shareFile)

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, shareFile.name)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(sendIntent, "Bagikan berkas").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(chooser)
            Result.success(shareFile.name)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun zipDirectory(sourceDir: File, destZip: File) {
        val baseLen = sourceDir.canonicalPath.length + 1
        val buffer = ByteArray(16 * 1024)
        ZipOutputStream(FileOutputStream(destZip)).use { zos ->
            fun walk(dir: File) {
                val children = dir.listFiles() ?: return
                for (child in children) {
                    val rel = child.canonicalPath.substring(baseLen).replace('\\', '/')
                    if (child.isDirectory) {
                        zos.putNextEntry(ZipEntry("$rel/"))
                        zos.closeEntry()
                        walk(child)
                    } else if (child.isFile) {
                        zos.putNextEntry(ZipEntry(rel))
                        FileInputStream(child).use { fis ->
                            while (true) {
                                val read = fis.read(buffer)
                                if (read <= 0) break
                                zos.write(buffer, 0, read)
                            }
                        }
                        zos.closeEntry()
                    }
                }
            }
            walk(sourceDir)
        }
    }

    private fun cleanupOldExports(exportDir: File) {
        val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L
        exportDir.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }
}
