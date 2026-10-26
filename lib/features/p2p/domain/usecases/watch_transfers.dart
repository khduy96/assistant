import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/transfer.dart';
import '../repositories/transfer_repository.dart';

/// Snapshots of every transfer as it changes, to be kept with
/// `TransferHistory`. Open across start and stop.
class WatchTransfers implements UseCase<Stream<Transfer>, NoParams> {
  WatchTransfers(this._transfers);

  final TransferRepository _transfers;

  @override
  Future<Result<Stream<Transfer>>> call(NoParams params) async =>
      Ok(_transfers.updates);
}
