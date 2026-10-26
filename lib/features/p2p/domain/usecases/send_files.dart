import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/outgoing_file.dart';
import '../entities/peer.dart';
import '../entities/transfer.dart';
import '../repositories/transfer_repository.dart';

/// What [SendFiles] takes: the device to send to, and the files in order.
typedef SendFilesParams = ({Peer peer, List<OutgoingFile> files});

/// Sends files to a device one after the other, not side by side: two files
/// sharing one Wi-Fi link are both slower and the total time is the same.
/// Yields the final snapshot of each file sent.
///
/// A file the user cancelled ends the batch; the files after it are not
/// sent. A file that failed does not: the next one is tried. An `Err` means a
/// file could not begin, e.g. transfer is off; the batch stops there.
class SendFiles implements UseCase<List<Transfer>, SendFilesParams> {
  SendFiles(this._transfers);

  final TransferRepository _transfers;

  @override
  Future<Result<List<Transfer>>> call(SendFilesParams params) async {
    final sent = <Transfer>[];
    for (final file in params.files) {
      switch (await _transfers.send(peer: params.peer, file: file)) {
        case Ok(:final value):
          sent.add(value);
          if (value.state == TransferState.cancelled) return Ok(sent);
        case Err(:final failure):
          return Err(failure);
      }
    }
    return Ok(sent);
  }
}
