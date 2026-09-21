/// Vietnamese relative-time helpers shared by the list and detail views.
String formatRelative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  return '${time.day}/${time.month}/${time.year}';
}

String formatRemaining(Duration left) {
  if (left <= Duration.zero) return 'sắp bị xoá';
  if (left.inHours >= 1) return 'còn ${left.inHours} giờ';
  if (left.inMinutes >= 1) return 'còn ${left.inMinutes} phút';
  return 'còn dưới 1 phút';
}
