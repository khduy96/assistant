import 'package:event_notice/core/presentation/format.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/presentation/clip_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  test('mỗi loại clip có đúng nhãn và icon như trước', () {
    expect(
      {for (final type in ClipType.values) type: (type.label, type.icon)},
      {
        ClipType.text: ('Văn bản', Icons.notes_rounded),
        ClipType.link: ('Liên kết', Icons.link_rounded),
        ClipType.email: ('Email', Icons.alternate_email_rounded),
        ClipType.phone: ('Số điện thoại', Icons.phone_rounded),
        ClipType.number: ('Số', Icons.tag_rounded),
        ClipType.color: ('Màu', Icons.palette_rounded),
        ClipType.code: ('Mã / Code', Icons.code_rounded),
      },
    );
  });

  test('màu của nhóm là màu ARGB đã lưu', () {
    expect(
      clipGroup('g', color: 0xFFE17055).materialColor,
      const Color(0xFFE17055),
    );
  });

  // formatRelative và formatRemaining nằm ở core/presentation/format.dart;
  // clipboard là nơi dùng chúng, nên kiểm ở đây với một thời điểm cố định.
  group('formatRelative', () {
    final now = DateTime(2026, 10, 22, 9);
    String ago(Duration d) => formatRelative(now.subtract(d), now: now);

    test('dưới một phút là vừa xong', () {
      expect(ago(Duration.zero), 'vừa xong');
      expect(ago(const Duration(seconds: 59)), 'vừa xong');
      // Thời điểm ở tương lai (đồng hồ lệch) cũng là vừa xong.
      expect(ago(const Duration(minutes: -5)), 'vừa xong');
    });

    test('đếm phút, giờ rồi ngày', () {
      expect(ago(const Duration(minutes: 1)), '1 phút trước');
      expect(ago(const Duration(minutes: 59, seconds: 59)), '59 phút trước');
      expect(ago(const Duration(hours: 1)), '1 giờ trước');
      expect(ago(const Duration(hours: 23, minutes: 59)), '23 giờ trước');
      expect(ago(const Duration(days: 1)), '1 ngày trước');
      expect(ago(const Duration(days: 6, hours: 23)), '6 ngày trước');
    });

    test('từ một tuần trở lên thì ghi ngày, không đệm số 0', () {
      expect(formatRelative(DateTime(2026, 10, 1, 8), now: now), '1/10/2026');
      expect(ago(const Duration(days: 7)), '15/10/2026');
    });

    test('không truyền now thì tính theo giờ hiện tại', () {
      expect(formatRelative(DateTime.now()), 'vừa xong');
    });
  });

  group('formatRemaining', () {
    test('hết hạn thì sắp bị xoá', () {
      expect(formatRemaining(Duration.zero), 'sắp bị xoá');
      expect(formatRemaining(const Duration(seconds: -1)), 'sắp bị xoá');
    });

    test('còn giờ, còn phút, còn dưới 1 phút', () {
      expect(
        formatRemaining(const Duration(hours: 23, minutes: 59)),
        'còn 23 giờ',
      );
      expect(formatRemaining(const Duration(hours: 1)), 'còn 1 giờ');
      expect(formatRemaining(const Duration(minutes: 59)), 'còn 59 phút');
      expect(formatRemaining(const Duration(minutes: 1)), 'còn 1 phút');
      expect(formatRemaining(const Duration(seconds: 59)), 'còn dưới 1 phút');
    });

    test('đi cùng ClipItem.remaining với một thời điểm cố định', () {
      final c = clip('a', createdMin: 0);
      expect(formatRemaining(c.remaining(at(60))), 'còn 23 giờ');
      expect(formatRemaining(c.remaining(at(24 * 60 - 30))), 'còn 30 phút');
      expect(formatRemaining(c.remaining(at(24 * 60 + 1))), 'sắp bị xoá');
    });
  });
}
