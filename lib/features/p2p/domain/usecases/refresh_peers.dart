import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/peer.dart';
import '../repositories/peer_repository.dart';
import 'probe_manual_peers.dart';

/// "Search again": announces this device at once, asks the devices added by
/// IP again, then greets every address of the local /24 range for networks
/// that drop broadcasts. Yields the answers of [ProbeManualPeers].
///
/// A failed announcement or sweep does not stop the rest: whoever answers
/// shows up on the sightings stream anyway.
class RefreshPeers implements UseCase<Map<String, Peer?>, NoParams> {
  RefreshPeers(this._peers, this._probeManual);

  final PeerRepository _peers;
  final ProbeManualPeers _probeManual;

  @override
  Future<Result<Map<String, Peer?>>> call(NoParams params) async {
    await _peers.announce();
    final answers = await _probeManual(const NoParams());
    await _peers.sweep();
    return answers;
  }
}
