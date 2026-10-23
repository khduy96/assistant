import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../entities/peer.dart';
import '../repositories/p2p_settings_repository.dart';
import '../repositories/peer_repository.dart';
import '../services/manual_entry.dart';

/// How adding a device by IP went. Problems the user can fix are outcomes,
/// not failures; an `Err` means the settings could not be read or saved.
sealed class AddManualPeerOutcome {
  const AddManualPeerOutcome();
}

/// The device answered and its entry is saved.
final class ManualPeerAdded extends AddManualPeerOutcome {
  const ManualPeerAdded({required this.entry, required this.peer});

  /// `host:port`, as saved.
  final String entry;
  final Peer peer;
}

/// What was typed cannot be an address.
final class ManualPeerInvalid extends AddManualPeerOutcome {
  const ManualPeerInvalid();
}

/// Nothing at [entry] answered as this app; nothing was saved.
final class ManualPeerUnreachable extends AddManualPeerOutcome {
  const ManualPeerUnreachable(this.entry);

  final String entry;
}

/// Adds a device by what the user typed (`172.28.0.50` or
/// `172.28.0.50:45701`): checks that the app answers there, then keeps the
/// entry in the settings, once. For networks that block broadcasts.
class AddManualPeer implements UseCase<AddManualPeerOutcome, String> {
  AddManualPeer(this._settings, this._peers);

  final P2pSettingsRepository _settings;
  final PeerRepository _peers;

  @override
  Future<Result<AddManualPeerOutcome>> call(String input) async {
    final entry = normalizeEntry(input);
    if (entry == null) return const Ok(ManualPeerInvalid());

    final peer = (await _peers.probe(entry)).valueOrNull;
    if (peer == null) return Ok(ManualPeerUnreachable(entry));

    final P2pSettings current;
    switch (await _settings.load()) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (!current.manualPeers.contains(entry)) {
      final next = current.copyWith(
        manualPeers: [...current.manualPeers, entry],
      );
      if (await _settings.save(next) case Err(:final failure)) {
        return Err(failure);
      }
    }
    return Ok(ManualPeerAdded(entry: entry, peer: peer));
  }
}
