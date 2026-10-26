import '../../domain/entities/transfer.dart';

/// A transfer while its bytes move, changed in place by the read and write
/// loops. The rest of the app only ever sees [snapshot]s of it.
class TransferJob {
  TransferJob({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.peerName,
    this.peerId,
    this.size,
    required this.startedAt,
    this.state = TransferState.running,
  });

  final String id;
  final TransferDirection direction;
  final String fileName;
  final String peerName;
  final String? peerId;

  /// Total bytes; null when the sender could not tell.
  final int? size;
  final DateTime startedAt;

  int transferred = 0;
  TransferState state;
  TransferProblem? problem;
  String? problemDetail;
  String? savedPath;
  String? savedUri;

  /// Checked by the read and write loops after every chunk.
  bool cancelRequested = false;

  bool get isActive =>
      state == TransferState.running || state == TransferState.pending;

  /// The transfer as it is now.
  Transfer snapshot() => Transfer(
    id: id,
    direction: direction,
    fileName: fileName,
    peerName: peerName,
    peerId: peerId,
    size: size,
    startedAt: startedAt,
    transferred: transferred,
    state: state,
    problem: problem,
    problemDetail: problemDetail,
    savedPath: savedPath,
    savedUri: savedUri,
  );
}
