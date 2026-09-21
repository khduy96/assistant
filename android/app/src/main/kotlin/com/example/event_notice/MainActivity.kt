package com.example.event_notice

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Bridge between the Dart schedule and the native alarm clock plumbing. */
class MainActivity : FlutterActivity() {
  private companion object {
    const val CHANNEL = "event_notice/alarm"
    const val NOTIFICATION_PERMISSION_REQUEST = 4201
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
      call, result ->
      when (call.method) {
        "scheduleAll" -> {
          val raw = call.argument<List<Map<String, Any>>>("alarms") ?: emptyList()
          val alarms = raw.map {
            PlannedAlarm(
              id = (it["id"] as Number).toInt(),
              atMillis = (it["at"] as Number).toLong(),
              title = it["title"] as? String ?: "Nhắc việc",
              body = it["body"] as? String ?: "",
              payload = it["payload"] as? String ?: ""
            )
          }
          AlarmScheduler.replaceAll(this, alarms)
          result.success(alarms.size)
        }

        "cancelAll" -> {
          AlarmScheduler.cancelAll(this)
          result.success(null)
        }

        "stopRinging" -> {
          AlarmService.stop(this)
          result.success(null)
        }

        "testRing" -> {
          val service = Intent(this, AlarmService::class.java).apply {
            action = AlarmService.ACTION_START
            putExtra(AlarmService.EXTRA_TITLE, "Nghe thử chuông")
            putExtra(AlarmService.EXTRA_BODY, "Bấm Tắt chuông để dừng")
            putExtra(AlarmService.EXTRA_PAYLOAD, "test")
          }
          startForegroundService(service)
          result.success(null)
        }

        "ringingPayload" -> result.success(AlarmService.ringingPayload(this))

        "launchPayload" -> result.success(intent?.getStringExtra(AlarmService.EXTRA_PAYLOAD))

        "canScheduleExact" -> result.success(AlarmScheduler.canScheduleExact(this))

        "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))

        "requestOverlayPermission" -> {
          if (!Settings.canDrawOverlays(this)) {
            runCatching {
              startActivity(
                Intent(
                  Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                  Uri.parse("package:" + packageName)
                )
              )
            }
          }
          result.success(null)
        }

        "requestPermissions" -> {
          requestNotificationPermission()
          requestExactAlarmPermission()
          result.success(null)
        }

        else -> result.notImplemented()
      }
    }
  }

  /**
   * A volume key turns a ringing alarm off instead of changing the volume.
   *
   * The focused activity is handed the keys before the service's media
   * session, so the alarm screen has to catch them itself.
   */
  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    val volumeKey = when (event.keyCode) {
      KeyEvent.KEYCODE_VOLUME_UP,
      KeyEvent.KEYCODE_VOLUME_DOWN,
      KeyEvent.KEYCODE_VOLUME_MUTE -> true
      else -> false
    }
    if (volumeKey && AlarmService.ringingPayload(this) != null) {
      // On the press, not the release: nothing else should see either half.
      if (event.action == KeyEvent.ACTION_DOWN) AlarmService.stop(this)
      return true
    }
    return super.dispatchKeyEvent(event)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
  }

  private fun requestNotificationPermission() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
      PackageManager.PERMISSION_GRANTED
    if (!granted) {
      requestPermissions(
        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
        NOTIFICATION_PERMISSION_REQUEST
      )
    }
  }

  private fun requestExactAlarmPermission() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    if (AlarmScheduler.canScheduleExact(this)) return
    runCatching {
      startActivity(
        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
          .setData(Uri.parse("package:$packageName"))
      )
    }
  }
}
