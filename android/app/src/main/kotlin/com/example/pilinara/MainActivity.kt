package com.example.pilinara

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private lateinit var methodChannel: MethodChannel

    companion object {
        private const val PREFS_NAME = "pilinara_native"
        private const val KEY_IMPELLER = "enable-impeller"
    }

    /// The Impeller flag has to be known before the engine exists, i.e. before
    /// Dart can read the Hive setting, so the native side keeps its own copy.
    private val nativePrefs by lazy {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }

    /// `AudioServiceActivity` overrides `provideFlutterEngine()` and returns the
    /// engine owned by `AudioServicePlugin`, constructed without shell args, so
    /// `getFlutterShellArgs()` is never consulted. Pre-seeding the plugin's own
    /// engine id keeps audio service and activity on the same instrumented
    /// engine.
    private fun preSeedFlutterEngine() {
        val cache = FlutterEngineCache.getInstance()
        val engineId = AudioServicePlugin.getFlutterEngineId()
        if (cache.contains(engineId)) return
        val args = arrayOf("--enable-impeller=${resolveImpeller()}")
        cache.put(engineId, FlutterEngine(applicationContext, args))
    }

    private fun resolveImpeller(): Boolean {
        // `am start --ez enable-impeller true` wins over the stored value.
        val override: Boolean? = intent?.let {
            if (it.hasExtra(KEY_IMPELLER)) it.getBooleanExtra(KEY_IMPELLER, false) else null
        }
        return override ?: nativePrefs.getBoolean(KEY_IMPELLER, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "PiliNara")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getImpeller" -> result.success(nativePrefs.getBoolean(KEY_IMPELLER, false))
                "setImpeller" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    nativePrefs.edit().putBoolean(KEY_IMPELLER, enabled).apply()
                    result.success(enabled)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Must run before super.onCreate(): the parent reads the cached engine
        // inside it.
        preSeedFlutterEngine()
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
        methodChannel.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
