/// The alarm tone the app plays itself while an alert is on screen (desktop).
/// Implemented in the data layer.
abstract interface class AlarmRinger {
  /// Starts looping the tone. Does nothing while it is already playing.
  Future<void> start();

  /// Stops the tone. Does nothing while it is silent.
  Future<void> stop();

  /// Stops the tone and frees what playing it held.
  Future<void> dispose();
}
