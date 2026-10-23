import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../ports/clipboard_source.dart';
import 'capture_clip.dart';

/// Clips made from what the user copies anywhere: every new clipboard value
/// goes through [CaptureClip], and the clip it stored is yielded.
///
/// Values are handled one at a time, in the order they were seen. A value that
/// stores nothing is skipped; a failure is yielded as an `Err` and watching
/// goes on. The clipboard is watched while the stream is listened to.
class WatchCapturedClips
    implements UseCase<Stream<Result<ClipItem>>, NoParams> {
  WatchCapturedClips(this._source, this._capture);

  final ClipboardSource _source;
  final CaptureClip _capture;

  @override
  Future<Result<Stream<Result<ClipItem>>>> call(NoParams params) async => Ok(
    // asyncMap holds the next value back until the previous one is
    // stored, and a cancel reaches the source at once; an async* loop
    // would only see the cancel at its next yield.
    _source.captures
        .asyncMap(_capture.call)
        .expand<Result<ClipItem>>(
          (result) => switch (result) {
            Ok(value: final clip?) => [Ok(clip)],
            Ok() => const [],
            Err(:final failure) => [Err(failure)],
          },
        ),
  );
}
