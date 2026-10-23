/// Why an operation did not succeed, as seen by the domain.
///
/// Data code catches IO, network and format errors and turns them into one of
/// these, so nothing below presentation has to throw. Sealed so a `switch`
/// over it has to name every kind.
sealed class Failure {
  const Failure(this.message, {this.cause});

  /// Short description, meant for logs rather than for the user.
  final String message;

  /// The error that was caught, when there was one.
  final Object? cause;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is Failure &&
      other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => '$runtimeType($message)';
}

/// Reading or writing local storage (JSON files, SQLite) went wrong.
final class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause});
}

/// A request to the server failed or could not be sent.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause});
}

/// The input broke a rule of the domain.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause});
}

/// Anything not covered by the kinds above.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause});
}
