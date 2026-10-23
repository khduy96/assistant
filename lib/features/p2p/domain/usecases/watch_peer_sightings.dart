import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/peer.dart';
import '../repositories/peer_repository.dart';

/// What discovery hears, to be kept with `PeerTable`. Open across start and
/// stop.
class WatchPeerSightings implements UseCase<Stream<PeerSighting>, NoParams> {
  WatchPeerSightings(this._peers);

  final PeerRepository _peers;

  @override
  Future<Result<Stream<PeerSighting>>> call(NoParams params) async =>
      Ok(_peers.sightings);
}
