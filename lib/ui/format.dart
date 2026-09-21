import 'package:flutter/material.dart';

import '../models/reminder.dart';

String two(int v) => v.toString().padLeft(2, '0');

String formatTime(TimeOfDay t) => '${two(t.hour)}:${two(t.minute)}';

String formatDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${two(d.hour)}:${two(d.minute)}';

/// "2 giờ", "30 phút", "1 giờ 30 phút".
String formatEvery(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m phút';
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

/// "còn 1 ngày 3 giờ", "còn 12 phút", "còn 45 giây".
String formatCountdown(Duration d) {
  if (d.isNegative) return 'đã qua';
  if (d.inSeconds < 60) return 'còn ${d.inSeconds} giây';
  if (d.inMinutes < 60) return 'còn ${d.inMinutes} phút';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? 'còn ${d.inHours} giờ' : 'còn ${d.inHours} giờ $m phút';
  }
  final h = d.inHours % 24;
  return h == 0 ? 'còn ${d.inDays} ngày' : 'còn ${d.inDays} ngày $h giờ';
}

/// Human description of when a reminder fires, e.g.
/// "Hàng ngày lúc 10:00, lặp mỗi 2 giờ đến 22:00".
String describeSchedule(Reminder r) {
  final time = formatTime(r.time);
  final String base;
  switch (r.repeat) {
    case RepeatRule.once:
      base = '${formatDate(r.date)} lúc $time';
    case RepeatRule.daily:
      base = 'Hàng ngày lúc $time';
    case RepeatRule.weekly:
      if (r.weekdays.isEmpty) {
        base = 'Chưa chọn thứ — lúc $time';
      } else {
        final days = (r.weekdays.toList()..sort())
            .map((d) => weekdayShortNames[d]!)
            .join(', ');
        base = '$days lúc $time';
      }
  }
  if (!r.repeatsWithinDay) return base;
  return '$base, lặp mỗi ${formatEvery(r.repeatEveryMinutes)}'
      ' đến ${formatTime(r.endTime!)}';
}

/// Long countdown for deadlines: "2 ngày 05:12:33", "05:12:33", "00:04:09".
String formatLongCountdown(Duration d) {
  final abs = d.abs();
  final days = abs.inDays;
  final hours = abs.inHours % 24;
  final minutes = abs.inMinutes % 60;
  final seconds = abs.inSeconds % 60;
  final clock = '${two(hours)}:${two(minutes)}:${two(seconds)}';
  return days > 0 ? '$days ngày $clock' : clock;
}
