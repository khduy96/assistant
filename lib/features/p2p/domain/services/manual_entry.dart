import '../p2p_protocol.dart';

/// Turns what the user typed in "add device by IP" into a `host:port` entry,
/// or null when it cannot be an address.
///
/// `172.28.0.50` → `172.28.0.50:45700`; `172.28.0.50:45701` stays as it is.
/// Blanks around the text are ignored; a port outside 1..65535, a port that
/// is not a number, or a host with spaces in it is rejected.
String? normalizeEntry(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  var port = P2pProtocol.basePort;
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

/// Splits an entry made by [normalizeEntry] into host and port, or yields
/// null when [entry] has no `:port` at the end.
({String host, int port})? splitEntry(String entry) {
  final colon = entry.lastIndexOf(':');
  if (colon <= 0) return null;
  final port = int.tryParse(entry.substring(colon + 1));
  if (port == null) return null;
  return (host: entry.substring(0, colon), port: port);
}
