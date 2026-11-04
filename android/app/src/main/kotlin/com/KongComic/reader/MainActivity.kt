package com.KongComic.reader

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutManager
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import android.webkit.CookieManager
import androidx.activity.result.ActivityResultCallback
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import dev.flutter.packages.file_selector_android.FileUtils
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterFragmentActivity() {
    var volumeListen = VolumeListen()
    var listening = false

    private val nextLocalRequestCode = AtomicInteger()

    private val sharedTexts = ArrayList<String>()

    private var textShareHandler: ((String) -> Unit)? = null

    // Pending result of a runtime permission prompt started from Flutter
    // (see the "requestStoragePermission" channel). Kept here because the
    // answer only arrives in onRequestPermissionsResult.
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val storagePermissionRequestCode = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (intent?.action == Intent.ACTION_SEND) {
            if (intent.type == "text/plain") {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null)
                    handleSharedText(text)
            }
        }

        // Remove any stale LeakCanary dynamic shortcut that might have been
        // registered by a previous install (e.g. before the manifest fix).
        // This ensures long-press of the app icon stays clean in debug builds.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            try {
                val sm = getSystemService(ShortcutManager::class.java)
                sm?.dynamicShortcuts?.firstOrNull { it.id == "leakcanary-launcher-shortcut" }
                    ?.let { sm.removeDynamicShortcuts(listOf(it.id)) }
            } catch (_: Exception) {
                // Best-effort; safe to ignore
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Intent.ACTION_SEND) {
            if (intent.type == "text/plain") {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null)
                    handleSharedText(text)
            }
        }
    }

    private fun handleSharedText(text: String) {
        if (textShareHandler != null) {
            textShareHandler?.invoke(text)
        } else {
            sharedTexts.add(text)
        }
    }

    private fun <I, O> startContractForResult(
        contract: ActivityResultContract<I, O>,
        input: I,
        callback: ActivityResultCallback<O>
    ) {
        val key = "activity_rq_for_result#${nextLocalRequestCode.getAndIncrement()}"
        val registry = activityResultRegistry
        var launcher: ActivityResultLauncher<I>? = null
        val observer = object : LifecycleEventObserver {
            override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
                if (Lifecycle.Event.ON_DESTROY == event) {
                    launcher?.unregister()
                    lifecycle.removeObserver(this)
                }
            }
        }
        lifecycle.addObserver(observer)
        val newCallback = ActivityResultCallback<O> {
            launcher?.unregister()
            lifecycle.removeObserver(observer)
            callback.onActivityResult(it)
        }
        launcher = registry.register(key, contract, newCallback)
        launcher.launch(input)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kong_comic/method_channel"
        ).setMethodCallHandler { call, res ->
            when (call.method) {
                "getProxy" -> res.success(getProxy())
                "setScreenOn" -> {
                    val set = call.argument<Boolean>("set") ?: false
                    if (set) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    res.success(null)
                }

                "getDirectoryPath" -> {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    startContractForResult(ActivityResultContracts.StartActivityForResult(), intent) { activityResult ->
                        if (activityResult.resultCode != Activity.RESULT_OK) {
                            res.success(null)
                            return@startContractForResult
                        }
                        val pickedDirectoryUri = activityResult.data?.data
                        if (pickedDirectoryUri == null)
                            res.success(null)
                        else
                            onPickedDirectory(pickedDirectoryUri, res)
                    }
                }

                "getDeviceAbi" -> {
                    res.success(getDeviceAbi())
                }

                // Exclude a strip of the window from the system back gesture
                // (Android 10+). Used by the horizontally scrolling tab bar on
                // the root pages: the system's back-gesture hotspot is a ~20dp
                // vertical band along each screen edge, so swiping the tab bar
                // from the very left edge used to be swallowed by the system,
                // which then popped the "really exit?" dialog instead of
                // scrolling the tabs.
                //
                // Rects are physical pixels in window coordinates, and the
                // system caps the excluded height at 200dp per edge — a tab bar
                // (48dp) fits, the whole content area does not. Passing an
                // empty list clears the exclusions; the caller MUST clear them
                // when leaving the page, otherwise edge-swiping back on a
                // sub-page stops working.
                "setGestureExclusionRects" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        @Suppress("UNCHECKED_CAST")
                        val rects = call.argument<List<List<Int>>>("rects")
                            ?: emptyList()
                        window.decorView.systemGestureExclusionRects =
                            rects.mapNotNull { r ->
                                if (r.size != 4) null
                                else Rect(r[0], r[1], r[2], r[3])
                            }
                    }
                    res.success(null)
                }

                // Public (shared) external storage root, e.g. /storage/emulated/0.
                // path_provider's getExternalStorageDirectory() returns the
                // app-specific directory (/Android/data/<pkg>/files) instead,
                // so it cannot be used to reach the real Download folder.
                "getPublicStorageRoot" -> {
                    res.success(Environment.getExternalStorageDirectory().absolutePath)
                }

                // MANAGE_EXTERNAL_STORAGE is declared in the manifest but was never
                // requested at runtime, so `Download/Comic` probing used to fail
                // silently and fall back to the app-specific directory. Expose the
                // real state so the default-path logic can branch on it instead of
                // guessing, and give the settings page an entry point to grant it.
                "hasAllFilesAccess" -> {
                    res.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Environment.isExternalStorageManager()
                        } else {
                            // Pre-11 uses WRITE_EXTERNAL_STORAGE instead.
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.WRITE_EXTERNAL_STORAGE
                            ) == PackageManager.PERMISSION_GRANTED
                        }
                    )
                }

                "openAllFilesAccessSettings" -> {
                    // 返回是否真的跳转成功了。部分 ROM（MIUI / HyperOS / 部分
                    // 定制系统）没有 ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
                    // 这个页面，startActivity 直接抛 ActivityNotFoundException；
                    // 以前这里只写一行日志就 res.success(null)，界面表现为「点了
                    // 按钮什么都没有发生」，用户没有任何下一步可走。
                    res.success(openAllFilesAccessSettings())
                }

                // 后台追更检查 / 自动备份是否会被系统省电策略压制。
                //
                // 这两个任务跑在 WorkManager 里，Doze 只会把它们推迟到维护窗口，
                // 而国产 ROM 的「省电策略」「自启动管理」会直接不执行。Mihon 与
                // Tachiyomi 都把这一项摆在设置页，让用户自己决定是否豁免 ——
                // 我们同样只负责展示状态和提供入口，不替用户改系统设置。
                "isIgnoringBatteryOptimizations" -> {
                    res.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    // 先弹本应用的系统确认框（一次点击即可）；ROM 上该对话框被拦或
                    // 权限未获准时降级到「电池优化」列表页，再不行进应用详情页。
                    // 返回值只表示「是否成功把用户送到某个设置页」，真正的授权结果
                    // 由 Dart 侧在回到前台时重新查询。
                    res.success(requestIgnoreBatteryOptimizations())
                }

                // Android 10 and below: WRITE_EXTERNAL_STORAGE is a runtime
                // permission that this app never requested, so `hasAllFilesAccess`
                // was permanently false there and the public Download/Comic folder
                // could never be used. Android 11+ has no such prompt (the only
                // switch lives in the all-files-access settings page), so report
                // false and let Dart fall back to opening that page.
                "requestStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        res.success(false)
                    } else if (ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.WRITE_EXTERNAL_STORAGE
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        res.success(true)
                    } else {
                        pendingPermissionResult = res
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                            storagePermissionRequestCode
                        )
                    }
                }

                // Android 13 made notifications a runtime permission: deny it once
                // and the system never prompts again, so the app needs a direct
                // route back to the system switch. Returns whether the page
                // actually opened (see openNotificationSettings).
                "openNotificationSettings" -> {
                    res.success(openNotificationSettings())
                }

                // Android 8.0 起「安装未知应用」是按来源授予的开关。它不属于运行时
                // 权限，没有申请接口，只能查状态 + 跳设置页；不显示出来时，用户点
                // 「立即更新」只会看到安装器一闪而过，完全不知道被谁拦下了。
                "canRequestPackageInstalls" -> {
                    res.success(canRequestPackageInstalls())
                }

                "openInstallPermissionSettings" -> {
                    res.success(openInstallPermissionSettings())
                }

                "getWebViewCookie" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        res.success("")
                    } else {
                        try {
                            // 原生 CookieManager.getCookie 不受 HttpOnly 限制，
                            // 能拿到 WebView 会话里包括 cf_clearance 在内的全部 cookie，
                            // 补 document.cookie（JS 读不到 HttpOnly）的抓取缺口。
                            res.success(CookieManager.getInstance().getCookie(url) ?: "")
                        } catch (e: Exception) {
                            res.success("")
                        }
                    }
                }

                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        res.error("invalid_arguments", "Missing 'path'", null)
                    } else {
                        try {
                            installApk(path)
                            res.success(null)
                        } catch (e: Exception) {
                            res.error("install_failed", e.message, null)
                        }
                    }
                }

                "installApkFromDownloads" -> {
                    val path = call.argument<String>("path")
                    val fileName = call.argument<String>("fileName")
                    if (path.isNullOrEmpty() || fileName.isNullOrEmpty()) {
                        res.error("invalid_arguments", "Missing 'path' or 'fileName'", null)
                    } else {
                        try {
                            installApkFromDownloads(path, fileName)
                            res.success(null)
                        } catch (e: Exception) {
                            res.error("install_failed", e.message, null)
                        }
                    }
                }

                else -> res.notImplemented()
            }
        }

        val channel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kong_comic/volume")
        channel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listening = true
                    volumeListen.onUp = {
                        events.success(1)
                    }
                    volumeListen.onDown = {
                        events.success(2)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    listening = false
                }
            })

        val selectFileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kong_comic/select_file")
        selectFileChannel.setMethodCallHandler { req, res ->
            val mimeType = req.arguments<String>()
            openFile(res, mimeType!!)
        }

        val shareTextChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kong_comic/text_share")
        shareTextChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    textShareHandler = {text ->
                        events.success(text)
                    }
                    if (sharedTexts.isNotEmpty()) {
                        for (text in sharedTexts) {
                            events.success(text)
                        }
                        sharedTexts.clear()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    textShareHandler = null
                }
            })
    }

    private fun getProxy(): String {
        val host = System.getProperty("http.proxyHost")
        val port = System.getProperty("http.proxyPort")
        return if (host != null && port != null) {
            "$host:$port"
        } else {
            "No Proxy"
        }
    }

    /// Return the device's primary ABI, e.g. "arm64-v8a", "armeabi-v7a", "x86_64".
    /// Falls back to "arm64-v8a" if it cannot be determined.
    private fun getDeviceAbi(): String {
        return if (Build.SUPPORTED_ABIS.isNotEmpty()) {
            Build.SUPPORTED_ABIS[0]
        } else {
            @Suppress("DEPRECATION")
            Build.CPU_ABI
        }
    }

    /// Launch the system installer for the given APK file path.
    /// Uses FileProvider with the applicationId authority to share the file
    /// as a content URI. Required on Android 7.0+ (N+) and especially Android 13+.
    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw Exception("APK file not found: $path")
        }
        // Android 8.0+ requires the "install unknown apps" permission for this
        // specific source. Without it the install intent is silently dropped,
        // so send the user to the system setting first.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            // Report as an error so Dart doesn't announce "update ready" while
            // the user is actually sitting on the permission settings page.
            // The APK stays on disk, so tapping the completion notification
            // once permission is granted installs it.
            throw Exception("install_permission_required")
        }
        val authority = "$packageName.fileprovider"
        val uri: Uri = FileProvider.getUriForFile(this, authority, file)
        val intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(uri, "application/vnd.android.package-archive")
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    /// Manual fallback for installs that fail from the private files dir.
    ///
    /// Copies the APK into the *public* Download directory (via MediaStore on
    /// Android 10+, which needs no storage permission) and hands the resulting
    /// content URI to the package installer. Installing from a public location
    /// works on ROMs that refuse `fileprovider`-backed APKs.
    private fun installApkFromDownloads(path: String, fileName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            throw Exception("install_permission_required")
        }

        val source = File(path)
        if (!source.exists()) {
            throw Exception("APK file not found: $path")
        }

        val context = applicationContext
        val resolver = context.contentResolver

        // Drop any earlier copy so the installer never sees a stale/partial APK.
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(fileName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            resolver.delete(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                selection,
                selectionArgs
            )
        }

        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/vnd.android.package-archive")
                // IS_PENDING keeps other apps from seeing a half-written file.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val inserted = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("Could not create Download entry")
            resolver.openOutputStream(inserted)?.use { out ->
                source.inputStream().use { it.copyTo(out, bufferSize = DEFAULT_BUFFER_SIZE) }
                out.flush()
            } ?: throw Exception("Could not open Download entry for writing")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(inserted, values, null, null)
            inserted
        } else {
            @Suppress("DEPRECATION")
            val downloads = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (!downloads.exists() && !downloads.mkdirs()) {
                throw Exception("Could not access the Download directory")
            }
            val target = File(downloads, fileName)
            source.inputStream().use { input ->
                target.outputStream().use { input.copyTo(it, bufferSize = DEFAULT_BUFFER_SIZE) }
            }
            FileProvider.getUriForFile(context, "$packageName.fileprovider", target)
        }

        val intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(uri, "application/vnd.android.package-archive")
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (listening) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    volumeListen.down()
                    return true
                }

                KeyEvent.KEYCODE_VOLUME_UP -> {
                    volumeListen.up()
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    /// Ensure that the directory is accessible by dart:io
    private fun onPickedDirectory(uri: Uri, result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            var plain = uri.toString()
            if(plain.contains("%3A")) {
                plain = Uri.decode(plain)
            }
            val externalStoragePrefix = "content://com.android.externalstorage.documents/tree/primary:";
            if(plain.startsWith(externalStoragePrefix)) {
                val path = plain.substring(externalStoragePrefix.length)
                // 选中「内部存储」根目录时 path 是空串。放行的话存储路径会变成
                // /storage/emulated/0：漫画、备份、临时文件全部散落到存储根，
                // 而且「移动到当前存储路径」会把根目录下的东西一起卷进来。
                // Mihon / Tachiyomi 也明确要求用户选根目录**下**的一个文件夹。
                // 这里直接拒绝，并让 Dart 侧给出可读提示 —— 静默成功比报错更糟。
                if (path.isEmpty()) {
                    result.error(
                        "root_directory",
                        "Please pick a folder inside the storage root, not the storage root itself",
                        null
                    )
                    return
                }
                result.success(Environment.getExternalStorageDirectory().absolutePath + "/" + path)
                // 必须 return：以前这里漏了，success 之后继续往下走「复制整个
                // 目录到 cache」的兜底分支，等于把用户选中的目录（可能是几 GB
                // 的漫画库）完整复制一份到缓存，最后再 success 一次（已被忽略）。
                // 表现为「选完目录卡很久、缓存暴涨」，且复制出的副本再没人清理。
                return
            }
            // The uri cannot be parsed to plain path, use copy method
        }
        // dart:io cannot access the directory without permission.
        // so we need to copy the directory to cache directory
        val contentResolver = contentResolver
        var tmp = cacheDir
        // 根目录（DocumentFile.name 为 null）会在这里 NPE；宁可当作「没选」，
        // 也不要让 MethodChannel 回调永远不返回（Dart 侧 await 会一直挂着）。
        // 现在改成明确的错误码，界面能告诉用户「别选根目录」，而不是静默无反应。
        val dirName = DocumentFile.fromTreeUri(this, uri)?.name
        if (dirName == null) {
            result.error(
                "root_directory",
                "Please pick a folder inside the storage root, not the storage root itself",
                null
            )
            return
        }
        tmp = File(tmp, dirName)
        if(tmp.exists()) {
            tmp.deleteRecursively()
        }
        tmp.mkdir()
        Thread {
            try {
                copyDirectory(contentResolver, uri, tmp)
                result.success(tmp.absolutePath)
            }
            catch (e: Exception) {
                result.error("copy error", e.message, null)
            }
        }.start()

    }

    private fun copyDirectory(resolver: ContentResolver, srcUri: Uri, destDir: File) {
        val src = DocumentFile.fromTreeUri(this, srcUri) ?: return
        for (file in src.listFiles()) {
            if (file.isDirectory) {
                val newDir = File(destDir, file.name!!)
                newDir.mkdir()
                copyDirectory(resolver, file.uri, newDir)
            } else {
                val newFile = File(destDir, file.name!!)
                resolver.openInputStream(file.uri)?.use { input ->
                    FileOutputStream(newFile).use { output ->
                        input.copyTo(output, bufferSize = DEFAULT_BUFFER_SIZE)
                        output.flush()
                    }
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == storagePermissionRequestCode) {
            pendingPermissionResult?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pendingPermissionResult = null
        }
    }

    /// 本应用是否已被排除在电池优化之外。
    ///
    /// Android 6（API 23）起才有这套机制；更低版本没有 Doze，等价于「不受限制」。
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /// 把用户送到「是否允许后台运行」的开关前，返回是否跳转成功。
    ///
    /// 首选 ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS：系统会针对本应用弹出
    /// 一个「允许/拒绝」对话框，一次点击就能生效。它依赖 manifest 里的
    /// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 声明，也依赖 ROM 实现了这个页面 ——
    /// 部分定制系统（以及企业策略管控的设备）会直接抛异常，于是降级到电池优化
    /// 列表页让用户自己找，最后兜底到应用详情页。
    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val candidates = ArrayList<Intent>()
        // 已经豁免时再去请求只会被系统立刻拒绝（对话框都不会弹），所以改为打开
        // 列表页 —— 用户仍可能想把这个权限收回去，按钮不该变成「点了没反应」。
        if (!isIgnoringBatteryOptimizations()) {
            candidates.add(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        }
        candidates.add(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w("MainActivity", "Cannot open battery optimization page $intent: $e")
            }
        }
        return false
    }

    /// 跳本应用的通知设置页，返回是否跳转成功。
    ///
    /// 与「所有文件访问」同理：ACTION_APP_NOTIFICATION_SETTINGS 依赖 ROM 实现，
    /// 缺失时 startActivity 会抛 ActivityNotFoundException。这里降级到应用详情页，
    /// 页面打不开就返回 false，由 Dart 侧提示用户手动去系统设置。
    private fun openNotificationSettings(): Boolean {
        val candidates = ArrayList<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            candidates.add(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            )
        }
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w("MainActivity", "Cannot open notification settings page $intent: $e")
            }
        }
        return false
    }

    /// 是否允许本应用安装 APK。
    ///
    /// Android 8.0 以下没有这个开关，恒为 true；8.0+ 查询
    /// [PackageManager.canRequestPackageInstalls]。
    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            true
        } else {
            try {
                packageManager.canRequestPackageInstalls()
            } catch (e: Exception) {
                Log.w("MainActivity", "Cannot read install permission state: $e")
                // 读不到状态时按「已允许」处理：把用户引到一个其实不需要的开关前，
                // 比让他直接去装要更烦人。
                true
            }
        }
    }

    /// 跳本应用的「安装未知应用」开关，返回是否跳转成功。
    ///
    /// 与其它权限页一样做降级：本应用专属页可能在定制 ROM 上缺失，最后兜底到
    /// 应用详情页；全都失败返回 false，由 Dart 侧提示手动授予。
    private fun openInstallPermissionSettings(): Boolean {
        val candidates = ArrayList<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            candidates.add(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            candidates.add(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
        }
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w("MainActivity", "Cannot open install permission page $intent: $e")
            }
        }
        return false
    }

    /// 跳「所有文件访问」授权页，返回是否跳转成功。
    ///
    /// 按「本应用专属页 → 全部应用列表页 → 应用详情页」依次尝试：只有第一项是
    /// 官方推荐入口，但它依赖 ROM 实现了对应的 Settings Activity。国产 ROM 上
    /// 经常缺失或改名，逐级降级才能保证用户总有地方打开开关；全都失败时返回
    /// false，由 Dart 侧给出可见提示，而不是静默什么都不发生。
    private fun openAllFilesAccessSettings(): Boolean {
        val candidates = ArrayList<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            candidates.add(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
            candidates.add(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w("MainActivity", "Cannot open settings page $intent: $e")
            }
        }
        return false
    }

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED && ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            Environment.isExternalStorageManager()
        }
    }

    private fun openFile(result: MethodChannel.Result, mimeType: String) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.type = mimeType
        startContractForResult(ActivityResultContracts.StartActivityForResult(), intent){ activityResult ->
            if (activityResult.resultCode != Activity.RESULT_OK) {
                result.success(null)
                return@startContractForResult
            }
            val uri = activityResult.data?.data
            if (uri == null) {
                result.success(null)
                return@startContractForResult
            }
            val contentResolver = contentResolver
            val file = DocumentFile.fromSingleUri(this, uri)
            if (file == null) {
                result.success(null)
                return@startContractForResult
            }
            val fileName = file.name
            if (fileName == null) {
                result.success(null)
                return@startContractForResult
            }
            if(hasStoragePermission()) {
                try {
                    val filePath = FileUtils.getPathFromUri(this, uri)
                    result.success(filePath)
                    return@startContractForResult
                }
                catch (e: Exception) {
                    // ignore
                }
            }
            // use copy method
            val tmp = File(cacheDir, fileName)
            if(tmp.exists()) {
                tmp.delete()
            }
            Log.i("Venera", "copy file (${fileName}) to ${tmp.absolutePath}")
            Thread {
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(tmp).use { output ->
                            input.copyTo(output, bufferSize = DEFAULT_BUFFER_SIZE)
                            output.flush()
                        }
                    }
                    result.success(tmp.absolutePath)
                }
                catch (e: Exception) {
                    result.error("copy error", e.message, null)
                }
            }.start()
        }
    }
}

class VolumeListen {
    var onUp = fun() {}
    var onDown = fun() {}
    fun up() {
        onUp()
    }

    fun down() {
        onDown()
    }
}
