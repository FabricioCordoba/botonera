package com.example.botonera

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.database.ContentObserver
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import kotlin.math.sqrt
import androidx.media.VolumeProviderCompat

class BackgroundAudioService : Service(), SensorEventListener {
    companion object {
        const val ACTION_START_OR_UPDATE = "com.example.botonera.START_OR_UPDATE"
        const val ACTION_VOLUME_UP = "com.example.botonera.VOLUME_UP"
        const val ACTION_VOLUME_DOWN = "com.example.botonera.VOLUME_DOWN"
        const val ACTION_NOTIFICATION_PLAY_1 = "com.example.botonera.NOTIF_PLAY_1"
        const val ACTION_NOTIFICATION_PLAY_2 = "com.example.botonera.NOTIF_PLAY_2"
        const val ACTION_NOTIFICATION_STOP = "com.example.botonera.NOTIF_STOP"

        const val EXTRA_VOLUME_UP_PATH = "volume_up_path"
        const val EXTRA_VOLUME_UP_LABEL = "volume_up_label"
        const val EXTRA_VOLUME_DOWN_PATH = "volume_down_path"
        const val EXTRA_VOLUME_DOWN_LABEL = "volume_down_label"
        const val EXTRA_MEDIA_BUTTON_PATH = "media_button_path"
        const val EXTRA_MEDIA_BUTTON_LABEL = "media_button_label"
        const val EXTRA_SHAKE_PATH = "shake_path"
        const val EXTRA_SHAKE_LABEL = "shake_label"
        const val EXTRA_SHAKE_ENABLED = "shake_enabled"
        const val EXTRA_NOTIFICATION_1_PATH = "notification_1_path"
        const val EXTRA_NOTIFICATION_1_LABEL = "notification_1_label"
        const val EXTRA_NOTIFICATION_2_PATH = "notification_2_path"
        const val EXTRA_NOTIFICATION_2_LABEL = "notification_2_label"

        private const val NOTIFICATION_CHANNEL_ID = "botonera_background_audio"
        private const val NOTIFICATION_ID = 4242
        private const val TAG = "BotoneraBgService"
        private const val SHAKE_THRESHOLD_GRAVITY = 3.0f
        private const val SHAKE_CONFIRMATION_WINDOW_MS = 260L
        private const val SHAKE_DEBOUNCE_MS = 1800L
        private const val PREFS_NAME = "botonera_background_service"
    }

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var volumeProvider: VolumeProviderCompat
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var volumeUpPath: String? = null
    private var volumeUpLabel: String? = null
    private var volumeDownPath: String? = null
    private var volumeDownLabel: String? = null
    private var mediaButtonPath: String? = null
    private var mediaButtonLabel: String? = null
    private var shakePath: String? = null
    private var shakeLabel: String? = null
    private var shakeEnabled = false
    private var lastShakeTimestamp = 0L
    private var lastShakeCandidateTimestamp = 0L
    private var shakeCandidateCount = 0
    private var notification1Path: String? = null
    private var notification1Label: String? = null
    private var notification2Path: String? = null
    private var notification2Label: String? = null
    private var syntheticRemoteVolume = 50
    private val observedVolumeStreams = intArrayOf(
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_RING,
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_ALARM
    )
    private var lastObservedVolumes: MutableMap<Int, Int> = mutableMapOf()
    private var suppressNextVolumeObserverEvent = false
    private var lastVolumeObserverTriggerMs = 0L
    private var volumeObserver: ContentObserver? = null

    private var currentPlayer: MediaPlayer? = null
    private var silentAudioTrack: AudioTrack? = null

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER, true)
                ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        } else {
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        }
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:BotoneraShake"
        )
        Log.d(
            TAG,
            "onCreate() accelerometer=${accelerometer != null} wakeUp=${accelerometer?.isWakeUpSensor == true}"
        )
        createNotificationChannel()
        createMediaSession()
        loadConfiguration()
        lastObservedVolumes = currentObservedVolumes()
        updateVolumeObserverRegistration()
        updateShakeRegistration()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_OR_UPDATE -> {
                volumeUpPath = intent.getStringExtra(EXTRA_VOLUME_UP_PATH)
                volumeUpLabel = intent.getStringExtra(EXTRA_VOLUME_UP_LABEL)
                volumeDownPath = intent.getStringExtra(EXTRA_VOLUME_DOWN_PATH)
                volumeDownLabel = intent.getStringExtra(EXTRA_VOLUME_DOWN_LABEL)
                mediaButtonPath = intent.getStringExtra(EXTRA_MEDIA_BUTTON_PATH)
                mediaButtonLabel = intent.getStringExtra(EXTRA_MEDIA_BUTTON_LABEL)
                shakePath = intent.getStringExtra(EXTRA_SHAKE_PATH)
                shakeLabel = intent.getStringExtra(EXTRA_SHAKE_LABEL)
                shakeEnabled = intent.getBooleanExtra(EXTRA_SHAKE_ENABLED, false)
                notification1Path = intent.getStringExtra(EXTRA_NOTIFICATION_1_PATH)
                notification1Label = intent.getStringExtra(EXTRA_NOTIFICATION_1_LABEL)
                notification2Path = intent.getStringExtra(EXTRA_NOTIFICATION_2_PATH)
                notification2Label = intent.getStringExtra(EXTRA_NOTIFICATION_2_LABEL)
                saveConfiguration()

                Log.d(
                    TAG,
                    "startOrUpdate volUp=${volumeUpPath != null} volDown=${volumeDownPath != null} mediaButton=${mediaButtonPath != null} shakeEnabled=$shakeEnabled shakePath=${shakePath != null} notif1=${notification1Path != null} notif2=${notification2Path != null}"
                )

                updatePlaybackState()
                updateVolumeObserverRegistration()
                updateShakeRegistration()
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_VOLUME_UP -> {
                loadConfiguration()
                promoteToForeground()
                Log.d(TAG, "accessibility action: volume up")
                playPath(volumeUpPath)
            }
            ACTION_VOLUME_DOWN -> {
                loadConfiguration()
                promoteToForeground()
                Log.d(TAG, "accessibility action: volume down")
                playPath(volumeDownPath)
            }
            ACTION_NOTIFICATION_PLAY_1 -> {
                loadConfiguration()
                Log.d(TAG, "notification action: play1")
                playPath(notification1Path)
                // refrescar texto/botones si cambió algo
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_NOTIFICATION_PLAY_2 -> {
                loadConfiguration()
                Log.d(TAG, "notification action: play2")
                playPath(notification2Path)
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_NOTIFICATION_STOP -> {
                Log.d(TAG, "notification action: stop")
                stopPlayback()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        unregisterVolumeObserver()
        stopSilentVolumeAnchor()
        sensorManager.unregisterListener(this)
        releaseShakeWakeLock()
        stopPlayback()
        mediaSession.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onSensorChanged(event: SensorEvent) {
        if (!shakeEnabled || shakePath == null) {
            return
        }

        if (!shouldHandleBackgroundTrigger()) {
            return
        }

        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val gravity = sqrt((x * x + y * y + z * z).toDouble()).toFloat() /
            SensorManager.GRAVITY_EARTH

        if (gravity < SHAKE_THRESHOLD_GRAVITY) {
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastShakeTimestamp < SHAKE_DEBOUNCE_MS) {
            return
        }

        if (now - lastShakeCandidateTimestamp > SHAKE_CONFIRMATION_WINDOW_MS) {
            shakeCandidateCount = 0
        }

        lastShakeCandidateTimestamp = now
        shakeCandidateCount++

        if (shakeCandidateCount < 2) {
            return
        }

        shakeCandidateCount = 0
        lastShakeTimestamp = now
        Log.d(TAG, "shake detected gravity=$gravity path=$shakePath")
        playPath(shakePath)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun createMediaSession() {
        mediaSession = MediaSessionCompat(this, "BotoneraMediaSession").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            setMediaButtonReceiver(
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this@BackgroundAudioService,
                    PlaybackStateCompat.ACTION_PLAY_PAUSE
                )
            )
            setCallback(
                object : MediaSessionCompat.Callback() {
                    override fun onPlay() = triggerMediaButtonSound()
                    override fun onPause() = triggerMediaButtonSound()
                    override fun onSkipToNext() = triggerMediaButtonSound()
                    override fun onSkipToPrevious() = triggerMediaButtonSound()
                }
            )
            volumeProvider = object : VolumeProviderCompat(
                VolumeProviderCompat.VOLUME_CONTROL_RELATIVE,
                100,
                syntheticRemoteVolume
            ) {
                override fun onAdjustVolume(direction: Int) {
                    syntheticRemoteVolume = (syntheticRemoteVolume + direction).coerceIn(0, 100)
                    currentVolume = syntheticRemoteVolume

                    if (!shouldHandleBackgroundTrigger()) {
                        Log.d(TAG, "ignoring media session volume while device is unlocked")
                        return
                    }

                    when {
                        direction > 0 -> {
                            Log.d(TAG, "media session volume up path=${volumeUpPath != null}")
                            playPath(volumeUpPath)
                        }
                        direction < 0 -> {
                            Log.d(TAG, "media session volume down path=${volumeDownPath != null}")
                            playPath(volumeDownPath)
                        }
                    }
                }
            }
            setPlaybackToRemote(volumeProvider)
            isActive = true
        }
    }

    private fun triggerMediaButtonSound() {
        if (!shouldHandleBackgroundTrigger()) {
            Log.d(TAG, "ignoring media button while device is unlocked")
            return
        }

        playPath(mediaButtonPath)
    }

    private fun updateShakeRegistration() {
        sensorManager.unregisterListener(this)
        if (shakeEnabled && shakePath != null && accelerometer != null) {
            acquireShakeWakeLock()
            val ok = sensorManager.registerListener(
                this,
                accelerometer,
                SensorManager.SENSOR_DELAY_GAME
            )
            Log.d(TAG, "shake listener registered=$ok")
        } else {
            releaseShakeWakeLock()
            Log.d(
                TAG,
                "shake listener NOT registered (enabled=$shakeEnabled path=${shakePath != null} accel=${accelerometer != null})"
            )
        }
    }

    private fun updateVolumeObserverRegistration() {
        unregisterVolumeObserver()

        if (!hasVolumeButtonSounds()) {
            stopSilentVolumeAnchor()
            return
        }

        startSilentVolumeAnchor()
        lastObservedVolumes = currentObservedVolumes()
        volumeObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                handleObservedVolumeChanged()
            }
        }
        contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI,
            true,
            volumeObserver!!
        )
        Log.d(TAG, "volume observer registered initial=$lastObservedVolumes")
    }

    private fun unregisterVolumeObserver() {
        val observer = volumeObserver ?: return
        contentResolver.unregisterContentObserver(observer)
        volumeObserver = null
    }

    private fun handleObservedVolumeChanged() {
        val currentVolumes = currentObservedVolumes()
        val changedStream = observedVolumeStreams.firstOrNull { stream ->
            currentVolumes[stream] != lastObservedVolumes[stream]
        } ?: return

        val currentVolume = currentVolumes[changedStream] ?: return
        val previousVolume = lastObservedVolumes[changedStream] ?: return

        if (currentVolume == previousVolume) {
            return
        }

        lastObservedVolumes = currentVolumes.toMutableMap()

        if (suppressNextVolumeObserverEvent) {
            suppressNextVolumeObserverEvent = false
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastVolumeObserverTriggerMs < 80L) {
            return
        }
        lastVolumeObserverTriggerMs = now

        if (!shouldHandleBackgroundTrigger()) {
            Log.d(TAG, "ignoring observed volume change while device is unlocked")
            return
        }

        if (currentVolume > previousVolume) {
            Log.d(TAG, "observed volume up stream=$changedStream $previousVolume->$currentVolume")
            playPath(volumeUpPath)
        } else {
            Log.d(TAG, "observed volume down stream=$changedStream $previousVolume->$currentVolume")
            playPath(volumeDownPath)
        }

        restoreVolume(changedStream, previousVolume)
    }

    private fun currentObservedVolumes(): MutableMap<Int, Int> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return observedVolumeStreams.associateWith { stream ->
            audioManager.getStreamVolume(stream)
        }.toMutableMap()
    }

    private fun restoreVolume(stream: Int, volume: Int) {
        Handler(Looper.getMainLooper()).postDelayed(
            {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                suppressNextVolumeObserverEvent = true
                try {
                    audioManager.setStreamVolume(stream, volume, 0)
                } catch (e: SecurityException) {
                    Log.w(TAG, "Could not restore volume stream=$stream", e)
                }
                lastObservedVolumes = currentObservedVolumes()
                suppressNextVolumeObserverEvent = false
            },
            120L
        )
    }

    private fun startSilentVolumeAnchor() {
        if (silentAudioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING) {
            return
        }

        stopSilentVolumeAnchor()

        try {
            val sampleRate = 8000
            val samples = ShortArray(sampleRate)
            val track = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setSampleRate(sampleRate)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(samples.size * 2)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                AudioTrack(
                    AudioManager.STREAM_MUSIC,
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    samples.size * 2,
                    AudioTrack.MODE_STATIC
                )
            }

            track.write(samples, 0, samples.size)
            track.setLoopPoints(0, samples.size, -1)
            @Suppress("DEPRECATION")
            track.setStereoVolume(0f, 0f)
            track.play()
            silentAudioTrack = track
            Log.d(TAG, "silent volume anchor started")
        } catch (e: Exception) {
            Log.w(TAG, "Could not start silent volume anchor", e)
        }
    }

    private fun stopSilentVolumeAnchor() {
        val track = silentAudioTrack ?: return
        try {
            track.pause()
            track.flush()
            track.release()
        } catch (_: Exception) {
        } finally {
            silentAudioTrack = null
        }
    }

    private fun promoteToForeground() {
        try {
            updatePlaybackState()
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            Log.w(TAG, "Could not promote service to foreground", e)
        }
    }

    private fun acquireShakeWakeLock() {
        val lock = wakeLock ?: return
        if (!lock.isHeld) {
            lock.acquire()
        }
    }

    private fun releaseShakeWakeLock() {
        val lock = wakeLock ?: return
        if (lock.isHeld) {
            lock.release()
        }
    }

    private fun saveConfiguration() {
        prefs().edit()
            .putString(EXTRA_VOLUME_UP_PATH, volumeUpPath)
            .putString(EXTRA_VOLUME_UP_LABEL, volumeUpLabel)
            .putString(EXTRA_VOLUME_DOWN_PATH, volumeDownPath)
            .putString(EXTRA_VOLUME_DOWN_LABEL, volumeDownLabel)
            .putString(EXTRA_MEDIA_BUTTON_PATH, mediaButtonPath)
            .putString(EXTRA_MEDIA_BUTTON_LABEL, mediaButtonLabel)
            .putString(EXTRA_SHAKE_PATH, shakePath)
            .putString(EXTRA_SHAKE_LABEL, shakeLabel)
            .putBoolean(EXTRA_SHAKE_ENABLED, shakeEnabled)
            .putString(EXTRA_NOTIFICATION_1_PATH, notification1Path)
            .putString(EXTRA_NOTIFICATION_1_LABEL, notification1Label)
            .putString(EXTRA_NOTIFICATION_2_PATH, notification2Path)
            .putString(EXTRA_NOTIFICATION_2_LABEL, notification2Label)
            .apply()
    }

    private fun loadConfiguration() {
        val prefs = prefs()
        volumeUpPath = prefs.getString(EXTRA_VOLUME_UP_PATH, volumeUpPath)
        volumeUpLabel = prefs.getString(EXTRA_VOLUME_UP_LABEL, volumeUpLabel)
        volumeDownPath = prefs.getString(EXTRA_VOLUME_DOWN_PATH, volumeDownPath)
        volumeDownLabel = prefs.getString(EXTRA_VOLUME_DOWN_LABEL, volumeDownLabel)
        mediaButtonPath = prefs.getString(EXTRA_MEDIA_BUTTON_PATH, mediaButtonPath)
        mediaButtonLabel = prefs.getString(EXTRA_MEDIA_BUTTON_LABEL, mediaButtonLabel)
        shakePath = prefs.getString(EXTRA_SHAKE_PATH, shakePath)
        shakeLabel = prefs.getString(EXTRA_SHAKE_LABEL, shakeLabel)
        shakeEnabled = prefs.getBoolean(EXTRA_SHAKE_ENABLED, shakeEnabled)
        notification1Path = prefs.getString(EXTRA_NOTIFICATION_1_PATH, notification1Path)
        notification1Label = prefs.getString(EXTRA_NOTIFICATION_1_LABEL, notification1Label)
        notification2Path = prefs.getString(EXTRA_NOTIFICATION_2_PATH, notification2Path)
        notification2Label = prefs.getString(EXTRA_NOTIFICATION_2_LABEL, notification2Label)
    }

    private fun prefs(): SharedPreferences {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun updatePlaybackState() {
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        val state = if (hasVolumeButtonSounds()) {
            PlaybackStateCompat.STATE_PLAYING
        } else {
            PlaybackStateCompat.STATE_PAUSED
        }

        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, 0L, 1f)
                .build()
        )
        mediaSession.isActive = true
    }

    private fun hasVolumeButtonSounds(): Boolean {
        return !volumeUpPath.isNullOrBlank() || !volumeDownPath.isNullOrBlank()
    }

    private fun shouldHandleBackgroundTrigger(): Boolean {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return keyguardManager.isKeyguardLocked || !powerManager.isInteractive
    }

    private fun buildNotification(): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )

        val notificationText = buildList {
            if (volumeUpLabel != null) add("Vol+: $volumeUpLabel")
            if (volumeDownLabel != null) add("Vol-: $volumeDownLabel")
            if (mediaButtonLabel != null) add("Auricular: $mediaButtonLabel")
            if (notification1Label != null) add("N1: $notification1Label")
            if (notification2Label != null) add("N2: $notification2Label")
            if (shakeEnabled && shakeLabel != null) add("Shake: $shakeLabel")
        }.joinToString(" | ").ifBlank {
            "Acciones listas para reproducir con el telefono bloqueado."
        }

        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Botonera activa en segundo plano")
            .setContentText(notificationText)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setStyle(MediaStyle().setMediaSession(mediaSession.sessionToken))

        var compactIndex = 0

        if (notification1Path != null) {
            builder.addAction(
                android.R.drawable.ic_media_play,
                notification1Label ?: "Sonido 1",
                buildServicePendingIntent(ACTION_NOTIFICATION_PLAY_1, 10)
            )
            compactIndex++
        }

        if (notification2Path != null) {
            builder.addAction(
                android.R.drawable.ic_media_play,
                notification2Label ?: "Sonido 2",
                buildServicePendingIntent(ACTION_NOTIFICATION_PLAY_2, 11)
            )
            compactIndex++
        }

        builder.addAction(
            android.R.drawable.ic_media_pause,
            "Stop",
            buildServicePendingIntent(ACTION_NOTIFICATION_STOP, 12)
        )

        builder.setStyle(
            MediaStyle()
                .setMediaSession(mediaSession.sessionToken)
                .setShowActionsInCompactView(
                    0,
                    if (compactIndex > 1) 1 else 0,
                    if (compactIndex > 2) 2 else 0
                )
        )

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Botonera segundo plano",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mantiene activa la reproduccion por auricular y shake."
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun playPath(path: String?) {
        if (path.isNullOrBlank()) {
            return
        }

        stopPlayback()

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.requestAudioFocus(
            null,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
        )

        currentPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(path)
            setOnPreparedListener { player ->
                player.start()
                mediaSession.setPlaybackState(
                    PlaybackStateCompat.Builder()
                        .setActions(
                            PlaybackStateCompat.ACTION_PLAY or
                                PlaybackStateCompat.ACTION_PAUSE or
                                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                        )
                        .setState(PlaybackStateCompat.STATE_PLAYING, 0L, 1f)
                        .build()
                )
            }
            setOnCompletionListener { player ->
                player.release()
                if (currentPlayer === player) {
                    currentPlayer = null
                }
                updatePlaybackState()
            }
            setOnErrorListener { player, _, _ ->
                player.release()
                if (currentPlayer === player) {
                    currentPlayer = null
                }
                updatePlaybackState()
                true
            }
            prepareAsync()
        }
    }

    private fun stopPlayback() {
        val player = currentPlayer ?: return
        try {
            player.stop()
        } catch (_: IllegalStateException) {
        } finally {
            try {
                player.release()
            } catch (_: Exception) {
            }
            currentPlayer = null
            updatePlaybackState()
        }
    }

    private fun buildServicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, BackgroundAudioService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }
}
