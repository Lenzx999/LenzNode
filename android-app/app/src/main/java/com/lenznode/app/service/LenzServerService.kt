package com.lenznode.app.service

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.lenznode.app.R
import com.lenznode.app.model.AppMode
import com.lenznode.app.model.ProgressParser
import com.lenznode.app.model.ServerPhase
import com.lenznode.app.model.ServerSnapshot
import com.lenznode.app.runtime.AppModeStore
import com.lenznode.app.runtime.NativeBridgeServer
import com.lenznode.app.runtime.RootfsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

class LenzServerService : Service() {

    companion object {
        const val ACTION_START = "com.lenznode.app.action.START"
        const val ACTION_STOP = "com.lenznode.app.action.STOP"
        const val ACTION_RESTART = "com.lenznode.app.action.RESTART"
        const val ACTION_REINSTALL_BOOTSTRAP = "com.lenznode.app.action.REINSTALL_BOOTSTRAP"

        private const val CHANNEL_ID = "lenznode_server_channel"
        private const val NOTIFICATION_ID = 1001
        private const val MAX_LOG_LINES = 200
        private const val PANEL_PORT = 8080
        private const val SSH_PORT = 2222

        private val _stateFlow = MutableStateFlow(ServerSnapshot())
        val stateFlow: StateFlow<ServerSnapshot> = _stateFlow.asStateFlow()
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lifecycleMutex = Mutex()

    private lateinit var rootfsManager: RootfsManager
    private lateinit var bridgeServer: NativeBridgeServer

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    @Volatile
    private var serverProcess: Process? = null
    private var monitorJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        rootfsManager = RootfsManager(applicationContext)
        bridgeServer = NativeBridgeServer(applicationContext, port = 48080) { requested ->
            setWakeLocksEnabled(requested ?: !(wakeLock?.isHeld == true))
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        val appMode = AppModeStore(applicationContext).getAppMode()
        if (action != ACTION_STOP && appMode != AppMode.HOST_SERVER) {
            rootfsManager.cleanupOrphanedProcesses()
            stopSelf()
            return START_NOT_STICKY
        }
        when (action) {
            ACTION_START -> {
                promoteToForeground("Menyiapkan LenzNode Server...")
                serviceScope.launch {
                    lifecycleMutex.withLock {
                        startServerInternal(forceReinstall = false)
                    }
                }
            }

            ACTION_STOP -> {
                serviceScope.launch {
                    lifecycleMutex.withLock {
                        stopServerInternal(keepNotification = false)
                    }
                }
            }

            ACTION_RESTART -> {
                promoteToForeground("Memulai ulang LenzNode Server...")
                serviceScope.launch {
                    lifecycleMutex.withLock {
                        stopProcessOnly()
                        startServerInternal(forceReinstall = false)
                    }
                }
            }

            ACTION_REINSTALL_BOOTSTRAP -> {
                promoteToForeground("Memasang ulang runtime Linux...")
                serviceScope.launch {
                    lifecycleMutex.withLock {
                        stopProcessOnly()
                        rootfsManager.clearBootstrap()
                        startServerInternal(forceReinstall = true)
                    }
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopProcessOnly()
        bridgeServer.stop()
        setWakeLocksEnabled(false)
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun startServerInternal(forceReinstall: Boolean) {
        val currentPhase = _stateFlow.value.phase
        if (!forceReinstall &&
            (currentPhase == ServerPhase.RUNNING || currentPhase == ServerPhase.STARTING) &&
            isProcessAlive(serverProcess)
        ) {
            updateNotification(_stateFlow.value)
            return
        }

        setWakeLocksEnabled(true)
        try {
            bridgeServer.start()
        } catch (e: Exception) {
            appendLog("Peringatan NativeBridge: ${e.message}")
        }

        val ip = detectLocalIp()
        _stateFlow.value = _stateFlow.value.copy(
            localIp = ip,
            panelUrl = "http://127.0.0.1:$PANEL_PORT",
            sshPort = SSH_PORT,
            errorMessage = null
        )

        if (forceReinstall || !rootfsManager.isBootstrapped()) {
            updateState(
                phase = ServerPhase.INSTALLING_ROOTFS,
                progress = 2,
                statusText = "Menyiapkan rootfs Linux minimal...",
                errorMessage = null
            )
            appendLog("Memulai instalasi bootstrap LenzNode...")

            val setupResult = rootfsManager.runBootstrapSetup(
                onLine = { line -> appendLog(line) },
                onProgress = { update ->
                    val nextPhase = update.suggestedPhase ?: _stateFlow.value.phase
                    updateState(
                        phase = nextPhase,
                        progress = update.progress,
                        statusText = update.message
                    )
                }
            )

            if (setupResult.isFailure) {
                val errMsg = setupResult.exceptionOrNull()?.message ?: "Gagal memasang runtime LenzNode."
                appendLog("ERROR: $errMsg")
                updateState(
                    phase = ServerPhase.ERROR,
                    progress = _stateFlow.value.progress,
                    statusText = "Instalasi runtime gagal",
                    errorMessage = errMsg
                )
                return
            }
        }

        updateState(
            phase = ServerPhase.STARTING,
            progress = 92,
            statusText = "Menyalakan layanan SSH & Web Panel...",
            errorMessage = null
        )
        appendLog("Menjalankan start-lenznode-app.sh...")

        val proc = try {
            rootfsManager.startServerProcess()
        } catch (e: Exception) {
            val errMsg = e.message ?: "Gagal menjalankan proses server."
            appendLog("ERROR: $errMsg")
            updateState(
                phase = ServerPhase.ERROR,
                progress = 0,
                statusText = "Gagal menyalakan server",
                errorMessage = errMsg
            )
            return
        }

        serverProcess = proc
        monitorJob?.cancel()
        monitorJob = serviceScope.launch {
            streamProcessOutput(proc)
        }

        val ready = rootfsManager.waitForPanelReady(
            probeUrl = "http://127.0.0.1:$PANEL_PORT/api/auth/status",
            timeoutMs = 60_000L,
            isProcessAlive = { isProcessAlive(proc) }
        )

        if (!ready) {
            val errMsg = if (!isProcessAlive(proc)) {
                "Proses server berhenti sebelum panel siap."
            } else {
                "Panel web tidak merespons di port $PANEL_PORT dalam 60 detik."
            }
            appendLog("ERROR: $errMsg")
            stopProcessOnly()
            updateState(
                phase = ServerPhase.ERROR,
                progress = 0,
                statusText = "Server gagal aktif",
                errorMessage = errMsg
            )
            return
        }

        val refreshedIp = detectLocalIp()
        appendLog("LenzNode aktif di http://$refreshedIp:$PANEL_PORT (SSH port $SSH_PORT)")
        updateState(
            phase = ServerPhase.RUNNING,
            progress = 100,
            statusText = "Server berjalan di http://$refreshedIp:$PANEL_PORT",
            localIp = refreshedIp,
            errorMessage = null
        )
    }

    private fun streamProcessOutput(proc: Process) {
        try {
            BufferedReader(InputStreamReader(proc.inputStream)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val raw = line ?: continue
                    val clean = ProgressParser.stripAnsi(raw)
                    if (clean.isNotBlank()) {
                        appendLog(clean)
                    }
                }
            }
        } catch (_: Exception) {
        }

        val exitCode = try {
            proc.waitFor()
        } catch (_: Exception) {
            -1
        }

        if (serverProcess === proc) {
            serverProcess = null
            val current = _stateFlow.value
            if (current.phase == ServerPhase.RUNNING || current.phase == ServerPhase.STARTING) {
                val msg = "Proses server berhenti tak terduga (kode $exitCode)."
                appendLog(msg)
                updateState(
                    phase = ServerPhase.ERROR,
                    progress = 0,
                    statusText = "Server terhenti",
                    errorMessage = msg
                )
            }
        }
    }

    private fun stopProcessOnly() {
        monitorJob?.cancel()
        monitorJob = null
        val proc = serverProcess
        serverProcess = null
        rootfsManager.terminateProcessTree(proc)
    }

    private fun stopServerInternal(keepNotification: Boolean) {
        stopProcessOnly()
        bridgeServer.stop()
        setWakeLocksEnabled(false)
        appendLog("LenzNode Server dihentikan.")
        updateState(
            phase = ServerPhase.STOPPED,
            progress = 0,
            statusText = "Server dihentikan",
            errorMessage = null
        )
        if (!keepNotification) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
    }

    @SuppressLint("WakelockTimeout")
    @Synchronized
    private fun setWakeLocksEnabled(enable: Boolean): Boolean {
        if (enable) {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lenznode:ServerWakeLock")?.apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                try {
                    wakeLock?.acquire()
                } catch (_: Exception) {
                }
            }

            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm?.createWifiLock(mode, "lenznode:ServerWifiLock")?.apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                try {
                    wifiLock?.acquire()
                } catch (_: Exception) {
                }
            }
            return true
        } else {
            try {
                if (wakeLock?.isHeld == true) wakeLock?.release()
            } catch (_: Exception) {
            }
            try {
                if (wifiLock?.isHeld == true) wifiLock?.release()
            } catch (_: Exception) {
            }
            return false
        }
    }

    private fun isProcessAlive(proc: Process?): Boolean {
        if (proc == null) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            proc.isAlive
        } else {
            try {
                proc.exitValue()
                false
            } catch (_: IllegalThreadStateException) {
                true
            }
        }
    }

    private fun updateState(
        phase: ServerPhase = _stateFlow.value.phase,
        progress: Int = _stateFlow.value.progress,
        statusText: String = _stateFlow.value.statusText,
        localIp: String = _stateFlow.value.localIp,
        errorMessage: String? = _stateFlow.value.errorMessage
    ) {
        val next = _stateFlow.value.copy(
            phase = phase,
            progress = progress.coerceIn(0, 100),
            statusText = statusText,
            localIp = localIp,
            errorMessage = errorMessage
        )
        _stateFlow.value = next
        updateNotification(next)
    }

    private fun appendLog(line: String) {
        val current = _stateFlow.value
        val updatedLogs = (current.logs + line).let { list ->
            if (list.size > MAX_LOG_LINES) list.takeLast(MAX_LOG_LINES) else list
        }
        _stateFlow.value = current.copy(logs = updatedLogs)
    }

    private fun detectLocalIp(): String {
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            var fallback: String? = null
            for (iface in interfaces) {
                if (!iface.isUp || iface.isLoopback) continue
                val name = iface.name.lowercase()
                for (addr in Collections.list(iface.inetAddresses)) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val host = addr.hostAddress ?: continue
                        if (name.startsWith("wlan") || name.startsWith("ap") || name.startsWith("eth") || name.startsWith("rndis")) {
                            return host
                        }
                        if (fallback == null) fallback = host
                    }
                }
            }
            if (fallback != null) return fallback
        } catch (_: Exception) {
        }
        return "127.0.0.1"
    }

    private fun promoteToForeground(initialText: String) {
        val notification = buildNotification(
            _stateFlow.value.copy(statusText = initialText)
        )
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun updateNotification(snapshot: ServerSnapshot) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.notify(NOTIFICATION_ID, buildNotification(snapshot))
    }

    private fun buildNotification(snapshot: ServerSnapshot): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        } ?: Intent()

        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val openPending = PendingIntent.getActivity(this, 0, launchIntent, immutableFlag)
        val stopPending = PendingIntent.getService(
            this,
            1,
            Intent(this, LenzServerService::class.java).setAction(ACTION_STOP),
            immutableFlag
        )
        val startPending = PendingIntent.getService(
            this,
            2,
            Intent(this, LenzServerService::class.java).setAction(ACTION_START),
            immutableFlag
        )
        val restartPending = PendingIntent.getService(
            this,
            3,
            Intent(this, LenzServerService::class.java).setAction(ACTION_RESTART),
            immutableFlag
        )

        val title = when (snapshot.phase) {
            ServerPhase.RUNNING -> "LenzNode Aktif (${snapshot.localIp}:$PANEL_PORT)"
            ServerPhase.INSTALLING_ROOTFS, ServerPhase.INSTALLING_DEPS -> "Menyiapkan LenzNode (${snapshot.progress}%)"
            ServerPhase.STARTING -> "Menyalakan LenzNode..."
            ServerPhase.ERROR -> "LenzNode Gangguan"
            ServerPhase.STOPPED -> "LenzNode Berhenti"
            ServerPhase.IDLE -> "LenzNode"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_lenznode_logo)
            .setContentTitle(title)
            .setContentText(snapshot.statusText)
            .setContentIntent(openPending)
            .setOngoing(snapshot.phase != ServerPhase.STOPPED && snapshot.phase != ServerPhase.ERROR)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, "Buka Dashboard", openPending)

        if (snapshot.phase == ServerPhase.STOPPED || snapshot.phase == ServerPhase.ERROR) {
            builder.addAction(0, "Mulai", startPending)
        } else {
            builder.addAction(0, "Mulai Ulang", restartPending)
            builder.addAction(0, "Hentikan", stopPending)
        }

        if (snapshot.phase == ServerPhase.INSTALLING_ROOTFS || snapshot.phase == ServerPhase.INSTALLING_DEPS) {
            builder.setProgress(100, snapshot.progress, false)
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "LenzNode Server Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Menjaga server LenzNode tetap berjalan di latar belakang"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.createNotificationChannel(channel)
        }
    }
}
