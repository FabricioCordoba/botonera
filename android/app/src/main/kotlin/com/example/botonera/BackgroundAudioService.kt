package com.example.botonera

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import kotlin.math.sqrt

class BackgroundAudioService : Service(), SensorEventListener {
    companion object {
        const val ACTION_START_OR_UPDATE = "com.example.botonera.START_OR_UPDATE"
        const val ACTION_NOTIFICATION_PLAY_1 = "com.example.botonera.NOTIF_PLAY_1"
        const val ACTION_NOTIFICATION_PLAY_2 = "com.example.botonera.NOTIF_PLAY_2"
        const val ACTION_NOTIFICATION_STOP = "com.example.botonera.NOTIF_STOP"

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
        // 2.7g es demasiado exigente en muchos teléfonos. 2.0g suele ser más realista.
        private const val SHAKE_THRESHOLD_GRAVITY = 2.0f
        private const val SHAKE_DEBOUNCE_MS = 700L
    }

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null

    private var mediaButtonPath: String? = null
    private var mediaButtonLabel: String? = null
    private var shakePath: String? = null
    private var shakeLabel: String? = null
    private var shakeEnabled = false
    private var lastShakeTimestamp = 0L
    private var notification1Path: String? = null
    private var notification1Label: String? = null
    private var notification2Path: String? = null
    private var notification2Label: String? = null

    private var currentPlayer: MediaPlayer? = null

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        Log.d(TAG, "onCreate() accelerometer=${accelerometer != null}")
        createNotificationChannel()
        createMediaSession()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_OR_UPDATE -> {
                mediaButtonPath = intent.getStringExtra(EXTRA_MEDIA_BUTTON_PATH)
                mediaButtonLabel = intent.getStringExtra(EXTRA_MEDIA_BUTTON_LABEL)
                shakePath = intent.getStringExtra(EXTRA_SHAKE_PATH)
                shakeLabel = intent.getStringExtra(EXTRA_SHAKE_LABEL)
                shakeEnabled = intent.getBooleanExtra(EXTRA_SHAKE_ENABLED, false)
                notification1Path = intent.getStringExtra(EXTRA_NOTIFICATION_1_PATH)
                notification1Label = intent.getStringExtra(EXTRA_NOTIFICATION_1_LABEL)
                notification2Path = intent.getStringExtra(EXTRA_NOTIFICATION_2_PATH)
                notification2Label = intent.getStringExtra(EXTRA_NOTIFICATION_2_LABEL)

                Log.d(
                    TAG,
                    "startOrUpdate mediaButton=${mediaButtonPath != null} shakeEnabled=$shakeEnabled shakePath=${shakePath != null} notif1=${notification1Path != null} notif2=${notification2Path != null}"
                )

                updatePlaybackState()
                updateShakeRegistration()
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_NOTIFICATION_PLAY_1 -> {
                Log.d(TAG, "notification action: play1")
                playPath(notification1Path)
                // refrescar texto/botones si cambió algo
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_NOTIFICATION_PLAY_2 -> {
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
        sensorManager.unregisterListener(this)
        stopPlayback()
        mediaSession.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onSensorChanged(event: SensorEvent) {
        if (!shakeEnabled || shakePath == null) {
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
            isActive = true
        }
    }

    private fun triggerMediaButtonSound() {
        playPath(mediaButtonPath)
    }

    private fun updateShakeRegistration() {
        sensorManager.unregisterListener(this)
        if (shakeEnabled && shakePath != null && accelerometer != null) {
            val ok = sensorManager.registerListener(
                this,
                accelerometer,
                SensorManager.SENSOR_DELAY_GAME
            )
            Log.d(TAG, "shake listener registered=$ok")
        } else {
            Log.d(
                TAG,
                "shake listener NOT registered (enabled=$shakeEnabled path=${shakePath != null} accel=${accelerometer != null})"
            )
        }
    }

    private fun updatePlaybackState() {
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS

        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(PlaybackStateCompat.STATE_PAUSED, 0L, 1f)
                .build()
        )
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