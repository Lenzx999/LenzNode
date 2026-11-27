package com.lenznode.app.runtime

import java.net.URLDecoder
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

object NativeBridgeJson {

    fun escapeJson(value: String): String {
        val sb = StringBuilder(value.length + 8)
        for (ch in value) {
            when (ch) {
                '\\' -> sb.append("\\\\")
                '"' -> sb.append("\\\"")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (ch.code < 0x20) {
                    sb.append(String.format(Locale.US, "\\u%04x", ch.code))
                } else {
                    sb.append(ch)
                }
            }
        }
        return sb.toString()
    }

    private fun jsonString(value: String?): String =
        if (value == null) "null" else "\"${escapeJson(value)}\""

    fun batteryJson(
        percentage: Int,
        status: String,
        plugged: String,
        temperatureC: Double,
        voltageMv: Int,
        currentMa: Double,
        isCharging: Boolean
    ): String {
        val pct = percentage.coerceIn(0, 100)
        val volts = if (voltageMv > 0) voltageMv / 1000.0 else 3.85
        val roundedVolts = (volts * 100.0).roundToInt() / 100.0
        val absMa = abs(currentMa)
        val roundedMa = (absMa * 10.0).roundToInt() / 10.0
        val amps = absMa / 1000.0
        val watts = ((volts * amps) * 100.0).roundToInt() / 100.0
        val temp = (temperatureC * 10.0).roundToInt() / 10.0
        val vStr = String.format(Locale.US, "%.2fV", volts)
        val aStr = String.format(Locale.US, "%.2fA", amps)
        val powerText = if (isCharging) {
            String.format(Locale.US, "Pengisian: +%.2f W (%s • %s)", watts, vStr, aStr)
        } else {
            String.format(Locale.US, "Konsumsi: %.2f W (%s • %s)", watts, vStr, aStr)
        }

        return buildString {
            append('{')
            append("\"percentage\":").append(pct).append(',')
            append("\"status\":").append(jsonString(status)).append(',')
            append("\"plugged\":").append(jsonString(plugged)).append(',')
            append("\"temperature\":").append(String.format(Locale.US, "%.1f", temp)).append(',')
            append("\"voltage\":").append(jsonString(String.format(Locale.US, "%.2f V", volts))).append(',')
            append("\"voltageVolts\":").append(String.format(Locale.US, "%.2f", roundedVolts)).append(',')
            append("\"voltageMv\":").append(voltageMv).append(',')
            append("\"current\":").append(jsonString(String.format(Locale.US, "%.2f A", amps))).append(',')
            append("\"currentMa\":").append(String.format(Locale.US, "%.1f", roundedMa)).append(',')
            append("\"watts\":").append(String.format(Locale.US, "%.2f", watts)).append(',')
            append("\"powerWatts\":").append(String.format(Locale.US, "%.2f", watts)).append(',')
            append("\"powerText\":").append(jsonString(powerText)).append(',')
            append("\"isCharging\":").append(isCharging)
            append('}')
        }
    }

    fun parseBatteryThermalTemp(type: String, raw: Int): Double? {
        val norm = type.trim().lowercase(Locale.US)
        if (norm.contains("ibat") || norm.contains("vbat") || norm.contains("lvl") || norm.contains("usb")) {
            return null
        }
        val isBatteryZone = norm == "battery" || norm == "batt_therm" || norm == "battery_therm" || norm == "bms"
        if (!isBatteryZone) return null
        val deg = when {
            raw > 1000 -> raw / 1000.0
            raw > 100 -> raw / 10.0
            else -> raw.toDouble()
        }
        return if (deg in 5.0..95.0) deg else null
    }

    fun thermalJson(
        cpuTemp: Int?,
        batteryTemp: Double?,
        cores: List<Int?> = List(4) { cpuTemp }
    ): String {
        val coreValues = (0 until 4).map { i -> cores.getOrNull(i) ?: cpuTemp }
        val status = when {
            cpuTemp == null -> "Optimal"
            cpuTemp >= 75 -> "Panas"
            cpuTemp >= 60 -> "Hangat"
            else -> "Optimal"
        }
        val cpuStr = cpuTemp?.let { "${it}°C" }
        val roundedBat = batteryTemp?.let { (it * 10.0).roundToInt() / 10.0 }
        val batStr = roundedBat?.let { String.format(Locale.US, "%.1f°C", it) }

        return buildString {
            append('{')
            append("\"cpu\":").append(jsonString(cpuStr)).append(',')
            append("\"cpuTemp\":").append(cpuTemp?.toString() ?: "null").append(',')
            append("\"cores\":[").append(coreValues.joinToString(",") { it?.toString() ?: "null" }).append("],")
            append("\"battery\":").append(jsonString(batStr)).append(',')
            append("\"batteryTemp\":").append(roundedBat?.let { String.format(Locale.US, "%.1f", it) } ?: "null").append(',')
            append("\"status\":").append(jsonString(status))
            append('}')
        }
    }

    fun parseProcStatTotals(procStatLine: String): Pair<Long, Long>? {
        val parts = procStatLine.trim().split(Regex("\\s+"))
        if (parts.size < 5) return null
        val user = parts[1].toLongOrNull() ?: return null
        val nice = parts[2].toLongOrNull() ?: return null
        val sys = parts[3].toLongOrNull() ?: return null
        val idle = parts[4].toLongOrNull() ?: return null
        val iowait = parts.getOrNull(5)?.toLongOrNull() ?: 0L
        val irq = parts.getOrNull(6)?.toLongOrNull() ?: 0L
        val softirq = parts.getOrNull(7)?.toLongOrNull() ?: 0L
        val steal = parts.getOrNull(8)?.toLongOrNull() ?: 0L
        val idleTotal = idle + iowait
        val total = user + nice + sys + idleTotal + irq + softirq + steal
        return total to idleTotal
    }

    fun parsePidStatTicks(statText: String): Long? {
        val closeParen = statText.lastIndexOf(')')
        if (closeParen < 0 || closeParen + 2 >= statText.length) return null
        val rest = statText.substring(closeParen + 2).trim().split(Regex("\\s+"))
        // Field 3 is state (rest[0]), so utime is field 14 (rest[11]) and stime is field 15 (rest[12])
        if (rest.size <= 12) return null
        val utime = rest[11].toLongOrNull() ?: return null
        val stime = rest[12].toLongOrNull() ?: return null
        return utime + stime
    }

    fun computeCpuPercentFromDeltas(
        cpuDeltaTicks: Long,
        wallDeltaMs: Long,
        cores: Int,
        clkTckHz: Long = 100L
    ): Double {
        if (cpuDeltaTicks <= 0L || wallDeltaMs <= 0L || cores <= 0 || clkTckHz <= 0L) return 0.0
        val wallDeltaSec = wallDeltaMs / 1000.0
        val maxTicks = wallDeltaSec * cores.toDouble() * clkTckHz.toDouble()
        if (maxTicks <= 0.0) return 0.0
        val rawPct = (cpuDeltaTicks.toDouble() / maxTicks) * 100.0
        val clamped = rawPct.coerceIn(0.0, 100.0)
        return (clamped * 10.0).roundToInt() / 10.0
    }

    fun statsJson(
        cpuPercent: Double,
        cpuCores: Int,
        cpuSource: String,
        ramTotalBytes: Long,
        ramUsedBytes: Long,
        ramFreeBytes: Long,
        storageTotalBytes: Long,
        storageUsedBytes: Long,
        storageFreeBytes: Long,
        androidApi: Int,
        androidVersion: String,
        batteryJsonStr: String? = null
    ): String {
        val roundedCpu = ((cpuPercent.coerceIn(0.0, 100.0) * 10.0).roundToInt() / 10.0)
        val ramPct = if (ramTotalBytes > 0L) ((ramUsedBytes * 100.0) / ramTotalBytes).roundToInt().coerceIn(0, 100) else 0
        val storagePct = if (storageTotalBytes > 0L) ((storageUsedBytes * 100.0) / storageTotalBytes).roundToInt().coerceIn(0, 100) else 0
        return buildString {
            append('{')
            append("\"ok\":true,")
            append("\"cpuPercent\":").append(String.format(Locale.US, "%.1f", roundedCpu)).append(',')
            append("\"cpuCores\":").append(cpuCores).append(',')
            append("\"cpuSource\":").append(jsonString(cpuSource)).append(',')
            append("\"androidApi\":").append(androidApi).append(',')
            append("\"androidVersion\":").append(jsonString(androidVersion)).append(',')
            append("\"ram\":{")
            append("\"totalBytes\":").append(ramTotalBytes).append(',')
            append("\"usedBytes\":").append(ramUsedBytes).append(',')
            append("\"freeBytes\":").append(ramFreeBytes).append(',')
            append("\"usagePercent\":").append(ramPct)
            append("},")
            append("\"storage\":{")
            append("\"totalBytes\":").append(storageTotalBytes).append(',')
            append("\"usedBytes\":").append(storageUsedBytes).append(',')
            append("\"freeBytes\":").append(storageFreeBytes).append(',')
            append("\"usagePercent\":").append(storagePct)
            append('}')
            if (!batteryJsonStr.isNullOrBlank()) {
                append(",\"battery\":").append(batteryJsonStr)
            }
            append('}')
        }
    }

    fun torchJson(ok: Boolean, torchOn: Boolean, message: String): String =
        "{\"ok\":$ok,\"torch\":$torchOn,\"message\":${jsonString(message)}}"

    fun vibrateJson(ok: Boolean, durationMs: Long, message: String): String =
        "{\"ok\":$ok,\"duration\":$durationMs,\"message\":${jsonString(message)}}"

    fun wakelockJson(ok: Boolean, active: Boolean, message: String): String =
        "{\"ok\":$ok,\"active\":$active,\"message\":${jsonString(message)}}"

    fun healthJson(port: Int): String =
        "{\"ok\":true,\"bridge\":\"lenznode-native-bridge\",\"port\":$port}"

    fun errorJson(message: String): String =
        "{\"ok\":false,\"message\":${jsonString(message)}}"

    fun parseHttpTarget(rawTarget: String): Pair<String, Map<String, String>> {
        val qIdx = rawTarget.indexOf('?')
        val path = if (qIdx >= 0) rawTarget.substring(0, qIdx) else rawTarget
        val queryMap = linkedMapOf<String, String>()
        if (qIdx >= 0 && qIdx + 1 < rawTarget.length) {
            val rawQuery = rawTarget.substring(qIdx + 1)
            for (pair in rawQuery.split('&')) {
                if (pair.isBlank()) continue
                val eq = pair.indexOf('=')
                val key = if (eq >= 0) pair.substring(0, eq) else pair
                val value = if (eq >= 0) pair.substring(eq + 1) else ""
                try {
                    queryMap[URLDecoder.decode(key, "UTF-8")] = URLDecoder.decode(value, "UTF-8")
                } catch (_: Exception) {
                    queryMap[key] = value
                }
            }
        }
        return path to queryMap
    }

    fun parseJsonParams(body: String): Map<String, String> {
        val trimmed = body.trim()
        if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return emptyMap()
        val result = linkedMapOf<String, String>()
        val inner = trimmed.substring(1, trimmed.length - 1).trim()
        if (inner.isEmpty()) return emptyMap()

        val pairRegex = Regex("\"((?:\\\\.|[^\"\\\\])*)\"\\s*:\\s*(?:\"((?:\\\\.|[^\"\\\\])*)\"|(-?\\d+(?:\\.\\d+)?|true|false))")
        for (match in pairRegex.findAll(inner)) {
            val key = unescapeJson(match.groupValues[1])
            val strVal = match.groupValues[2]
            val primVal = match.groupValues[3]
            result[key] = if (primVal.isNotEmpty()) primVal else unescapeJson(strVal)
        }
        return result
    }

    private fun unescapeJson(raw: String): String {
        if (!raw.contains('\\')) return raw
        val sb = StringBuilder(raw.length)
        var i = 0
        while (i < raw.length) {
            val ch = raw[i]
            if (ch == '\\' && i + 1 < raw.length) {
                when (val next = raw[i + 1]) {
                    '\\', '"', '/' -> sb.append(next)
                    'n' -> sb.append('\n')
                    'r' -> sb.append('\r')
                    't' -> sb.append('\t')
                    else -> sb.append(next)
                }
                i += 2
            } else {
                sb.append(ch)
                i++
            }
        }
        return sb.toString()
    }
}
