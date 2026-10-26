import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/check_layers.dart';

void main() {
  late Directory root;
  late Directory lib;

  setUp(() {
    root = Directory.systemTemp.createTempSync('check_layers_');
    lib = Directory(p.join(root.path, 'lib'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Ghi file vào lib/ theo đường dẫn dạng `a/b/c.dart`.
  void write(String rel, String content) {
    File(p.joinAll([lib.path, ...rel.split('/')]))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  List<String> found() => checkLayers(lib).map((v) => v.toString()).toList();

  group('domain_purity', () {
    test('báo domain import flutter, dart:io, data và presentation', () {
      write('features/notes/domain/note.dart', '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import '../data/note_model.dart';
import 'package:event_notice/features/notes/presentation/notes_tab.dart';
export '../../../core/data/system_clock.dart';
''');

      expect(found(), [
        "lib/features/notes/domain/note.dart:2 domain_purity  package:flutter/material.dart",
        'lib/features/notes/domain/note.dart:3 domain_purity  dart:io',
        'lib/features/notes/domain/note.dart:4 domain_purity  ../data/note_model.dart',
        'lib/features/notes/domain/note.dart:5 domain_purity  '
            'package:event_notice/features/notes/presentation/notes_tab.dart',
        'lib/features/notes/domain/note.dart:6 domain_purity  '
            '../../../core/data/system_clock.dart',
      ]);
    });

    test('domain import core/domain và dart:async là hợp lệ', () {
      write('features/notes/domain/usecases/get_notes.dart', '''
import 'dart:async';
import 'package:event_notice/core/domain/result.dart';
import '../../../../core/domain/clock.dart';
import '../entities/note.dart';
// import 'package:flutter/material.dart';
''');
      write('core/domain/clock.dart', "import 'dart:core';\n");
      // data được dùng dart:io và flutter.
      write('features/notes/data/note_model.dart', '''
import 'dart:io';
import 'package:flutter/foundation.dart';
''');

      expect(found(), isEmpty);
    });
  });

  group('presentation_no_data', () {
    test('báo presentation import data của chính feature và core/data', () {
      write('features/notes/presentation/pages/notes_tab.dart', '''
import 'package:flutter/material.dart';
import '../../data/note_model.dart';
import 'package:event_notice/core/data/app_paths.dart';
''');

      expect(found(), [
        'lib/features/notes/presentation/pages/notes_tab.dart:2 '
            'presentation_no_data  ../../data/note_model.dart',
        'lib/features/notes/presentation/pages/notes_tab.dart:3 '
            'presentation_no_data  package:event_notice/core/data/app_paths.dart',
      ]);
    });

    test('presentation import flutter, domain và core/presentation là hợp lệ', () {
      write('features/notes/presentation/notes_controller.dart', '''
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../domain/usecases/get_notes.dart';
import 'package:event_notice/core/presentation/format.dart';
''');

      expect(found(), isEmpty);
    });
  });

  group('no_cross_feature', () {
    test('báo features/a import features/b', () {
      write('features/todos/data/todo_repository_impl.dart', '''
import '../../notes/data/note_model.dart';
import 'package:event_notice/features/reminders/domain/reminder.dart';
''');

      expect(found(), [
        'lib/features/todos/data/todo_repository_impl.dart:1 '
            'no_cross_feature  ../../notes/data/note_model.dart',
        'lib/features/todos/data/todo_repository_impl.dart:2 '
            'no_cross_feature  package:event_notice/features/reminders/domain/reminder.dart',
      ]);
    });

    test('import trong cùng feature và core là hợp lệ', () {
      write('features/todos/data/todo_repository_impl.dart', '''
import '../domain/todo.dart';
import 'package:event_notice/features/todos/domain/todo_repository.dart';
import '../../../core/data/json_file_store.dart';
''');
      // app/ được import mọi feature.
      write('app/di/injection.dart', '''
import '../../features/notes/notes_injection.dart';
import '../../features/todos/todos_injection.dart';
''');

      expect(found(), isEmpty);
    });
  });

  group('core_independence', () {
    test('báo core import features, app và thư mục cũ', () {
      write('core/data/app_database.dart', '''
import 'package:event_notice/features/notes/domain/note.dart';
import '../../app/di/injection.dart';
import '../../models/reminder.dart';
import 'package:event_notice/services/note_store.dart';
import '../../ui/format.dart';
import '../../clipboard/sync/class_names.dart';
import '../../p2p/models/peer.dart';
import '../../running_text/ui/running_text_page.dart';
''');

      final rules = checkLayers(lib).map((v) => '${v.line} ${v.rule}');
      expect(rules, [
        for (var line = 1; line <= 8; line++) '$line core_independence',
      ]);
    });

    test('core import core, dart:io và package ngoài là hợp lệ', () {
      write('core/data/app_database.dart', '''
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../domain/clock.dart';
import 'package:event_notice/core/sync/data/parse_client.dart';
''');
      write('core/platform/startup.dart', "import '../data/app_database.dart';\n");

      expect(found(), isEmpty);
    });
  });

  group('cách quét directive', () {
    test('đọc directive nhiều dòng và import có điều kiện', () {
      write('features/notes/domain/io.dart', '''
import 'stub.dart'
    if (dart.library.io) 'dart:io'
    show File;
export 'package:flutter/widgets.dart'
    hide Text;
''');

      expect(found(), [
        'lib/features/notes/domain/io.dart:2 domain_purity  dart:io',
        'lib/features/notes/domain/io.dart:4 domain_purity  '
            'package:flutter/widgets.dart',
      ]);
    });

    test('một import có thể phạm nhiều quy tắc', () {
      write('features/todos/domain/link.dart',
          "import '../../reminders/data/reminder_model.dart';\n");

      expect(checkLayers(lib).map((v) => v.rule), [
        'domain_purity',
        'no_cross_feature',
      ]);
    });
  });

  group('runCheckLayers', () {
    void addViolation() => write(
          'features/notes/domain/note.dart',
          "import 'package:flutter/material.dart';\n",
        );

    test('không cờ là chế độ bắt buộc: in vi phạm, exit khác 0', () {
      addViolation();
      final out = StringBuffer();

      expect(runCheckLayers(const [], root: root.path, out: out), isNot(0));
      expect(
        out.toString(),
        contains('lib/features/notes/domain/note.dart:1 domain_purity'),
      );
      expect(out.toString(), contains('1 vi phạm (chế độ bắt buộc)'));
    });

    test('không cờ trả 0 khi không có vi phạm', () {
      write('core/domain/clock.dart', "import 'dart:async';\n");

      expect(runCheckLayers(const [], root: root.path, out: StringBuffer()), 0);
    });

    test('--strict trả exit khác 0 khi có vi phạm', () {
      addViolation();

      expect(
        runCheckLayers(const ['--strict'], root: root.path, out: StringBuffer()),
        isNot(0),
      );
    });

    test('--strict trả 0 khi không có vi phạm', () {
      write('core/domain/clock.dart', "import 'dart:async';\n");

      expect(
        runCheckLayers(const ['--strict'], root: root.path, out: StringBuffer()),
        0,
      );
    });

    test('--warn trả 0 dù có vi phạm', () {
      addViolation();
      final out = StringBuffer();

      expect(runCheckLayers(const ['--warn'], root: root.path, out: out), 0);
      expect(out.toString(), contains('1 vi phạm (chế độ cảnh báo)'));
    });

    test('cờ lạ hoặc --strict cùng --warn trả 64', () {
      final out = StringBuffer();
      expect(runCheckLayers(const ['--bogus'], root: root.path, out: out), 64);
      expect(
        runCheckLayers(const ['--strict', '--warn'], root: root.path, out: out),
        64,
      );
    });
  });
}
