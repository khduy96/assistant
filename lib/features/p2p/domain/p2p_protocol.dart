/// Numbers both ends of a LAN transfer rely on.
///
/// Devices running an older build of the app must still find this one and
/// swap files with it, so none of these may change: the ports and the magic
/// tag are on the wire, and the timings are what users have come to expect.
abstract final class P2pProtocol {
  /// UDP port every device listens and announces on.
  static const discoveryPort = 45699;

  /// Tag carried by every discovery packet, so anything else on the port is
  /// ignored.
  static const magic = 'event_notice_p2p/1';

  /// Gap between two broadcast announcements.
  static const announceEvery = Duration(seconds: 3);

  /// HTTP port that receives files; when it is taken, the next ports are
  /// tried, [portAttempts] in all.
  static const basePort = 45700;
  static const portAttempts = 5;

  /// A device not heard from for longer than this has left the list: a
  /// machine switched off never gets to say goodbye.
  static const staleAfter = Duration(seconds: 15);

  /// How often the list of devices is swept for ones gone quiet.
  static const pruneEvery = Duration(seconds: 5);

  /// An incoming file nobody accepts or declines within this time is
  /// declined.
  static const offerTimeout = Duration(seconds: 90);

  /// Finished transfers kept in the list shown to the user. Running ones are
  /// kept on top of these, however many there are.
  static const historyLimit = 40;

  /// Devices added by IP do not reach us through broadcasts, so they are
  /// asked again this often.
  static const manualPingEvery = Duration(seconds: 15);

  /// Longest wait to connect to a device added by IP, and for its answer.
  static const probeConnectTimeout = Duration(seconds: 3);
  static const probeTimeout = Duration(seconds: 4);

  /// Longest wait to connect when sending. Once connected there is no limit:
  /// a large file may take minutes.
  static const sendConnectTimeout = Duration(seconds: 10);
}
