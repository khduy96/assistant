import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../entities/peer.dart';
import '../repositories/p2p_settings_repository.dart';
import '../repositories/peer_repository.dart';

/// Asks every device added by IP whether it is still there, one after the
/// other, and yields the answers by entry, in the saved order: the device, or
/// null when it did not answer.
///
/// Devices added by IP are not heard through broadcasts, so this runs every
/// `P2pProtocol.manualPingEvery` while transfer is on.
class ProbeManualPeers implements UseCase<Map<String, Peer?>, NoParams> {
  ProbeManualPeers(this._settings, this._peers);

  final P2pSettingsRepository _settings;
  final PeerRepository _peers;

  @override
  Future<Result<Map<String, Peer?>>> call(NoParams params) async {
    final P2pSettings settings;
    switch (await _settings.load()) {
      case Ok(:final value):
        settings = value;
      case Err(:final failure):
        return Err(failure);
    }
    final answers = <String, Peer?>{};
    for (final entry in settings.manualPeers) {
      // A probe that failed outright is as good as no answer.
      answers[entry] = (await _peers.probe(entry)).valueOrNull;
    }
    return Ok(answers);
  }
}
