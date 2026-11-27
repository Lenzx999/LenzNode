package com.lenznode.app.model

enum class AppMode {
    UNSELECTED,
    HOST_SERVER,
    REMOTE_CLIENT
}

data class RemoteProfile(
    val id: String,
    val name: String,
    val baseUrl: String,
    val token: String,
    val lastConnectedMs: Long = 0L
)

enum class ServerPhase {
    IDLE,
    INSTALLING_ROOTFS,
    INSTALLING_DEPS,
    STARTING,
    RUNNING,
    STOPPED,
    ERROR
}

data class ServerSnapshot(
    val phase: ServerPhase = ServerPhase.IDLE,
    val progress: Int = 0,
    val statusText: String = "Menyiapkan lingkungan server...",
    val logs: List<String> = emptyList(),
    val panelUrl: String = "http://127.0.0.1:8080",
    val localIp: String = "127.0.0.1",
    val sshPort: Int = 2222,
    val errorMessage: String? = null
)

data class ProgressUpdate(
    val progress: Int,
    val message: String,
    val suggestedPhase: ServerPhase? = null
)

object ProgressParser {
    private val ANSI_REGEX = Regex("\u001B\\[[;\\d]*m")
    private val PROGRESS_REGEX = Regex("\\[PROGRESS:(\\d{1,3})]\\s*(.*)")

    fun stripAnsi(line: String): String = ANSI_REGEX.replace(line, "")

    fun parseLine(rawLine: String): ProgressUpdate? {
        val cleaned = stripAnsi(rawLine).trim()
        val match = PROGRESS_REGEX.find(cleaned) ?: return null
        val pct = match.groupValues[1].toIntOrNull()?.coerceIn(0, 100) ?: return null
        val message = match.groupValues[2].trim().ifEmpty { "Memproses ($pct%)..." }
        val lower = message.lowercase()
        val suggestedPhase = when {
            lower.contains("rootfs") ||
                lower.contains("ubuntu") ||
                lower.contains("ekstrak") ||
                lower.contains("unduh") ||
                lower.contains("download") ||
                pct < 35 -> ServerPhase.INSTALLING_ROOTFS

            lower.contains("apt") ||
                lower.contains("dependensi") ||
                lower.contains("paket") ||
                lower.contains("node") ||
                lower.contains("cloudflared") ||
                lower.contains("ssh") ||
                lower.contains("panel") ||
                pct < 90 -> ServerPhase.INSTALLING_DEPS

            else -> ServerPhase.STARTING
        }
        return ProgressUpdate(progress = pct, message = message, suggestedPhase = suggestedPhase)
    }
}

object AbiHelper {
    fun resolvePrimaryAbi(supportedAbis: Array<String>): String {
        for (abi in supportedAbis) {
            if (abi.equals("arm64-v8a", ignoreCase = true)) return "arm64-v8a"
        }
        for (abi in supportedAbis) {
            if (abi.equals("armeabi-v7a", ignoreCase = true)) return "armeabi-v7a"
        }
        return supportedAbis.firstOrNull { it.isNotBlank() } ?: "armeabi-v7a"
    }

    fun resolveLinuxArch(abi: String): String {
        val norm = abi.trim().lowercase()
        return when {
            norm.contains("arm64") || norm.contains("aarch64") || norm.contains("armv8") -> "arm64"
            norm.contains("armeabi") || norm.contains("armv7") || norm.contains("armhf") || norm == "arm" -> "armhf"
            norm.contains("x86_64") || norm.contains("amd64") -> "amd64"
            norm.contains("x86") || norm.contains("i386") || norm.contains("i686") -> "i386"
            else -> "armhf"
        }
    }

    fun resolveCloudflaredArch(abi: String): String {
        return when (resolveLinuxArch(abi)) {
            "arm64" -> "arm64"
            "armhf" -> "arm"
            "amd64" -> "amd64"
            "i386" -> "386"
            else -> "arm"
        }
    }

    fun rootfsTarballName(linuxArch: String): String {
        return "ubuntu-base-22.04.5-base-$linuxArch.tar.gz"
    }
}
