import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/transfer.dart';
import '../repositories/transfer_repository.dart';

/// Opens a received file with the default app; false when it cannot be.
class OpenReceivedFile implements UseCase<bool, Transfer> {
  OpenReceivedFile(this._transfers);

  final TransferRepository _transfers;

  @override
  Future<Result<bool>> call(Transfer transfer) =>
      _transfers.openReceived(transfer);
}
