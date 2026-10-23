import '../../../../core/domain/result.dart';

/// The system clipboard, as the clipboard feature sees it: text the user
/// copies anywhere comes in through [captures], and clips go back out through
/// [write]. Implemented in the data layer.
abstract interface class ClipboardSource {
  /// Text values newly seen on the system clipboard, trimmed, never empty and
  /// never the same as the value seen just before.
  ///
  /// The clipboard is watched while this stream has a listener; cancelling
  /// the subscription stops the watching.
  Stream<String> get captures;

  /// Whether [captures] currently reports anything. On by default.
  bool get isEnabled;

  /// Pauses or resumes capturing without cancelling [captures].
  void setEnabled(bool enabled);

  /// Puts [text] on the system clipboard. The value is remembered as already
  /// seen, so copying from inside the app does not come back as a capture.
  Future<Result<void>> write(String text);
}
