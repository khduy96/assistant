import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:event_notice/features/p2p/presentation/p2p_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';

Transfer _ended(
  TransferState state, {
  TransferProblem? problem,
  String? detail,
  TransferDirection direction = TransferDirection.send,
}) => transfer(
  'x',
  state: state,
  direction: direction,
).copyWith(problem: problem, problemDetail: detail);

void main() {
  test('every problem reads as before', () {
    expect(TransferProblem.cancelled.label, 'Đã huỷ');
    expect(TransferProblem.declined.label, 'Đã từ chối');
    expect(TransferProblem.offerExpired.label, 'Hết giờ chờ trả lời');
    expect(
      TransferProblem.rejectedByPeer.label,
      'Thiết bị kia đã từ chối nhận',
    );
    expect(
      TransferProblem.unreachable.label,
      'Không nối được tới thiết bị kia (cùng Wi-Fi? tường lửa?)',
    );
    expect(TransferProblem.failed.label, 'Lỗi');
  });

  group('describeTransfer', () {
    test('done says who it went to or came from', () {
      expect(
        describeTransfer(_ended(TransferState.done)),
        'Đã gửi tới Máy kia',
      );
      expect(
        describeTransfer(
          _ended(TransferState.done, direction: TransferDirection.receive),
        ),
        'Đã nhận từ Máy kia',
      );
    });

    test('a failure says why, with the detail when there is one', () {
      expect(
        describeTransfer(
          _ended(
            TransferState.failed,
            problem: TransferProblem.failed,
            detail: 'HttpException: 500',
          ),
        ),
        'HttpException: 500',
      );
      expect(
        describeTransfer(
          _ended(TransferState.failed, problem: TransferProblem.failed),
        ),
        'Lỗi',
      );
      expect(
        describeTransfer(
          _ended(TransferState.failed, problem: TransferProblem.unreachable),
        ),
        'Không nối được tới thiết bị kia (cùng Wi-Fi? tường lửa?)',
      );
      expect(describeTransfer(_ended(TransferState.failed)), 'Lỗi');
    });

    test('a cancelled transfer says why', () {
      expect(
        describeTransfer(
          _ended(TransferState.cancelled, problem: TransferProblem.declined),
        ),
        'Đã từ chối',
      );
      expect(
        describeTransfer(
          _ended(
            TransferState.cancelled,
            problem: TransferProblem.offerExpired,
          ),
        ),
        'Hết giờ chờ trả lời',
      );
      expect(describeTransfer(_ended(TransferState.cancelled)), 'Đã huỷ');
    });

    test('a running transfer shows how far along it is', () {
      expect(
        describeTransfer(transfer('x', size: 2048, transferred: 1024)),
        'Đang gửi tới Máy kia — 1,0 KB / 2,0 KB',
      );
      expect(
        describeTransfer(
          transfer(
            'x',
            direction: TransferDirection.receive,
            size: null,
            transferred: 10,
          ),
        ),
        'Đang nhận từ Máy kia — 10 B / ?',
      );
    });
  });

  test('formatBytes', () {
    expect(formatBytes(null), '?');
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1,5 KB');
    expect(formatBytes(150 * 1024), '150 KB');
    expect(formatBytes(12 * 1024 * 1024 + 300 * 1024), '12,3 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3,0 GB');
  });

  test('platformIcon', () {
    expect(platformIcon('android'), Icons.smartphone);
    expect(platformIcon('ios'), Icons.smartphone);
    expect(platformIcon('windows'), Icons.computer);
    expect(platformIcon('linux'), Icons.computer);
    expect(platformIcon('macos'), Icons.computer);
    expect(platformIcon('other'), Icons.devices_other);
  });
}
