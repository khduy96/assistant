// Renders the "Nhắc việc" logo to every icon asset the app ships.
// Run with: flutter test tool/gen_logo.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

const double S = 1024; // design canvas

const blueLight = Color(0xFF3B82F6);
const blueMid = Color(0xFF2563EB);
const blueDeep = Color(0xFF1E40AF);
const amber = Color(0xFFF59E0B);
const white = Color(0xFFFFFFFF);

const center = Offset(512, 512);
const ringRadius = 338.0;
const ringWidth = 80.0;
const arcSweepDeg = 200.0; // amber arc = time left before the reminder fires

/// Background plate. [squircle] false gives a full-bleed square for maskable icons.
void plate(Canvas c, {bool squircle = true}) {
  final paint = Paint()
    ..shader = Gradient.linear(
      const Offset(0, 0),
      const Offset(S, S),
      const [blueLight, blueMid, blueDeep],
      const [0.0, 0.45, 1.0],
    );
  final rect = Rect.fromLTWH(0, 0, S, S);
  if (squircle) {
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(230)), paint);
  } else {
    c.drawRect(rect, paint);
  }
}

/// The mark itself: countdown ring plus clock hands.
void mark(Canvas c) {
  c.drawCircle(
    center,
    ringRadius,
    Paint()
      ..color = white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth,
  );
  c.drawArc(
    Rect.fromCircle(center: center, radius: ringRadius),
    -math.pi / 2,
    arcSweepDeg * math.pi / 180,
    false,
    Paint()
      ..color = amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round,
  );
  hand(c, 120, 168, 48); // hour hand at 4
  hand(c, 0, 230, 40); // minute hand at 12
  c.drawCircle(center, 42, Paint()..color = white);
}

void hand(Canvas c, double deg, double len, double w) {
  final a = deg * math.pi / 180;
  c.drawLine(
    center,
    center + Offset(math.sin(a) * len, -math.cos(a) * len),
    Paint()
      ..color = white
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round,
  );
}

/// Standard app icon.
void logo(Canvas c) {
  plate(c);
  mark(c);
}

/// Tiny sizes (16-24px): drop the faint track and thicken everything, or the
/// mark turns into a smudge in the Windows tray.
void logoSmall(Canvas c) {
  plate(c);
  c.drawArc(
    Rect.fromCircle(center: center, radius: ringRadius + 10),
    -math.pi / 2,
    arcSweepDeg * math.pi / 180,
    false,
    Paint()
      ..color = amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 84
      ..strokeCap = StrokeCap.butt,
  );
  hand(c, 120, 138, 84);
  hand(c, 0, 186, 74);
}

/// Android adaptive / PWA maskable: full bleed, mark shrunk into the 80% safe zone.
void logoMaskable(Canvas c) {
  plate(c, squircle: false);
  c.save();
  c.translate(S / 2, S / 2);
  c.scale(0.78);
  c.translate(-S / 2, -S / 2);
  mark(c);
  c.restore();
}

typedef Draw = void Function(Canvas c);

Future<Image> raster(int size, Draw draw) async {
  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.scale(size / S);
  draw(c);
  return rec.endRecording().toImage(size, size);
}

Future<Uint8List> pngBytes(int size, Draw draw) async {
  final img = await raster(size, draw);
  final data = await img.toByteData(format: ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> writePng(String path, int size, Draw draw) async {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(await pngBytes(size, draw));
  stdout.writeln('  $path (${size}px)');
}

/// ICO: BMP frames for the small sizes, PNG frames from 128px up.
Future<void> writeIco(String path, List<int> sizes, Draw draw) async {
  final frames = <Uint8List>[];
  for (final size in sizes) {
    final d = size <= 24 ? logoSmall : draw;
    frames.add(size >= 128 ? await pngBytes(size, d) : await bmpFrame(size, d));
  }

  final out = BytesBuilder();
  void u16(int v) => out.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  void u32(int v) => out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  u16(0);
  u16(1); // type: icon
  u16(sizes.length);
  var offset = 6 + 16 * sizes.length;
  for (var i = 0; i < sizes.length; i++) {
    out.add(Uint8List.fromList([sizes[i] >= 256 ? 0 : sizes[i], sizes[i] >= 256 ? 0 : sizes[i], 0, 0]));
    u16(1); // colour planes
    u16(32); // bpp
    u32(frames[i].length);
    u32(offset);
    offset += frames[i].length;
  }
  for (final f in frames) {
    out.add(f);
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(out.toBytes());
  stdout.writeln('  $path (${sizes.join("/")})');
}

/// DIB frame: BITMAPINFOHEADER + BGRA rows bottom-up + AND mask.
Future<Uint8List> bmpFrame(int size, Draw draw) async {
  final img = await raster(size, draw);
  final rgba = (await img.toByteData(format: ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final bgra = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    final src = y * size * 4;
    final dst = (size - 1 - y) * size * 4; // ICO rows run bottom-up
    for (var x = 0; x < size; x++) {
      bgra[dst + x * 4] = rgba[src + x * 4 + 2];
      bgra[dst + x * 4 + 1] = rgba[src + x * 4 + 1];
      bgra[dst + x * 4 + 2] = rgba[src + x * 4];
      bgra[dst + x * 4 + 3] = rgba[src + x * 4 + 3];
    }
  }
  final maskRowBytes = ((size + 31) ~/ 32) * 4; // rows padded to 4 bytes
  final mask = Uint8List(maskRowBytes * size); // all zero = fully opaque

  final b = BytesBuilder();
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  u32(40);
  u32(size);
  u32(size * 2); // height covers image + mask
  u16(1);
  u16(32);
  u32(0); // BI_RGB
  u32(bgra.length + mask.length);
  u32(0);
  u32(0);
  u32(0);
  u32(0);
  b.add(bgra);
  b.add(mask);
  return b.toBytes();
}

/// Contact sheet so the icon can be eyeballed at the sizes it actually ships at.
Future<void> writeSheet(String path) async {
  const sizes = [16, 24, 32, 48, 64, 128];
  Draw pick(int s) => s <= 24 ? logoSmall : logo;
  const big = 360.0, pad = 32.0;
  final w = big + pad * 3 + const [16, 24, 32, 48].fold<double>(0, (a, s) => a + s * 8 + pad);
  const h = big + pad * 2;
  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF334155));
  c.save();
  c.translate(pad, pad);
  c.scale(big / S);
  logo(c);
  c.restore();
  var x = big + pad * 2;
  for (final s in sizes) {
    c.save();
    c.translate(x, h - pad - s);
    c.scale(s / S);
    pick(s)(c);
    c.restore();
    x += s + pad;
  }
  // Bottom row: the tiny frames blown up 8x, nearest-neighbour, to inspect pixels.
  var zx = big + pad * 2;
  for (final s in const [16, 24, 32, 48]) {
    final img = await raster(s, pick(s));
    final side = s * 8.0;
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, s.toDouble(), s.toDouble()),
      Rect.fromLTWH(zx, pad, side, side),
      Paint()..filterQuality = FilterQuality.none,
    );
    zx += side + pad;
  }
  final img = await rec.endRecording().toImage(w.round(), h.round());
  final data = await img.toByteData(format: ImageByteFormat.png);
  File(path).writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('generate app icons', () async {
    stdout.writeln('Writing icons:');
    await writePng('assets/branding/logo.png', 1024, logo);

    // Windows: tray icon + executable icon.
    await writeIco('assets/icons/tray.ico', const [16, 20, 24, 32, 48, 64], logo);
    await writeIco('windows/runner/resources/app_icon.ico', const [16, 24, 32, 48, 64, 128, 256], logo);

    // Android launcher.
    const mipmap = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final e in mipmap.entries) {
      await writePng('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png', e.value, logo);
    }

    // Web.
    await writePng('web/favicon.png', 32, logo);
    await writePng('web/icons/Icon-192.png', 192, logo);
    await writePng('web/icons/Icon-512.png', 512, logo);
    await writePng('web/icons/Icon-maskable-192.png', 192, logoMaskable);
    await writePng('web/icons/Icon-maskable-512.png', 512, logoMaskable);

    await writeSheet('build/logo/sheet.png');
  });
}
