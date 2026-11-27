package com.lenznode.app.ui

import android.content.Context
import android.net.Uri
import android.text.InputType
import android.view.LayoutInflater
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.ImageButton
import android.widget.TextView
import androidx.lifecycle.LifecycleCoroutineScope
import com.lenznode.app.R
import com.lenznode.app.databinding.ActivityMainBinding
import com.lenznode.app.model.RemoteProfile
import com.lenznode.app.runtime.AppModeStore
import com.lenznode.app.runtime.RemoteAuthClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RemoteConnectController(
    private val context: Context,
    private val binding: ActivityMainBinding,
    private val scope: LifecycleCoroutineScope,
    private val modeStore: AppModeStore,
    private val onSwitchMode: () -> Unit,
    private val onConnected: (normalizedUrl: String, cookieHeader: String?) -> Unit
) {

    private val authClient = RemoteAuthClient()
    private var tokenVisible: Boolean = false
    private var connectJob: Job? = null

    init {
        binding.btnRemoteSwitchMode.setOnClickListener {
            cancelPendingConnect()
            onSwitchMode()
        }

        binding.btnToggleRemoteToken.setOnClickListener {
            tokenVisible = !tokenVisible
            val sel = binding.etRemoteToken.selectionEnd.coerceAtLeast(0)
            binding.etRemoteToken.inputType = if (tokenVisible) {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            } else {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            }
            binding.etRemoteToken.setSelection(sel.coerceAtMost(binding.etRemoteToken.text?.length ?: 0))
            binding.btnToggleRemoteToken.setImageResource(
                if (tokenVisible) R.drawable.ic_eye_off else R.drawable.ic_eye
            )
        }

        binding.etRemoteToken.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                submitForm()
                true
            } else {
                false
            }
        }

        binding.btnRemoteConnect.setOnClickListener {
            submitForm()
        }
    }

    fun show(animated: Boolean = true, autoConnectActiveProfile: Boolean = false) {
        val active = modeStore.getActiveProfile()
        if (active != null && binding.etRemoteUrl.text.isNullOrBlank()) {
            binding.etRemoteUrl.setText(active.baseUrl)
            binding.etRemoteToken.setText(active.token)
        }
        renderSavedProfiles()
        hideError()

        if (binding.remoteConnectView.visibility != View.VISIBLE) {
            binding.remoteConnectView.visibility = View.VISIBLE
            if (animated) {
                binding.remoteConnectView.alpha = 0f
                binding.remoteConnectView.animate().alpha(1f).setDuration(200L).start()
            } else {
                binding.remoteConnectView.alpha = 1f
            }
        }

        if (autoConnectActiveProfile && active != null && active.token.isNotBlank()) {
            connectTo(active.baseUrl, active.token)
        }
    }

    fun hideImmediate() {
        cancelPendingConnect()
        binding.remoteConnectView.animate().cancel()
        binding.remoteConnectView.visibility = View.GONE
        binding.remoteConnectView.alpha = 1f
    }

    fun hideToWebView() {
        binding.webView.visibility = View.VISIBLE
        if (binding.webView.alpha < 1f) {
            binding.webView.alpha = 0f
            binding.webView.animate().alpha(1f).setDuration(200L).start()
        }
        if (binding.remoteConnectView.visibility == View.VISIBLE) {
            binding.remoteConnectView.animate()
                .alpha(0f)
                .setDuration(200L)
                .withEndAction {
                    binding.remoteConnectView.visibility = View.GONE
                    binding.remoteConnectView.alpha = 1f
                }
                .start()
        }
    }

    fun isVisible(): Boolean = binding.remoteConnectView.visibility == View.VISIBLE

    fun submitForm() {
        val url = binding.etRemoteUrl.text?.toString()?.trim().orEmpty()
        val token = binding.etRemoteToken.text?.toString()?.trim().orEmpty()

        if (url.isEmpty()) {
            showError(context.getString(R.string.remote_err_empty_url))
            binding.etRemoteUrl.requestFocus()
            return
        }
        if (token.isEmpty()) {
            showError(context.getString(R.string.remote_err_empty_token))
            binding.etRemoteToken.requestFocus()
            return
        }
        connectTo(url, token)
    }

    fun reconnectActiveOrShow() {
        val active = modeStore.getActiveProfile()
        if (active != null && active.token.isNotBlank()) {
            show(animated = true, autoConnectActiveProfile = true)
        } else {
            show(animated = true, autoConnectActiveProfile = false)
        }
    }

    fun cancelPendingConnect() {
        connectJob?.cancel()
        connectJob = null
        setLoading(false)
    }

    private fun connectTo(rawUrl: String, rawToken: String) {
        if (connectJob?.isActive == true) return
        hideError()
        setLoading(true)

        connectJob = scope.launch {
            val result = withContext(Dispatchers.IO) {
                authClient.authenticate(rawUrl, rawToken)
            }
            setLoading(false)

            if (result.ok) {
                val hostLabel = try {
                    Uri.parse(result.normalizedUrl).host ?: result.normalizedUrl
                } catch (_: Exception) {
                    result.normalizedUrl
                }
                val profileId = result.normalizedUrl.lowercase()
                modeStore.saveProfile(
                    RemoteProfile(
                        id = profileId,
                        name = hostLabel,
                        baseUrl = result.normalizedUrl,
                        token = rawToken.trim(),
                        lastConnectedMs = System.currentTimeMillis()
                    )
                )
                renderSavedProfiles()
                onConnected(result.normalizedUrl, result.webViewCookieHeader())
            } else {
                showError(result.message.ifBlank { "Gagal terhubung ke server." })
            }
        }
    }

    private fun renderSavedProfiles() {
        val profiles = modeStore.getSavedProfiles()
        val container = binding.remoteSavedContainer
        container.removeAllViews()

        if (profiles.isEmpty()) {
            binding.remoteSavedSection.visibility = View.GONE
            return
        }

        binding.remoteSavedSection.visibility = View.VISIBLE
        val inflater = LayoutInflater.from(context)
        for (profile in profiles) {
            val row = inflater.inflate(R.layout.item_remote_profile, container, false)
            val tvName = row.findViewById<TextView>(R.id.tvProfileName)
            val tvUrl = row.findViewById<TextView>(R.id.tvProfileUrl)
            val btnDelete = row.findViewById<ImageButton>(R.id.btnDeleteProfile)

            tvName.text = profile.name
            tvUrl.text = profile.baseUrl

            row.setOnClickListener {
                binding.etRemoteUrl.setText(profile.baseUrl)
                binding.etRemoteToken.setText(profile.token)
                connectTo(profile.baseUrl, profile.token)
            }
            btnDelete.setOnClickListener {
                modeStore.deleteProfile(profile.id)
                renderSavedProfiles()
            }
            container.addView(row)
        }
    }

    private fun setLoading(loading: Boolean) {
        binding.btnRemoteConnect.isEnabled = !loading
        binding.pbRemoteConnecting.visibility = if (loading) View.VISIBLE else View.GONE
        binding.tvRemoteConnectBtn.setText(
            if (loading) R.string.remote_connecting else R.string.remote_btn_connect
        )
    }

    private fun showError(msg: String) {
        binding.tvRemoteError.text = msg
        binding.tvRemoteError.visibility = View.VISIBLE
    }

    private fun hideError() {
        binding.tvRemoteError.text = ""
        binding.tvRemoteError.visibility = View.GONE
    }
}
