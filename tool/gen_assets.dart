// Generates the bundled alarm sound (WAV).
// The app icons live in tool/gen_logo.dart.
// Run once with: dart run tool/gen_assets.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int sampleRate = 44100;

void main() {
  _writeWav('assets/sounds/alarm.wav');
  stdout.writeln('Assets generated.');
}

/// Three short beeps followed by silence, so looping sounds like an alarm clock.
void _writeWav(String path) {
  final samples = <int>[];
  void tone(double seconds, double freq) {
    final n = (seconds * sampleRate).round();
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      // Short fade in/out to avoid clicks between segments.
      final fade = min(1.0, min(i, n - i) / (sampleRate * 0.01));
      final v = sin(2 * pi * freq * t) * 0.55 * fade;
      samples.add((v * 32767).round());
    }
  }

  for (var i = 0; i < 3; i++) {
    tone(0.14, 880);
    tone(0.09, 0);
  }
  tone(0.7, 0);

  final data = Uint8List(samples.length * 2);
  final dv = ByteData.view(data.buffer);
  for (var i = 0; i < samples.length; i++) {
    dv.setInt16(i * 2, samples[i], Endian.little);
  }

  final header = BytesBuilder();
  void str(String s) => header.add(s.codeUnits);
  void u32(int v) => header.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => header.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  str('RIFF');
  u32(36 + data.length);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits per sample
  str('data');
  u32(data.length);

  File(path).writeAsBytesSync(header.toBytes() + data);
}

