package com.lenznode.app.runtime

import android.content.Context
import android.content.res.AssetManager
import android.os.Build
import com.lenznode.app.BuildConfig
import com.lenznode.app.model.AbiHelper
import com.lenznode.app.model.ProgressParser
import com.lenznode.app.model.ProgressUpdate
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

class RootfsManager(private val context: Context) {

    val filesDir: File = context.filesDir
    val nativeLibDir: String = context.applicationInfo.nativeLibraryDir
    val bootstrapDir: File = File(filesDir, "bootstrap")
    val bundleDir: File = File(filesDir, "lenznode-bundle")
    val rootfsDir: File = File(filesDir, "rootfs")
    val tmpDir: File = File(filesDir, "tmp")
    val cacheDir: File = File(filesDir, "cache")
    val homeDir: File = File(filesDir, "home")
    val logsDir: File = File(filesDir, "logs")

    private val bootstrapMarker: File
        get() = File(rootfsDir, ".lenznode_bootstrapped")

    private val readyMarker: File
        get() = File(rootfsDir, "root/.lenznode-ready")

    private val rootfsPanelEntry: File
        get() = File(rootfsDir, "root/LenzNode/panel/server.js")

    private val bundleVersionFile: File
        get() = File(bundleDir, ".bundle_version")

    fun resolveLinuxArch(): String {
        val abi = AbiHelper.resolvePrimaryAbi(Build.SUPPORTED_ABIS ?: emptyArray())
        return AbiHelper.resolveLinuxArch(abi)
    }

    fun isBootstrapped(): Boolean {
        return (bootstrapMarker.exists() || readyMarker.exists()) && rootfsPanelEntry.exists()
    }

    fun ensureDirectories() {
        listOf(bootstrapDir, bundleDir, tmpDir, cacheDir, homeDir, logsDir).forEach { dir ->
            if (!dir.exists()) {
                dir.mkdirs()
            }
        }
    }

    fun extractAssetsIfNeeded(force: Boolean = false) {
        ensureDirectories()
        copyAssetTree(context.assets, "bootstrap", bootstrapDir)
        bootstrapDir.listFiles()?.forEach { file ->
            if (file.name.endsWith(".sh")) {
                file.setExecutable(true, false)
            }
        }

        @Suppress("DEPRECATION")
        val lastUpdateTime = try {
            context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
        } catch (_: Exception) {
            0L
        }
        val currentVersion = "${BuildConfig.VERSION_NAME}-${BuildConfig.VERSION_CODE}-$lastUpdateTime"
        val installedVersion = if (bundleVersionFile.exists()) bundleVersionFile.readText().trim() else ""
        val bundlePanel = File(bundleDir, "panel/server.js")

        if (force || installedVersion != currentVersion || !bundlePanel.exists()) {
            if (bundleDir.exists()) {
                bundleDir.deleteRecursively()
            }
            bundleDir.mkdirs()

            val hasEncryptedBundle = try {
                context.assets.list("")?.contains("lenznode-bundle.dat") == true
            } catch (_: Exception) {
                false
            }

            if (hasEncryptedBundle) {
                BundleCrypto.verifyPackageName(context.packageName)
                val key = BundleCrypto.deriveKey(context.packageName)
                context.assets.open("lenznode-bundle.dat").use { encryptedStream ->
                    val count = BundleCrypto.extractXorZip(encryptedStream, bundleDir, key)
                    if (count <= 0 || !bundlePanel.exists()) {
                        throw IllegalStateException("Ekstraksi lenznode-bundle.dat gagal atau tidak lengkap.")
                    }
                }
            } else {
                copyAssetTree(context.assets, "lenznode-bundle", bundleDir)
            }
            bundleVersionFile.writeText(currentVersion)
        }
    }

    fun clearBootstrap() {
        if (rootfsDir.exists()) {
            rootfsDir.deleteRecursively()
        }
        if (tmpDir.exists()) {
            tmpDir.deleteRecursively()
        }
        ensureDirectories()
    }

    fun ensureRootfsTarball(
        linuxArch: String,
        onLine: (String) -> Unit,
        onProgress: (ProgressUpdate) -> Unit
    ): File? {
        ensureDirectories()
        val fileName = AbiHelper.rootfsTarballName(linuxArch)
        val targetFile = File(cacheDir, fileName)
        if (targetFile.exists() && targetFile.length() > 5_000_000L) {
            onLine("Cache rootfs ditemukan: ${targetFile.name}")
            onProgress(ProgressUpdate(20, "Berkas rootfs Ubuntu siap diekstrak."))
            return targetFile
        }

        val downloadUrl = "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/$fileName"
        val partFile = File(cacheDir, "$fileName.part")
        if (partFile.exists()) {
            partFile.delete()
        }

        onLine("Mengunduh $fileName dari Ubuntu Base...")
        onProgress(ProgressUpdate(5, "Mengunduh base Linux Ubuntu ($linuxArch)..."))

        return try {
            var currentUrl = downloadUrl
            var connection: HttpURLConnection? = null
            var redirects = 0
            while (redirects < 5) {
                val conn = (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = false
                    connectTimeout = 15_000
                    readTimeout = 30_000
                    requestMethod = "GET"
                    setRequestProperty("User-Agent", "LenzNode-Android/${BuildConfig.VERSION_NAME}")
                }
                val code = conn.responseCode
                if (code in 301..308) {
                    val loc = conn.getHeaderField("Location")
                    conn.disconnect()
                    if (loc.isNullOrBlank()) break
                    currentUrl = URL(URL(currentUrl), loc).toString()
                    redirects++
                    continue
                }
                connection = conn
                break
            }

            val conn = connection ?: throw IllegalStateException("Koneksi gagal dibuat")
            try {
                val status = conn.responseCode
                if (status !in 200..299) {
                    throw IllegalStateException("HTTP $status saat mengunduh rootfs")
                }
                val totalBytes = conn.contentLengthLong
                var downloaded = 0L
                var lastPct = 5

                conn.inputStream.use { input ->
                    FileOutputStream(partFile).use { output ->
                        val buffer = ByteArray(16 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            downloaded += read
                            if (totalBytes > 0) {
                                val pct = 5 + ((downloaded * 15) / totalBytes).toInt().coerceIn(0, 15)
                                if (pct != lastPct) {
                                    lastPct = pct
                                    val mbDone = downloaded / (1024 * 1024)
                                    val mbTotal = totalBytes / (1024 * 1024)
                                    onProgress(ProgressUpdate(pct, "Mengunduh Ubuntu Base (${mbDone}/${mbTotal} MB)..."))
                                }
                            }
                        }
                    }
                }
            } finally {
                conn.disconnect()
            }

            val partSize = partFile.length()
            if (partSize < 5_000_000L) {
                partFile.delete()
                throw IllegalStateException("Ukuran file unduhan tidak valid ($partSize byte)")
            }
            if (targetFile.exists()) targetFile.delete()
            if (!partFile.renameTo(targetFile)) {
                partFile.copyTo(targetFile, overwrite = true)
                partFile.delete()
            }
            onLine("Unduhan rootfs selesai: ${targetFile.length() / (1024 * 1024)} MB")
            onProgress(ProgressUpdate(20, "Unduhan Ubuntu Base selesai."))
            targetFile
        } catch (e: Exception) {
            if (partFile.exists()) partFile.delete()
            onLine("Peringatan pra-unduh rootfs: ${e.message}. Mencoba via skrip bootstrap...")
            null
        }
    }

    fun buildEnvironment(linuxArch: String, tarball: File? = null): Map<String, String> {
        val loader = File(nativeLibDir, "libproot-loader.so").absolutePath
        val loader32 = File(nativeLibDir, "libproot-loader32.so")
        val env = linkedMapOf(
            "FILES_DIR" to filesDir.absolutePath,
            "NATIVE_LIB_DIR" to nativeLibDir,
            "PROOT_TMP_DIR" to tmpDir.absolutePath,
            "PROOT_LOADER" to loader,
            "LD_LIBRARY_PATH" to nativeLibDir,
            "LENZ_BRIDGE_URL" to "http://127.0.0.1:48080",
            "LENZ_APP_MODE" to "android-apk",
            "LENZ_ARCH" to linuxArch,
            "PANEL_PORT" to "8080",
            "SSH_PORT" to "2222",
            "HOME" to homeDir.absolutePath,
            "TMPDIR" to tmpDir.absolutePath,
            "PATH" to "$nativeLibDir:/system/bin:/system/xbin"
        )
        if (loader32.exists()) {
            env["PROOT_LOADER_32"] = loader32.absolutePath
        }
        if (tarball != null && tarball.exists()) {
            env["ROOTFS_TARBALL"] = tarball.absolutePath
        }
        return env
    }

    fun runBootstrapSetup(
        onLine: (String) -> Unit,
        onProgress: (ProgressUpdate) -> Unit
    ): Result<Unit> {
        return try {
            extractAssetsIfNeeded()
            val linuxArch = resolveLinuxArch()
            val tarball = ensureRootfsTarball(linuxArch, onLine, onProgress)
            val script = File(bootstrapDir, "setup-lenznode.sh")
            if (!script.exists()) {
                return Result.failure(IllegalStateException("Skrip setup-lenznode.sh tidak ditemukan di aset."))
            }

            val shellCmd = buildShellCommand(script)
            val pb = ProcessBuilder(shellCmd).apply {
                directory(filesDir)
                redirectErrorStream(true)
                environment().putAll(buildEnvironment(linuxArch, tarball))
            }

            val process = pb.start()
            BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val raw = line ?: continue
                    val clean = ProgressParser.stripAnsi(raw)
                    if (clean.isNotBlank()) {
                        onLine(clean)
                    }
                    ProgressParser.parseLine(raw)?.let { update ->
                        onProgress(update)
                    }
                }
            }

            val exitCode = process.waitFor()
            if (exitCode != 0) {
                return Result.failure(IllegalStateException("Instalasi runtime berhenti dengan kode $exitCode"))
            }
            if (!rootfsPanelEntry.exists()) {
                return Result.failure(IllegalStateException("Panel server.js tidak ditemukan setelah instalasi rootfs."))
            }
            if (!bootstrapMarker.exists()) {
                bootstrapMarker.writeText("ok\n")
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    fun startServerProcess(): Process {
        extractAssetsIfNeeded()
        cleanupOrphanedProcesses()
        BundleCrypto.syncBundleIfNewer(
            bundleDir = bundleDir,
            targetAppDir = File(rootfsDir, "root/LenzNode"),
            fallbackBundleVersion = BuildConfig.VERSION_NAME
        )
        val linuxArch = resolveLinuxArch()
        val script = File(bootstrapDir, "start-lenznode-app.sh")
        if (!script.exists()) {
            throw IllegalStateException("Skrip start-lenznode-app.sh tidak ditemukan.")
        }
        val pb = ProcessBuilder(buildShellCommand(script)).apply {
            directory(filesDir)
            redirectErrorStream(true)
            environment().putAll(buildEnvironment(linuxArch))
        }
        return pb.start()
    }

    fun terminateProcessTree(proc: Process?) {
        if (proc != null) {
            try {
                proc.destroy()
            } catch (_: Exception) {
            }
        }

        cleanupOrphanedProcesses()

        if (proc != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                if (proc.isAlive) {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) {
            }
        }
    }

    fun cleanupOrphanedProcesses() {
        val myPid = android.os.Process.myPid()
        val pidFiles = listOf(
            File(tmpDir, "lenz-node.pid"),
            File(tmpDir, "lenz-proot.pid"),
            File(rootfsDir, "tmp/lenz-node.pid"),
            File(rootfsDir, "tmp/lenz-proot.pid"),
            File(rootfsDir, "run/sshd.pid")
        )

        val pidsToKill = linkedSetOf<Int>()
        for (pidFile in pidFiles) {
            if (!pidFile.exists()) continue
            try {
                val pid = pidFile.readText().trim().toIntOrNull()
                if (pid != null && pid > 1 && pid != myPid) {
                    pidsToKill.add(pid)
                }
            } catch (_: Exception) {
            }
        }

        // Send graceful SIGTERM first, then SIGKILL if still alive
        for (pid in pidsToKill) {
            try {
                android.system.Os.kill(pid, android.system.OsConstants.SIGTERM)
            } catch (_: Exception) {
            }
        }
        if (pidsToKill.isNotEmpty()) {
            try {
                Thread.sleep(250)
            } catch (_: InterruptedException) {
            }
            for (pid in pidsToKill) {
                try {
                    android.system.Os.kill(pid, android.system.OsConstants.SIGKILL)
                } catch (_: Exception) {
                }
            }
        }

        // Clean up any stale cloudflared / node / proot processes belonging to this app sandbox via /proc
        killResidualSandboxProcesses(myPid)

        for (pidFile in pidFiles) {
            try {
                if (pidFile.exists()) pidFile.delete()
            } catch (_: Exception) {
            }
        }
    }

    private fun killResidualSandboxProcesses(myPid: Int) {
        val myUid = android.os.Process.myUid()
        val markers = listOf("libproot.so", "/root/LenzNode/panel/server.js", "cloudflared", "sshd")
        try {
            val procDir = File("/proc")
            val entries = procDir.listFiles() ?: return
            for (entry in entries) {
                val pid = entry.name.toIntOrNull() ?: continue
                if (pid <= 1 || pid == myPid) continue
                try {
                    val stat = android.system.Os.stat(entry.absolutePath)
                    if (stat.st_uid != myUid) continue
                    val cmdlineFile = File(entry, "cmdline")
                    if (!cmdlineFile.exists()) continue
                    val cmdline = cmdlineFile.readBytes()
                        .toString(Charsets.UTF_8)
                        .replace('\u0000', ' ')
                        .trim()
                    if (cmdline.isEmpty()) continue
                    if (markers.any { marker -> cmdline.contains(marker) }) {
                        try {
                            android.system.Os.kill(pid, android.system.OsConstants.SIGKILL)
                        } catch (_: Exception) {
                        }
                    }
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
    }

    fun waitForPanelReady(
        probeUrl: String = "http://127.0.0.1:8080/api/auth/status",
        timeoutMs: Long = 60_000L,
        isProcessAlive: () -> Boolean
    ): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline && isProcessAlive()) {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL(probeUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    instanceFollowRedirects = false
                    connectTimeout = 1000
                    readTimeout = 1000
                }
                val code = conn.responseCode
                if (code in 200..399) {
                    return true
                }
            } catch (_: Exception) {
                // Server belum siap menerima koneksi
            } finally {
                try {
                    conn?.disconnect()
                } catch (_: Exception) {
                }
            }
            try {
                Thread.sleep(500)
            } catch (_: InterruptedException) {
                return false
            }
        }
        return false
    }

    private fun buildShellCommand(script: File): List<String> {
        // Use Android native Bionic /system/bin/sh to avoid musl static busybox SIGSYS under untrusted_app seccomp
        return listOf("/system/bin/sh", script.absolutePath)
    }

    private fun copyAssetTree(assets: AssetManager, assetPath: String, destDir: File) {
        val children = assets.list(assetPath)
        if (children.isNullOrEmpty()) {
            destDir.parentFile?.mkdirs()
            try {
                assets.open(assetPath).use { input ->
                    FileOutputStream(destDir).use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (_: java.io.IOException) {
                if (!destDir.exists()) {
                    destDir.mkdirs()
                }
            }
            return
        }
        if (!destDir.exists()) {
            destDir.mkdirs()
        }
        for (child in children) {
            val childAssetPath = if (assetPath.isEmpty()) child else "$assetPath/$child"
            val childDest = File(destDir, child)
            copyAssetTree(assets, childAssetPath, childDest)
        }
    }
}
