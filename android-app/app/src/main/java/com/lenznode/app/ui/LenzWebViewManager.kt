package com.lenznode.app.ui

import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Message
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.MimeTypeMap
import android.webkit.RenderProcessGoneDetail
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.core.content.ContextCompat
import com.lenznode.app.BuildConfig
import com.lenznode.app.R
import com.lenznode.app.runtime.NativeFileShareHelper

class LenzWebViewManager(
    private val activity: ComponentActivity,
    private val webView: WebView,
    private val onOpenFileChooser: (Intent, ValueCallback<Array<Uri>>?) -> Unit,
    private val onPageReady: () -> Unit,
    private val onConnectionLost: (String) -> Unit,
    private val onToast: (String) -> Unit,
    private val onSwitchModeRequested: () -> Unit = {},
    private val getCurrentModeName: () -> String = { "HOST_SERVER" }
) {

    var hasLoadedOnce: Boolean = false
        private set

    private var hasErrorOnCurrentLoad: Boolean = false
    private var lastLoadedUrl: String? = null
    private var allowedBaseUri: Uri = Uri.parse("http://127.0.0.1:8080")

    @SuppressLint("SetJavaScriptEnabled")
    @Suppress("DEPRECATION")
    fun configure() {
        val isDebuggable = BuildConfig.DEBUG &&
            (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        WebView.setWebContentsDebuggingEnabled(isDebuggable)

        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        webView.setBackgroundColor(Color.parseColor("#06080A"))
        webView.isVerticalScrollBarEnabled = false
        webView.isHorizontalScrollBarEnabled = false

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = false
            allowContentAccess = true
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            cacheMode = WebSettings.LOAD_DEFAULT
            setSupportMultipleWindows(true)
            javaScriptCanOpenWindowsAutomatically = true
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val uri = request?.url ?: return false
                return handleUriNavigation(uri)
            }

            @Deprecated("Deprecated in Java")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                val parsed = url?.let { Uri.parse(it) } ?: return false
                return handleUriNavigation(parsed)
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                hasErrorOnCurrentLoad = false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                CookieManager.getInstance().flush()
                if (!hasErrorOnCurrentLoad) {
                    hasLoadedOnce = true
                    onPageReady()
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                if (request?.isForMainFrame == true) {
                    hasErrorOnCurrentLoad = true
                    val desc = error?.description?.toString()
                        ?.takeIf { it.isNotBlank() }
                        ?: activity.getString(R.string.recovery_disconnected)
                    onConnectionLost(desc)
                }
            }

            override fun onRenderProcessGone(
                view: WebView?,
                detail: RenderProcessGoneDetail?
            ): Boolean {
                hasErrorOnCurrentLoad = true
                onConnectionLost(activity.getString(R.string.recovery_disconnected))
                return true
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                val baseIntent = buildFileChooserIntent(fileChooserParams)
                val chooser = Intent.createChooser(baseIntent, "Pilih File")
                onOpenFileChooser(chooser, filePathCallback)
                return true
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                val hit = view?.hitTestResult
                val hitExtra = hit?.extra
                if (!hitExtra.isNullOrBlank() &&
                    (hit.type == WebView.HitTestResult.SRC_ANCHOR_TYPE ||
                        hit.type == WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE)
                ) {
                    val uri = Uri.parse(hitExtra)
                    if (!handleUriNavigation(uri)) {
                        view.loadUrl(hitExtra)
                    }
                    return false
                }

                val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                val tempWebView = WebView(activity)
                tempWebView.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        v: WebView?,
                        request: WebResourceRequest?
                    ): Boolean {
                        val uri = request?.url
                        if (uri != null && !handleUriNavigation(uri)) {
                            webView.loadUrl(uri.toString())
                        }
                        tempWebView.destroy()
                        return true
                    }
                }
                transport.webView = tempWebView
                resultMsg.sendToTarget()
                return true
            }
        }

        webView.setDownloadListener { url, userAgent, contentDisposition, mimetype, _ ->
            enqueueDownload(url, userAgent, contentDisposition, mimetype)
        }

        webView.addJavascriptInterface(LenzBridgeJsInterface(), "LenzAndroidBridge")
    }

    private inner class LenzBridgeJsInterface {
        @JavascriptInterface
        fun switchMode() {
            activity.runOnUiThread {
                val currentUrl = webView.url?.let { Uri.parse(it) }
                if (currentUrl != null && isInternalPanelUri(currentUrl)) {
                    onSwitchModeRequested()
                }
            }
        }

        @JavascriptInterface
        fun getAppMode(): String {
            return getCurrentModeName()
        }

        @JavascriptInterface
        fun shareFile(serverPath: String?) {
            val targetPath = serverPath?.trim().orEmpty()
            if (targetPath.isEmpty()) return
            activity.runOnUiThread {
                val currentUrl = webView.url?.let { Uri.parse(it) }
                if (currentUrl != null && isInternalPanelUri(currentUrl)) {
                    val res = NativeFileShareHelper.shareServerPath(activity, targetPath)
                    res.onFailure { err ->
                        onToast(err.message ?: "Gagal membagikan berkas")
                    }
                }
            }
        }
    }

    fun setAllowedOrigin(baseUrl: String) {
        allowedBaseUri = Uri.parse(baseUrl)
    }

    fun loadDashboardIfNeeded(panelUrl: String) {
        setAllowedOrigin(panelUrl)
        if (!hasLoadedOnce || lastLoadedUrl != panelUrl) {
            lastLoadedUrl = panelUrl
            webView.loadUrl(panelUrl)
        }
    }

    fun loadWithSessionCookie(baseUrl: String, cookieHeader: String?) {
        val cleanBase = baseUrl.trimEnd('/')
        val targetUrl = "$cleanBase/"
        setAllowedOrigin(cleanBase)
        val cm = CookieManager.getInstance()
        cm.setAcceptCookie(true)
        if (!cookieHeader.isNullOrBlank()) {
            cm.setCookie(cleanBase, cookieHeader)
            cm.flush()
        }
        hasLoadedOnce = false
        lastLoadedUrl = targetUrl
        webView.loadUrl(targetUrl)
    }

    fun reloadDashboard(panelUrl: String) {
        setAllowedOrigin(panelUrl)
        lastLoadedUrl = panelUrl
        if (webView.url.isNullOrBlank()) {
            webView.loadUrl(panelUrl)
        } else {
            webView.reload()
        }
    }

    fun resetSessionView() {
        hasLoadedOnce = false
        lastLoadedUrl = null
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.clearHistory()
    }

    fun canGoBack(): Boolean = webView.canGoBack()

    fun goBack() {
        webView.goBack()
    }

    fun destroy() {
        webView.stopLoading()
        webView.webChromeClient = null
        webView.setDownloadListener(null)
        webView.destroy()
    }

    private fun handleUriNavigation(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme == "about" || scheme == "data" || scheme == "blob") {
            return false
        }
        if (scheme == "http" || scheme == "https") {
            if (isInternalPanelUri(uri)) {
                return false
            }
            openExternalUri(uri)
            return true
        }
        openExternalUri(uri)
        return true
    }

    private fun isInternalPanelUri(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: return false
        val allowedHost = allowedBaseUri.host?.lowercase() ?: "127.0.0.1"
        val hostMatches = if (allowedHost == "127.0.0.1" || allowedHost == "localhost") {
            host == "127.0.0.1" || host == "localhost"
        } else {
            host == allowedHost
        }
        if (!hostMatches) return false

        return effectivePort(uri) == effectivePort(allowedBaseUri)
    }

    private fun effectivePort(uri: Uri): Int {
        if (uri.port != -1) return uri.port
        return if (uri.scheme.equals("https", ignoreCase = true)) 443 else 80
    }

    private fun openExternalUri(uri: Uri) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            onToast(activity.getString(R.string.external_open_failed))
        } catch (_: Exception) {
            onToast(activity.getString(R.string.external_open_failed))
        }
    }

    private fun buildFileChooserIntent(params: WebChromeClient.FileChooserParams?): Intent {
        val allowMultiple = params?.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE
        val acceptTypes = params?.acceptTypes
            ?.mapNotNull { normalizeMimeType(it) }
            ?.distinct()
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        return Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (acceptTypes.size == 1) acceptTypes.first() else "*/*"
            if (acceptTypes.size > 1) {
                putExtra(Intent.EXTRA_MIME_TYPES, acceptTypes.toTypedArray())
            }
            if (allowMultiple) {
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }
    }

    private fun normalizeMimeType(rawType: String?): String? {
        val trimmed = rawType?.trim()?.lowercase() ?: return null
        if (trimmed.isEmpty()) return null
        if (trimmed.contains('/')) return trimmed
        val ext = trimmed.removePrefix(".")
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
    }

    private fun enqueueDownload(
        url: String,
        userAgent: String,
        contentDisposition: String,
        mimetype: String
    ) {
        try {
            val uri = Uri.parse(url)
            val scheme = uri.scheme?.lowercase()
            if (scheme != "http" && scheme != "https") {
                openExternalUri(uri)
                return
            }

            val fileName = URLUtil.guessFileName(url, contentDisposition, mimetype)
                .ifBlank { "lenznode-download" }
            val cookies = CookieManager.getInstance().getCookie(url)
            val request = DownloadManager.Request(uri).apply {
                setTitle(fileName)
                setDescription("LenzNode File Manager")
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                if (mimetype.isNotBlank()) {
                    setMimeType(mimetype)
                }
                if (!cookies.isNullOrBlank()) {
                    addRequestHeader("Cookie", cookies)
                }
                if (userAgent.isNotBlank()) {
                    addRequestHeader("User-Agent", userAgent)
                }
                val canWritePublic = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                    ContextCompat.checkSelfPermission(
                        activity,
                        android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ) == PackageManager.PERMISSION_GRANTED
                if (canWritePublic) {
                    setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
                } else {
                    setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS, fileName)
                }
            }

            val dm = activity.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            if (dm != null) {
                dm.enqueue(request)
                onToast(activity.getString(R.string.download_started, fileName))
            } else {
                openExternalUri(uri)
            }
        } catch (_: Exception) {
            onToast(activity.getString(R.string.download_failed))
        }
    }
}
