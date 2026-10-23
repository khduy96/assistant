import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../repositories/p2p_settings_repository.dart';
import '../repositories/peer_repository.dart';
import '../repositories/transfer_repository.dart';

/// Turns file transfer on: opens the receiving server, then starts discovery
/// announcing the server's port, and yields that port.
///
/// When discovery cannot start, the server is closed again, so a failed start
/// leaves nothing half open.
class StartP2p implements UseCase<int, NoParams> {
  StartP2p(this._settings, this._transfers, this._peers);

  final P2pSettingsRepository _settings;
  final TransferRepository _transfers;
  final PeerRepository _peers;

  @override
  Future<Result<int>> call(NoParams params) async {
    final P2pSettings settings;
    switch (await _settings.load()) {
      case Ok(:final value):
        settings = value;
      case Err(:final failure):
        return Err(failure);
    }

    final int port;
    switch (await _transfers.start(settings)) {
      case Ok(:final value):
        port = value;
      case Err(:final failure):
        return Err(failure);
    }

    if (await _peers.start(settings, servicePort: port) case Err(
      :final failure,
    )) {
      await _transfers.stop();
      return Err(failure);
    }
    return Ok(port);
  }
}
