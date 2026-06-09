package com.example.botonera

import android.Manifest
import android.app.ForegroundServiceStartNotAllowedException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "botonera/hardware"
    private val tag = "BotoneraMainActivity"
    private var channel: MethodChannel? = null
    private var interceptEnabled = false
    private var pendingResult: MethodChannel.Result? = null
    private var pendingForegroundServiceIntent: Intent? = null
    private var foregroundServiceStartAttempts = 0
    private var isActivityResumed = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        pendingResult?.success(granted)
        pendingResult = null
    }

    private val batteryOptimizationLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        pendingResult?.success(isIgnoringBatteryOptimizations())
        pendingResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setInterceptEnabled" -> {
                        interceptEnabled = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations(result)
                    }
                    "isNotificationPermissionGranted" -> {
                        result.success(isNotificationPermissionGranted())
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermission(result)
                    }
                    "isVolumeAccessibilityServiceEnabled" -> {
                        result.success(isVolumeAccessibilityServiceEnabled())
                    }
                    "requestVolumeAccessibilityService" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(isVolumeAccessibilityServiceEnabled())
                    }
                    "startOrUpdateBackgroundService" -> {
                        val args = call.arguments as? Map<*, *>
                        startOrUpdateBackgroundService(args)
                        result.success(null)
                    }
                    "stopBackgroundService" -> {
                        stopService(Intent(this@MainActivity, BackgroundAudioService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        setAppForeground(true)
        mainHandler.postDelayed({ flushPendingForegroundServiceStart() }, 300)
    }

    override fun onPostResume() {
        super.onPostResume()
        mainHandler.postDelayed({ flushPendingForegroundServiceStart() }, 300)
    }

    override fun onPause() {
        isActivityResumed = false
        setAppForeground(false)
        super.onPause()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!interceptEnabled || event.action != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        val buttonName = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "volume_up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "volume_down"
            KeyEvent.KEYCODE_HEADSETHOOK -> "headset"
            else -> null
        }

        if (buttonName != null) {
            channel?.invokeMethod("buttonPressed", buttonName)
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    private fun isNotificationPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }

        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        if (isNotificationPermissionGranted()) {
            result.success(true)
            return
        }

        pendingResult = result
        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }

        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }

        pendingResult = result
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName")
        )
        batteryOptimizationLauncher.launch(intent)
    }

    private fun startOrUpdateBackgroundService(args: Map<*, *>?) {
        val intent = Intent(this, BackgroundAudioService::class.java).apply {
            action = BackgroundAudioService.ACTION_START_OR_UPDATE
            putExtra(
                BackgroundAudioService.EXTRA_VOLUME_UP_PATH,
                args?.get("volumeUpPath") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_VOLUME_UP_LABEL,
                args?.get("volumeUpLabel") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_VOLUME_DOWN_PATH,
                args?.get("volumeDownPath") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_VOLUME_DOWN_LABEL,
                args?.get("volumeDownLabel") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_MEDIA_BUTTON_PATH,
                args?.get("mediaButtonPath") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_MEDIA_BUTTON_LABEL,
                args?.get("mediaButtonLabel") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_SHAKE_PATH,
                args?.get("shakePath") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_SHAKE_LABEL,
                args?.get("shakeLabel") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_SHAKE_ENABLED,
                args?.get("shakeEnabled") as? Boolean ?: false
            )
            putExtra(
                BackgroundAudioService.EXTRA_NOTIFICATION_1_PATH,
                args?.get("notification1Path") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_NOTIFICATION_1_LABEL,
                args?.get("notification1Label") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_NOTIFICATION_2_PATH,
                args?.get("notification2Path") as? String
            )
            putExtra(
                BackgroundAudioService.EXTRA_NOTIFICATION_2_LABEL,
                args?.get("notification2Label") as? String
            )
        }

        pendingForegroundServiceIntent = intent
        foregroundServiceStartAttempts = 0
        flushPendingForegroundServiceStart()
    }

    private fun isVolumeAccessibilityServiceEnabled(): Boolean {
        val expected = ComponentName(
            this,
            VolumeButtonAccessibilityService::class.java
        ).flattenToString()
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        return enabledServices.split(':').any { service ->
            service.equals(expected, ignoreCase = true)
        }
    }

    private fun setAppForeground(isForeground: Boolean) {
        getSharedPreferences(
            BackgroundAudioService.PREFS_NAME,
            Context.MODE_PRIVATE
        ).edit()
            .putBoolean(BackgroundAudioService.PREF_APP_FOREGROUND, isForeground)
            .apply()
    }

    private fun flushPendingForegroundServiceStart() {
        if (!isActivityResumed) {
            return
        }

        mainHandler.postDelayed(
            {
                if (!isActivityResumed) {
                    return@postDelayed
                }

                val intent = pendingForegroundServiceIntent ?: return@postDelayed
                try {
                    pendingForegroundServiceIntent = null
                    foregroundServiceStartAttempts = 0
                    ContextCompat.startForegroundService(this, intent)
                } catch (e: ForegroundServiceStartNotAllowedException) {
                    pendingForegroundServiceIntent = intent
                    foregroundServiceStartAttempts++
                    if (foregroundServiceStartAttempts <= 4) {
                        Log.w(
                            tag,
                            "startForegroundService rejected; retrying after resume",
                            e
                        )
                        flushPendingForegroundServiceStart()
                    } else {
                        pendingForegroundServiceIntent = null
                        foregroundServiceStartAttempts = 0
                        Log.e(tag, "startForegroundService rejected too many times", e)
                    }
                } catch (e: Exception) {
                    pendingForegroundServiceIntent = null
                    foregroundServiceStartAttempts = 0
                    Log.e(tag, "startForegroundService failed", e)
                }
            },
            if (foregroundServiceStartAttempts == 0) 300L else 700L
        )
    }
}
