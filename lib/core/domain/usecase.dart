import 'result.dart';

/// One action of a feature, exposed as a class with a single [call].
///
/// [T] is what the action yields, [P] what it takes; actions that take
/// nothing use [NoParams].
abstract class UseCase<T, P> {
  Future<Result<T>> call(P params);
}

/// Parameter of a [UseCase] that needs no input.
class NoParams {
  const NoParams();
}
