// Kiểm tra quy tắc phụ thuộc giữa các layer (docs/architecture.md, mục 2 và 6).
//
//   dart run tool/check_layers.dart            # chế độ bắt buộc, exit 1 khi có vi phạm
//   dart run tool/check_layers.dart --strict   # như trên, ghi rõ
//   dart run tool/check_layers.dart --warn     # chế độ cảnh báo, luôn exit 0
//
// Quét mọi directive import/export trong lib/. URI dạng package:event_notice/...
// và đường dẫn tương đối đều được đổi về đường dẫn trong lib trước khi so quy tắc.
// Mỗi vi phạm in một dòng `lib/<path>:<line> <rule>  <uri>`.
import 'dart:io';

import 'package:path/path.dart' as p;

/// Chế độ mặc định khi không truyền cờ. Giai đoạn 0–7: cảnh báo; từ giai đoạn 8:
/// bắt buộc.
const bool defaultStrict = true;

const String _packageName = 'event_notice';

/// Thư mục cấp một trong lib/ của cấu trúc cũ; core không được import chúng.
/// Từ giai đoạn 8 các thư mục này đã bị xoá; giữ lại để chúng không quay lại
/// qua đường core.
const Set<String> legacyDirs = {
  'models',
  'services',
  'ui',
  'clipboard',
  'p2p',
  'running_text',
};

/// Tên các quy tắc, in ra cạnh mỗi vi phạm.
abstract final class LayerRule {
  /// File trong */domain/ import package:flutter/, dart:io, /data/ hoặc /presentation/.
  static const domainPurity = 'domain_purity';

  /// File trong */presentation/ import /data/.
  static const presentationNoData = 'presentation_no_data';

  /// File trong features/a/ import features/b/.
  static const noCrossFeature = 'no_cross_feature';

  /// File trong core/ import features/, app/ hoặc thư mục cũ.
  static const coreIndependence = 'core_independence';
}

class LayerViolation {
  const LayerViolation({
    required this.path,
    required this.line,
    required this.rule,
    required this.uri,
  });

  /// Đường dẫn file vi phạm, tính từ lib/ (dấu `/`).
  final String path;

  /// Số dòng của URI vi phạm, bắt đầu từ 1.
  final int line;
  final String rule;

  /// URI đúng như viết trong directive.
  final String uri;

  @override
  String toString() => 'lib/$path:$line $rule  $uri';
}

/// Một URI trong directive import/export, kèm số dòng.
class _Directive {
  const _Directive(this.uri, this.line);
  final String uri;
  final int line;
}

// `import 'x.dart' ... ;` hoặc `export ...;`, cho phép kéo qua nhiều dòng.
final _directiveRe = RegExp(
  r'''^[ \t]*(?:import|export)\s+(['"])([^'"]+)\1([^;]*);''',
  multiLine: true,
);
// Nhánh của import có điều kiện: `if (dart.library.io) 'y.dart'`.
final _configRe = RegExp(r'''if\s*\([^)]*\)\s*(['"])([^'"]+)\1''');

/// Quét mọi file .dart trong [libDir] và trả về danh sách vi phạm đã sắp xếp.
List<LayerViolation> checkLayers(Directory libDir) {
  final violations = <LayerViolation>[];
  var base = _slash(libDir.absolute.path);
  if (!base.endsWith('/')) base = '$base/';
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final rel = _slash(file.absolute.path).substring(base.length);
    final source = file.readAsStringSync();
    for (final d in _directives(source)) {
      for (final rule in _rulesBroken(rel, d.uri)) {
        violations.add(
          LayerViolation(path: rel, line: d.line, rule: rule, uri: d.uri),
        );
      }
    }
  }
  violations.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    if (byPath != 0) return byPath;
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.rule.compareTo(b.rule);
  });
  return violations;
}

/// Điểm vào cho cả `main` lẫn test. [root] là thư mục gốc project (mặc định
/// thư mục hiện tại); kết quả ghi ra [out] (mặc định stdout). Trả về exit code.
int runCheckLayers(List<String> args, {String? root, StringSink? out}) {
  final sink = out ?? stdout;
  var strict = defaultStrict;
  final hasStrict = args.contains('--strict');
  final hasWarn = args.contains('--warn');
  final unknown =
      args.where((a) => a != '--strict' && a != '--warn').toList();
  if (unknown.isNotEmpty || (hasStrict && hasWarn)) {
    sink.writeln('Cách dùng: dart run tool/check_layers.dart [--strict | --warn]');
    if (unknown.isNotEmpty) sink.writeln('Cờ lạ: ${unknown.join(' ')}');
    return 64;
  }
  if (hasStrict) strict = true;
  if (hasWarn) strict = false;

  final libDir = Directory(p.join(root ?? Directory.current.path, 'lib'));
  if (!libDir.existsSync()) {
    sink.writeln('Không thấy thư mục ${libDir.path}.');
    return 2;
  }

  final violations = checkLayers(libDir);
  for (final v in violations) {
    sink.writeln(v);
  }
  final mode = strict ? 'bắt buộc' : 'cảnh báo';
  if (violations.isEmpty) {
    sink.writeln('check_layers: không có vi phạm (chế độ $mode).');
    return 0;
  }
  sink.writeln('check_layers: ${violations.length} vi phạm (chế độ $mode).');
  return strict ? 1 : 0;
}

void main(List<String> args) {
  exitCode = runCheckLayers(args);
}

List<_Directive> _directives(String source) {
  final result = <_Directive>[];
  for (final m in _directiveRe.allMatches(source)) {
    final whole = m.group(0)!;
    final uriAt = m.start + whole.indexOf(m.group(1)! + m.group(2)!);
    result.add(_Directive(m.group(2)!, _lineAt(source, uriAt)));
    final tail = m.group(3)!;
    // whole kết thúc bằng tail rồi tới ';'.
    final tailStart = m.end - 1 - tail.length;
    for (final c in _configRe.allMatches(tail)) {
      final at = tailStart + c.start + c.group(0)!.indexOf(c.group(1)! + c.group(2)!);
      result.add(_Directive(c.group(2)!, _lineAt(source, at)));
    }
  }
  return result;
}

int _lineAt(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// Đổi [uri] về đường dẫn trong lib/ (vd. `core/domain/clock.dart`).
/// Trả về null cho dart:, package khác, hoặc đường dẫn ra ngoài lib/.
String? _resolveInLib(String fromRel, String uri) {
  const prefix = 'package:$_packageName/';
  if (uri.startsWith(prefix)) {
    return p.posix.normalize(uri.substring(prefix.length));
  }
  if (uri.contains(':')) return null;
  final resolved = p.posix.normalize(p.posix.join(p.posix.dirname(fromRel), uri));
  if (resolved == '..' || resolved.startsWith('../')) return null;
  return resolved;
}

/// Các thư mục chứa file (bỏ tên file).
List<String> _dirs(String rel) => p.posix.split(p.posix.dirname(rel));

/// Tên feature nếu [rel] nằm trong `features/<name>/`.
String? _feature(String rel) {
  final parts = p.posix.split(rel);
  return parts.length > 2 && parts.first == 'features' ? parts[1] : null;
}

List<String> _rulesBroken(String fromRel, String uri) {
  final broken = <String>[];
  final fromDirs = _dirs(fromRel);
  final target = _resolveInLib(fromRel, uri);
  final targetDirs = target == null ? const <String>[] : _dirs(target);

  if (fromDirs.contains('domain')) {
    final bad = uri.startsWith('package:flutter/') ||
        uri == 'dart:io' ||
        targetDirs.contains('data') ||
        targetDirs.contains('presentation');
    if (bad) broken.add(LayerRule.domainPurity);
  }

  if (fromDirs.contains('presentation') && targetDirs.contains('data')) {
    broken.add(LayerRule.presentationNoData);
  }

  final fromFeature = _feature(fromRel);
  if (fromFeature != null && target != null) {
    final targetFeature = _feature(target);
    if (targetFeature != null && targetFeature != fromFeature) {
      broken.add(LayerRule.noCrossFeature);
    }
  }

  if (fromDirs.first == 'core' && target != null) {
    final top = p.posix.split(target).first;
    final targetIsDir = p.posix.split(target).length > 1;
    if (targetIsDir &&
        (top == 'features' || top == 'app' || legacyDirs.contains(top))) {
      broken.add(LayerRule.coreIndependence);
    }
  }
  return broken;
}

String _slash(String path) => path.replaceAll(r'\', '/');
