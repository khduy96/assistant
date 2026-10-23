import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/data/system_clock.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_controller.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_tab_state.dart';
import 'package:event_notice/features/clipboard/presentation/pages/clip_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// Clipboard giờ là một tab, bên trong mới chia bốn mục — bài test này canh
/// cái vỏ đó: thanh mục con, ô tìm kiếm dùng chung, và việc đổi mục có báo ra
/// ngoài cho AppBar với nút nổi hay không.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late ClipboardRepositoryImpl repo;
  late FakeClipboardSource source;
  late ClipboardController store;
  late ClipboardTabState tabState;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clip_tab_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    const clock = SystemClock();
    repo = ClipboardRepositoryImpl(ClipLocalDataSource(db), clock);
    source = FakeClipboardSource();
    store = controllerFor(repo, source, clock: clock);
    tabState = ClipboardTabState();
    await store.init();
  });

  tearDown(() async {
    store.dispose();
    source.dispose();
    await repo.dispose();
    tabState.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  Widget harness() => MultiProvider(
        providers: [
          ChangeNotifierProvider<ClipboardController>.value(value: store),
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

  testWidgets('một lượt pull ghi nhiều clip thì danh sách tự cập nhật, '
      'chỉ tải lại một lần', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    var repaints = 0;
    store.addListener(() => repaints++);

    // Ghi như sync engine ghi: mỗi clip một lần báo thay đổi nguồn sync.
    await tester.runAsync(() async {
      final base = DateTime(2026, 10, 22, 9);
      for (var i = 0; i < 40; i++) {
        final at = base.add(Duration(minutes: i));
        await repo.putClipFromSync(ClipModel(
          id: 'pulled-$i',
          content: 'clip kéo về $i',
          type: ClipType.text,
          createdAt: at,
          updatedAt: at,
          isSaved: true,
          remoteId: 'r$i',
          dirty: false,
        ));
      }
      await Future<void>.delayed(ClipboardController.syncReloadDelay * 3);
    });
    await tester.pump();

    expect(store.savedCount, 40);
    expect(repaints, 1);
    expect(find.text('Đã lưu (40)'), findsOneWidget);

    await tester.tap(find.text('Đã lưu (40)'));
    await tester.pumpAndSettle();
    expect(find.text('clip kéo về 39'), findsOneWidget);
  });

  testWidgets('sửa trên máy này thì không tải lại theo đường sync',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    var repaints = 0;
    store.addListener(() => repaints++);

    await tester.runAsync(() async {
      await store.addManual('gõ tay');
      await Future<void>.delayed(ClipboardController.syncReloadDelay * 3);
    });
    await tester.pump();

    // Một lần do addManual tự vẽ lại, không có lần tải lại nào sau đó.
    expect(repaints, 1);
    expect(store.savedCount, 1);
  });
}
