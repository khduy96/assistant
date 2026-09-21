/// Back4App connection settings, taken from `--dart-define` at build time.
///
/// Fill `.env` (see `.env.example`) and run with:
///   flutter run --dart-define-from-file=.env
///
/// Only the App ID and the **Client Key** belong in a shipped build. The REST
/// API key must stay server-side and is never read here.
class ParseConfig {
  const ParseConfig({
    required this.appId,
    required this.clientKey,
    required this.serverUrl,
    required this.space,
    this.autoSync = true,
  });

  final String appId;
  final String clientKey;
  final String serverUrl;

  /// Namespace shared by the devices that should see each other's clips.
  ///
  /// Stands in for an account until sign-in exists: build the desktop and the
  /// phone with the same `PARSE_SPACE` and they sync together, while other
  /// people on the same Back4App app keep their own space.
  final String space;

  final bool autoSync;

  static const String defaultServerUrl = 'https://parseapi.back4app.com';
  static const String defaultSpace = 'default';

  /// `.env.example` ships placeholders; an uncopied one counts as empty so the
  /// app stays offline instead of failing against a fake App ID.
  static String cleanValue(String value) {
    final text = value.trim();
    return text.startsWith('YOUR_') ? '' : text;
  }

  /// The configuration this build was compiled with.
  factory ParseConfig.fromEnvironment() {
    const appId = String.fromEnvironment('PARSE_APP_ID');
    const clientKey = String.fromEnvironment('PARSE_CLIENT_KEY');
    const serverUrl = String.fromEnvironment('PARSE_SERVER_URL');
    const space = String.fromEnvironment('PARSE_SPACE');
    const autoSync = String.fromEnvironment('PARSE_AUTO_SYNC');

    final url = cleanValue(serverUrl);
    final namespace = cleanValue(space);
    return ParseConfig(
      appId: cleanValue(appId),
      clientKey: cleanValue(clientKey),
      serverUrl: url.isEmpty ? defaultServerUrl : url,
      space: namespace.isEmpty ? defaultSpace : namespace,
      autoSync: cleanValue(autoSync) != '0',
    );
  }

  /// True once there is enough to talk to Back4App.
  bool get isConfigured => appId.isNotEmpty && clientKey.isNotEmpty;

  String get _base => serverUrl.replaceAll(RegExp(r'/+$'), '');

  Uri classUri(String className, [Map<String, String>? query]) =>
      Uri.parse('$_base/classes/$className').replace(queryParameters: query);

  Uri objectUri(String className, String objectId) =>
      Uri.parse('$_base/classes/$className/$objectId');


  Map<String, String> get headers => {
        'X-Parse-Application-Id': appId,
        'X-Parse-Client-Key': clientKey,
      };
}
