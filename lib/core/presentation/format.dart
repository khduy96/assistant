import 'package:flutter/material.dart';

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

/// "vừa xong", "5 phút trước", "3 giờ trước", "2 ngày trước", then the date
/// once [time] is a week old. Counted back from [now], the current time by
/// default.
String formatRelative(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 60) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  return '${time.day}/${time.month}/${time.year}';
}

/// Time left before a temp clip is purged: "còn 3 giờ", "còn 12 phút",
/// "còn dưới 1 phút", or "sắp bị xoá" once it is due.
String formatRemaining(Duration left) {
  if (left <= Duration.zero) return 'sắp bị xoá';
  if (left.inHours >= 1) return 'còn ${left.inHours} giờ';
  if (left.inMinutes >= 1) return 'còn ${left.inMinutes} phút';
  return 'còn dưới 1 phút';
}
