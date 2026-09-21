import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/peer.dart';
import '../models/transfer.dart';
import '../services/discovery_service.dart';
import '../services/file_sender.dart';
import '../services/file_server.dart';
import '../services/p2p_settings.dart';
import '../services/public_files.dart';

/// Trạng thái của phần truyền tệp ngang hàng: danh sách thiết bị thấy được,
/// các lượt truyền đang chạy và những lời mời nhận đang chờ trả lời.
///
/// Không có máy chủ ở giữa: hai máy tự thấy nhau bằng UDP broadcast rồi đẩy
/// thẳng tệp cho nhau qua HTTP trong LAN, nên tệp không rời khỏi mạng nhà.
class P2pStore extends ChangeNotifier {
  /// Nhịp vẽ lại tối đa khi đang truyền; không có thì mỗi khối 64 KB lại dựng
  /// lại cả cây widget.
  static const _uiThrottle = Duration(milliseconds: 120);

  /// Lời mời nhận không ai bấm gì trong khoảng này thì tự từ chối.
  static const _offerTimeout = Duration(seconds: 90);

  /// Giữ lại bấy nhiêu lượt đã kết thúc trong lịch sử hiển thị.
  static const _historyLimit = 40;

  /// Chờ lâu nhất bấy nhiêu khi hỏi `/info` một thiết bị khai bằng IP.
  static const _probeTimeout = Duration(seconds: 4);

  P2pSettings? _settings;
  DiscoveryService? _discovery;
  FileServer? _server;
  FileSender? _sender;

  final Map<String, Peer> _peers = {};

  /// Thiết bị khai bằng IP đang nối được, khoá là mục `host:port` đã lưu.
  final Map<String, Peer> _manualPeers = {};
  final List<TransferTask> _transfers = [];
  final Map<String, Completer<bool>> _offers = {};

  Timer? _pruneTimer;
  Timer? _manualTimer;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _starting = false;
  String? _error;
  String _localAddress = '';
  String _saveLabel = '';

  bool get isReady => _settings != null;
  bool get isRunning => _server?.isRunning ?? false;
  bool get isStarting => _starting;
  String? get error => _error;

  String get deviceName => _settings?.deviceName ?? '';
  String get deviceId => _settings?.deviceId ?? '';
  bool get autoAccept => _settings?.autoAccept ?? false;
  bool get enabled => _settings?.enabled ?? false;
  String? get saveDir => _settings?.saveDir;

  /// IPv4 của máy này trong LAN, để đọc cho nhau nghe khi cần dò mạng.
  String get localAddress => _localAddress;
  int? get port => _server?.port;

  /// Thiết bị còn nghe thấy được, xếp theo tên.
  List<Peer> get peers {
    final list = _peers.values.where((p) => !p.isStale).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<TransferTask> get transfers => List.unmodifiable(_transfers);

  /// Các lời mời nhận đang chờ người dùng quyết định.
  List<TransferTask> get pendingOffers =>
      _transfers.where((t) => t.state == TransferState.pending).toList();

  int get activeCount => _transfers.where((t) => t.isActive).length;

  // --------------------------------------------------------------- lifecycle

  Future<void> init() async {
    _settings = await P2pSettings.load();
    unawaited(_refreshSaveLabel());
    notifyListeners();
    if (_settings!.enabled) await start();
  }

  Future<void> start() async {
    final settings = _settings;
    if (settings == null || _starting || isRunning) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      final server = FileServer(
        settings: settings,
        onOffer: _askUser,
        onProgress: _touch,
        onFinished: _finish,
        // Android: chuyển tiếp ra Download công cộng, xem [PublicFiles].
        publish: Platform.isAndroid ? PublicFiles.publish : null,
      );
      await server.start();
      _server = server;
      _sender = FileSender(
        deviceId: settings.deviceId,
        deviceName: settings.deviceName,
      );
      final discovery = DiscoveryService(
        deviceId: settings.deviceId,
        deviceName: settings.deviceName,
        platform: P2pSettings.platformTag,
        servicePort: server.port!,
        onPeer: _onPeer,
      );
      await discovery.start();
      _discovery = discovery;
      _localAddress = await _findLocalAddress();
      // Máy tắt nguồn không kịp chào tạm biệt, nên phải tự dọn theo giờ.
      _pruneTimer = Timer.periodic(const Duration(seconds: 5), (_) => _prune());
      // Thiết bị khai bằng IP không tự quảng bá tới được, phải chủ động hỏi.
      _manualTimer =
          Timer.periodic(const Duration(seconds: 15), (_) => pingManual());
      unawaited(pingManual());
    } catch (e) {
      _error = 'Không bật được: $e';
      await _shutdown();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _shutdown();
    notifyListeners();
  }

  Future<void> _shutdown() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _manualTimer?.cancel();
    _manualTimer = null;
    _manualPeers.clear();
    await _discovery?.stop();
    _discovery = null;
    await _server?.stop();
    _server = null;
    _sender = null;
    _peers.clear();
    // Không còn đường truyền nào nữa: cắt mọi thứ đang dang dở.
    for (final task in _transfers.where((t) => t.isActive)) {
      task.cancelRequested = true;
    }
    for (final completer in _offers.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _offers.clear();
  }

  Future<void> setEnabled(bool value) async {
    final settings = _settings;
    if (settings == null) return;
    settings.enabled = value;
    await settings.save();
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> setAutoAccept(bool value) async {
    final settings = _settings;
    if (settings == null) return;
    settings.autoAccept = value;
    await settings.save();
    notifyListeners();
  }

  Future<void> rename(String name) async {
    final settings = _settings;
    final trimmed = name.trim();
    if (settings == null || trimmed.isEmpty || trimmed == settings.deviceName) {
      return;
    }
    settings.deviceName = trimmed;
    await settings.save();
    _discovery?.deviceName = trimmed;
    if (_sender != null) {
      _sender = FileSender(deviceId: settings.deviceId, deviceName: trimmed);
    }
    await _discovery?.announce();
    notifyListeners();
  }

  Future<void> setSaveDir(String? path) async {
    final settings = _settings;
    if (settings == null) return;
    settings.saveDir = path;
    unawaited(_refreshSaveLabel());
    await settings.save();
    notifyListeners();
  }

  /// Thư mục đang thực sự dùng để cất tệp nhận được. Trên Android đây chỉ là
  /// chỗ ghi tạm, xem [saveLocationLabel].
  Future<String> currentSaveDir() async {
    final settings = _settings;
    if (settings == null) return '';
    return (await settings.resolveSaveDir()).path;
  }

  /// Câu chữ hiện trên thẻ trạng thái cho biết tệp nhận được nằm ở đâu.
  ///
  /// Tính sẵn một lần chứ không hỏi lại mỗi lần vẽ: trong lúc truyền, thẻ này
  /// dựng lại mấy lần một giây.
  String get saveLocationLabel => _saveLabel;

  Future<void> _refreshSaveLabel() async {
    final label = await PublicFiles.isSupported()
        ? 'Download/${PublicFiles.subDir}'
        : await currentSaveDir();
    if (label == _saveLabel) return;
    _saveLabel = label;
    notifyListeners();
  }

  /// Bắn ngay một nhịp quảng bá, rồi chào riêng từng địa chỉ trong dải /24 cho
  /// trường hợp mạng chặn broadcast, rồi hỏi lại các thiết bị khai bằng IP.
  Future<void> refresh() async {
    _prune();
    await _discovery?.announce();
    await pingManual();
    await _discovery?.sweep();
  }

  // -------------------------------------------------- thiết bị khai bằng IP

  /// Các mục người dùng tự gõ, dạng `172.28.0.50:45700`.
  List<String> get manualEntries =>
      List.unmodifiable(_settings?.manualPeers ?? const <String>[]);

  /// Thiết bị khai bằng IP mà lần hỏi gần nhất còn trả lời; null là không nối
  /// được.
  Peer? manualPeer(String entry) => _manualPeers[entry];

  /// Thêm một thiết bị bằng địa chỉ IP. Trả về câu báo lỗi, hoặc null nếu xong.
  Future<String?> addManualPeer(String input) async {
    final settings = _settings;
    if (settings == null) return 'Chưa sẵn sàng';
    final entry = normalizeEntry(input);
    if (entry == null) return 'Địa chỉ không hợp lệ. Ví dụ: 172.28.0.50';

    final peer = await _probe(entry);
    if (peer == null) {
      return 'Không nối được tới $entry. Máy kia đã mở app và bật truyền tệp '
          'chưa? Tường lửa của máy đó có cho phép không?';
    }
    _manualPeers[entry] = peer;
    if (!settings.manualPeers.contains(entry)) {
      settings.manualPeers.add(entry);
      await settings.save();
    }
    notifyListeners();
    return null;
  }

  Future<void> removeManualPeer(String entry) async {
    final settings = _settings;
    if (settings == null) return;
    settings.manualPeers.remove(entry);
    _manualPeers.remove(entry);
    await settings.save();
    notifyListeners();
  }

  /// Hỏi lại tất cả thiết bị khai bằng IP xem còn sống không.
  Future<void> pingManual() async {
    final entries = _settings?.manualPeers.toList() ?? const <String>[];
    for (final entry in entries) {
      final peer = await _probe(entry);
      if (peer == null) {
        _manualPeers.remove(entry);
      } else {
        _manualPeers[entry] = peer;
      }
    }
    notifyListeners();
  }

  /// `172.28.0.50` hoặc `172.28.0.50:45701` → `172.28.0.50:45701`.
  static String? normalizeEntry(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    var port = FileServer.basePort;
    final colon = text.lastIndexOf(':');
    if (colon > 0) {
      final parsed = int.tryParse(text.substring(colon + 1));
      if (parsed == null || parsed < 1 || parsed > 65535) return null;
      port = parsed;
      text = text.substring(0, colon);
    }
    if (text.isEmpty || text.contains(' ')) return null;
    return '$text:$port';
  }

  /// Gọi `GET /info` để biết máy ở địa chỉ đó là ai.
  Future<Peer?> _probe(String entry) async {
    final colon = entry.lastIndexOf(':');
    final host = entry.substring(0, colon);
    final port = int.parse(entry.substring(colon + 1));
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request =
          await client.getUrl(Uri.parse('http://$host:$port/info'));
      final response = await request.close().timeout(_probeTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      return Peer(
        id: body['id'] as String? ?? entry,
        name: body['name'] as String? ?? host,
        platform: body['platform'] as String? ?? 'other',
        address: host,
        port: port,
        seenAt: DateTime.now(),
      );
    } catch (_) {
      // Không nối được, sai cổng, hoặc bên kia không phải app này.
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _shutdown();
    super.dispose();
  }

  // ------------------------------------------------------------------ gửi đi

  /// Gửi lần lượt từng tệp sang [peer]. Nối tiếp chứ không song song: một
  /// đường Wi-Fi chia đôi thì cả hai tệp cùng chậm mà tổng thời gian không đổi.
  Future<void> sendFiles(Peer peer, List<OutgoingFile> files) async {
    final sender = _sender;
    if (sender == null) {
      _error = 'Chưa bật truyền tệp';
      notifyListeners();
      return;
    }
    for (final file in files) {
      final task = TransferTask(
        id: 'out-${DateTime.now().microsecondsSinceEpoch}-${file.name.hashCode}',
        direction: TransferDirection.send,
        fileName: file.name,
        peerName: peer.name,
        peerId: peer.id,
        size: file.size,
      );
      _add(task);
      try {
        await sender.send(
          peer: peer,
          file: file,
          task: task,
          onProgress: _touch,
        );
        task.state = TransferState.done;
      } catch (e) {
        final cancelled = e is P2pCancelled || task.cancelRequested;
        task.state = cancelled ? TransferState.cancelled : TransferState.failed;
        task.error = cancelled ? 'Đã huỷ' : _describe(e);
      }
      _finish(task);
      // Người dùng huỷ giữa chừng thì bỏ luôn các tệp còn lại trong lô.
      if (task.state == TransferState.cancelled) break;
    }
  }

  static String _describe(Object error) {
    if (error is P2pRejected) return 'Thiết bị kia đã từ chối nhận';
    if (error is SocketException) {
      return 'Không nối được tới thiết bị kia (cùng Wi-Fi? tường lửa?)';
    }
    return '$error';
  }

  void cancel(TransferTask task) {
    task.cancelRequested = true;
    final completer = _offers.remove(task.id);
    if (completer != null && !completer.isCompleted) completer.complete(false);
    notifyListeners();
  }

  /// Trả lời một lời mời nhận đang chờ.
  void respond(TransferTask task, {required bool accept}) {
    final completer = _offers.remove(task.id);
    if (completer == null || completer.isCompleted) return;
    if (!accept) task.cancelRequested = true;
    completer.complete(accept);
    notifyListeners();
  }

  void clearHistory() {
    _transfers.removeWhere((t) => !t.isActive);
    notifyListeners();
  }

  // ----------------------------------------------------------------- nhận về

  /// Được [FileServer] gọi khi có tệp gõ cửa.
  Future<bool> _askUser(TransferTask task) async {
    _add(task);
    if (autoAccept) {
      task.state = TransferState.running;
      notifyListeners();
      return true;
    }
    final completer = Completer<bool>();
    _offers[task.id] = completer;
    notifyListeners();

    final timer = Timer(_offerTimeout, () {
      if (!completer.isCompleted) {
        task.error = 'Hết giờ chờ trả lời';
        completer.complete(false);
      }
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      _offers.remove(task.id);
    }
  }

  void _add(TransferTask task) {
    _transfers.insert(0, task);
    _trim();
    notifyListeners();
  }

  void _trim() {
    if (_transfers.length <= _historyLimit) return;
    // Chỉ cắt phần đã kết thúc; cái đang chạy phải giữ dù danh sách có dài.
    for (var i = _transfers.length - 1; i >= 0; i--) {
      if (_transfers.length <= _historyLimit) break;
      if (!_transfers[i].isActive) _transfers.removeAt(i);
    }
  }

  /// Vẽ lại nhưng không quá dày; gọi từ vòng lặp đọc/ghi.
  void _touch(TransferTask task) {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < _uiThrottle) return;
    _lastNotify = now;
    notifyListeners();
  }

  void _finish(TransferTask task) {
    // Lần vẽ cuối phải qua được cửa chặn nhịp, nếu không thanh tiến trình
    // đứng lại ở 99%.
    _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }

  /// Khoá theo cả id lẫn cổng: hai bản app mở trên cùng một máy trùng id
  /// nhưng là hai đầu truyền riêng, không được đè lên nhau.
  static String _key(Peer peer) => '${peer.id}@${peer.port}';

  void _onPeer(Peer peer) {
    if (peer.isStale) {
      // Gói "bye": thiết bị kia vừa tắt phần truyền tệp.
      _peers.remove(_key(peer));
    } else {
      _peers[_key(peer)] = peer;
    }
    notifyListeners();
  }

  void _prune() {
    final before = _peers.length;
    _peers.removeWhere((_, peer) => peer.isStale);
    if (_peers.length != before) notifyListeners();
  }

  static Future<String> _findLocalAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // Không xem được card mạng thì thôi, đây chỉ là dòng chữ hiển thị.
    }
    return '';
  }
}
