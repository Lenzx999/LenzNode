package com.lenznode.app.runtime

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.system.Os
import android.system.OsConstants
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileFilter
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.roundToInt

class NativeBridgeServer(
    private val context: Context,
    private val port: Int = 48080,
    private val onWakeLockControl: (Boolean?) -> Boolean = { enable -> enable ?: true }
) {
    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var workerPool: ExecutorService? = null
    @Volatile
    private var torchEnabled: Boolean = false

    private val cpuLock = Any()
    private var prevProcStatTotal: Long = -1L
    private var prevProcStatIdle: Long = -1L
    private var prevUidTicks: Long = -1L
    private var prevUidWallMs: Long = -1L
    private var prevElapsedCpuMs: Long = -1L
    private var prevElapsedWallMs: Long = -1L
    private var lastCpuPercent: Double = 0.0
    private var lastCpuSource: String = "initializing"
    private var lastCpuSampleAtMs: Long = 0L

    fun start() {
        if (!running.compareAndSet(false, true)) return
        workerPool = Executors.newCachedThreadPool()
        val socket = ServerSocket(port, 32, InetAddress.getByName("127.0.0.1")).apply {
            reuseAddress = true
        }
        serverSocket = socket
        acceptThread = Thread({
            while (running.get() && !socket.isClosed) {
                try {
                    val client = socket.accept()
                    workerPool?.execute { handleClient(client) }
                } catch (_: Exception) {
                    if (!running.get()) break
                }
            }
        }, "LenzNativeBridge").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        workerPool?.shutdownNow()
        workerPool = null
        acceptThread = null
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            try {
                client.soTimeout = 3000
                val input = BufferedInputStream(client.getInputStream())
                val headerText = readHeaders(input) ?: return
                val lines = headerText.split("\r\n")
                if (lines.isEmpty()) return

                val parts = lines[0].split(' ')
                if (parts.size < 2) return
                val rawTarget = parts[1]

                var contentLength = 0
                for (i in 1 until lines.size) {
                    val line = lines[i]
                    val colon = line.indexOf(':')
                    if (colon > 0) {
                        val name = line.substring(0, colon).trim().lowercase(Locale.US)
                        if (name == "content-length") {
                            contentLength = line.substring(colon + 1).trim().toIntOrNull() ?: 0
                        }
                    }
                }

                val body = if (contentLength in 1..65_536) {
                    readBody(input, contentLength)
                } else {
                    ""
                }

                val (path, queryParams) = NativeBridgeJson.parseHttpTarget(rawTarget)
                val bodyParams = NativeBridgeJson.parseJsonParams(body)
                val params = queryParams + bodyParams

                val (statusCode, payload) = routeRequest(path, params)
                val bodyBytes = payload.toByteArray(Charsets.UTF_8)
                val statusLabel = if (statusCode == 200) "OK" else "Not Found"
                val responseHeaders = buildString {
                    append("HTTP/1.1 ").append(statusCode).append(' ').append(statusLabel).append("\r\n")
                    append("Content-Type: application/json; charset=utf-8\r\n")
                    append("Content-Length: ").append(bodyBytes.size).append("\r\n")
                    append("Cache-Control: no-cache\r\n")
                    append("Connection: close\r\n\r\n")
                }

                val out = client.getOutputStream()
                out.write(responseHeaders.toByteArray(Charsets.US_ASCII))
                out.write(bodyBytes)
                out.flush()
            } catch (_: Exception) {
            }
        }
    }

    private fun routeRequest(path: String, params: Map<String, String>): Pair<Int, String> {
        return when (path) {
            "/health" -> 200 to NativeBridgeJson.healthJson(port)
            "/battery" -> 200 to readBatteryJson()
            "/thermal" -> 200 to readThermalJson()
            "/stats" -> 200 to readStatsJson()
            "/torch" -> 200 to handleTorch(params["state"])
            "/vibrate" -> 200 to handleVibrate(params["duration"])
            "/wakelock" -> 200 to handleWakeLock(params["enable"])
            else -> 404 to NativeBridgeJson.errorJson("Endpoint tidak ditemukan: $path")
        }
    }

    private fun readBatteryJson(): String {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager

        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val percentage = if (level >= 0 && scale > 0) {
            (level * 100) / scale
        } else {
            batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
        }

        val statusCode = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
            ?: BatteryManager.BATTERY_STATUS_UNKNOWN
        val pluggedCode = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val isCharging = statusCode == BatteryManager.BATTERY_STATUS_CHARGING ||
            statusCode == BatteryManager.BATTERY_STATUS_FULL ||
            pluggedCode != 0

        val statusText = when (statusCode) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "Mengisi Daya"
            BatteryManager.BATTERY_STATUS_FULL -> "Penuh"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "Melepas Daya"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Tidak Mengisi"
            else -> if (isCharging) "Mengisi Daya" else "Tidak Mengisi"
        }

        val pluggedText = when (pluggedCode) {
            BatteryManager.BATTERY_PLUGGED_AC -> "AC"
            BatteryManager.BATTERY_PLUGGED_USB -> "USB"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "WIRELESS"
            else -> "UNPLUGGED"
        }

        val tempRaw = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 320) ?: 320
        val tempC = (tempRaw / 10.0).let { if (it in 5.0..95.0) it else 32.5 }

        val voltageMv = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 3850) ?: 3850

        val rawCurrentUa = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW) ?: 0
        val currentMa = if (rawCurrentUa != Int.MIN_VALUE && rawCurrentUa != 0) {
            if (abs(rawCurrentUa) > 10_000) abs(rawCurrentUa) / 1000.0 else abs(rawCurrentUa).toDouble()
        } else {
            0.0
        }

        return NativeBridgeJson.batteryJson(
            percentage = percentage,
            status = statusText,
            plugged = pluggedText,
            temperatureC = tempC,
            voltageMv = voltageMv,
            currentMa = currentMa,
            isCharging = isCharging
        )
    }

    private fun readStatsJson(): String {
        val cores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        val (cpuPercent, cpuSource) = readCpuTelemetry(cores)

        var ramTotal = 0L
        var ramFree = 0L
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (am != null) {
                val memInfo = ActivityManager.MemoryInfo()
                am.getMemoryInfo(memInfo)
                ramTotal = memInfo.totalMem.coerceAtLeast(0L)
                ramFree = memInfo.availMem.coerceAtLeast(0L)
            }
        } catch (_: Exception) {
        }
        val ramUsed = (ramTotal - ramFree).coerceAtLeast(0L)

        var storageTotal = 0L
        var storageFree = 0L
        try {
            val stat = StatFs(context.filesDir.absolutePath)
            storageTotal = stat.totalBytes.coerceAtLeast(0L)
            storageFree = stat.availableBytes.coerceAtLeast(0L)
        } catch (_: Exception) {
        }
        val storageUsed = (storageTotal - storageFree).coerceAtLeast(0L)

        return NativeBridgeJson.statsJson(
            cpuPercent = cpuPercent,
            cpuCores = cores,
            cpuSource = cpuSource,
            ramTotalBytes = ramTotal,
            ramUsedBytes = ramUsed,
            ramFreeBytes = ramFree,
            storageTotalBytes = storageTotal,
            storageUsedBytes = storageUsed,
            storageFreeBytes = storageFree,
            androidApi = Build.VERSION.SDK_INT,
            androidVersion = Build.VERSION.RELEASE ?: "unknown",
            batteryJsonStr = readBatteryJson()
        )
    }

    private fun readCpuTelemetry(cores: Int): Pair<Double, String> = synchronized(cpuLock) {
        val nowMs = SystemClock.elapsedRealtime()
        if (lastCpuSampleAtMs > 0L && (nowMs - lastCpuSampleAtMs) < 900L && lastCpuPercent > 0.0) {
            return lastCpuPercent to lastCpuSource
        }

        // 1. Try /proc/stat delta first (works on Android 7 and permissive kernels)
        try {
            val procStat = File("/proc/stat")
            if (procStat.exists() && procStat.canRead()) {
                val firstLine = procStat.bufferedReader().use { it.readLine() }
                val parsed = firstLine?.let { NativeBridgeJson.parseProcStatTotals(it) }
                if (parsed != null) {
                    val (total, idle) = parsed
                    if (prevProcStatTotal >= 0L && total > prevProcStatTotal) {
                        val totalDiff = total - prevProcStatTotal
                        val idleDiff = (idle - prevProcStatIdle).coerceAtLeast(0L)
                        prevProcStatTotal = total
                        prevProcStatIdle = idle
                        val pct = (((totalDiff - idleDiff).toDouble() / totalDiff.toDouble()) * 1000.0)
                            .roundToInt() / 10.0
                        lastCpuPercent = pct.coerceIn(0.0, 100.0)
                        lastCpuSource = "proc_stat"
                        lastCpuSampleAtMs = nowMs
                        return lastCpuPercent to lastCpuSource
                    }
                    prevProcStatTotal = total
                    prevProcStatIdle = idle
                }
            }
        } catch (_: Exception) {
        }

        // 2. Android 8-16 SELinux blocks /proc/stat: sum utime+stime across all processes owned by myUid()
        val uidTicks = sumUidCpuTicks()
        val clkTck = try {
            Os.sysconf(OsConstants._SC_CLK_TCK).coerceAtLeast(1L)
        } catch (_: Exception) {
            100L
        }
        if (uidTicks != null) {
            if (prevUidTicks >= 0L && prevUidWallMs > 0L && (nowMs - prevUidWallMs) >= 150L) {
                val deltaTicks = (uidTicks - prevUidTicks).coerceAtLeast(0L)
                val wallDeltaMs = nowMs - prevUidWallMs
                val pct = NativeBridgeJson.computeCpuPercentFromDeltas(deltaTicks, wallDeltaMs, cores, clkTck)
                prevUidTicks = uidTicks
                prevUidWallMs = nowMs
                lastCpuPercent = if (pct > 0.0) pct else 0.1
                lastCpuSource = "uid_proc_stat"
                lastCpuSampleAtMs = nowMs
                return lastCpuPercent to lastCpuSource
            }
            // Take a short baseline delta on very first call so CPU doesn't stick at 0% on first poll
            if (prevUidTicks < 0L) {
                prevUidTicks = uidTicks
                prevUidWallMs = nowMs
                try {
                    Thread.sleep(160)
                } catch (_: InterruptedException) {
                }
                val afterTicks = sumUidCpuTicks()
                val afterMs = SystemClock.elapsedRealtime()
                if (afterTicks != null && afterMs > prevUidWallMs) {
                    val deltaTicks = (afterTicks - prevUidTicks).coerceAtLeast(0L)
                    val pct = NativeBridgeJson.computeCpuPercentFromDeltas(
                        deltaTicks,
                        afterMs - prevUidWallMs,
                        cores,
                        clkTck
                    )
                    prevUidTicks = afterTicks
                    prevUidWallMs = afterMs
                    lastCpuPercent = if (pct > 0.0) pct else 0.1
                    lastCpuSource = "uid_proc_stat"
                    lastCpuSampleAtMs = afterMs
                    return lastCpuPercent to lastCpuSource
                }
            }
        }

        // 3. Fallback: Process.getElapsedCpuTime() delta
        val elapsedCpu = Process.getElapsedCpuTime()
        if (prevElapsedCpuMs >= 0L && prevElapsedWallMs > 0L && nowMs > prevElapsedWallMs) {
            val deltaCpuMs = (elapsedCpu - prevElapsedCpuMs).coerceAtLeast(0L)
            val wallDeltaMs = nowMs - prevElapsedWallMs
            val pct = ((deltaCpuMs.toDouble() / (wallDeltaMs.toDouble() * cores.toDouble())) * 1000.0)
                .roundToInt() / 10.0
            prevElapsedCpuMs = elapsedCpu
            prevElapsedWallMs = nowMs
            lastCpuPercent = pct.coerceIn(0.1, 100.0)
            lastCpuSource = "process_cpu_time"
            lastCpuSampleAtMs = nowMs
            return lastCpuPercent to lastCpuSource
        }
        prevElapsedCpuMs = elapsedCpu
        prevElapsedWallMs = nowMs

        // 4. Fallback: /proc/loadavg
        try {
            val loadAvg = File("/proc/loadavg")
            if (loadAvg.exists() && loadAvg.canRead()) {
                val first = loadAvg.readText().trim().split(Regex("\\s+")).firstOrNull()?.toDoubleOrNull()
                if (first != null && first > 0.0) {
                    val pct = (((first / cores.toDouble()) * 1000.0).roundToInt() / 10.0).coerceIn(0.1, 100.0)
                    lastCpuPercent = pct
                    lastCpuSource = "loadavg"
                    lastCpuSampleAtMs = nowMs
                    return lastCpuPercent to lastCpuSource
                }
            }
        } catch (_: Exception) {
        }

        return lastCpuPercent to lastCpuSource
    }

    private fun sumUidCpuTicks(): Long? {
        val myUid = Process.myUid()
        var sum = 0L
        var count = 0
        try {
            val entries = File("/proc").listFiles() ?: return null
            for (entry in entries) {
                if (entry.name.toIntOrNull() == null) continue
                try {
                    if (Os.stat(entry.absolutePath).st_uid != myUid) continue
                    val statFile = File(entry, "stat")
                    if (!statFile.canRead()) continue
                    val ticks = NativeBridgeJson.parsePidStatTicks(statFile.readText()) ?: continue
                    sum += ticks
                    count++
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
            return null
        }
        return if (count > 0) sum else null
    }

    private fun readThermalJson(): String {
        var cpuTemp: Int? = null
        var batteryTemp: Double? = null
        val cpuCandidates = mutableListOf<Int>()
        val cores = MutableList<Int?>(4) { null }

        try {
            val tzRoot = File("/sys/class/thermal")
            if (tzRoot.exists() && tzRoot.isDirectory) {
                tzRoot.listFiles(FileFilter { f -> f.name.startsWith("thermal_zone") })?.forEach { zone ->
                    try {
                        val typeFile = File(zone, "type")
                        val tempFile = File(zone, "temp")
                        if (typeFile.exists() && tempFile.exists()) {
                            val type = typeFile.readText().trim().lowercase(Locale.US)
                            val raw = tempFile.readText().trim().toIntOrNull()
                            if (raw != null) {
                                val deg = if (raw > 1000) (raw / 1000.0).roundToInt() else raw
                                if (deg in 1..119 && (type.contains("cpu") || type.contains("tsens") || type.contains("soc"))) {
                                    cpuCandidates.add(deg)
                                    val coreMatch = Regex("(?:cpu|core)[_-]?([0-3])").find(type)
                                    if (coreMatch != null) {
                                        val idx = coreMatch.groupValues[1].toIntOrNull()
                                        if (idx != null && idx in 0..3) {
                                            cores[idx] = deg
                                        }
                                    }
                                }
                                if (batteryTemp == null) {
                                    batteryTemp = NativeBridgeJson.parseBatteryThermalTemp(type, raw)
                                }
                            }
                        }
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }

        if (cpuCandidates.isNotEmpty()) {
            cpuTemp = cpuCandidates.maxOrNull()
        }

        if (batteryTemp == null) {
            val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val tempRaw = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
            if (tempRaw > 0) {
                val candidate = tempRaw / 10.0
                if (candidate in 5.0..95.0) {
                    batteryTemp = candidate
                }
            }
        }

        if (cpuTemp == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                val status = pm?.currentThermalStatus
                if (status != null) {
                    cpuTemp = when (status) {
                        PowerManager.THERMAL_STATUS_NONE -> 36
                        PowerManager.THERMAL_STATUS_LIGHT -> 45
                        PowerManager.THERMAL_STATUS_MODERATE -> 55
                        PowerManager.THERMAL_STATUS_SEVERE -> 68
                        PowerManager.THERMAL_STATUS_CRITICAL -> 78
                        else -> 85
                    }
                }
            } catch (_: Exception) {
            }
        }

        val resolvedBattery = batteryTemp
        if (cpuTemp == null && resolvedBattery != null) {
            cpuTemp = (resolvedBattery + 4.0).roundToInt()
        }

        return NativeBridgeJson.thermalJson(
            cpuTemp = cpuTemp,
            batteryTemp = resolvedBattery,
            cores = cores
        )
    }

    private fun handleTorch(rawState: String?): String {
        val nextState = when (rawState?.trim()?.lowercase(Locale.US)) {
            "on", "true", "1" -> true
            "off", "false", "0" -> false
            else -> !torchEnabled
        }
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                ?: return NativeBridgeJson.torchJson(false, torchEnabled, "CameraManager tidak tersedia.")
            var targetId: String? = null
            for (id in cm.cameraIdList) {
                val chars = cm.getCameraCharacteristics(id)
                val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (hasFlash) {
                    targetId = id
                    if (facing == CameraCharacteristics.LENS_FACING_BACK) break
                }
            }
            if (targetId == null) {
                return NativeBridgeJson.torchJson(false, torchEnabled, "Perangkat tidak memiliki lampu flash.")
            }
            cm.setTorchMode(targetId, nextState)
            torchEnabled = nextState
            val msg = if (nextState) "Senter HP dinyalakan." else "Senter HP dimatikan."
            NativeBridgeJson.torchJson(true, torchEnabled, msg)
        } catch (e: Exception) {
            NativeBridgeJson.torchJson(false, torchEnabled, "Gagal mengontrol senter: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun handleVibrate(rawDuration: String?): String {
        val duration = (rawDuration?.toLongOrNull() ?: 400L).coerceIn(50L, 5000L)
        return try {
            val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            if (vibrator == null || !vibrator.hasVibrator()) {
                return NativeBridgeJson.vibrateJson(false, duration, "Perangkat tidak mendukung vibrator.")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                vibrator.vibrate(duration)
            }
            NativeBridgeJson.vibrateJson(true, duration, "Getaran dikirim ke perangkat HP.")
        } catch (e: Exception) {
            NativeBridgeJson.vibrateJson(false, duration, "Gagal menggetarkan HP: ${e.message}")
        }
    }

    private fun handleWakeLock(rawEnable: String?): String {
        val requested = when (rawEnable?.trim()?.lowercase(Locale.US)) {
            "on", "true", "1" -> true
            "off", "false", "0" -> false
            else -> null
        }
        return try {
            val active = onWakeLockControl(requested)
            val msg = if (active) {
                "Wake-Lock diaktifkan (HP tidak akan sleep)."
            } else {
                "Wake-Lock dinonaktifkan."
            }
            NativeBridgeJson.wakelockJson(true, active, msg)
        } catch (e: Exception) {
            NativeBridgeJson.wakelockJson(false, false, "Gagal mengatur wake-lock: ${e.message}")
        }
    }

    private fun readHeaders(input: BufferedInputStream): String? {
        val out = ByteArrayOutputStream()
        var matched = 0
        while (out.size() < 8192) {
            val b = input.read()
            if (b == -1) break
            out.write(b)
            matched = when {
                b == '\r'.code && (matched == 0 || matched == 2) -> matched + 1
                b == '\n'.code && (matched == 1 || matched == 3) -> matched + 1
                b == '\r'.code -> 1
                else -> 0
            }
            if (matched == 4) break
        }
        if (out.size() == 0) return null
        return out.toString(Charsets.US_ASCII.name())
    }

    private fun readBody(input: BufferedInputStream, length: Int): String {
        val buf = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val read = input.read(buf, offset, length - offset)
            if (read <= 0) break
            offset += read
        }
        return String(buf, 0, offset, Charsets.UTF_8)
    }
}
