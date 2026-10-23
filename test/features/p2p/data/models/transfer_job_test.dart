import 'package:event_notice/features/p2p/data/models/transfer_job.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  TransferJob job() => TransferJob(
    id: 'in-1',
    direction: TransferDirection.receive,
    fileName: 'a.txt',
    peerName: 'Máy',
    peerId: 'pc',
    size: 10,
    startedAt: start,
    state: TransferState.pending,
  );

  test('snapshot chép đủ mọi trường', () {
    final j = job()
      ..transferred = 4
      ..state = TransferState.failed
      ..problem = TransferProblem.failed
      ..problemDetail = 'hỏng'
      ..savedPath = '/x/a.txt'
      ..savedUri = 'content://1';

    expect(
      j.snapshot(),
      Transfer(
        id: 'in-1',
        direction: TransferDirection.receive,
        fileName: 'a.txt',
        peerName: 'Máy',
        peerId: 'pc',
        size: 10,
        startedAt: start,
        transferred: 4,
        state: TransferState.failed,
        problem: TransferProblem.failed,
        problemDetail: 'hỏng',
        savedPath: '/x/a.txt',
        savedUri: 'content://1',
      ),
    );
  });

  test('snapshot không đổi theo job sau đó', () {
    final j = job();
    final before = j.snapshot();
    j
      ..transferred = 9
      ..state = TransferState.running;

    expect(before.transferred, 0);
    expect(before.state, TransferState.pending);
    expect(j.isActive, isTrue);
    j.state = TransferState.done;
    expect(j.isActive, isFalse);
  });
}
