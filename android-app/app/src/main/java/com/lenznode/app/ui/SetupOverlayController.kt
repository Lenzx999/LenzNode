package com.lenznode.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.res.ColorStateList
import android.view.View
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.lenznode.app.R
import com.lenznode.app.databinding.ActivityMainBinding
import com.lenznode.app.model.ServerPhase
import com.lenznode.app.model.ServerSnapshot

class SetupOverlayController(
    private val context: Context,
    private val binding: ActivityMainBinding,
    private val onStartServer: () -> Unit,
    private val onStopServer: () -> Unit,
    private val onRetryServer: () -> Unit,
    private val onReinstallBootstrap: () -> Unit,
    private val onOpenDashboardRequested: () -> Unit
) {

    private var consoleExpanded: Boolean = false
    private var lastLogCount: Int = -1

    init {
        binding.consoleHeader.setOnClickListener {
            setConsoleExpanded(!consoleExpanded)
        }

        binding.btnCopyLogs.setOnClickListener {
            val text = binding.tvConsoleLogs.text?.toString().orEmpty()
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            if (clipboard != null && text.isNotBlank()) {
                clipboard.setPrimaryClip(ClipData.newPlainText("LenzNode Logs", text))
                Toast.makeText(context, R.string.console_copied, Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun render(snapshot: ServerSnapshot) {
        binding.tvCurrentStep.text = snapshot.statusText.ifBlank { defaultStatusText(snapshot.phase) }
        binding.tvProgressPercent.text = "${snapshot.progress.coerceIn(0, 100)}%"
        binding.setupProgressBar.setProgressCompatIfAvailable(snapshot.progress.coerceIn(0, 100))

        binding.tvHostEndpoints.text = "${snapshot.panelUrl.removePrefix("http://")}  •  SSH :${snapshot.sshPort}"

        updateStatusDot(snapshot.phase)
        updateErrorBanner(snapshot)
        updateConsoleLogs(snapshot.logs)
        updateActionButtons(snapshot.phase)
    }

    fun showOverlay(animated: Boolean = true) {
        if (binding.setupOverlay.visibility == View.VISIBLE && binding.setupOverlay.alpha >= 1f) return
        binding.setupOverlay.visibility = View.VISIBLE
        if (animated) {
            binding.setupOverlay.alpha = 0f
            binding.setupOverlay.animate().alpha(1f).setDuration(200L).start()
        } else {
            binding.setupOverlay.alpha = 1f
        }
    }

    fun hideOverlayImmediate() {
        binding.setupOverlay.animate().cancel()
        binding.setupOverlay.visibility = View.GONE
        binding.setupOverlay.alpha = 1f
    }

    fun hideOverlayToWebView() {
        binding.webView.visibility = View.VISIBLE
        if (binding.webView.alpha < 1f) {
            binding.webView.alpha = 0f
            binding.webView.animate().alpha(1f).setDuration(200L).start()
        }
        if (binding.setupOverlay.visibility == View.VISIBLE) {
            binding.setupOverlay.animate()
                .alpha(0f)
                .setDuration(200L)
                .withEndAction {
                    binding.setupOverlay.visibility = View.GONE
                    binding.setupOverlay.alpha = 1f
                }
                .start()
        }
    }

    fun isOverlayVisible(): Boolean = binding.setupOverlay.visibility == View.VISIBLE

    fun setConsoleExpanded(expanded: Boolean) {
        consoleExpanded = expanded
        binding.consoleScrollView.visibility = if (expanded) View.VISIBLE else View.GONE
        binding.btnCopyLogs.visibility = if (expanded) View.VISIBLE else View.GONE
        binding.tvConsoleToggleLabel.setText(
            if (expanded) R.string.console_toggle_hide else R.string.console_toggle_show
        )
        binding.ivConsoleChevron.animate()
            .rotation(if (expanded) 180f else 0f)
            .setDuration(180L)
            .start()
        if (expanded) {
            binding.consoleScrollView.post {
                binding.consoleScrollView.fullScroll(View.FOCUS_DOWN)
            }
        }
    }

    private fun updateStatusDot(phase: ServerPhase) {
        val dotColorRes = when (phase) {
            ServerPhase.IDLE,
            ServerPhase.INSTALLING_ROOTFS,
            ServerPhase.INSTALLING_DEPS -> R.color.lenz_accent_cyan
            ServerPhase.STARTING -> R.color.lenz_accent_amber
            ServerPhase.RUNNING -> R.color.lenz_accent_emerald
            ServerPhase.STOPPED -> R.color.lenz_text_muted
            ServerPhase.ERROR -> R.color.lenz_accent_rose
        }
        val dotColor = ContextCompat.getColor(context, dotColorRes)
        ViewCompat.setBackgroundTintList(binding.statusDot, ColorStateList.valueOf(dotColor))
    }

    private fun updateErrorBanner(snapshot: ServerSnapshot) {
        val msg = snapshot.errorMessage?.takeIf { it.isNotBlank() }
        if (snapshot.phase == ServerPhase.ERROR && msg != null) {
            binding.errorBanner.visibility = View.VISIBLE
            binding.tvErrorMessage.text = msg
        } else {
            binding.errorBanner.visibility = View.GONE
        }
    }

    private fun updateConsoleLogs(logs: List<String>) {
        if (logs.isEmpty()) {
            if (lastLogCount != 0) {
                binding.tvConsoleLogs.setText(R.string.console_empty)
                lastLogCount = 0
            }
            return
        }
        if (logs.size != lastLogCount) {
            lastLogCount = logs.size
            binding.tvConsoleLogs.text = logs.joinToString("\n")
            if (consoleExpanded) {
                binding.consoleScrollView.post {
                    binding.consoleScrollView.fullScroll(View.FOCUS_DOWN)
                }
            }
        }
    }

    private fun updateActionButtons(phase: ServerPhase) {
        val density = context.resources.displayMetrics.density
        val gapPx = (10 * density).toInt()
        val secondaryLp = binding.btnSecondaryAction.layoutParams as? android.widget.LinearLayout.LayoutParams

        when (phase) {
            ServerPhase.IDLE, ServerPhase.STOPPED -> {
                binding.btnPrimaryAction.visibility = View.VISIBLE
                binding.tvPrimaryAction.setText(R.string.btn_start)
                binding.btnPrimaryAction.setOnClickListener { onStartServer() }

                binding.btnSecondaryAction.visibility = View.VISIBLE
                binding.btnSecondaryAction.setBackgroundResource(R.drawable.bg_btn_ghost)
                binding.tvSecondaryAction.setText(R.string.btn_reinstall)
                binding.tvSecondaryAction.setTextColor(ContextCompat.getColor(context, R.color.lenz_text_secondary))
                secondaryLp?.marginStart = gapPx
                binding.btnSecondaryAction.setOnClickListener { confirmReinstall() }
            }

            ServerPhase.INSTALLING_ROOTFS,
            ServerPhase.INSTALLING_DEPS,
            ServerPhase.STARTING -> {
                binding.btnPrimaryAction.visibility = View.GONE

                binding.btnSecondaryAction.visibility = View.VISIBLE
                binding.btnSecondaryAction.setBackgroundResource(R.drawable.bg_btn_danger)
                binding.tvSecondaryAction.setText(R.string.btn_stop)
                binding.tvSecondaryAction.setTextColor(ContextCompat.getColor(context, R.color.lenz_accent_rose))
                secondaryLp?.marginStart = 0
                binding.btnSecondaryAction.setOnClickListener { onStopServer() }
            }

            ServerPhase.ERROR -> {
                binding.btnPrimaryAction.visibility = View.VISIBLE
                binding.tvPrimaryAction.setText(R.string.btn_retry)
                binding.btnPrimaryAction.setOnClickListener { onRetryServer() }

                binding.btnSecondaryAction.visibility = View.VISIBLE
                binding.btnSecondaryAction.setBackgroundResource(R.drawable.bg_btn_ghost)
                binding.tvSecondaryAction.setText(R.string.btn_reinstall)
                binding.tvSecondaryAction.setTextColor(ContextCompat.getColor(context, R.color.lenz_text_secondary))
                secondaryLp?.marginStart = gapPx
                binding.btnSecondaryAction.setOnClickListener { confirmReinstall() }
            }

            ServerPhase.RUNNING -> {
                binding.btnPrimaryAction.visibility = View.VISIBLE
                binding.tvPrimaryAction.setText(R.string.btn_open_dashboard)
                binding.btnPrimaryAction.setOnClickListener { onOpenDashboardRequested() }

                binding.btnSecondaryAction.visibility = View.VISIBLE
                binding.btnSecondaryAction.setBackgroundResource(R.drawable.bg_btn_danger)
                binding.tvSecondaryAction.setText(R.string.btn_stop)
                binding.tvSecondaryAction.setTextColor(ContextCompat.getColor(context, R.color.lenz_accent_rose))
                secondaryLp?.marginStart = gapPx
                binding.btnSecondaryAction.setOnClickListener { onStopServer() }
            }
        }
        binding.btnSecondaryAction.layoutParams = secondaryLp
    }

    private fun confirmReinstall() {
        MaterialAlertDialogBuilder(context, R.style.Theme_LenzNode_Dialog)
            .setTitle(R.string.reinstall_confirm_title)
            .setMessage(R.string.reinstall_confirm_message)
            .setNegativeButton(R.string.dialog_cancel, null)
            .setPositiveButton(R.string.dialog_confirm) { _, _ ->
                onReinstallBootstrap()
            }
            .show()
    }

    private fun defaultStatusText(phase: ServerPhase): String {
        val resId = when (phase) {
            ServerPhase.IDLE -> R.string.phase_idle
            ServerPhase.INSTALLING_ROOTFS -> R.string.phase_installing_rootfs
            ServerPhase.INSTALLING_DEPS -> R.string.phase_installing_deps
            ServerPhase.STARTING -> R.string.phase_starting
            ServerPhase.RUNNING -> R.string.phase_running
            ServerPhase.STOPPED -> R.string.phase_stopped
            ServerPhase.ERROR -> R.string.phase_error
        }
        return context.getString(resId)
    }

    private fun android.widget.ProgressBar.setProgressCompatIfAvailable(value: Int) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            setProgress(value, true)
        } else {
            progress = value
        }
    }
}
