/// Which way a transfer goes: this device sends, or receives.
enum TransferDirection { send, receive }

enum TransferState {
  /// An incoming file waiting for the user to accept or decline it (receive
  /// only).
  pending,

  /// Connecting, or bytes are moving.
  running,
  done,
  failed,

  /// Stopped by the user, by turning file transfer off, or an incoming file
  /// that was declined.
  cancelled,
}

/// Why a transfer did not end [TransferState.done]. The presentation layer
/// turns it into words.
enum TransferProblem {
  /// Cancelled while running (ends [TransferState.cancelled]).
  cancelled,

  /// An incoming file this device declined, or cancelled before accepting
  /// (ends [TransferState.cancelled]).
  declined,

  /// An incoming file nobody answered in time (ends
  /// [TransferState.cancelled]).
  offerExpired,

  /// The receiving device declined the file (ends [TransferState.failed]).
  rejectedByPeer,

  /// The other device could not be reached (ends [TransferState.failed]).
  unreachable,

  /// Anything else; [Transfer.problemDetail] says what (ends
  /// [TransferState.failed]).
  failed,
}

/// Marks a [Transfer.copyWith] argument that was not passed, so an explicit
/// null can clear a field.
const Object _unset = Object();

/// One file being sent or received, or one that was.
///
/// Immutable: each change while a file moves comes as a new snapshot with the
/// same [id].
class Transfer {
  const Transfer({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.peerName,
    this.peerId,
    this.size,
    required this.startedAt,
    this.transferred = 0,
    this.state = TransferState.running,
    this.problem,
    this.problemDetail,
    this.savedPath,
    this.savedUri,
  });

  final String id;
  final TransferDirection direction;
  final String fileName;
  final String peerName;
  final String? peerId;

  /// Total bytes; null when the sender could not tell.
  final int? size;
  final DateTime startedAt;

  /// Bytes moved so far.
  final int transferred;
  final TransferState state;

  /// Why the transfer did not end done; null while active and when done.
  final TransferProblem? problem;

  /// What went wrong, for [TransferProblem.failed].
  final String? problemDetail;

  /// Where the received file was written (receive only).
  final String? savedPath;

  /// `content://...` of the received file once moved into Download (Android
  /// only), used to open it with the default app.
  final String? savedUri;

  bool get isActive =>
      state == TransferState.running || state == TransferState.pending;

  /// 0..1, or null when the total size is unknown.
  double? get progress {
    final total = size;
    if (total == null || total <= 0) return null;
    return (transferred / total).clamp(0.0, 1.0);
  }

  /// A copy with the given fields replaced. An explicit null clears
  /// [problem], [problemDetail], [savedPath] or [savedUri]. What the transfer
  /// is (id, direction, file, peer, size, start) never changes.
  Transfer copyWith({
    int? transferred,
    TransferState? state,
    Object? problem = _unset,
    Object? problemDetail = _unset,
    Object? savedPath = _unset,
    Object? savedUri = _unset,
  }) => Transfer(
    id: id,
    direction: direction,
    fileName: fileName,
    peerName: peerName,
    peerId: peerId,
    size: size,
    startedAt: startedAt,
    transferred: transferred ?? this.transferred,
    state: state ?? this.state,
    problem: identical(problem, _unset)
        ? this.problem
        : problem as TransferProblem?,
    problemDetail: identical(problemDetail, _unset)
        ? this.problemDetail
        : problemDetail as String?,
    savedPath: identical(savedPath, _unset)
        ? this.savedPath
        : savedPath as String?,
    savedUri: identical(savedUri, _unset) ? this.savedUri : savedUri as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Transfer &&
      other.id == id &&
      other.direction == direction &&
      other.fileName == fileName &&
      other.peerName == peerName &&
      other.peerId == peerId &&
      other.size == size &&
      other.startedAt == startedAt &&
      other.transferred == transferred &&
      other.state == state &&
      other.problem == problem &&
      other.problemDetail == problemDetail &&
      other.savedPath == savedPath &&
      other.savedUri == savedUri;

  @override
  int get hashCode => Object.hash(
    id,
    direction,
    fileName,
    peerName,
    peerId,
    size,
    startedAt,
    transferred,
    state,
    problem,
    problemDetail,
    savedPath,
    savedUri,
  );

  @override
  String toString() =>
      'Transfer($id, ${direction.name}, $fileName, ${state.name}, '
      '$transferred/${size ?? '?'})';
}
