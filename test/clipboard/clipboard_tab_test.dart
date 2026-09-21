import 'dart:io';

import 'package:event_notice/clipboard/data/app_database.dart';
import 'package:event_notice/clipboard/data/clip_repository.dart';
import 'package:event_notice/clipboard/state/clipboard_store.dart';
import 'package:event_notice/clipboard/ui/clip_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Clipboard giờ là một tab, bên trong mới chia bốn mục — bài test này canh
/// cái vỏ đó: thanh mục con, ô tìm kiếm dùng chung, và việc đổi mục có báo ra
/// ngoài cho AppBar với nút nổi hay không.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late ClipboardStore store;
  late ClipboardTabState tabState;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clip_tab_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    store = ClipboardStore(repository: ClipRepository(db: db));
    tabState = ClipboardTabState();
    await store.init();
  });

  tearDown(() async {
    store.dispose();
    tabState.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  Widget harness() => MultiProvider(
        providers: [
          ChangeNotifierProvider<ClipboardStore>.value(value: store),
          ChangeNotifierProvider<ClipboardTabState>.value(value: tabState),
        ],
        child: const MaterialApp(home: Scaffold(body: ClipboardTab())),
      );

  testWidgets('hiện đủ bốn mục con và ô tìm kiếm dùng chung', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (final section in ClipboardSection.values) {
      expect(find.text(section.label), findsOneWidget);
    }
    expect(find.text('Tìm trong clipboard…'), findsOneWidget);
    // Mục đầu tiên là "Tạm", và lời nhắc của nó đang hiện.
    expect(tabState.section, ClipboardSection.temp);
    expect(find.text('Chưa có gì trong bộ nhớ tạm'), findsOneWidget);
  });

  testWidgets('đổi mục con thì trạng thái ngoài tab cũng đổi theo',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nhóm'));
    await tester.pumpAndSettle();

    // Đây là thứ AppBar và nút nổi của app đọc để đổi nút theo mục đang mở.
    expect(tabState.section, ClipboardSection.groups);
    expect(find.text('Chưa có nhóm nào'), findsOneWidget);
    // Mục Nhóm không có bộ lọc theo loại.
    expect(find.byTooltip('Lọc theo loại'), findsNothing);

    await tester.tap(find.text('Ghim'));
    await tester.pumpAndSettle();

    expect(tabState.section, ClipboardSection.pinned);
    expect(find.text('Chưa ghim clip nào'), findsOneWidget);
    expect(find.byTooltip('Lọc theo loại'), findsOneWidget);
  });

  testWidgets('gõ tìm kiếm ở mục này thì mục khác vẫn giữ nguyên chữ',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wifi');
    await tester.pumpAndSettle();
    expect(store.query, 'wifi');

    await tester.tap(find.text('Đã lưu'));
    await tester.pumpAndSettle();

    expect(find.text('wifi'), findsOneWidget);
    expect(store.query, 'wifi');
  });
}
