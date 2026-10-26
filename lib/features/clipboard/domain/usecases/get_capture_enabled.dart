import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/clipboard_source.dart';

/// Whether new clipboard values are being captured.
class GetCaptureEnabled implements UseCase<bool, NoParams> {
  GetCaptureEnabled(this._source);

  final ClipboardSource _source;

  @override
  Future<Result<bool>> call(NoParams params) async => Ok(_source.isEnabled);
}
