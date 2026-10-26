import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:event_notice/features/p2p/domain/services/transfer_history.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('lượt mới lên đầu danh sách', () {
    var list = TransferHistory.record(const [], transfer('a'));
    list = TransferHistory.record(list, transfer('b'));
    expect(list.map((t) => t.id), ['b', 'a']);
  });

  test('ảnh chụp mới của lượt đã có thay đúng chỗ', () {
    var list = TransferHistory.record(const [], transfer('a'));
    list = TransferHistory.record(list, transfer('b'));
    final before = list;
    list = TransferHistory.record(
      list,
      transfer('a', transferred: 50, state: TransferState.done),
    );
    expect(list.map((t) => t.id), ['b', 'a']);
    expect(list[1].state, TransferState.done);
    expect(before[1].state, TransferState.running);
  });

  test('giữ tối đa 40 lượt đã xong, bỏ lượt cũ nhất', () {
    var list = <Transfer>[];
    for (var i = 0; i < 45; i++) {
      list = TransferHistory.record(
        list,
        transfer('t$i', state: TransferState.done),
      );
    }
    expect(list, hasLength(40));
    expect(list.first.id, 't44');
    expect(list.last.id, 't5');
  });

  test('lượt đang chạy không bao giờ bị cắt, dù danh sách dài', () {
    var list = <Transfer>[];
    for (var i = 0; i < 45; i++) {
      list = TransferHistory.record(list, transfer('t$i'));
    }
    expect(list, hasLength(45));

    // Một lượt chạy xong thì thành lượt cũ duy nhất có thể cắt, nhưng thay
    // tại chỗ không cắt; lượt mới tiếp theo mới kéo nó ra.
    list = TransferHistory.record(
      list,
      transfer('t0', state: TransferState.done),
    );
    expect(list, hasLength(45));
    list = TransferHistory.record(list, transfer('t45'));
    expect(list, hasLength(45));
    expect(list.map((t) => t.id), isNot(contains('t0')));
    expect(list.first.id, 't45');
  });

  test('cắt từ cuối: chỉ bỏ lượt đã kết thúc', () {
    final list = [
      transfer('new', state: TransferState.done),
      transfer('mid', state: TransferState.done),
      transfer('running'),
      transfer('old', state: TransferState.failed),
    ];
    final trimmed = TransferHistory.trim(list, limit: 2);
    expect(trimmed.map((t) => t.id), ['new', 'running']);
  });

  test('xoá lịch sử chỉ giữ các lượt còn hoạt động', () {
    final list = [
      transfer('a', state: TransferState.done),
      transfer('b', state: TransferState.pending),
      transfer('c'),
      transfer('d', state: TransferState.cancelled),
    ];
    expect(TransferHistory.clearFinished(list).map((t) => t.id), ['b', 'c']);
    expect(TransferHistory.activeCount(list), 2);
  });

  test('tách lời mời đang chờ khỏi danh sách lượt truyền', () {
    final list = [
      transfer('offer', state: TransferState.pending),
      transfer('run'),
      transfer('done', state: TransferState.done),
    ];
    expect(TransferHistory.pendingOffers(list).map((t) => t.id), ['offer']);
    expect(TransferHistory.withoutOffers(list).map((t) => t.id), [
      'run',
      'done',
    ]);
  });
}
