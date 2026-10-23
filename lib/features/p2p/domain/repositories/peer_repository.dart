import '../../../../core/domain/result.dart';
import '../entities/p2p_settings.dart';
import '../entities/peer.dart';

/// Finding other devices on the LAN: UDP discovery on
/// `P2pProtocol.discoveryPort`, and direct `GET /info` probes for devices
/// added by IP. Implemented in the data layer; the packets must stay readable
/// by older builds of the app.
///
/// No method throws: socket errors come back as an `Err`, or are swallowed
/// where noted.
abstract interface class PeerRepository {
  /// Starts discovery as the device in [settings] (id and name), reachable on
  /// [servicePort]: listens for other devices, announces this one every
  /// `P2pProtocol.announceEvery` and once right away, and answers each
  /// announcement it hears with a direct reply so both sides see each other
  /// at once. Does nothing when already started.
  Future<Result<void>> start(P2pSettings settings, {required int servicePort});

  /// Says goodbye, so the others drop this device at once, and stops. Does
  /// nothing when not started.
  Future<Result<void>> stop();

  /// Takes new [settings] into account while started: the name announced
  /// from now on. Does not announce by itself. Does nothing when not started.
  Future<Result<void>> updateSettings(P2pSettings settings);

  /// Announces this device right away. Does nothing when not started.
  Future<Result<void>> announce();

  /// Greets every address of this machine's /24 range one by one, for
  /// networks that drop broadcasts but let direct packets through. Only on
  /// demand, never on a timer. Does nothing when not started.
  Future<Result<void>> sweep();

  /// What discovery hears: devices announcing or answering, and devices
  /// saying goodbye. A device's own packets are not reported; another copy of
  /// the app on the same machine (same id, other port) is.
  ///
  /// One broadcast stream for the life of the repository, open across
  /// [start] and [stop]; it only carries events while started.
  Stream<PeerSighting> get sightings;

  /// Asks the device at [entry] (`host:port`, see `normalizeEntry`) who it is,
  /// with `GET /info`. Yields it as seen now, or null when nothing answered
  /// within `P2pProtocol.probeTimeout`, the answer was not this app's, or the
  /// entry is malformed. Works whether or not discovery is started; an
  /// unreachable device is not an `Err`.
  Future<Result<Peer?>> probe(String entry);

  /// This machine's IPv4 address on the LAN, to read out to the other side;
  /// empty when there is none or it cannot be found.
  Future<Result<String>> localAddress();
}
