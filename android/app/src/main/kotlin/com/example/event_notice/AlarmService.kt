package com.example.event_notice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Rings an alarm: plays the bundled tone in a loop on the alarm stream and
 * shows a full-screen notification, until the user turns it off.
 *
 * The sound is played here rather than left to the notification channel, so a
 * silenced notification sound or an OEM tweak cannot swallow the alarm.
 */
class AlarmService : Service() {
  companion object {
    const val ACTION_START = "com.example.event_notice.RING"
    const val ACTION_STOP = "com.example.event_notice.STOP_RINGING"

    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_PAYLOAD = "payload"

    private const val TAG = "AlarmSvc"
    private const val CHANNEL_ID = "alarm_ring_channel"
    private const val NOTIFICATION_ID = 9001
    private const val PREFS = "alarm_state"
    private const val KEY_RINGING = "ringing_payload"

    /** Stops after this long so a missed alarm cannot ring forever. */
    private const val MAX_RING_MS = 5 * 60 * 1000L

    /** Payload of the alarm ringing right now, read by the Flutter side. */
    fun ringingPayload(context: Context): String? =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_RINGING, null)

    fun stop(context: Context) {
      val intent = Intent(context, AlarmService::class.java).setAction(ACTION_STOP)
      context.startService(intent)
    }
  }

  private var player: MediaPlayer? = null
  private var vibrator: Vibrator? = null
  private var wakeLock: PowerManager.WakeLock? = null
  private var screenLock: PowerManager.WakeLock? = null
  private var keyWatch: MediaSession? = null
  private var screenOff: BroadcastReceiver? = null
  private val autoStop = Handler(Looper.getMainLooper())

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.i(TAG, "onStartCommand action=" + intent?.action + " flags=" + flags + " startId=" + startId)
    // A null intent means the system restarted the service on its own (app
    // update, low memory). Never ring on that: only a real alarm may.
    if (intent == null || intent.action != ACTION_START) {
      stopRinging()
      return START_NOT_STICKY
    }

    val title = intent.getStringExtra(EXTRA_TITLE) ?: "Nhắc việc"
    val body = intent.getStringExtra(EXTRA_BODY) ?: "Đến giờ rồi"
    val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: ""

    getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
      .putString(KEY_RINGING, payload).apply()

    Log.i(TAG, "ring start: $title")
    startForeground(NOTIFICATION_ID, buildNotification(title, body, payload))
    acquireWakeLock()
    startSound()
    startVibration()
    startKeyWatch()
    watchScreenOff()
    showAlarmScreen(payload)

    autoStop.removeCallbacksAndMessages(null)
    autoStop.postDelayed({ stopRinging() }, MAX_RING_MS)
    return START_NOT_STICKY
  }

  /**
   * Takes over the screen like a real alarm clock.
   *
   * A full-screen intent only takes over when the phone is locked, so while
   * the alarm's background-start exemption is live the activity is started
   * directly; the notification stays as the fallback if the system refuses.
   */
  private fun showAlarmScreen(payload: String) {
    runCatching {
      startActivity(
        Intent(this, MainActivity::class.java).apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
          putExtra(EXTRA_PAYLOAD, payload)
        }
      )
    }
  }

  override fun onDestroy() {
    releaseAll()
    super.onDestroy()
  }

  private fun stopRinging() {
    Log.i(TAG, "ring stop", Throwable("caller"))
    getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_RINGING).apply()
    releaseAll()
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  private fun releaseAll() {
    autoStop.removeCallbacksAndMessages(null)
    keyWatch?.let {
      it.isActive = false
      it.release()
    }
    keyWatch = null
    screenOff?.let { runCatching { unregisterReceiver(it) } }
    screenOff = null
    player?.let {
      if (it.isPlaying) it.stop()
      it.release()
    }
    player = null
    vibrator?.cancel()
    vibrator = null
    wakeLock?.let { if (it.isHeld) it.release() }
    wakeLock = null
    screenLock?.let { if (it.isHeld) it.release() }
    screenLock = null
  }

  /**
   * Lets a volume key turn the alarm off, the way a real alarm clock does.
   *
   * An active media session that owns its own volume takes the volume keys
   * system-wide, so this also works from the lock screen and from whatever app
   * is on top — our own screen only sees the keys while it has focus.
   */
  private fun startKeyWatch() {
    if (keyWatch != null) return
    runCatching {
      val session = MediaSession(this, "event_notice_alarm")
      session.setPlaybackToRemote(
        object : VolumeProvider(VOLUME_CONTROL_RELATIVE, 100, 50) {
          override fun onAdjustVolume(direction: Int) {
            if (direction != 0) {
              Log.i(TAG, "stopped by volume key")
              stopRinging()
            }
          }

          override fun onSetVolumeTo(volume: Int) {
            Log.i(TAG, "stopped by volume slider")
            stopRinging()
          }
        }
      )
      // Only a session that looks like it is playing is offered the keys.
      session.setPlaybackState(
        PlaybackState.Builder()
          .setState(PlaybackState.STATE_PLAYING, 0L, 1f)
          .setActions(PlaybackState.ACTION_STOP or PlaybackState.ACTION_PAUSE)
          .build()
      )
      session.setCallback(object : MediaSession.Callback() {
        override fun onStop() = stopRinging()
        override fun onPause() = stopRinging()
      })
      session.isActive = true
      keyWatch = session
    }.onFailure { Log.w(TAG, "no volume-key watch", it) }
  }

  /**
   * Lets the power button turn the alarm off.
   *
   * An app cannot read the power key, but the screen going dark says the same
   * thing here: the ring holds the screen lit, so it can only go off because
   * the user pressed power.
   */
  private fun watchScreenOff() {
    if (screenOff != null) return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        Log.i(TAG, "stopped by power button")
        stopRinging()
      }
    }
    runCatching {
      registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
      screenOff = receiver
    }.onFailure { Log.w(TAG, "no screen-off watch", it) }
  }

  private fun startSound() {
    if (player != null) return

    // An alarm should be audible even if the alarm stream was left low.
    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
    val wanted = (max * 0.7).toInt().coerceAtLeast(1)
    if (audio.getStreamVolume(AudioManager.STREAM_ALARM) < wanted) {
      runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, wanted, 0) }
    }

    // The phone's own alarm ringtone first: loud, long and familiar. The
    // bundled tone is the fallback when the device has no alarm sound set.
    val candidates = listOfNotNull(
      RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
      RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
      Uri.parse("android.resource://$packageName/${R.raw.alarm}")
    )
    for (uri in candidates) {
      val attempt = runCatching {
        MediaPlayer().apply {
          setAudioAttributes(
            AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_ALARM)
              .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
              .build()
          )
          setDataSource(this@AlarmService, uri)
          isLooping = true
          setVolume(1f, 1f)
          prepare()
          start()
        }
      }
      val created = attempt.getOrNull()
      if (created != null) {
        Log.i(TAG, "ringing with $uri")
        player = created
        return
      }
      Log.w(TAG, "cannot play $uri", attempt.exceptionOrNull())
    }
    Log.e(TAG, "no playable alarm sound")
  }

  private fun startVibration() {
    val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    } else {
      @Suppress("DEPRECATION")
      getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    vibrator = vib
    val pattern = longArrayOf(0, 700, 500)
    vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
  }

  private fun acquireWakeLock() {
    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
    wakeLock = power.newWakeLock(
      PowerManager.PARTIAL_WAKE_LOCK,
      "event_notice:alarm"
    ).apply { acquire(MAX_RING_MS) }

    // Holding the screen on is what makes the power button unambiguous: with
    // no display timeout to race, a dark screen means the user pressed it.
    @Suppress("DEPRECATION")
    screenLock = runCatching {
      power.newWakeLock(
        PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
        "event_notice:alarm_screen"
      ).apply { acquire(MAX_RING_MS) }
    }.getOrNull()
  }

  private fun buildNotification(title: String, body: String, payload: String): Notification {
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        CHANNEL_ID,
        "Chuông nhắc việc",
        NotificationManager.IMPORTANCE_HIGH
      ).apply {
        description = "Chuông báo khi tới giờ sự kiện"
        // The service plays the tone itself; the channel must stay silent so
        // the two do not overlap.
        setSound(null, null)
        enableVibration(false)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
      }
      manager.createNotificationChannel(channel)
    }

    val open = Intent(this, MainActivity::class.java).apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
      putExtra(EXTRA_PAYLOAD, payload)
    }
    val openIntent = PendingIntent.getActivity(
      this, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    val stopIntent = PendingIntent.getService(
      this,
      1,
      Intent(this, AlarmService::class.java).setAction(ACTION_STOP),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    return Notification.Builder(this, CHANNEL_ID)
      .setContentTitle(title)
      .setContentText(body)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setCategory(Notification.CATEGORY_ALARM)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .setOngoing(true)
      .setAutoCancel(false)
      .setContentIntent(openIntent)
      .setFullScreenIntent(openIntent, true)
      .addAction(
        Notification.Action.Builder(null, "Tắt chuông", stopIntent).build()
      )
      .build()
  }
}
