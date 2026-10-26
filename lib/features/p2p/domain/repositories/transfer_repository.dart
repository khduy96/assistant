import '../../../../core/domain/result.dart';
import '../entities/outgoing_file.dart';
import '../entities/p2p_settings.dart';
import '../entities/peer.dart';
import '../entities/save_location.dart';
import '../entities/transfer.dart';

/// Moving files between devices over HTTP on the LAN: a small server receives
/// files, and files are pushed to other devices' servers. Implemented in the
/// data layer; the requests must stay readable by older builds of the app.
///
/// Every transfer, sent or received, is reported on [updates]: once when it
/// appears, as its bytes move, and once when it ends. Received files are
/// written to `<name>.part` and renamed when complete, never overwrite a file
/// already there (`name (1).ext` instead), and leave nothing behind when the
/// transfer stops halfway.
///
/// No method throws: IO and socket errors come back as an `Err`, or end the
/// transfer concerned as [TransferState.failed].
abstract interface class TransferRepository {
  /// Opens the receiving server on `P2pProtocol.basePort`, or on one of the
  /// next ports when it is taken (`P2pProtocol.portAttempts` in all), and
  /// yields the port. It answers `GET /info` with the id and name in
  /// [settings]. When already started, yields the open port.
  ///
  /// An incoming file is accepted at once when [P2pSettings.autoAccept] is
  /// on, and first reported as [TransferState.running]. Otherwise it is
  /// reported as [TransferState.pending] and held until [respond], [cancel]
  /// or [stop]; after `P2pProtocol.offerTimeout` without an answer it is
  /// declined and ends with [TransferProblem.offerExpired].
  Future<Result<int>> start(P2pSettings settings);

  /// Closes the server. Running transfers end [TransferState.cancelled] with
  /// [TransferProblem.cancelled]; waiting offers are declined
  /// ([TransferProblem.declined]). Does nothing when not started.
  Future<Result<void>> stop();

  /// Takes new [settings] into account while started: the name sent and
  /// shown by `/info`, whether files are accepted without asking, and the
  /// save folder of files that arrive from now on. Does nothing when not
  /// started.
  Future<Result<void>> updateSettings(P2pSettings settings);

  /// Snapshots of every transfer as it changes; see the class comment.
  /// Progress may come many times a second, so listeners that redraw should
  /// throttle, letting the final snapshot through.
  ///
  /// One broadcast stream for the life of the repository, open across
  /// [start] and [stop].
  Stream<Transfer> get updates;

  /// Sends [file] to [peer] and completes when the transfer ended, with its
  /// final snapshot: [TransferState.done], [TransferState.cancelled] with
  /// [TransferProblem.cancelled], or [TransferState.failed] with
  /// [TransferProblem.rejectedByPeer], [TransferProblem.unreachable] or
  /// [TransferProblem.failed]. A transfer that did not go through is still
  /// `Ok`; an `Err` means it could not begin, e.g. when not started.
  Future<Result<Transfer>> send({
    required Peer peer,
    required OutgoingFile file,
  });

  /// Answers the waiting offer [id]: accepting starts receiving, declining
  /// ends it [TransferState.cancelled] with [TransferProblem.declined]. An id
  /// that is not a waiting offer (answered already, expired, unknown) is
  /// ignored.
  Future<Result<void>> respond(String id, {required bool accept});

  /// Stops the transfer [id]: a running one ends [TransferState.cancelled]
  /// with [TransferProblem.cancelled] after the chunk in flight, a waiting
  /// offer is declined as by [respond]. An id that is not active is ignored.
  Future<Result<void>> cancel(String id);

  /// Where received files go when [customDir] is the chosen folder (null or
  /// blank: the default one). Falls back to the default folder when
  /// [customDir] cannot be written to.
  Future<Result<SaveLocation>> saveLocation(String? customDir);

  /// Opens the system's Downloads screen. Yields false where there is none to
  /// open (only Android has one).
  Future<Result<bool>> openDownloads();

  /// Opens the received file of [transfer] with the default app, through its
  /// [Transfer.savedUri]. Yields false when it has none or it cannot be
  /// opened.
  Future<Result<bool>> openReceived(Transfer transfer);
}
