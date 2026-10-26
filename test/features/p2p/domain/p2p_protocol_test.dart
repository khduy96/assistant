import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/p2p_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// These numbers are on the wire or are what users expect; a change here
/// breaks devices running an older build.
void main() {
  test('thiết bị im quá 15 giây thì biến mất', () {
    expect(P2pProtocol.staleAfter, const Duration(seconds: 15));
    expect(Peer.staleAfter, P2pProtocol.staleAfter);
  });

  test('lời mời nhận tệp hết hạn sau 90 giây', () {
    expect(P2pProtocol.offerTimeout, const Duration(seconds: 90));
  });

  test('lịch sử giữ 40 lượt', () {
    expect(P2pProtocol.historyLimit, 40);
  });

  test('máy thêm bằng IP được hỏi lại mỗi 15 giây', () {
    expect(P2pProtocol.manualPingEvery, const Duration(seconds: 15));
  });

  test('cổng, nhãn gói tin và nhịp quảng bá giữ như bản cũ', () {
    expect(P2pProtocol.discoveryPort, 45699);
    expect(P2pProtocol.magic, 'event_notice_p2p/1');
    expect(P2pProtocol.announceEvery, const Duration(seconds: 3));
    expect(P2pProtocol.basePort, 45700);
    expect(P2pProtocol.portAttempts, 5);
  });

  test('các thời hạn chờ và nhịp dọn giữ như bản cũ', () {
    expect(P2pProtocol.pruneEvery, const Duration(seconds: 5));
    expect(P2pProtocol.probeConnectTimeout, const Duration(seconds: 3));
    expect(P2pProtocol.probeTimeout, const Duration(seconds: 4));
    expect(P2pProtocol.sendConnectTimeout, const Duration(seconds: 10));
  });
}
