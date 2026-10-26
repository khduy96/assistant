import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/presentation/notes_controller.dart';
import 'package:event_notice/features/notes/presentation/pages/notes_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

Widget _harness(NotesController controller) =>
    ChangeNotifierProvider<NotesController>.value(
      value: controller,
      child: const MaterialApp(home: Scaffold(body: NotesTab())),
    );

void main() {
  late FakeClock clock;
  late InMemoryNoteRepository repo;
  late NotesController controller;

  /// Shows the tab with [notes] and opens the page of the first one.
  Future<void> openFirst(WidgetTester tester, List<Note> notes) async {
    repo = InMemoryNoteRepository(notes);
    controller = controllerFor(repo, clock: clock);
    await controller.init();
    await tester.pumpWidget(_harness(controller));
    await tester.tap(find.text(notes.first.displayTitle));
    await tester.pumpAndSettle();
  }

  setUp(() => clock = FakeClock(at(60)));

  tearDown(() async {
    controller.dispose();
    await repo.dispose();
  });

  testWidgets('chạm thẻ mở trang xem: tiêu đề, giờ sửa, nội dung thường', (
    tester,
  ) async {
    await openFirst(tester, [
      note('a', title: 'Wifi', body: 'mật khẩu\n1234', updatedMin: 5),
    ]);

    expect(find.text('Ghi chú'), findsOneWidget);
    expect(find.widgetWithText(SelectableText, 'Wifi'), findsOneWidget);
    expect(find.text('Sửa lần cuối 22/10/2026 09:35'), findsOneWidget);
    expect(
      find.widgetWithText(SelectableText, 'mật khẩu\n1234'),
      findsOneWidget,
    );
    expect(find.text('Markdown'), findsNothing);
    for (final tip in [
      'Ghim lên đầu',
      'Sao chép nội dung',
      'Sửa ghi chú',
      'Xoá ghi chú',
    ]) {
      expect(find.byTooltip(tip), findsWidgets, reason: tip);
    }
  });

  testWidgets('ghi chú markdown được render', (tester) async {
    await openFirst(tester, [
      note('a', title: 'Họp', body: '## Việc\n- **slide**', markdown: true),
    ]);

    expect(find.text('Markdown'), findsOneWidget);
    expect(find.text('Việc', findRichText: true), findsOneWidget);
    expect(find.text('## Việc', findRichText: true), findsNothing);
  });

  testWidgets('ghi chú không có nội dung', (tester) async {
    await openFirst(tester, [note('a', title: 'Chỉ tiêu đề')]);

    expect(find.text('Ghi chú này chưa có nội dung.'), findsOneWidget);
  });

  testWidgets('ghim từ trang xem', (tester) async {
    await openFirst(tester, [note('a', title: 'Wifi')]);

    await tester.tap(find.byTooltip('Ghim lên đầu'));
    await tester.pumpAndSettle();

    expect(repo['a']!.pinned, isTrue);
    expect(find.byTooltip('Bỏ ghim'), findsOneWidget);
  });

  testWidgets('sửa từ trang xem cập nhật ngay, giữ createdAt', (tester) async {
    await openFirst(tester, [
      note('a', title: 'Wifi', body: 'cũ', createdMin: -50, updatedMin: 1),
    ]);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Sửa ghi chú'), findsWidgets);

    final body = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .at(1);
    await tester.enterText(body, 'mới');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SelectableText, 'mới'), findsOneWidget);
    expect(repo['a']!.createdAt, at(-50));
    expect(repo['a']!.updatedAt, at(60));
  });

  testWidgets('sao chép nội dung vào clipboard', (tester) async {
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openFirst(tester, [note('a', title: 'Wifi', body: 'mật khẩu 1234')]);

    await tester.tap(find.byTooltip('Sao chép nội dung'));
    await tester.pump();

    expect(copied, [
      {'text': 'mật khẩu 1234'},
    ]);
    expect(find.text('Đã sao chép nội dung ghi chú'), findsOneWidget);
  });

  testWidgets('xoá từ trang xem rồi quay về danh sách', (tester) async {
    await openFirst(tester, [
      note('a', title: 'Wifi'),
      note('b', title: 'Họp'),
    ]);

    await tester.tap(find.byTooltip('Xoá ghi chú'));
    await tester.pumpAndSettle();
    expect(find.text('Xoá ghi chú?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();

    expect(repo['a'], isNull);
    expect(find.text('Ghi chú'), findsNothing);
    expect(find.text('Họp'), findsOneWidget);
    expect(find.text('Tìm trong ghi chú...'), findsOneWidget);
  });

  testWidgets('bị xoá ở nơi khác (như sync) thì trang tự đóng', (tester) async {
    await openFirst(tester, [
      note('a', title: 'Wifi'),
      note('b', title: 'Họp'),
    ]);
    expect(find.text('Ghi chú'), findsOneWidget);

    await repo.delete('a');
    await tester.pumpAndSettle();

    expect(find.text('Ghi chú'), findsNothing);
    expect(find.text('Họp'), findsOneWidget);
  });
}
