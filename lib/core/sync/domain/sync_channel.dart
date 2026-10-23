import 'sync_collection.dart';

/// One or more collections the engine pulls together, under one cursor.
///
/// Most classes travel alone ([SyncChannel.single]). The clipboard's two
/// classes share the cursor they have always shared ([SyncChannel.shared]):
/// when either one changed both are pulled, and the collections are queried,
/// reconciled and applied in the order given, so a group lands before the
/// clips that point at it.
class SyncChannel {
  /// A collection with a cursor of its own.
  SyncChannel.single(SyncCollection collection)
    : collections = List.unmodifiable([collection]),
      shared = false;

  /// Collections pulled as one, under the space-wide cursor. An engine holds
  /// at most one such channel.
  SyncChannel.shared(List<SyncCollection> collections)
    : assert(collections.isNotEmpty),
      collections = List.unmodifiable(collections),
      shared = true;

  /// In push, reconcile and apply order.
  final List<SyncCollection> collections;

  /// Whether this channel uses the space-wide cursor instead of one per class.
  final bool shared;
}
