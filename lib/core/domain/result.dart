import 'failure.dart';

/// Outcome of a repository call or a use case: a value, or a [Failure].
///
/// Sealed with exactly two variants, so callers handle both with a `switch`:
///
/// ```dart
/// switch (await getNotes(const NoParams())) {
///   case Ok(:final value): show(value);
///   case Err(:final failure): report(failure);
/// }
/// ```
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  /// The value when this is [Ok], otherwise null.
  T? get valueOrNull => switch (this) {
        Ok(:final value) => value,
        Err() => null,
      };

  /// The failure when this is [Err], otherwise null.
  Failure? get failureOrNull => switch (this) {
        Ok() => null,
        Err(:final failure) => failure,
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
