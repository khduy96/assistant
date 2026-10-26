import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/peer_repository.dart';
import '../repositories/transfer_repository.dart';

/// Turns file transfer off: says goodbye and stops discovery, then closes the
/// server, which cuts every running transfer and declines waiting offers.
///
/// Both are stopped even when the first fails; the first failure is
/// returned.
class StopP2p implements UseCase<void, NoParams> {
  StopP2p(this._transfers, this._peers);

  final TransferRepository _transfers;
  final PeerRepository _peers;

  @override
  Future<Result<void>> call(NoParams params) async {
    final peers = await _peers.stop();
    final transfers = await _transfers.stop();
    return switch ((peers, transfers)) {
      (Err(:final failure), _) => Err(failure),
      (_, Err(:final failure)) => Err(failure),
      _ => const Ok(null),
    };
  }
}
