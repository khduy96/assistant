import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/features/p2p/domain/entities/outgoing_file.dart';
import 'package:event_notice/features/p2p/domain/usecases/add_manual_peer.dart';
import 'package:event_notice/features/p2p/domain/usecases/cancel_transfer.dart';
import 'package:event_notice/features/p2p/domain/usecases/get_local_address.dart';
import 'package:event_notice/features/p2p/domain/usecases/get_save_location.dart';
import 'package:event_notice/features/p2p/domain/usecases/load_p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/usecases/open_downloads.dart';
import 'package:event_notice/features/p2p/domain/usecases/open_received_file.dart';
import 'package:event_notice/features/p2p/domain/usecases/probe_manual_peers.dart';
import 'package:event_notice/features/p2p/domain/usecases/refresh_peers.dart';
import 'package:event_notice/features/p2p/domain/usecases/remove_manual_peer.dart';
import 'package:event_notice/features/p2p/domain/usecases/rename_device.dart';
import 'package:event_notice/features/p2p/domain/usecases/respond_to_offer.dart';
import 'package:event_notice/features/p2p/domain/usecases/send_files.dart';
import 'package:event_notice/features/p2p/domain/usecases/set_auto_accept.dart';
import 'package:event_notice/features/p2p/domain/usecases/set_p2p_enabled.dart';
import 'package:event_notice/features/p2p/domain/usecases/set_save_dir.dart';
import 'package:event_notice/features/p2p/domain/usecases/start_p2p.dart';
import 'package:event_notice/features/p2p/domain/usecases/stop_p2p.dart';
import 'package:event_notice/features/p2p/domain/usecases/watch_peer_sightings.dart';
import 'package:event_notice/features/p2p/domain/usecases/watch_transfers.dart';
import 'package:event_notice/features/p2p/presentation/p2p_controller.dart';
import 'package:event_notice/features/p2p/presentation/p2p_files.dart';

import '../domain/fakes.dart';

class FakeClock implements Clock {
  FakeClock(this.current);

  DateTime current;

  void advance(Duration by) => current = current.add(by);

  @override
  DateTime now() => current;
}

/// The repositories behind a controller made by [controllerFor].
class P2pFakes {
  P2pFakes()
    : settings = InMemoryP2pSettingsRepository(),
      peers = FakePeerRepository(),
      transfers = FakeTransferRepository(),
      clock = FakeClock(seen);

  final InMemoryP2pSettingsRepository settings;
  final FakePeerRepository peers;
  final FakeTransferRepository transfers;
  final FakeClock clock;
}

/// A controller wired to [fakes] through the real use cases.
P2pController controllerFor(P2pFakes fakes) {
  final settings = fakes.settings;
  final peers = fakes.peers;
  final transfers = fakes.transfers;
  final probe = ProbeManualPeers(settings, peers);
  return P2pController(
    loadSettings: LoadP2pSettings(settings),
    setEnabled: SetP2pEnabled(settings),
    setAutoAccept: SetAutoAccept(settings, transfers),
    setSaveDir: SetSaveDir(settings, transfers),
    renameDevice: RenameDevice(settings, transfers, peers),
    getSaveLocation: GetSaveLocation(settings, transfers),
    startP2p: StartP2p(settings, transfers, peers),
    stopP2p: StopP2p(transfers, peers),
    getLocalAddress: GetLocalAddress(peers),
    watchPeerSightings: WatchPeerSightings(peers),
    probeManualPeers: probe,
    refreshPeers: RefreshPeers(peers, probe),
    addManualPeer: AddManualPeer(settings, peers),
    removeManualPeer: RemoveManualPeer(settings),
    watchTransfers: WatchTransfers(transfers),
    sendFiles: SendFiles(transfers),
    respondToOffer: RespondToOffer(transfers),
    cancelTransfer: CancelTransfer(transfers),
    openDownloads: OpenDownloads(transfers),
    openReceivedFile: OpenReceivedFile(transfers),
    clock: fakes.clock,
  );
}

/// Records every call in [calls]. [picked] is what the file picker yields,
/// [folder] what the folder picker yields, [dropped] the files at the dropped
/// paths; [openError] makes opening the file manager throw it.
class FakeP2pFiles implements P2pFiles {
  final calls = <String>[];
  List<OutgoingFile> picked = const [];
  String? folder;
  DroppedFiles dropped = (files: const [], skipped: 0);
  Object? openError;

  @override
  Future<List<OutgoingFile>> pickFiles({required String dialogTitle}) async {
    calls.add('pickFiles $dialogTitle');
    return picked;
  }

  @override
  Future<String?> pickDirectory({required String dialogTitle}) async {
    calls.add('pickDirectory $dialogTitle');
    return folder;
  }

  @override
  Future<DroppedFiles> filesAt(List<String> paths) async {
    calls.add('filesAt ${paths.join(',')}');
    return dropped;
  }

  @override
  Future<void> openInFileManager(String path, {bool select = false}) async {
    calls.add('open $path select: $select');
    if (openError case final error?) throw error;
  }
}
