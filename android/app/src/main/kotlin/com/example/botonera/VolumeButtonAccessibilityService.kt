package com.example.botonera

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import androidx.core.content.ContextCompat

class VolumeButtonAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        }
        Log.d(TAG, "Volume button accessibility service connected")
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) {
            return false
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        Log.d(
            TAG,
            "key down code=${event.keyCode} locked=${isDeviceLocked()} interactive=${powerManager.isInteractive}"
        )

        if (!shouldHandleVolumeKey()) {
            return false
        }

        val action = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> BackgroundAudioService.ACTION_VOLUME_UP
            KeyEvent.KEYCODE_VOLUME_DOWN -> BackgroundAudioService.ACTION_VOLUME_DOWN
            else -> return false
        }

        try {
            ContextCompat.startForegroundService(
                this,
                Intent(this, BackgroundAudioService::class.java).apply {
                    this.action = action
                }
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not dispatch volume key to background service", e)
        }

        return true
    }

    private fun isDeviceLocked(): Boolean {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return keyguardManager.isKeyguardLocked
    }

    private fun shouldHandleVolumeKey(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return isDeviceLocked() || !powerManager.isInteractive
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    companion object {
        private const val TAG = "BotoneraVolumeKeys"
    }
}
