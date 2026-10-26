/// What the user chose about sync on this device, kept between launches.
abstract interface class SyncPreferences {
  /// Whether sync runs on its own, or null when the user never chose, in
  /// which case the build setting applies.
  Future<bool?> autoSync();

  /// Stores whether sync runs on its own.
  Future<void> setAutoSync(bool enabled);
}
