import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/peer_repository.dart';

/// This machine's IPv4 address on the LAN; empty when unknown.
class GetLocalAddress implements UseCase<String, NoParams> {
  GetLocalAddress(this._peers);

  final PeerRepository _peers;

  @override
  Future<Result<String>> call(NoParams params) => _peers.localAddress();
}
