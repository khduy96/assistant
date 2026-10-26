import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/transfer_repository.dart';

/// Opens the system's Downloads screen; false where there is none (only
/// Android has one).
class OpenDownloads implements UseCase<bool, NoParams> {
  OpenDownloads(this._transfers);

  final TransferRepository _transfers;

  @override
  Future<Result<bool>> call(NoParams params) => _transfers.openDownloads();
}
