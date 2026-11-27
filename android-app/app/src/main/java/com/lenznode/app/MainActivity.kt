package com.lenznode.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.webkit.ValueCallback
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.lenznode.app.databinding.ActivityMainBinding
import com.lenznode.app.model.AppMode
import com.lenznode.app.model.ServerPhase
import com.lenznode.app.model.ServerSnapshot
import com.lenznode.app.runtime.AppModeStore
import com.lenznode.app.service.LenzServerService
import com.lenznode.app.ui.LenzWebViewManager
import com.lenznode.app.ui.RemoteConnectController
import com.lenznode.app.ui.SetupOverlayController
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var modeStore: AppModeStore
    private lateinit var webViewManager: LenzWebViewManager
    private lateinit var setupController: SetupOverlayController
    private lateinit var remoteController: RemoteConnectController

    private var currentMode: AppMode = AppMode.UNSELECTED
    private var activeRemoteUrl: String? = null
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var userManuallyOpenedLogs: Boolean = false
    private var webViewConnected: Boolean = false
    private var lastBackPressedMs: Long = 0L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var revealFallbackRunnable: Runnable? = null

    private val fileChooserLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val callback = filePathCallback
        filePathCallback = null
        if (callback == null) return@registerForActivityResult

        if (result.resultCode != Activity.RESULT_OK || result.data == null) {
            callback.onReceiveValue(null)
            return@registerForActivityResult
        }

        val data = result.data!!
        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null && clipData.itemCount > 0) {
            for (i in 0 until clipData.itemCount) {
                clipData.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        callback.onReceiveValue(if (uris.isEmpty()) null else uris.toTypedArray())
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
        maybePromptBatteryOptimizationOnce()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        modeStore = AppModeStore(applicationContext)
        applySystemAndImeInsets()
        setupControllers()
        setupBackNavigation()
        observeServerState()

        applyAppMode(modeStore.getAppMode(), initialLaunch = true)
    }

    private fun applySystemAndImeInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.rootContainer) { view, insets ->
            val barsAndIme = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime()
            )
            view.setPadding(
                barsAndIme.left,
                barsAndIme.top,
                barsAndIme.right,
                barsAndIme.bottom
            )
            insets
        }
    }

    private fun setupControllers() {
        binding.cardModeHost.setOnClickListener {
            modeStore.setAppMode(AppMode.HOST_SERVER)
            applyAppMode(AppMode.HOST_SERVER, initialLaunch = false)
        }

        binding.cardModeRemote.setOnClickListener {
            modeStore.setAppMode(AppMode.REMOTE_CLIENT)
            applyAppMode(AppMode.REMOTE_CLIENT, initialLaunch = false)
        }

        binding.btnHostSwitchMode.setOnClickListener {
            switchBackToModeSelector()
        }

        setupController = SetupOverlayController(
            context = this,
            binding = binding,
            onStartServer = {
                userManuallyOpenedLogs = false
                sendServiceAction(LenzServerService.ACTION_START)
            },
            onStopServer = {
                sendServiceAction(LenzServerService.ACTION_STOP)
            },
            onRetryServer = {
                userManuallyOpenedLogs = false
                sendServiceAction(LenzServerService.ACTION_RESTART)
            },
            onReinstallBootstrap = {
                userManuallyOpenedLogs = false
                sendServiceAction(LenzServerService.ACTION_REINSTALL_BOOTSTRAP)
            },
            onOpenDashboardRequested = {
                userManuallyOpenedLogs = false
                val snapshot = LenzServerService.stateFlow.value
                webViewManager.loadDashboardIfNeeded(snapshot.panelUrl)
                setupController.hideOverlayToWebView()
            }
        )

        remoteController = RemoteConnectController(
            context = this,
            binding = binding,
            scope = lifecycleScope,
            modeStore = modeStore,
            onSwitchMode = { switchBackToModeSelector() },
            onConnected = { normalizedUrl, cookieHeader ->
                activeRemoteUrl = normalizedUrl
                webViewConnected = false
                binding.recoveryPill.visibility = View.GONE
                webViewManager.loadWithSessionCookie(normalizedUrl, cookieHeader)
                scheduleRevealFallback()
            }
        )

        webViewManager = LenzWebViewManager(
            activity = this,
            webView = binding.webView,
            onOpenFileChooser = { intent, callback ->
                filePathCallback?.onReceiveValue(null)
                filePathCallback = callback
                try {
                    fileChooserLauncher.launch(intent)
                } catch (_: Exception) {
                    filePathCallback?.onReceiveValue(null)
                    filePathCallback = null
                }
            },
            onPageReady = {
                cancelRevealFallback()
                webViewConnected = true
                binding.recoveryPill.visibility = View.GONE
                if (currentMode == AppMode.HOST_SERVER &&
                    !userManuallyOpenedLogs &&
                    LenzServerService.stateFlow.value.phase == ServerPhase.RUNNING
                ) {
                    setupController.hideOverlayToWebView()
                } else if (currentMode == AppMode.REMOTE_CLIENT && activeRemoteUrl != null) {
                    remoteController.hideToWebView()
                }
            },
            onConnectionLost = { reason ->
                webViewConnected = false
                if (binding.webView.visibility == View.VISIBLE) {
                    if (currentMode == AppMode.HOST_SERVER) {
                        val phase = LenzServerService.stateFlow.value.phase
                        showRecoveryPill(
                            text = if (phase == ServerPhase.RUNNING) reason else getString(R.string.recovery_stopped),
                            isError = true,
                            secondaryTextRes = R.string.recovery_console
                        )
                    } else if (currentMode == AppMode.REMOTE_CLIENT) {
                        showRecoveryPill(
                            text = reason,
                            isError = true,
                            secondaryTextRes = R.string.recovery_servers
                        )
                    }
                }
            },
            onToast = { msg ->
                Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            },
            onSwitchModeRequested = {
                switchBackToModeSelector()
            },
            getCurrentModeName = {
                currentMode.name
            }
        )
        webViewManager.configure()

        binding.btnRecoveryReconnect.setOnClickListener {
            binding.recoveryPill.visibility = View.GONE
            if (currentMode == AppMode.HOST_SERVER) {
                val snapshot = LenzServerService.stateFlow.value
                if (snapshot.phase == ServerPhase.RUNNING) {
                    webViewManager.reloadDashboard(snapshot.panelUrl)
                } else {
                    userManuallyOpenedLogs = false
                    sendServiceAction(LenzServerService.ACTION_START)
                    setupController.showOverlay()
                }
            } else if (currentMode == AppMode.REMOTE_CLIENT) {
                val remoteUrl = activeRemoteUrl
                if (remoteUrl != null) {
                    webViewManager.reloadDashboard("$remoteUrl/")
                } else {
                    remoteController.reconnectActiveOrShow()
                }
            }
        }

        binding.btnRecoverySecondary.setOnClickListener {
            binding.recoveryPill.visibility = View.GONE
            if (currentMode == AppMode.HOST_SERVER) {
                userManuallyOpenedLogs = true
                setupController.showOverlay()
            } else if (currentMode == AppMode.REMOTE_CLIENT) {
                activeRemoteUrl = null
                binding.webView.visibility = View.INVISIBLE
                webViewManager.resetSessionView()
                remoteController.show(animated = true, autoConnectActiveProfile = false)
            }
        }
    }

    private fun applyAppMode(mode: AppMode, initialLaunch: Boolean) {
        currentMode = mode
        cancelRevealFallback()
        binding.recoveryPill.visibility = View.GONE

        when (mode) {
            AppMode.UNSELECTED -> {
                activeRemoteUrl = null
                webViewConnected = false
                binding.webView.visibility = View.INVISIBLE
                setupController.hideOverlayImmediate()
                remoteController.hideImmediate()
                showModeSelector(animated = !initialLaunch)
            }

            AppMode.HOST_SERVER -> {
                activeRemoteUrl = null
                hideModeSelectorImmediate()
                remoteController.hideImmediate()
                setupController.showOverlay(animated = !initialLaunch)
                sendServiceAction(LenzServerService.ACTION_START)
                requestNotificationPermissionThenBatteryOpt()
                handleSnapshot(LenzServerService.stateFlow.value)
            }

            AppMode.REMOTE_CLIENT -> {
                userManuallyOpenedLogs = false
                hideModeSelectorImmediate()
                setupController.hideOverlayImmediate()
                binding.webView.visibility = View.INVISIBLE
                remoteController.show(
                    animated = !initialLaunch,
                    autoConnectActiveProfile = initialLaunch
                )
            }
        }
    }

    private fun switchBackToModeSelector() {
        cancelRevealFallback()
        if (currentMode == AppMode.HOST_SERVER) {
            val phase = LenzServerService.stateFlow.value.phase
            if (phase != ServerPhase.STOPPED && phase != ServerPhase.IDLE) {
                startService(Intent(this, LenzServerService::class.java).setAction(LenzServerService.ACTION_STOP))
            }
        }
        activeRemoteUrl = null
        webViewConnected = false
        userManuallyOpenedLogs = false
        webViewManager.resetSessionView()
        modeStore.setAppMode(AppMode.UNSELECTED)
        applyAppMode(AppMode.UNSELECTED, initialLaunch = false)
    }

    private fun showModeSelector(animated: Boolean) {
        if (binding.modeSelectorView.visibility == View.VISIBLE && binding.modeSelectorView.alpha >= 1f) return
        binding.modeSelectorView.visibility = View.VISIBLE
        if (animated) {
            binding.modeSelectorView.alpha = 0f
            binding.modeSelectorView.animate().alpha(1f).setDuration(200L).start()
        } else {
            binding.modeSelectorView.alpha = 1f
        }
    }

    private fun hideModeSelectorImmediate() {
        binding.modeSelectorView.animate().cancel()
        binding.modeSelectorView.visibility = View.GONE
        binding.modeSelectorView.alpha = 1f
    }

    private fun setupBackNavigation() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (currentMode == AppMode.HOST_SERVER &&
                    setupController.isOverlayVisible() &&
                    LenzServerService.stateFlow.value.phase == ServerPhase.RUNNING &&
                    webViewManager.hasLoadedOnce
                ) {
                    userManuallyOpenedLogs = false
                    setupController.hideOverlayToWebView()
                    return
                }

                if (binding.webView.visibility == View.VISIBLE && webViewManager.canGoBack()) {
                    webViewManager.goBack()
                    return
                }

                if (currentMode == AppMode.REMOTE_CLIENT &&
                    binding.webView.visibility == View.VISIBLE &&
                    !remoteController.isVisible()
                ) {
                    activeRemoteUrl = null
                    webViewConnected = false
                    binding.webView.visibility = View.INVISIBLE
                    webViewManager.resetSessionView()
                    remoteController.show(animated = true, autoConnectActiveProfile = false)
                    return
                }

                val now = System.currentTimeMillis()
                if (now - lastBackPressedMs < 2000L) {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                } else {
                    lastBackPressedMs = now
                    Toast.makeText(
                        this@MainActivity,
                        R.string.press_back_again,
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        })
    }

    private fun observeServerState() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                LenzServerService.stateFlow.collect { snapshot ->
                    if (currentMode == AppMode.HOST_SERVER) {
                        handleSnapshot(snapshot)
                    }
                }
            }
        }
    }

    private fun handleSnapshot(snapshot: ServerSnapshot) {
        if (currentMode != AppMode.HOST_SERVER) return
        setupController.render(snapshot)

        when (snapshot.phase) {
            ServerPhase.RUNNING -> {
                if (!userManuallyOpenedLogs) {
                    webViewManager.loadDashboardIfNeeded(snapshot.panelUrl)
                    if (webViewConnected) {
                        binding.recoveryPill.visibility = View.GONE
                        setupController.hideOverlayToWebView()
                    } else {
                        scheduleRevealFallback()
                    }
                }
            }

            ServerPhase.STOPPED, ServerPhase.ERROR -> {
                cancelRevealFallback()
                webViewConnected = false
                if (snapshot.phase == ServerPhase.ERROR) {
                    setupController.setConsoleExpanded(true)
                }
                if (binding.webView.visibility == View.VISIBLE && !setupController.isOverlayVisible()) {
                    showRecoveryPill(
                        text = if (snapshot.phase == ServerPhase.ERROR) {
                            getString(R.string.recovery_disconnected)
                        } else {
                            getString(R.string.recovery_stopped)
                        },
                        isError = snapshot.phase == ServerPhase.ERROR,
                        secondaryTextRes = R.string.recovery_console
                    )
                }
            }

            ServerPhase.IDLE,
            ServerPhase.INSTALLING_ROOTFS,
            ServerPhase.INSTALLING_DEPS,
            ServerPhase.STARTING -> {
                cancelRevealFallback()
                webViewConnected = false
                binding.recoveryPill.visibility = View.GONE
                if (!setupController.isOverlayVisible()) {
                    setupController.showOverlay()
                }
            }
        }
    }

    private fun scheduleRevealFallback() {
        if (revealFallbackRunnable != null) return
        val runnable = Runnable {
            revealFallbackRunnable = null
            if (isFinishing) return@Runnable
            if (currentMode == AppMode.HOST_SERVER &&
                !userManuallyOpenedLogs &&
                LenzServerService.stateFlow.value.phase == ServerPhase.RUNNING
            ) {
                webViewManager.loadDashboardIfNeeded(LenzServerService.stateFlow.value.panelUrl)
                setupController.hideOverlayToWebView()
            } else if (currentMode == AppMode.REMOTE_CLIENT && activeRemoteUrl != null) {
                remoteController.hideToWebView()
            }
        }
        revealFallbackRunnable = runnable
        mainHandler.postDelayed(runnable, 2500L)
    }

    private fun cancelRevealFallback() {
        revealFallbackRunnable?.let { mainHandler.removeCallbacks(it) }
        revealFallbackRunnable = null
    }

    private fun showRecoveryPill(text: String, isError: Boolean, secondaryTextRes: Int) {
        binding.recoveryText.text = text
        binding.btnRecoverySecondary.setText(secondaryTextRes)
        val colorRes = if (isError) R.color.lenz_accent_rose else R.color.lenz_accent_amber
        ViewCompat.setBackgroundTintList(
            binding.recoveryDot,
            ColorStateList.valueOf(ContextCompat.getColor(this, colorRes))
        )
        binding.recoveryPill.visibility = View.VISIBLE
    }

    private fun sendServiceAction(action: String) {
        val intent = Intent(this, LenzServerService::class.java).setAction(action)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun requestNotificationPermissionThenBatteryOpt() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                return
            }
        }
        maybePromptBatteryOptimizationOnce()
    }

    @SuppressLint("BatteryLife")
    private fun maybePromptBatteryOptimizationOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return
        if (pm.isIgnoringBatteryOptimizations(packageName)) return

        val prefs = getSharedPreferences("lenznode_prefs", MODE_PRIVATE)
        if (prefs.getBoolean("battery_prompt_shown", false)) return
        prefs.edit().putBoolean("battery_prompt_shown", true).apply()

        MaterialAlertDialogBuilder(this, R.style.Theme_LenzNode_Dialog)
            .setTitle(R.string.battery_opt_title)
            .setMessage(R.string.battery_opt_message)
            .setNegativeButton(R.string.battery_opt_later, null)
            .setPositiveButton(R.string.battery_opt_allow) { _, _ ->
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (_: Exception) {
                }
            }
            .show()
    }

    override fun onDestroy() {
        cancelRevealFallback()
        remoteController.cancelPendingConnect()
        filePathCallback?.onReceiveValue(null)
        filePathCallback = null
        webViewManager.destroy()
        super.onDestroy()
    }
}
