import 'package:get_it/get_it.dart';

import 'data/datasources/p2p_settings_local_data_source.dart';
import 'data/repositories/p2p_settings_repository_impl.dart';
import 'data/repositories/peer_repository_impl.dart';
import 'data/repositories/transfer_repository_impl.dart';
import 'domain/repositories/p2p_settings_repository.dart';
import 'domain/repositories/peer_repository.dart';
import 'domain/repositories/transfer_repository.dart';
import 'domain/usecases/add_manual_peer.dart';
import 'domain/usecases/cancel_transfer.dart';
import 'domain/usecases/get_local_address.dart';
import 'domain/usecases/get_save_location.dart';
import 'domain/usecases/load_p2p_settings.dart';
import 'domain/usecases/open_downloads.dart';
import 'domain/usecases/open_received_file.dart';
import 'domain/usecases/probe_manual_peers.dart';
import 'domain/usecases/refresh_peers.dart';
import 'domain/usecases/remove_manual_peer.dart';
import 'domain/usecases/rename_device.dart';
import 'domain/usecases/respond_to_offer.dart';
import 'domain/usecases/send_files.dart';
import 'domain/usecases/set_auto_accept.dart';
import 'domain/usecases/set_p2p_enabled.dart';
import 'domain/usecases/set_save_dir.dart';
import 'domain/usecases/start_p2p.dart';
import 'domain/usecases/stop_p2p.dart';
import 'domain/usecases/watch_peer_sightings.dart';
import 'domain/usecases/watch_transfers.dart';
import 'presentation/p2p_controller.dart';

/// Registers the file-transfer feature in [sl]. Expects a `Clock` and an
/// `IdGenerator` to be registered already.
///
/// The two network repositories ([PeerRepositoryImpl], [TransferRepositoryImpl])
/// are singletons seen under two types: the use cases get them through their
/// domain interfaces, while the app shell disposes them. [P2pController] is a
/// singleton too, owned and disposed by the app shell; it holds the timers
/// and the only listeners of the sightings and transfer streams.
void registerP2p(GetIt sl) {
  sl
    ..registerLazySingleton(() => P2pSettingsLocalDataSource())
    ..registerLazySingleton<P2pSettingsRepository>(
      () => P2pSettingsRepositoryImpl(sl(), sl()),
    )
    ..registerLazySingleton(() => PeerRepositoryImpl(sl()))
    ..registerLazySingleton<PeerRepository>(() => sl<PeerRepositoryImpl>())
    ..registerLazySingleton(() => TransferRepositoryImpl(sl()))
    ..registerLazySingleton<TransferRepository>(
      () => sl<TransferRepositoryImpl>(),
    )
    ..registerLazySingleton(() => LoadP2pSettings(sl()))
    ..registerLazySingleton(() => SetP2pEnabled(sl()))
    ..registerLazySingleton(() => SetAutoAccept(sl(), sl()))
    ..registerLazySingleton(() => SetSaveDir(sl(), sl()))
    ..registerLazySingleton(() => RenameDevice(sl(), sl(), sl()))
    ..registerLazySingleton(() => GetSaveLocation(sl(), sl()))
    ..registerLazySingleton(() => StartP2p(sl(), sl(), sl()))
    ..registerLazySingleton(() => StopP2p(sl(), sl()))
    ..registerLazySingleton(() => GetLocalAddress(sl()))
    ..registerLazySingleton(() => WatchPeerSightings(sl()))
    ..registerLazySingleton(() => ProbeManualPeers(sl(), sl()))
    ..registerLazySingleton(() => RefreshPeers(sl(), sl()))
    ..registerLazySingleton(() => AddManualPeer(sl(), sl()))
    ..registerLazySingleton(() => RemoveManualPeer(sl()))
    ..registerLazySingleton(() => WatchTransfers(sl()))
    ..registerLazySingleton(() => SendFiles(sl()))
    ..registerLazySingleton(() => RespondToOffer(sl()))
    ..registerLazySingleton(() => CancelTransfer(sl()))
    ..registerLazySingleton(() => OpenDownloads(sl()))
    ..registerLazySingleton(() => OpenReceivedFile(sl()))
    ..registerLazySingleton(
      () => P2pController(
        loadSettings: sl(),
        setEnabled: sl(),
        setAutoAccept: sl(),
        setSaveDir: sl(),
        renameDevice: sl(),
        getSaveLocation: sl(),
        startP2p: sl(),
        stopP2p: sl(),
        getLocalAddress: sl(),
        watchPeerSightings: sl(),
        probeManualPeers: sl(),
        refreshPeers: sl(),
        addManualPeer: sl(),
        removeManualPeer: sl(),
        watchTransfers: sl(),
        sendFiles: sl(),
        respondToOffer: sl(),
        cancelTransfer: sl(),
        openDownloads: sl(),
        openReceivedFile: sl(),
        clock: sl(),
      ),
    );
}
