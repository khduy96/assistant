package com.example.event_notice

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/** One scheduled ring. */
data class PlannedAlarm(
  val id: Int,
  val atMillis: Long,
  val title: String,
  val body: String,
  val payload: String
) {
  fun toJson(): JSONObject = JSONObject()
    .put("id", id)
    .put("at", atMillis)
    .put("title", title)
    .put("body", body)
    .put("payload", payload)

  companion object {
    fun fromJson(o: JSONObject) = PlannedAlarm(
      o.getInt("id"),
      o.getLong("at"),
      o.optString("title"),
      o.optString("body"),
      o.optString("payload")
    )
  }
}

/**
 * Hands the schedule to [AlarmManager] with `setAlarmClock`, the mode meant for
 * alarm clocks: it survives Doze and grants the app the exemption it needs to
 * start [AlarmService] from the background when it fires.
 *
 * The plan is mirrored in prefs so it can be re-armed after a reboot.
 */
object AlarmScheduler {
  private const val PREFS = "alarm_state"
  private const val KEY_PLAN = "plan"

  fun replaceAll(context: Context, alarms: List<PlannedAlarm>) {
    cancelAll(context)
    val now = System.currentTimeMillis()
    val future = alarms.filter { it.atMillis > now }
    future.forEach { arm(context, it) }
    save(context, future)
  }

  fun rearmSaved(context: Context) {
    val now = System.currentTimeMillis()
    val saved = load(context).filter { it.atMillis > now }
    saved.forEach { arm(context, it) }
    save(context, saved)
  }

  fun cancelAll(context: Context) {
    val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    load(context).forEach { manager.cancel(pendingIntent(context, it, mutableFlag = false)) }
  }

  fun canScheduleExact(context: Context): Boolean {
    val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      manager.canScheduleExactAlarms()
    } else {
      true
    }
  }

  private fun arm(context: Context, alarm: PlannedAlarm) {
    val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val show = PendingIntent.getActivity(
      context,
      100_000 + alarm.id,
      Intent(context, MainActivity::class.java),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    val fire = pendingIntent(context, alarm, mutableFlag = false)
    if (canScheduleExact(context)) {
      manager.setAlarmClock(AlarmManager.AlarmClockInfo(alarm.atMillis, show), fire)
    } else {
      // Without the exact-alarm permission the ring may drift by a few minutes.
      manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.atMillis, fire)
    }
  }

  private fun pendingIntent(
    context: Context,
    alarm: PlannedAlarm,
    mutableFlag: Boolean
  ): PendingIntent {
    val intent = Intent(context, AlarmReceiver::class.java).apply {
      action = AlarmService.ACTION_START
      putExtra(AlarmService.EXTRA_TITLE, alarm.title)
      putExtra(AlarmService.EXTRA_BODY, alarm.body)
      putExtra(AlarmService.EXTRA_PAYLOAD, alarm.payload)
    }
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (mutableFlag) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getBroadcast(context, alarm.id, intent, flags)
  }

  private fun save(context: Context, alarms: List<PlannedAlarm>) {
    val array = JSONArray()
    alarms.forEach { array.put(it.toJson()) }
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
      .putString(KEY_PLAN, array.toString()).apply()
  }

  private fun load(context: Context): List<PlannedAlarm> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_PLAN, null) ?: return emptyList()
    return runCatching {
      val array = JSONArray(raw)
      (0 until array.length()).map { PlannedAlarm.fromJson(array.getJSONObject(it)) }
    }.getOrDefault(emptyList())
  }
}

/** Fired by AlarmManager at the scheduled moment. */
class AlarmReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val service = Intent(context, AlarmService::class.java).apply {
      action = AlarmService.ACTION_START
      putExtra(AlarmService.EXTRA_TITLE, intent.getStringExtra(AlarmService.EXTRA_TITLE))
      putExtra(AlarmService.EXTRA_BODY, intent.getStringExtra(AlarmService.EXTRA_BODY))
      putExtra(AlarmService.EXTRA_PAYLOAD, intent.getStringExtra(AlarmService.EXTRA_PAYLOAD))
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      context.startForegroundService(service)
    } else {
      context.startService(service)
    }
  }
}

/** Puts the schedule back after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    AlarmScheduler.rearmSaved(context)
  }
}
