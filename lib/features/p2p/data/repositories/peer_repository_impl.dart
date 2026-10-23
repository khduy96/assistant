import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/domain/clock.dart';
import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/p2p_settings.dart';
import '../../domain/entities/peer.dart';
import '../../domain/p2p_protocol.dart';
import '../../domain/repositories/peer_repository.dart';
import '../../domain/services/manual_entry.dart';
import '../datasources/discovery_service.dart';
import '../datasources/local_device.dart';

/// [PeerRepository] over UDP discovery ([DiscoveryService]) and
/// `GET /info` probes.
class PeerRepositoryImpl implements PeerRepository {
  /// [discoveryPort] replaces `P2pProtocol.discoveryPort`; tests use another
  /// one so they do not fight a running copy of the app for it.
  PeerRepositoryImpl(
    this._clock, {
    this.device = const LocalDevice(),
    this.discoveryPort = P2pProtocol.discoveryPort,
  });

  final Clock _clock;
  final LocalDevice device;
  final int discoveryPort;

  final _sightings = StreamController<PeerSighting>.broadcast();
  DiscoveryService? _discovery;

  @override
  Stream<PeerSighting> get sightings => _sightings.stream;

  @override
  Future<Result<void>> start(
    P2pSettings settings, {
    required int servicePort,
  }) async {
    if (_discovery != null) return const Ok(null);
    final discovery = DiscoveryService(
      deviceId: settings.deviceId,
      deviceName: settings.deviceName,
      platform: device.platformTag,
      servicePort: servicePort,
      onSighting: _report,
      clock: _clock,
      discoveryPort: discoveryPort,
    );
    try {
      await discovery.start();
    } catch (e) {
      try {
        await discovery.stop();
      } catch (_) {
        // Nothing was opened.
      }
      // The message is what the user is shown after "Không bật được: ".
      return Err(NetworkFailure('$e', cause: e));
    }
    _discovery = discovery;
    return const Ok(null);
  }

  @override
  Future<Result<void>> stop() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery == null) return const Ok(null);
    return _guard('stop', discovery.stop);
  }

  @override
  Future<Result<void>> updateSettings(P2pSettings settings) async {
    _discovery?.deviceName = settings.deviceName;
    return const Ok(null);
  }

  @override
  Future<Result<void>> announce() async {
    final discovery = _discovery;
    if (discovery == null) return const Ok(null);
    return _guard('announce', discovery.announce);
  }

  @override
  Future<Result<void>> sweep() async {
    final discovery = _discovery;
    if (discovery == null) return const Ok(null);
    return _guard('sweep', discovery.sweep);
  }

  @override
  Future<Result<Peer?>> probe(String entry) async {
    final address = splitEntry(entry);
    if (address == null) return const Ok(null);
    final (:host, :port) = address;
    final client = HttpClient()
      ..connectionTimeout = P2pProtocol.probeConnectTimeout;
    try {
      final request = await client.getUrl(Uri.parse('http://$host:$port/info'));
      final response = await request.close().timeout(P2pProtocol.probeTimeout);
      if (response.statusCode != 200) return const Ok(null);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      return Ok(
        Peer(
          id: body['id'] as String? ?? entry,
          name: body['name'] as String? ?? host,
          platform: body['platform'] as String? ?? 'other',
          address: host,
          port: port,
          seenAt: _clock.now(),
        ),
      );
    } catch (_) {
      // Not reachable, wrong port, or not this app on the other end.
      return const Ok(null);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Result<String>> localAddress() async =>
      Ok(await device.localAddress());

  /// Stops discovery and closes [sightings]. For tests and shutdown; the
  /// repository cannot be used afterwards.
  Future<void> dispose() async {
    await stop();
    await _sightings.close();
  }

  void _report(PeerSighting sighting) {
    if (!_sightings.isClosed) _sightings.add(sighting);
  }

  static Future<Result<void>> _guard(
    String what,
    Future<void> Function() body,
  ) async {
    try {
      await body();
      return const Ok(null);
    } catch (e) {
      return Err(NetworkFailure('Discovery $what failed', cause: e));
    }
  }
}
