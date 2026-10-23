import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/clipboard_source.dart';

/// Pauses or resumes capturing new clipboard values.
class SetCaptureEnabled implements UseCase<void, bool> {
  SetCaptureEnabled(this._source);

  final ClipboardSource _source;

  @override
  Future<Result<void>> call(bool enabled) async {
    _source.setEnabled(enabled);
    return const Ok(null);
  }
}
