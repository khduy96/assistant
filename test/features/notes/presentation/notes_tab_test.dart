import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/presentation/notes_controller.dart';
import 'package:event_notice/features/notes/presentation/pages/notes_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// The tab as the home page shows it, with an "add" button that goes through
/// [createNote] like the real floating button.
Widget _harness(NotesController controller) =>
    ChangeNotifierProvider<NotesController>.value(
      value: controller,
      child: MaterialApp(
        home: Scaffold(
          body: const NotesTab(),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton(
              onPressed: () => createNote(context),
              child: const Icon(Icons.note_add),
            ),
          ),
        ),
      ),
    );

/// The [i]-th text field of the open editor dialog, not the search box behind
/// it.
Finder _field(int i) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .at(i);

/// Scrolls [finder] into view inside the dialog, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  late FakeClock clock;
  late InMemoryNoteRepository repo;
  late NotesController controller;

  Future<void> pumpTab(
    WidgetTester tester, [
    List<Note> notes = const [],
  ]) async {
    repo = InMemoryNoteRepository(notes);
    controller = controllerFor(repo, clock: clock);
    await controller.init();
    await tester.pumpWidget(_harness(controller));
  }

  setUp(() => clock = FakeClock(at(60)));

  tearDown(() async {
    controller.dispose();
    await repo.dispose();
  });

  testWidgets('chưa có ghi chú thì hiện trạng thái trống, không có ô tìm', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(find.text('Chưa có ghi chú nào'), findsOneWidget);
    expect(
      find.text(
        'Bấm "Thêm ghi chú" để lưu lại một ý tưởng, '
        'mật khẩu wifi hay việc cần nhớ.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('thẻ ghi chú: tiêu đề, preview, giờ sửa, nút ghim, theo thứ tự', (
    tester,
  ) async {
    await pumpTab(tester, [
      note('a', title: 'Wifi', body: 'mật khẩu 1234', updatedMin: 1),
      note('b', body: '## Họp\n**slide**', markdown: true, pinned: true),
    ]);

    expect(find.text('Tìm trong ghi chú...'), findsOneWidget);
    expect(find.text('Wifi'), findsOneWidget);
    expect(find.text('mật khẩu 1234'), findsOneWidget);
    expect(find.text('Sửa lần cuối 22/10/2026 09:31'), findsOneWidget);
    // Markdown is stripped on the card.
    expect(find.text('Họp'), findsOneWidget);
    expect(find.text('Họp\nslide'), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byTooltip('Bỏ ghim'), findsOneWidget);
    expect(find.byTooltip('Ghim lên đầu'), findsOneWidget);

    // Pinned first.
    final pinnedY = tester.getTopLeft(find.text('Họp')).dy;
    final otherY = tester.getTopLeft(find.text('Wifi')).dy;
    expect(pinnedY, lessThan(otherY));
  });

  testWidgets('tìm kiếm lọc danh sách, không thấy thì báo, nút xoá tìm', (
    tester,
  ) async {
    await pumpTab(tester, [
      note('a', title: 'Wifi'),
      note('b', title: 'Họp tuần'),
    ]);

    await tester.enterText(find.byType(TextField), 'họp');
    await tester.pumpAndSettle();
    expect(find.text('Họp tuần'), findsOneWidget);
    expect(find.text('Wifi'), findsNothing);

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy ghi chú'), findsOneWidget);
    expect(find.text('Không có ghi chú nào chứa "xyz".'), findsOneWidget);

    await tester.tap(find.byTooltip('Xoá tìm kiếm'));
    await tester.pumpAndSettle();
    expect(find.text('Wifi'), findsOneWidget);
    expect(find.text('Họp tuần'), findsOneWidget);
    expect(controller.query, '');
    expect(find.byTooltip('Xoá tìm kiếm'), findsNothing);
  });

  testWidgets('ô tìm dựng lại vẫn hiện query đang lọc', (tester) async {
    await pumpTab(tester, [note('a', title: 'Wifi'), note('b', title: 'Họp')]);
    await controller.setQuery('wifi');

    // A fresh tab, as after switching away and back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_harness(controller));

    expect(find.widgetWithText(TextField, 'wifi'), findsOneWidget);
    expect(find.text('Họp'), findsNothing);
  });

  testWidgets('bấm ghim đưa ghi chú lên đầu', (tester) async {
    await pumpTab(tester, [note('a', title: 'Wifi')]);

    await tester.tap(find.byTooltip('Ghim lên đầu'));
    await tester.pumpAndSettle();

    expect(repo['a']!.pinned, isTrue);
    expect(repo['a']!.updatedAt, at(60));
    expect(find.byTooltip('Bỏ ghim'), findsOneWidget);
  });

  testWidgets('xoá qua menu phải xác nhận', (tester) async {
    await pumpTab(tester, [note('a', title: 'Wifi')]);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();

    expect(find.text('Xoá ghi chú?'), findsOneWidget);
    expect(find.text('"Wifi" sẽ bị xoá khỏi danh sách.'), findsOneWidget);

    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(repo['a'], isNotNull);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();

    expect(repo['a'], isNull);
    expect(find.text('Chưa có ghi chú nào'), findsOneWidget);
  });

  group('editor', () {
    testWidgets('thêm ghi chú: id và giờ từ use case, lưu với updatedAt mới', (
      tester,
    ) async {
      await pumpTab(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Thêm ghi chú'), findsOneWidget);
      expect(find.text('Tiêu đề (tuỳ chọn)'), findsOneWidget);

      clock.current = at(65);
      await tester.enterText(_field(0), '  Ý tưởng  ');
      await tester.enterText(_field(1), 'nội dung');
      await tapVisible(tester, find.text('Ghim lên đầu danh sách'));
      await tapVisible(tester, find.byTooltip('Vàng'));
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repo['id-1']!;
      expect(saved.title, 'Ý tưởng');
      expect(saved.body, 'nội dung');
      expect(saved.pinned, isTrue);
      expect(saved.color, NoteColor.yellow);
      expect(saved.markdown, isFalse);
      // createdAt comes from NewNote when the editor opened.
      expect(saved.createdAt, at(60));
      expect(saved.updatedAt, at(65));
      expect(find.text('Ý tưởng'), findsOneWidget);
    });

    testWidgets('lưu khi trống thì báo lỗi và không đóng', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pump();

      expect(find.text('Hãy nhập tiêu đề hoặc nội dung.'), findsOneWidget);
      expect(find.text('Thêm ghi chú'), findsOneWidget);
      expect(repo.length, 0);
    });

    testWidgets('huỷ thì không lưu gì', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'x');

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(repo.length, 0);
      expect(find.text('Chưa có ghi chú nào'), findsOneWidget);
    });

    testWidgets('sửa giữ id và createdAt, đặt updatedAt theo Clock', (
      tester,
    ) async {
      await pumpTab(tester, [
        note(
          'a',
          title: 'Wifi',
          body: 'cũ',
          markdown: true,
          color: NoteColor.blue,
          createdMin: -100,
          updatedMin: 1,
        ),
      ]);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      expect(find.text('Sửa ghi chú'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Wifi'), findsOneWidget);

      await tester.enterText(_field(0), 'Wifi mới');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(repo.length, 1);
      final saved = repo['a']!;
      expect(saved.title, 'Wifi mới');
      expect(saved.body, 'cũ');
      expect(saved.markdown, isTrue);
      expect(saved.color, NoteColor.blue);
      expect(saved.createdAt, at(-100));
      expect(saved.updatedAt, at(60));
    });

    testWidgets('markdown: thanh công cụ chèn cú pháp, xem trước', (
      tester,
    ) async {
      await pumpTab(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Viết bằng Markdown'));
      await tester.pumpAndSettle();
      expect(find.text('Soạn'), findsOneWidget);
      expect(find.text('Xem trước'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Đậm'));
      expect(find.widgetWithText(TextField, '**chữ đậm**'), findsOneWidget);

      await tapVisible(tester, find.text('Xem trước'));
      await tester.pumpAndSettle();
      expect(find.text('chữ đậm', findRichText: true), findsOneWidget);
      expect(find.text('**chữ đậm**', findRichText: true), findsNothing);
    });
  });
}
