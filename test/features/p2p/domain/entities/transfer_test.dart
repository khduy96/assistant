import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('đang chờ hoặc đang chạy thì còn hoạt động', () {
    expect(transfer('a', state: TransferState.pending).isActive, isTrue);
    expect(transfer('a', state: TransferState.running).isActive, isTrue);
    expect(transfer('a', state: TransferState.done).isActive, isFalse);
    expect(transfer('a', state: TransferState.failed).isActive, isFalse);
    expect(transfer('a', state: TransferState.cancelled).isActive, isFalse);
  });

  test('tiến độ là tỉ lệ đã truyền, kẹp trong 0..1', () {
    expect(transfer('a', size: 200, transferred: 50).progress, 0.25);
    expect(transfer('a', size: 100, transferred: 150).progress, 1.0);
  });

  test('không biết dung lượng thì tiến độ vô định', () {
    expect(transfer('a', size: null).progress, isNull);
    expect(transfer('a', size: 0).progress, isNull);
  });

  test('copyWith đổi trạng thái, giữ danh tính lượt truyền', () {
    final t = transfer('a').copyWith(
      transferred: 100,
      state: TransferState.done,
      savedPath: 'C:/Downloads/a.txt',
      savedUri: 'content://downloads/1',
    );
    expect(t.id, 'a');
    expect(t.fileName, 'a.txt');
    expect(t.startedAt, seen);
    expect(t.transferred, 100);
    expect(t.state, TransferState.done);
    expect(t.savedPath, 'C:/Downloads/a.txt');
    expect(t.savedUri, 'content://downloads/1');
    expect(transfer('a').copyWith(), transfer('a'));
  });

  test('copyWith nhận null tường minh để xoá lý do lỗi và chỗ lưu', () {
    final failed = transfer('a').copyWith(
      state: TransferState.failed,
      problem: TransferProblem.failed,
      problemDetail: 'Máy nhận trả về 500',
      savedPath: 'x',
    );
    expect(failed.problem, TransferProblem.failed);
    expect(failed.problemDetail, 'Máy nhận trả về 500');

    final cleared = failed.copyWith(
      problem: null,
      problemDetail: null,
      savedPath: null,
    );
    expect(cleared.problem, isNull);
    expect(cleared.problemDetail, isNull);
    expect(cleared.savedPath, isNull);
    expect(cleared.state, TransferState.failed);
  });

  test('so sánh bằng theo giá trị', () {
    expect(transfer('a'), transfer('a'));
    expect(transfer('a').hashCode, transfer('a').hashCode);
    expect(transfer('a'), isNot(transfer('a', transferred: 1)));
  });
}
