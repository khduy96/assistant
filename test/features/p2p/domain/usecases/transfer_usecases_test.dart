import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:event_notice/features/p2p/domain/usecases/cancel_transfer.dart';
import 'package:event_notice/features/p2p/domain/usecases/open_downloads.dart';
import 'package:event_notice/features/p2p/domain/usecases/open_received_file.dart';
import 'package:event_notice/features/p2p/domain/usecases/respond_to_offer.dart';
import 'package:event_notice/features/p2p/domain/usecases/send_files.dart';
import 'package:event_notice/features/p2p/domain/usecases/watch_transfers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _off = ValidationFailure('not started');

void main() {
  late FakeTransferRepository transfers;

  setUp(() => transfers = FakeTransferRepository());

  group('SendFiles', () {
    test('gửi lần lượt từng tệp, trả ảnh chụp cuối của mỗi tệp', () async {
      final result = await SendFiles(transfers)((
        peer: peer('pc'),
        files: [outgoing('a'), outgoing('b'), outgoing('c')],
      ));
      expect(result.valueOrNull?.map((t) => t.id), ['a', 'b', 'c']);
      expect(transfers.calls, ['send a to pc', 'send b to pc', 'send c to pc']);
    });

    test('người dùng huỷ một tệp thì bỏ luôn các tệp còn lại', () async {
      transfers.sendOutcomes['b'] = TransferState.cancelled;
      final result = await SendFiles(transfers)((
        peer: peer('pc'),
        files: [outgoing('a'), outgoing('b'), outgoing('c')],
      ));
      expect(result.valueOrNull?.map((t) => t.state), [
        TransferState.done,
        TransferState.cancelled,
      ]);
      expect(transfers.calls, ['send a to pc', 'send b to pc']);
    });

    test('một tệp lỗi thì vẫn gửi tiếp tệp sau', () async {
      transfers.sendOutcomes['a'] = TransferState.failed;
      final result = await SendFiles(transfers)((
        peer: peer('pc'),
        files: [outgoing('a'), outgoing('b')],
      ));
      expect(result.valueOrNull?.map((t) => t.state), [
        TransferState.failed,
        TransferState.done,
      ]);
    });

    test('chưa bật truyền tệp thì trả lỗi và dừng lô', () async {
      transfers.failures['send a to pc'] = _off;
      final result = await SendFiles(transfers)((
        peer: peer('pc'),
        files: [outgoing('a'), outgoing('b')],
      ));
      expect(result.failureOrNull, _off);
      expect(transfers.calls, ['send a to pc']);
    });
  });

  test('RespondToOffer chuyển câu trả lời của người dùng', () async {
    await RespondToOffer(transfers)((id: 'in-1', accept: true));
    await RespondToOffer(transfers)((id: 'in-2', accept: false));
    expect(transfers.calls, ['respond in-1 true', 'respond in-2 false']);
  });

  test('CancelTransfer huỷ theo id', () async {
    expect((await CancelTransfer(transfers)('out-1')).isOk, isTrue);
    expect(transfers.calls, ['cancel out-1']);
  });

  test('WatchTransfers chuyển nguyên các ảnh chụp', () async {
    final stream = (await WatchTransfers(transfers)(
      const NoParams(),
    )).valueOrNull!;
    final got = <Transfer>[];
    final sub = stream.listen(got.add);
    transfers.emit(transfer('a'));
    transfers.emit(transfer('a', transferred: 50));
    await sub.cancel();
    expect(got.map((t) => t.transferred), [0, 50]);
  });

  test('OpenDownloads và OpenReceivedFile hỏi repository', () async {
    expect(await OpenDownloads(transfers)(const NoParams()), const Ok(true));
    final received = transfer(
      'in-1',
      direction: TransferDirection.receive,
      state: TransferState.done,
    ).copyWith(savedUri: 'content://downloads/42');
    expect(await OpenReceivedFile(transfers)(received), const Ok(true));
    expect(transfers.calls, ['openDownloads', 'openReceived in-1']);
  });
}
