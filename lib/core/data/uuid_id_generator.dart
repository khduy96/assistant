import 'package:uuid/uuid.dart';

import '../domain/id_generator.dart';

/// The [IdGenerator] for notes, todos, reminders and the P2P device id:
/// random uuid v4, the format those ids already have on disk.
class UuidIdGenerator implements IdGenerator {
  const UuidIdGenerator();

  static const _uuid = Uuid();

  @override
  String newId() => _uuid.v4();
}
