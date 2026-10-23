import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../core/domain/usecase.dart';
import '../domain/entities/outgoing_file.dart';
import '../domain/entities/p2p_settings.dart';
import '../domain/entities/peer.dart';
import '../domain/entities/save_location.dart';
import '../domain/entities/transfer.dart';
import '../domain/p2p_protocol.dart';
import '../domain/services/peer_table.dart';
import '../domain/services/transfer_history.dart';
import '../domain/usecases/add_manual_peer.dart';
import '../domain/usecases/cancel_transfer.dart';
import '../domain/usecases/get_local_address.dart';
import '../domain/usecases/get_save_location.dart';
import '../domain/usecases/load_p2p_settings.dart';
import '../domain/usecases/open_downloads.dart';
import '../domain/usecases/open_received_file.dart';
import '../domain/usecases/probe_manual_peers.dart';
import '../domain/usecases/refresh_peers.dart';
import '../domain/usecases/remove_manual_peer.dart';
import '../domain/usecases/rename_device.dart';
import '../domain/usecases/respond_to_offer.dart';
import '../domain/usecases/send_files.dart';
import '../domain/usecases/set_auto_accept.dart';
import '../domain/usecases/set_p2p_enabled.dart';
import '../domain/usecases/set_save_dir.dart';
import '../domain/usecases/start_p2p.dart';
import '../domain/usecases/stop_p2p.dart';
import '../domain/usecases/watch_peer_sightings.dart';
import '../domain/usecases/watch_transfers.dart';

/// What the "Gửi tệp" tab shows: this device, the devices heard on the LAN,
/// the devices added by IP, the transfers and the offers waiting for an
/// answer.
///
/// No server in the middle: devices find each other by UDP broadcast and push
/// files straight to each other over HTTP, so files never leave the LAN.
///
/// Only talks to use cases. Listens to [WatchPeerSightings] and
/// [WatchTransfers] once, from [init] on, and keeps what they say with
/// [PeerTable] and [TransferHistory]. While transfer is on, sweeps silent
/// devices every `P2pProtocol.pruneEvery` and asks the devices added by IP
/// again every `P2pProtocol.manualPingEvery`. The [Clock] says what "now" is.
class P2pController extends ChangeNotifier {
  P2pController({
    required this._loadSettings,
    required this._setEnabled,
    required this._setAutoAccept,
    required this._setSaveDir,
    required this._renameDevice,
    required this._getSaveLocation,
    required this._startP2p,
    required this._stopP2p,
    required this._getLocalAddress,
    required this._watchPeerSightings,
    required this._probeManualPeers,
    required this._refreshPeers,
    required this._addManualPeer,
    required this._removeManualPeer,
    required this._watchTransfers,
    required this._sendFiles,
    required this._respondToOffer,
    required this._cancelTransfer,
    required this._openDownloads,
    required this._openReceivedFile,
    required this._clock,
  });

  final LoadP2pSettings _loadSettings;
  final SetP2pEnabled _setEnabled;
  final SetAutoAccept _setAutoAccept;
  final SetSaveDir _setSaveDir;
  final RenameDevice _renameDevice;
  final GetSaveLocation _getSaveLocation;
  final StartP2p _startP2p;
  final StopP2p _stopP2p;
  final GetLocalAddress _getLocalAddress;
  final WatchPeerSightings _watchPeerSightings;
  final ProbeManualPeers _probeManualPeers;
  final RefreshPeers _refreshPeers;
  final AddManualPeer _addManualPeer;
  final RemoveManualPeer _removeManualPeer;
  final WatchTransfers _watchTransfers;
  final SendFiles _sendFiles;
  final RespondToOffer _respondToOffer;
  final CancelTransfer _cancelTransfer;
  final OpenDownloads _openDownloads;
  final OpenReceivedFile _openReceivedFile;
  final Clock _clock;

  /// Shortest gap between two redraws for progress alone; without it every
  /// 64 KB chunk would rebuild the whole tab. A new transfer, a change of
  /// state and the final snapshot always redraw at once.
  static const uiThrottle = Duration(milliseconds: 120);

  P2pSettings? _settings;
  SaveLocation? _saveLocation;
  Map<String, Peer> _peers = const {};

  /// Devices added by IP that answered the last probe, by saved `host:port`.
  final Map<String, Peer> _manualPeers = {};
  List<Transfer> _transfers = const [];

  final List<StreamSubscription<Object?>> _watches = [];
  Timer? _pruneTimer;
  Timer? _manualTimer;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool _started = false;
  bool _disposed = false;
  bool _starting = false;
  bool _running = false;
  int? _port;
  String? _error;
  Failure? _failure;
  String _localAddress = '';

  /// Bumped by every start and stop, so a probe that answers after the
  /// service went off (or on again) is dropped.
  int _session = 0;

  /// Bumped by every save-location lookup, so a slow one does not overwrite a
  /// newer one.
  int _locations = 0;

  bool get isReady => _settings != null;
  bool get isRunning => _running;
  bool get isStarting => _starting;

  /// What the status card says went wrong: a failed start, or a send while
  /// transfer is off. Null when nothing did.
  String? get error => _error;

  /// Why the last settings call failed, or null when it went through.
  Failure? get failure => _failure;

  String get deviceName => _settings?.deviceName ?? '';
  String get deviceId => _settings?.deviceId ?? '';
  bool get autoAccept => _settings?.autoAccept ?? false;
  bool get enabled => _settings?.enabled ?? false;
  String? get saveDir => _settings?.saveDir;

  /// This machine's IPv4 on the LAN, to read out when adding it by IP.
  String get localAddress => _localAddress;

  /// The port files are received on, while transfer is on.
  int? get port => _running ? _port : null;

  /// Where received files end up, as the status card words it. Looked up
  /// once per change rather than on every redraw: during a transfer the card
  /// is rebuilt several times a second.
  String get saveLocationLabel => _saveLocation?.label ?? '';

  /// The current time.
  DateTime now() => _clock.now();

  /// Devices still heard from, sorted by name.
  List<Peer> get peers => PeerTable.visible(_peers.values, now());

  /// Every transfer, newest first, offers included.
  List<Transfer> get transfers => _transfers;

  /// Incoming files waiting for the user to accept or decline them.
  List<Transfer> get pendingOffers => TransferHistory.pendingOffers(_transfers);

  /// What the transfer list shows: everything but the waiting offers.
  List<Transfer> get history => TransferHistory.withoutOffers(_transfers);

  int get activeCount => TransferHistory.activeCount(_transfers);

  /// The devices the user added by IP, as `host:port`, in the saved order.
  List<String> get manualEntries => _settings?.manualPeers ?? const [];

  /// The device at [entry] as it last answered; null when it did not.
  Peer? manualPeer(String entry) => _manualPeers[entry];

  // --------------------------------------------------------------- lifecycle

  /// Starts listening, loads the settings, and turns transfer on when it was
  /// left on. Safe to call twice.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    if (await _watchPeerSightings(const NoParams()) case Ok(:final value)) {
      if (_disposed) return;
      _watches.add(value.listen(_onSighting));
    }
    if (await _watchTransfers(const NoParams()) case Ok(:final value)) {
      if (_disposed) return;
      _watches.add(value.listen(_onTransfer));
    }
    final loaded = await _loadSettings(const NoParams());
    if (_disposed || _failed(loaded)) return;
    _settings = loaded.valueOrNull;
    unawaited(_lookUpSaveLocation());
    _notify();
    if (enabled) await start();
  }

  /// Opens the receiving server and starts discovery.
  Future<void> start() async {
    if (_settings == null || _starting || _running || _disposed) return;
    _starting = true;
    _error = null;
    _notify();
    try {
      final result = await _startP2p(const NoParams());
      if (_disposed) {
        if (result.isOk) unawaited(_stopP2p(const NoParams()));
        return;
      }
      switch (result) {
        case Ok(:final value):
          _session++;
          _running = true;
          _port = value;
          _localAddress =
              (await _getLocalAddress(const NoParams())).valueOrNull ?? '';
          if (_disposed) return;
          // A machine switched off never says goodbye, so silent devices are
          // swept on a timer.
          _pruneTimer = Timer.periodic(P2pProtocol.pruneEvery, (_) => _prune());
          // Devices added by IP are not heard through broadcasts: ask them.
          _manualTimer = Timer.periodic(
            P2pProtocol.manualPingEvery,
            (_) => unawaited(pingManual()),
          );
          unawaited(pingManual());
        case Err(:final failure):
          _error = 'Không bật được: ${failure.message}';
      }
    } finally {
      _starting = false;
      _notify();
    }
  }

  /// Says goodbye, closes the server and cuts every transfer still going.
  Future<void> stop() async {
    _session++;
    _cancelTimers();
    _running = false;
    _port = null;
    _peers = const {};
    _manualPeers.clear();
    _notify();
    _failed(await _stopP2p(const NoParams()));
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    for (final watch in _watches) {
      unawaited(watch.cancel());
    }
    // Leaving with transfer on must still say goodbye and close the port.
    if (_running) unawaited(_stopP2p(const NoParams()));
    super.dispose();
  }

  // ---------------------------------------------------------------- settings

  /// Turns transfer on or off and remembers the choice.
  Future<void> setEnabled(bool value) async {
    if (_settings == null) return;
    final result = await _setEnabled(value);
    if (_disposed || _failed(result)) return;
    _settings = result.valueOrNull;
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> setAutoAccept(bool value) async {
    if (_settings == null) return;
    _applySettings(await _setAutoAccept(value));
  }

  /// Renames this device; a blank name or the current one changes nothing.
  Future<void> rename(String name) async {
    if (_settings == null) return;
    _applySettings(await _renameDevice(name));
  }

  /// Chooses the folder for received files; null goes back to the default.
  Future<void> setSaveDir(String? path) async {
    if (_settings == null) return;
    final result = await _setSaveDir(path);
    if (_applySettings(result)) unawaited(_lookUpSaveLocation());
  }

  /// The folder received files are written to right now; empty when it
  /// cannot be told. On Android this is only a staging folder, see
  /// [saveLocationLabel].
  Future<String> currentSaveDir() async =>
      (await _lookUpSaveLocation())?.directory ?? '';

  /// Opens the system's Downloads screen; false where there is none.
  Future<bool> openDownloads() async {
    final result = await _openDownloads(const NoParams());
    return !_failed(result) && (result.valueOrNull ?? false);
  }

  /// Opens a received file with the default app; false when it cannot be.
  Future<bool> openReceived(Transfer transfer) async {
    final result = await _openReceivedFile(transfer);
    return !_failed(result) && (result.valueOrNull ?? false);
  }

  // ----------------------------------------------------------------- devices

  /// Announces this device at once, asks the devices added by IP again, then
  /// greets every address of the /24 range for networks that drop
  /// broadcasts.
  Future<void> refresh() async {
    _prune();
    final session = _session;
    _applyProbes(await _refreshPeers(const NoParams()), session);
  }

  /// Asks every device added by IP whether it is still there.
  Future<void> pingManual() async {
    final session = _session;
    _applyProbes(await _probeManualPeers(const NoParams()), session);
  }

  /// Adds a device by what the user typed. Returns what to tell the user when
  /// it did not work, or null when the device is in the list.
  Future<String?> addManualPeer(String input) async {
    if (_settings == null) return 'Chưa sẵn sàng';
    final result = await _addManualPeer(input);
    if (_disposed) return null;
    switch (result) {
      case Ok(value: ManualPeerInvalid()):
        return 'Địa chỉ không hợp lệ. Ví dụ: 172.28.0.50';
      case Ok(value: ManualPeerUnreachable(:final entry)):
        return 'Không nối được tới $entry. Máy kia đã mở app và bật truyền tệp '
            'chưa? Tường lửa của máy đó có cho phép không?';
      case Ok(value: ManualPeerAdded(:final entry, :final peer)):
        _manualPeers[entry] = peer;
        _applySettings(await _loadSettings(const NoParams()));
        _notify();
        return null;
      case Err(:final failure):
        _failed(Err(failure));
        return failure.message;
    }
  }

  /// Forgets the device added by IP as [entry].
  Future<void> removeManualPeer(String entry) async {
    if (_settings == null) return;
    final result = await _removeManualPeer(entry);
    if (_applySettings(result)) {
      _manualPeers.remove(entry);
      _notify();
    }
  }

  // --------------------------------------------------------------- transfers

  /// Sends [files] to [peer] one after the other. The transfers show up
  /// through [WatchTransfers] as they go.
  Future<void> sendFiles(Peer peer, List<OutgoingFile> files) async {
    final result = await _sendFiles((peer: peer, files: files));
    if (_disposed || result.isOk) return;
    _error = 'Chưa bật truyền tệp';
    _notify();
  }

  /// Stops a running transfer, or declines a waiting offer.
  Future<void> cancel(Transfer transfer) async {
    _failed(await _cancelTransfer(transfer.id));
  }

  /// Answers a waiting offer.
  Future<void> respond(Transfer transfer, {required bool accept}) async {
    _failed(await _respondToOffer((id: transfer.id, accept: accept)));
  }

  /// Drops the finished transfers from the list.
  void clearHistory() {
    _transfers = TransferHistory.clearFinished(_transfers);
    _notify();
  }

  // ---------------------------------------------------------------- internal

  void _onSighting(PeerSighting sighting) {
    // Discovery only speaks while started; a packet caught on the way out
    // must not bring a device back.
    if (_disposed || !_running) return;
    _peers = PeerTable.record(_peers, sighting);
    _notify();
  }

  void _onTransfer(Transfer transfer) {
    if (_disposed) return;
    final previous = _transfers.where((t) => t.id == transfer.id).firstOrNull;
    _transfers = TransferHistory.record(_transfers, transfer);
    final progressOnly =
        previous != null &&
        previous.state == transfer.state &&
        transfer.isActive;
    if (!progressOnly) {
      // The last redraw must get through, or the bar stops at 99%.
      _notify();
      return;
    }
    final at = now();
    if (at.difference(_lastNotify) < uiThrottle) return;
    _lastNotify = at;
    _notify();
  }

  void _prune() {
    final before = _peers.length;
    _peers = PeerTable.prune(_peers, now());
    if (_peers.length != before) _notify();
  }

  void _applyProbes(Result<Map<String, Peer?>> result, int session) {
    if (_disposed || session != _session || !_running) return;
    if (_failed(result)) return;
    final answers = result.valueOrNull ?? const {};
    final entries = manualEntries;
    answers.forEach((entry, peer) {
      if (peer == null || !entries.contains(entry)) {
        _manualPeers.remove(entry);
      } else {
        _manualPeers[entry] = peer;
      }
    });
    _notify();
  }

  Future<SaveLocation?> _lookUpSaveLocation() async {
    final lookup = ++_locations;
    final result = await _getSaveLocation(const NoParams());
    if (_disposed || _failed(result)) return null;
    final location = result.valueOrNull;
    if (lookup == _locations && location != _saveLocation) {
      _saveLocation = location;
      _notify();
    }
    return location;
  }

  /// Keeps the settings [result] yields and redraws; false when it failed.
  bool _applySettings(Result<P2pSettings> result) {
    if (_disposed || _failed(result)) return false;
    _settings = result.valueOrNull ?? _settings;
    _notify();
    return true;
  }

  void _cancelTimers() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _manualTimer?.cancel();
    _manualTimer = null;
  }

  /// Records the failure of [result], if any, and tells the listeners.
  bool _failed(Result<Object?> result) {
    if (result case Err(:final failure)) {
      _failure = failure;
      _notify();
      return true;
    }
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
