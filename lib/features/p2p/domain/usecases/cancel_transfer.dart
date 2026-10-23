import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/transfer_repository.dart';

/// Stops a running transfer, or declines a waiting offer, by id.
class CancelTransfer implements UseCase<void, String> {
  CancelTransfer(this._transfers);

  final TransferRepository _transfers;

  @override
  Future<Result<void>> call(String id) => _transfers.cancel(id);
}
