/// Source of the current time.
///
/// Domain and data code ask this instead of calling `DateTime.now()`, so tests
/// can pin the clock to a fixed instant.
abstract interface class Clock {
  DateTime now();
}
