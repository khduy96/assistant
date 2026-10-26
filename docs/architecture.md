# Kiến trúc: chuyển sang Clean Architecture

> Trạng thái: **đã xong giai đoạn 0–8** (ghi lại ngày 22/10/2026). `lib/` đã theo
> cấu trúc đích ở [mục 2](#2-cấu-trúc-đích): `app/`, `core/` và
> `features/<feature>/{domain,data,presentation}`; các thư mục cũ `models/`,
> `services/`, `ui/`, `clipboard/`, `p2p/` và `running_text/` không còn.
> `tool/check_layers.dart` chạy bắt buộc theo mặc định và báo 0 vi phạm. Mục 1
> và mục 7 mô tả cấu trúc trước khi migrate, giữ lại để tra cứu. Các quyết
> đã chốt khi lập kế hoạch chi tiết nằm ở [mục 8](#8-các-quyết-định-đã-chốt).
> Mức độ: **strict**. Mỗi hành động là một `UseCase`, có mapper riêng giữa model
> và entity, DI bằng `get_it`.

Tài liệu này mô tả cấu trúc đích, quy tắc phụ thuộc và lộ trình migrate từng bước.
Ở mọi bước, app vẫn phải build được và `flutter test` vẫn phải xanh.

---

## 1. Hiện trạng

Trước khi migrate (commit `9799873`), `lib/` có khoảng 13k dòng, chia thành hai
kiểu tổ chức song song:

| Phần | Kiểu tổ chức | Vị trí |
|---|---|---|
| Nhắc nhở, todo, ghi chú, pomodoro | theo layer | `lib/models`, `lib/services`, `lib/ui` |
| Clipboard | theo feature | `lib/clipboard/{data,models,services,state,sync,ui}` |
| P2P | theo feature | `lib/p2p/{models,services,state,ui}` |
| Chữ chạy | theo feature, chỉ có UI | `lib/running_text/ui` |

### Các vấn đề cần sửa

1. **Phụ thuộc ngược vào UI.** `services/reminder_store.dart` và
   `services/android_alarm_service.dart` import `ui/format.dart` để lấy
   `formatDateTime`, `formatLongCountdown`, `describeSchedule`.
2. **Feature phụ thuộc chéo nhau.** `services/note_store.dart` và
   `services/todo_store.dart` import `clipboard/sync/class_names.dart`.
   `clipboard/state/clipboard_store.dart` lại import `services/sync/sync_collection.dart`.
3. **Sync engine dùng chung nhưng nằm trong clipboard.** `SyncService`,
   `ParseClient` và `ParseConfig` đều ở `clipboard/sync/`. `SyncService` biết trực
   tiếp `ClipRepository` (`_pullClipboard`, `_applyClip`, `_applyGroup`), trong khi
   todo và note thì đi qua interface `SyncCollection`. `ClipboardStore` nhận
   `extraCollections`, nên nó đang làm luôn việc điều phối sync cho cả app.
4. **Entity lẫn với DTO.** `Note`, `Todo`, `Reminder` và `ClipItem` tự lo `toJson`,
   `fromJson`, `toParse` và `fromParse`, tức domain biết cả định dạng file lẫn
   định dạng Back4App. Ngoài ra `Note` và `Todo` còn mang trạng thái sync
   (`remoteId`, `dirty`).
5. **Domain phụ thuộc Flutter.** `models/reminder.dart` dùng `TimeOfDay`
   (`package:flutter/material.dart`). `clipboard/models/clip_item.dart` có
   `IconData` trong extension `ClipTypeX`. `clipboard/models/clip_group.dart`
   cũng import `package:flutter/material.dart` để có getter
   `Color get materialColor` (dòng 1 và 24); getter này phải thành extension
   trong presentation, entity chỉ giữ màu dạng `int`.
6. **Store ôm ba việc một lúc.** Các `ChangeNotifier` (`NoteStore`, `TodoStore`,
   `ReminderStore`, `ClipboardStore`, `P2pStore`) vừa giữ state cho UI, vừa chứa
   nghiệp vụ (sort, giải quyết xung đột trong `applyRemote`, tính lần báo kế
   tiếp), vừa gọi trực tiếp storage.
7. **Không có ranh giới DI.** `main.dart` tự `new` mọi store và tự nối
   `extraCollections`. UI thì import thẳng service (`home_page.dart` import
   `startup_service`, `android_alarm_service`, ...).
8. **Thời gian và id sinh rải rác.** Ngoài `ui/` có 58 chỗ gọi `DateTime.now()`.
   `Uuid` được tạo trong từng store. Vì vậy logic phụ thuộc thời gian khó test.

### Những điểm nên giữ

- `SyncCollection` đã là một abstraction đúng hướng, chỉ cần chuyển chỗ và nâng lên
  thành interface của domain.
- Storage inject được qua constructor (`NoteStore({NoteStorage? storage})`), và
  test hiện có đã dựa vào điều này.
- Test cho sync (`test/clipboard/*`, có `fake_parse_server.dart`), note, todo,
  reminder và p2p là lưới an toàn cho cả quá trình refactor.

---

## 2. Cấu trúc đích

Tổ chức theo feature, mỗi feature chia ba layer:

```
lib/
  main.dart                      # chỉ gọi bootstrap() rồi runApp()
  app/
    bootstrap.dart               # khởi tạo platform, window, DB, gọi configureDependencies()
    di/injection.dart            # đăng ký get_it cho core + mọi feature
    di/bridges/                  # adapter nối port của feature này với feature kia
    app.dart                     # EventNoticeApp: MultiProvider, theme, router
    shell/                       # HomePage, tray, window listener, alarm overlay
  core/
    domain/
      clock.dart                 # abstract class Clock { DateTime now(); }
      id_generator.dart          # abstract class IdGenerator { String newId(); }
      failure.dart               # sealed class Failure
      result.dart                # sealed class Result<T> { Ok, Err }
      usecase.dart               # abstract class UseCase<T, P>, NoParams
      time_of_day.dart           # value object thay TimeOfDay của Flutter
    data/
      system_clock.dart
      uuid_id_generator.dart
      app_paths.dart             # bọc path_provider
      json_file_store.dart       # đọc/ghi file JSON có tombstone (gộp *_storage.dart)
      app_database.dart          # SQLite, chuyển từ clipboard/data
    sync/
      domain/
        entities/                # SyncRecord, SyncTombstone, SyncStatus, SyncState
        sync_collection.dart     # interface, chuyển từ services/sync
        sync_engine.dart         # interface: sync({full}), hasLocalChanges(), ...
        usecases/                # RunSync, HasPendingChanges, GetMonthRequests
      data/
        parse_client.dart
        parse_config.dart
        class_names.dart
        parse_sync_engine.dart   # SyncService hiện tại, chỉ còn biết SyncCollection
      presentation/
        sync_controller.dart     # ChangeNotifier: status, timer, focus-pull
    platform/                    # startup (registry), memory_trim, alarm_sound,
                                 # background_service, android_alarm (channel)
    presentation/
      format.dart                # format* dùng chung cho UI
      widgets/                   # app_logo, ...
  features/
    notes/
      domain/
        entities/note.dart       # thuần Dart, bất biến, có copyWith
        repositories/note_repository.dart      # abstract
        usecases/                # GetNotes, SearchNotes, SaveNote, DeleteNote, SetNotePinned
      data/
        models/note_model.dart   # NoteModel: fromJson/toJson/fromParse/toParse + remoteId, dirty
        mappers/note_mapper.dart # NoteModel <-> Note
        datasources/note_local_data_source.dart   # file notes.json
        repositories/note_repository_impl.dart
        sync/note_sync_collection.dart            # implements SyncCollection
      presentation/
        notes_controller.dart    # ChangeNotifier, chỉ gọi use case
        pages/                   # notes_tab, note_view_page, note_editor
        widgets/                 # note_markdown
    todos/        (cùng khung như notes)
    reminders/    (cùng khung, thêm domain/services/schedule_calculator.dart)
    clipboard/    (cùng khung, data dùng SQLite; watcher nằm trong data/datasources)
    p2p/          (cùng khung, data là discovery/file_server/file_sender/settings)
    pomodoro/     (chỉ có presentation, cộng thêm domain nếu tách timer logic)
    running_text/ (chỉ có presentation)
```

### Quy tắc phụ thuộc

```
presentation  ──▶  domain  ◀──  data
      │                           │
      └──────────▶ core ◀─────────┘
```

| Layer | Được import | Không được import |
|---|---|---|
| `features/*/domain` | `dart:core`, `dart:async`, `core/domain`, `core/sync/domain`, `meta`, `equatable` | `package:flutter/*`, `dart:io`, `data/`, `presentation/`, feature khác, mọi package hạ tầng (`sqflite`, `http`, `path_provider`, `uuid`, ...) |
| `features/*/data` | domain của chính feature, `core/domain`, `core/data`, `core/sync/{domain,data}`, package hạ tầng | `presentation/`, `package:flutter/material.dart`, feature khác |
| `features/*/presentation` | domain của chính feature, `core/domain`, `core/presentation`, `core/sync/presentation`, `flutter`, `provider` | `data/` (kể cả của chính feature), package hạ tầng |
| `core/*` | `core/*` khác | `features/*`, `app/*` |
| `app/*` | mọi thứ | — |

Ghi chú:

- Feature không import lẫn nhau. Khi cần dữ liệu của feature khác (todo liên kết
  reminder qua `linkReminder`), feature dùng interface (port) khai báo trong
  chính mình, và adapter trong `app/di/bridges/` nối với implementation của
  feature kia. Với todo↔nhắc nhở, một interface tra cứu là không đủ (xem
  [mục 8.4](#84-cầu-nối-todo--nhắc-nhở)).
- `HomePage` ghép tab của nhiều feature nên nằm ở `app/shell`, không thuộc feature nào.

---

## 3. Quy ước cho từng layer

Ví dụ dưới đây lấy feature `notes`, các feature khác làm theo cùng khuôn.

### 3.1 Domain

**Entity:** thuần Dart, bất biến, không chứa `remoteId`, `dirty`, `toJson` hay
`toParse`. Logic chỉ phụ thuộc vào dữ liệu của chính entity (`displayTitle`,
`preview`, `matches`, `isEmpty`) thì vẫn ở lại trong entity.

```dart
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.markdown,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  // ...

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;
  String get displayTitle => /* như hiện tại */;

  Note copyWith({String? title, String? body, bool? pinned, /* ... */});
}
```

**Repository interface:**

```dart
abstract interface class NoteRepository {
  Future<Result<List<Note>>> getAll();
  Future<Result<void>> save(Note note);
  Future<Result<void>> delete(String id);

  /// Bắn sự kiện khi dữ liệu đổi, kể cả do sync áp vào.
  Stream<void> get changes;
}
```

Repository trả về `Result<T>`, không ném exception ra domain. Lỗi IO hay
`FormatException` được bắt ở data rồi đổi thành `Failure`.

**Use case:** mỗi hành động là một class có duy nhất `call`.

```dart
abstract class UseCase<T, P> {
  Future<Result<T>> call(P params);
}

class SaveNote implements UseCase<void, Note> {
  SaveNote(this._repo, this._clock);
  final NoteRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(Note note) {
    // Note rỗng thì xoá: thoát editor mà không gõ gì sẽ không để lại rác.
    if (note.isEmpty) return _repo.delete(note.id);
    return _repo.save(note.copyWith(updatedAt: _clock.now()));
  }
}
```

Quy tắc đặt tên: động từ + danh từ (`GetNotes`, `SaveNote`, `DeleteNote`,
`SetNotePinned`, `SearchNotes`). Thứ tự sắp xếp (pinned trước, rồi theo
`updatedAt`) thuộc về domain, đặt trong `GetNotes` hoặc trong một
`NoteOrdering` dùng chung.

**Domain service:** dành cho logic thuần dùng chung giữa nhiều use case.
Ví dụ `reminders/domain/services/schedule_calculator.dart` sẽ chứa
`nextAlertAfter` và `_occurrencesAfter` lấy ra từ `Reminder`.

### 3.2 Data

- **Model** (`NoteModel`) giữ toàn bộ field đã lưu, kể cả `remoteId` và `dirty`.
  Đây là nơi duy nhất biết định dạng JSON và Parse.
- **Mapper** chuyển hai chiều `NoteModel` ⇄ `Note`. Khi map từ entity sang model,
  mapper phải giữ lại `remoteId` của bản đã lưu và bật `dirty = true`.
- **DataSource** chỉ làm IO: đọc/ghi `notes.json` qua `JsonFileStore`, gọi SQLite,
  hoặc gọi HTTP. Datasource không chứa nghiệp vụ.
- **RepositoryImpl** điều phối datasource và mapper, quản lý tombstone, đồng thời
  implement `SyncCollection` (có thể qua một class phụ như `NoteSyncCollection`
  giống `_NoteSyncCollection` hiện tại).

**Bắt buộc tương thích ngược:** tên file (`notes.json`, `todos.json`, ...), schema
JSON, schema SQLite và tên field trên Parse giữ nguyên tuyệt đối. Refactor không
được kèm migration dữ liệu. Mỗi model cần một test round-trip đọc fixture JSON
cũ, bao gồm cả dạng "bare list" từ thời chưa có sync.

### 3.3 Presentation

- Giữ `provider` + `ChangeNotifier`. Đổi tên `*Store` thành `*Controller`.
- Controller chỉ gọi use case và giữ state hiển thị (danh sách, query, loading,
  lỗi). Controller không import `data/`.
- Controller lắng nghe `repository.changes` thông qua use case `WatchNotes`, nên
  khi sync áp thay đổi vào thì UI tự cập nhật. Cách này thay cho việc store tự
  `notifyListeners()` trong `_persist(fromSync: true)`.
- Phần trình bày của enum như `label`, `icon` và màu (ví dụ `ClipTypeX.icon`,
  `NoteColorLabel.label`) chuyển thành extension trong `presentation/`.
- Các hàm `format*` dùng chung ở `core/presentation/format.dart`.
  `describeSchedule(Reminder)` chuyển sang `reminders/presentation`. Ngoài
  `ui/format.dart` còn có file format thứ hai là `lib/clipboard/ui/format.dart`
  (`formatRelative`, `formatRemaining`, dùng ở `clip_tabs.dart` và
  `widgets/clip_card.dart`). Ở giai đoạn 5 hai hàm này cũng chuyển vào
  `core/presentation/format.dart`, giữ nguyên hành vi. Riêng chuỗi
  hiển thị trên thông báo Android (`android_alarm_service._body`) được dựng ở
  presentation rồi truyền xuống dưới dạng dữ liệu, để `core/platform` không phải
  biết format.

### 3.4 Dependency Injection

Thêm `get_it` vào `pubspec.yaml`. Mỗi feature có một hàm đăng ký riêng:

```dart
// features/notes/notes_injection.dart
void registerNotes(GetIt sl) {
  sl
    ..registerLazySingleton(() => NoteLocalDataSource(sl()))
    ..registerLazySingleton<NoteRepository>(() => NoteRepositoryImpl(sl(), sl()))
    ..registerLazySingleton(() => GetNotes(sl()))
    ..registerLazySingleton(() => SaveNote(sl(), sl()))
    // ...
    ..registerFactory(() => NotesController(getNotes: sl(), saveNote: sl(), /* ... */));
}
```

`app/di/injection.dart` gọi lần lượt `registerCore`, `registerSync` và
`register<Feature>`, rồi đăng ký danh sách kênh (`SyncChannel`, xem
[mục 8.2](#82-syncchannel-clip-và-clipgroup-dùng-chung-cursor)) cho engine:

```dart
sl.registerLazySingleton<SyncEngine>(() => ParseSyncEngine(
      config: sl(),
      state: sl<SyncStateStore>(),
      clock: sl(),
      channels: [
        SyncChannel.shared([
          sl<ClipGroupSyncCollection>(),
          sl<ClipSyncCollection>(),
        ]),
        SyncChannel.single(sl<TodoSyncCollection>()),
        SyncChannel.single(sl<NoteSyncCollection>()),
      ],
    ));
```

Widget không gọi `sl` trực tiếp. `app.dart` tạo controller từ `sl` rồi đưa vào
`MultiProvider`, và widget chỉ dùng `context.watch/read`.

Test không dùng `get_it` toàn cục mà tự dựng object bằng constructor, truyền
fake vào.

---

## 4. Sync engine

Đây là phần thay đổi nhiều nhất, nên được tách thành một giai đoạn riêng.

1. Chuyển `parse_client.dart`, `parse_config.dart` và `class_names.dart` sang
   `core/sync/data/`. Chuyển `SyncRecord`, `SyncTombstone`, `SyncStatus` và
   `SyncState` sang `core/sync/domain/entities/`.
2. Biến clip và clip group thành hai `SyncCollection`
   (`ClipSyncCollection`, `ClipGroupSyncCollection`) trong `features/clipboard/data/sync/`.
   Có các điểm khác biệt hiện tại cần đưa vào interface:
   - Tombstone của clipboard lưu trong bảng SQLite theo `remoteId`
     (`queueRemoteDelete`, `clearPendingDelete(remoteId)`), còn todo/note lưu
     theo `localId`. **Đã chốt: chuẩn hoá về `remoteId`** cho mọi collection,
     vì bảng `pending_deletes` không có cột local id và schema SQLite không
     được đổi (xem [mục 8.1](#81-tombstone-khoá-theo-remoteid)).
   - Clip tạm không được đồng bộ. Điều kiện này nằm trong `dirtyRecords()` của
     `ClipSyncCollection`.
   - Clip và ClipGroup đang được kéo theo cặp với một cursor chung. Giữ nguyên
     bằng `SyncChannel` (xem [mục 8.2](#82-syncchannel-clip-và-clipgroup-dùng-chung-cursor)).
   - Settings của engine (`sync_rev_*`, cursor, `_inflight`) đang ghi vào bảng
     settings của `ClipRepository`. Cần tách thành interface
     `SyncStateStore` trong `core/sync/domain`, implement bằng SQLite ở `core/data`.
     Mọi key giữ nguyên văn (danh sách ở [mục 8.3](#83-key-trong-bảng-settings)).
3. Sau bước 2, `ParseSyncEngine` chỉ còn biết `List<SyncCollection>`. Các nhánh
   `_pullClipboard`, `_applyClip` và `_applyGroup` sẽ bị xoá.
4. Tách timer, trạng thái sync và nút "Đồng bộ ngay" ra khỏi `ClipboardStore`,
   đưa vào `core/sync/presentation/sync_controller.dart`. Callback
   `onLocalChange` của các store được thay bằng việc controller lắng nghe
   `changes` của các repository.
5. Giữ nguyên giao thức đã ghi trong `docs/sync-server-triggers.md` (bộ đếm
   `SyncMeta`, full pull định kỳ). Toàn bộ test sync có sẵn (nay ở
   `test/core/sync/` và `test/features/clipboard/data/sync/`) phải chạy được với
   engine mới mà không sửa assertion, chỉ sửa phần dựng object.

**Lịch và ngân sách request (nhánh `feat/sync-budget`).** Lịch sync không còn
là các mốc cố định (30 giây, 10 phút, 2 giờ, 24 giờ) mà suy ra từ một
**ngân sách request/tháng do người dùng đặt**, không phải hạn mức của Back4App.
Chi tiết, kèm bảng ước tính chi phí, ở `docs/sync-server-triggers.md`.

- Ngân sách khai báo ở `lib/core/sync/domain/entities/sync_budget.dart`:
  `userMonthlyRequestBudget = 10000` cho cả space và `expectedSyncDevices = 3`.
  Muốn đổi thì sửa hai hằng số này; mọi ngưỡng và khoảng thời gian tự tính lại.
- Mỗi máy giữ phần của mình: 10.000 / 3 = 3.333 request/tháng, đếm trong
  `sync_req_YYYY-MM`. Cảnh báo ở 70% (2.333), dừng ở 100% (3.333).
- Mức bình thường: đẩy sau 30 giây kể từ lần sửa cuối; focus/resume kéo nếu
  lượt kiểm server gần nhất đã cách ít nhất R = 14 phút; pull đầy đủ khi lần
  trước đã cũ hơn 21 giờ; timer dự phòng 2 giờ, chỉ chạy khi còn thay đổi chưa
  đẩy.
- Mức cảnh báo: mọi khoảng trên dài gấp 4, trừ pull đầy đủ chỉ tới 24 giờ ở
  ngân sách mặc định (`max(bình thường, min(bình thường × 4,
  SyncBudget.warningFullPullCap))`, hằng số này là 24 giờ);
  tooltip báo sắp hết ngân sách.
- Đã hết: không chạy chu kỳ tự động nào (đẩy lẫn kéo) tới tháng sau; thay đổi
  local nằm chờ. Nút đồng bộ hiện icon `sync_disabled_rounded` và lý do trong
  tooltip; "Đồng bộ ngay" vẫn chạy và vẫn được đếm. `ParseSyncEngine` chặn chu
  kỳ tự động ngay trước request vượt phần của máy.
- Sync tự động bật/tắt được khi app đang chạy, ở menu ⚙ "Tuỳ chọn" > "Sync tự
  động (clip, việc, ghi chú)" (mục có dấu tick, có ở mọi tab trên Windows và
  Android, bị vô hiệu khi build chưa cấu hình App ID/Client Key).
  - Máy chưa từng chỉnh dùng giá trị build `PARSE_AUTO_SYNC` (không đặt hoặc
    khác `0` là bật, `0` là tắt). Đã chỉnh thì lựa chọn của máy thắng giá trị
    build, theo cả hai chiều. Không đọc được lựa chọn đã lưu thì phiên đó coi
    như tắt, bất kể giá trị build; lựa chọn đã lưu không bị ghi đè và người
    dùng vẫn bật lại được.
  - Lựa chọn lưu trên từng máy, ở key mới `sync_auto` của bảng settings (xem
    [mục 8.3](#83-key-trong-bảng-settings)). Lựa chọn không đồng bộ qua Back4App
    và bản thân thao tác bật/tắt không gửi request nào; request chỉ đến từ
    chu kỳ mà việc bật lại hẹn (xem dòng "Bật lại" bên dưới).
  - Khác với "đã hết" ở trên: hết ngân sách là app tự tạm dừng (state paused,
    icon `sync_disabled_rounded`) và tự chạy lại khi sang tháng; còn tắt là
    người dùng chọn, giữ nguyên tới khi người dùng bật lại, kể cả qua các lần
    mở lại app.
  - Khi tắt: nút đồng bộ hiện icon `cloud_outlined` (không tô màu, vẫn bấm
    được, kể cả khi đồng thời hết ngân sách). Khởi động app, focus/resume, thay
    đổi local, timer đẩy và timer dự phòng đều không chạy chu kỳ tự động nào;
    chu kỳ đang chạy dở lúc tắt thì được chạy xong. Thay đổi local nằm chờ.
    "Đồng bộ ngay" vẫn chạy đủ một chu kỳ và vẫn được đếm.
  - Bật lại không cần khởi động lại app, hành xử như `onAppActive` cộng thêm
    việc đẩy thay đổi đang chờ: còn thay đổi chờ thì đẩy sau `pushDelay` của
    mức hiện tại; không có thì chỉ kiểm server khi lượt kiểm gần nhất đã cách
    ít nhất R. Nếu máy đã hết phần ngân sách thì vào lại trạng thái paused và
    chờ sang tháng. Bật lại lúc một chu kỳ đang chạy thì các việc này làm
    ngay khi chu kỳ đó xong.
  - Bấm "Đồng bộ ngay" lúc lượt "Đồng bộ ngay" trước đang chạy thì nhận kết
    quả của lượt đó, không tốn thêm request. Bấm lúc chu kỳ khác đang chạy
    (tự động, hoặc bấm tay không full) thì đúng một lượt full bấm tay chạy
    ngay sau chu kỳ đó, cả khi đang tắt hay đã hết ngân sách, và mọi lần bấm
    đang chờ nhận kết quả của lượt này.
  - Trạng thái đang áp dụng nằm ở `SyncController` (`autoSyncEnabled`,
    `settings`) trong `lib/core/sync/presentation/sync_controller.dart`;
    `SyncSettings.autoSync` lấy từ DI vẫn là giá trị build. UI chỉ đọc từ
    controller.
- Khoá 30 giây cho "Đồng bộ ngay", ở mọi mức kể cả khi đã hết ngân sách hay
  sync tự động đang tắt:
  - Sau mỗi lần bấm được nhận, nút đồng bộ ở tab clipboard và mục menu ⚙
    "Đồng bộ ngay (clip, việc, ghi chú)" cùng bị vô hiệu 30 giây tính từ lúc
    bấm; chu kỳ của lần bấm đó (kể cả lượt xếp hàng sau một chu kỳ đang chạy)
    lâu hơn thì khoá tới khi chu kỳ xong. Sync lỗi vẫn khoá đủ 30 giây. Bấm
    dồn chỉ tốn một chu kỳ; lần bấm rơi vào lúc khoá không làm gì và không
    gửi request. Khoá không áp dụng cho sync tự động.
  - Khoá nằm ở `SyncController`: `pressSyncNow()` là lối vào của người bấm,
    nhận khoá trước `await` đầu tiên và trả `null` khi đang khoá;
    `manualSyncLocked`, `manualSyncCooldownLeft` và hằng
    `SyncController.manualSyncCooldown` (30 giây) tính theo `Clock` được
    inject; giờ bị chỉnh lùi về trước lúc bấm thì `manualSyncCooldownLeft`
    về 0, không bao giờ quá 30 giây. `syncNow` không có khoá, nên các trigger
    tự động và harness mô phỏng không đổi. Controller không giữ `Timer` nào
    cho khoá; nút (`_SyncButton` trong `clip_tabs.dart`) tự hẹn `Timer` để vẽ
    lại khi hết khoá và vẽ lại khi app resume (Timer có thể không đếm lúc máy
    ngủ), còn mục menu (`syncNowMenuItem` trong `clip_actions.dart`) đọc khoá
    lúc mở menu.
  - Khoá chỉ nằm trong bộ nhớ, không lưu qua lần mở app, và không thêm key
    settings nào.
- Khi đã đọc được số đếm, tooltip hiện `x / 3333 request tháng này (máy này)`
  (`lib/core/sync/presentation/sync_status_text.dart`).
- Hai cách giảm request trong `lib/core/sync/data/parse_sync_engine.dart`:
  **kéo một lượt** (class dưới 500 bản ghi đã đồng bộ được tải cả class trong
  một query, bỏ request đối chiếu xoá) và **chu kỳ chỉ-đẩy** (thay đổi local đẩy
  lên mà không hỏi server, khi lượt kiểm gần nhất chưa cách quá R).
- Phương án chuyển bộ đếm sang trigger Cloud Code đã loại, vì mỗi lần ghi có
  `afterSave` bị Back4App tính ít nhất 2 request.

---

## 5. Lộ trình migrate

Mỗi giai đoạn là một PR riêng vào `dev`. Một PR chỉ được merge khi
`flutter analyze` không có lỗi mới, `flutter test` xanh, và đã chạy thử app
trên Windows (và Android nếu PR đụng tới reminder).

| # | Giai đoạn | Nội dung chính | Rủi ro |
|---|---|---|---|
| 0 | Nền móng | Thêm `get_it` và các file `core/domain` (`Clock`, `IdGenerator`, `Result`, `Failure`, `UseCase`, `TimeOfDay`). Thêm `tool/check_layers.dart` (mục 6). Chưa di chuyển code. | Thấp |
| 1 | Gom phần dùng chung | Chuyển `format.dart` sang `core/presentation`. Chuyển `class_names`, `sync_collection`, `parse_*` sang `core/sync`. Chuyển `app_database`, `startup_service`, `memory_trim`, `alarm_sound`, `background_service` sang `core/`. Hai vi phạm số 1 và 2 ở mục 1 biến mất ở bước này. | Thấp, chỉ đổi import |
| 2 | **Notes** (pilot) | Dựng đủ domain/data/presentation, mapper, use case và DI cho notes. Viết thêm test cho use case và mapper. Đây là feature mẫu cho các feature sau. | Trung bình |
| 3 | Todos | Làm như notes, thêm port `LinkedReminderRepository` và `TodoReminderEditor` cho phần nối với nhắc nhở, adapter ở `app/di/bridges/` (mục 8.4). | Trung bình |
| 4 | Sync engine | Thực hiện mục 4: clipboard thành `SyncCollection`, có `SyncStateStore` và `SyncController`. | **Cao**. Cần test hai máy thật trên cùng một space. |
| 5 | Clipboard | Tách `ClipboardStore` (497 dòng) thành use case và controller. `ClipboardWatcher` thành datasource. Tách `ClipboardTabState` khỏi `main.dart`. | Trung bình |
| 6 | Reminders | Thay `TimeOfDay` bằng value object, tách `ScheduleCalculator`, tách ticker và hàng đợi `PendingAlert` thành use case (`GetDueAlerts`, `SnoozeAlert`, `DismissAlert`). `AndroidAlarmService` thành một implementation của interface `AlarmScheduler`. | **Cao**. Đây là chức năng cốt lõi; cần test kỹ desktop và Android. |
| 7 | P2P | Chuyển `discovery_service`, `file_server`, `file_sender`, `p2p_settings` thành datasource sau các repository interface (`PeerRepository`, `TransferRepository`). Tách `P2pStore` (512 dòng) và `p2p_tab.dart` (817 dòng). | Trung bình |
| 8 | Pomodoro, chữ chạy, app shell | Chuyển hai feature chỉ có UI. Tách `main.dart` thành `bootstrap`, `app` và `shell`. Bật `check_layers` ở chế độ bắt buộc. | Thấp |

Gợi ý: làm giai đoạn 0–2 trước rồi dừng lại đánh giá. Nếu thấy lượng boilerplate
của bản strict không đáng với một app cỡ này, có thể nới lỏng cho các feature
sau, ví dụ bỏ use case với các thao tác CRUD một dòng.

---

## 6. Giữ cho quy tắc không bị phá

Viết script `tool/check_layers.dart`. Script quét các dòng `import` trong `lib/`
và báo lỗi khi vi phạm bảng ở mục 2, ví dụ:

- file trong `*/domain/` import `package:flutter/`, `dart:io`, `/data/` hoặc `/presentation/`;
- file trong `*/presentation/` import `/data/`;
- file trong `features/a/` import `features/b/`;
- file trong `core/` import `features/` hoặc `app/`.

Lộ trình chạy script:

- Từ giai đoạn 0, chạy ở chế độ cảnh báo, liệt kê vi phạm còn lại.
- Từ giai đoạn 8, chạy ở chế độ bắt buộc (exit code khác 0) trong CI và
  pre-commit.

Hiện tại `dart run tool/check_layers.dart` không kèm cờ đã là chế độ bắt buộc;
cờ `--warn` chạy chế độ cảnh báo. Dự án chưa có CI nên việc nối script vào CI
hay pre-commit để sau.

Test chuyển theo cấu trúc `test/features/<feature>/{domain,data,presentation}/`
và `test/core/sync/`. Domain test là unit test thuần, không cần `flutter_test`
binding.

Test cũ ở `test/clipboard/` và `test/*.dart` đã dời nguyên nội dung, chỉ đổi
dòng import:

| Trước | Sau |
|---|---|
| `test/clipboard/fake_parse_server.dart` | `test/core/sync/fake_parse_server.dart` |
| `test/clipboard/parse_client_test.dart` | `test/core/sync/data/parse_client_test.dart` |
| `test/clipboard/task_sync_test.dart` | `test/core/sync/data/task_sync_test.dart` |
| `test/clipboard/sync_service_test.dart` | `test/features/clipboard/data/sync/sync_service_test.dart` |
| `test/clipboard/sync_test.dart` | `test/features/clipboard/data/sync_test.dart` |
| `test/clipboard/clip_item_test.dart` | `test/features/clipboard/domain/entities/clip_item_basics_test.dart` |
| `test/clipboard/clipboard_tab_test.dart` | `test/features/clipboard/presentation/clipboard_tab_sqlite_test.dart` |
| `test/note_test.dart` | `test/features/notes/data/note_test.dart` |
| `test/todo_test.dart` | `test/features/todos/data/todo_test.dart` |
| `test/reminder_test.dart` | `test/features/reminders/data/reminder_test.dart` |
| `test/p2p_discovery_test.dart` | `test/features/p2p/data/datasources/p2p_discovery_test.dart` |
| `test/p2p_transfer_test.dart` | `test/features/p2p/data/datasources/p2p_transfer_test.dart` |
| `test/p2p_manual_peer_test.dart` | `test/features/p2p/domain/services/p2p_manual_peer_test.dart` |

File nào kiểm cả entity lẫn model hoặc mapper thì nằm ở `data/` của feature,
vì domain test không được phụ thuộc data. `task_sync_test.dart` chạy engine với
clipboard, todos và notes cùng lúc nên nằm ở `test/core/sync/data/`. Test của
`tool/check_layers.dart` ở `test/tool/`.

---

## 7. Ánh xạ file hiện tại → vị trí mới

| Hiện tại | Vị trí mới |
|---|---|
| `main.dart` | `main.dart` + `app/bootstrap.dart` + `app/app.dart` + `app/shell/` |
| `models/note.dart` | `features/notes/domain/entities/note.dart` + `features/notes/data/models/note_model.dart` |
| `services/note_store.dart` | `features/notes/presentation/notes_controller.dart` + `features/notes/domain/usecases/*` + `features/notes/data/sync/note_sync_collection.dart` |
| `services/note_storage.dart` | `features/notes/data/datasources/note_local_data_source.dart` |
| `ui/notes_tab.dart`, `note_editor.dart`, `note_view_page.dart`, `note_markdown.dart` | `features/notes/presentation/{pages,widgets}/` |
| `models/todo.dart`, `services/todo_store.dart`, `services/todo_storage.dart`, `ui/todo_page.dart`, `ui/todo_editor.dart` | `features/todos/...` (như notes) |
| `models/reminder.dart`, `services/reminder_store.dart`, `services/storage_service.dart` | `features/reminders/...` |
| `ui/reminder_editor.dart`, `ui/deadline_card.dart`, `ui/alarm_screen.dart` | `features/reminders/presentation/` |
| `services/android_alarm_service.dart` | `core/platform/android_alarm_channel.dart` + `features/reminders/data/android_alarm_scheduler.dart` |
| `services/alarm_sound.dart`, `startup_service.dart`, `memory_trim.dart`, `background_service.dart` | `core/platform/` |
| `services/sync/sync_collection.dart` | `core/sync/domain/` |
| `clipboard/sync/*` | `core/sync/data/` |
| `clipboard/data/app_database.dart` | `core/data/app_database.dart` |
| `clipboard/data/clip_repository.dart` | `features/clipboard/data/{datasources,repositories,sync}/` |
| `clipboard/models/*` | `features/clipboard/domain/entities/` + `features/clipboard/data/models/` |
| `clipboard/services/clipboard_watcher.dart` | `features/clipboard/data/datasources/clipboard_watcher.dart` |
| `clipboard/state/clipboard_store.dart` | `features/clipboard/presentation/clipboard_controller.dart` + `core/sync/presentation/sync_controller.dart` |
| `clipboard/ui/*` | `features/clipboard/presentation/` |
| `clipboard/ui/format.dart` | `core/presentation/format.dart` |
| `clipboard/ui/widgets/app_logo.dart` | `core/presentation/widgets/app_logo.dart` |
| `p2p/*` | `features/p2p/...` |
| `ui/pomodoro_*.dart`, `ui/countdown_card.dart` | `features/pomodoro/presentation/` |
| `running_text/ui/*` | `features/running_text/presentation/` |
| `ui/home_page.dart` | `app/shell/home_page.dart` |
| `ui/format.dart` | `core/presentation/format.dart` (riêng `describeSchedule` chuyển sang `features/reminders/presentation/`) |

---

## 8. Các quyết định đã chốt

Ghi lại khi lập kế hoạch chi tiết cho giai đoạn 0–8 (22/10/2026). Mục này
sửa hoặc làm rõ những chỗ ở trên không khớp với code. Khi hai nơi lệch nhau
thì theo mục này. Số dòng dẫn tới code tại commit `9799873` trên `dev`.

### 8.1 Tombstone khoá theo `remoteId`

- Bảng `pending_deletes` chỉ có `remote_id TEXT PRIMARY KEY`, `class_name` và
  `queued_at` (`lib/clipboard/data/app_database.dart:137-141`), không có cột
  local id. Clipboard xếp hàng và xoá dòng chờ theo `remoteId`
  (`lib/clipboard/data/clip_repository.dart:272-304`). Todo và ghi chú thì
  giữ tombstone trong file JSON với cả `id` lẫn `remoteId`
  (`lib/services/sync/sync_collection.dart:23-36`), nhưng engine gọi
  `clearPendingDelete(tombstone.localId)`
  (`lib/clipboard/sync/sync_service.dart:234-236`).
- **Quyết định:** mọi `SyncCollection` dùng `clearPendingDelete(String remoteId)`.
  Notes/todos chỉ cần tìm tombstone theo `remoteId`. `ClipSyncCollection` và
  `ClipGroupSyncCollection` đọc `pending_deletes` lọc theo `class_name`.
- Schema giữ nguyên, không có migration. Một DB do bản cũ ghi, còn dòng chờ của
  `Clip` và `ClipGroup`, sau lượt sync đầu của bản mới phải gửi đủ lệnh DELETE
  và xoá hết dòng chờ (có test ở giai đoạn 4).

### 8.2 `SyncChannel`: Clip và ClipGroup dùng chung cursor

- Hiện tại Clip và ClipGroup được kéo theo cặp với một cursor chung
  `sync_cursor_<space>`: chỉ cần một trong hai class đổi là query cả hai
  (`lib/clipboard/sync/sync_service.dart:424-429`, `441-467`). Nhóm được áp
  trước clip, vì `clips.group_id` là khoá ngoại tới `groups(id)`
  (`lib/clipboard/data/app_database.dart:86`). TodoItem và NoteItem mỗi class
  một cursor `sync_cursor_<space>_<Class>` (`sync_service.dart:470-480`).
- **Quyết định:** engine nhận danh sách `SyncChannel` thay cho danh sách
  `SyncCollection` phẳng.
  - `SyncChannel.shared([ClipGroup, Clip])` dùng key `sync_cursor_<space>`,
    kéo cả hai khi một trong hai `rev_<Class>` đổi, rồi query, đối chiếu xoá và
    áp theo đúng thứ tự `[ClipGroup, Clip]`.
  - `SyncChannel.single(collection)` dùng `sync_cursor_<space>_<Class>`.
  - `ParseSyncEngine` không còn nhánh riêng cho Clip hay ClipGroup.
- Push theo thứ tự đăng ký `[ClipGroup, Clip, TodoItem, NoteItem]`, mỗi class
  xoá trước rồi mới tạo/sửa. Khác hiện tại một chút: bây giờ mọi lệnh xoá của
  clipboard (theo `queued_at`) đi trước mọi upsert (`sync_service.dart:198-231`).
  Thay đổi này đã được chấp nhận vì không đổi số request.
- Loại phương án "hai collection độc lập, mỗi cái một cursor": đổi key cursor
  khiến máy đã nâng cấp tải lại toàn bộ dữ liệu, có thể áp clip trước nhóm, và
  làm `test/clipboard/sync_service_test.dart:251-252` fail.

### 8.3 Key trong bảng `settings`

Bảng `settings(key TEXT PRIMARY KEY, value TEXT)`
(`lib/clipboard/data/app_database.dart:124-128`) là trạng thái nằm trên đĩa của
engine, cộng thêm lựa chọn riêng của từng máy như `sync_auto` (ghi qua
`StateStoreSyncPreferences`). Vì vậy reset trạng thái engine thì chỉ được xoá
key của engine, không được xoá `sync_auto`. `SyncStateStore` (interface ở `core/sync/domain`, implement SQLite ở
`core/data`) phải đọc và ghi **đúng nguyên văn** các key sau. Đổi key thì máy đã
nâng cấp kéo lại toàn bộ dữ liệu, mất bộ đếm request của tháng và mất danh sách
inflight.

| Key | Giá trị | Nguồn (`lib/clipboard/sync/sync_service.dart`) |
|---|---|---|
| `sync_rev_<space>_<Class>` | `rev_<Class>` của `SyncMeta` máy này thấy lần cuối | 317 |
| `sync_cursor_<space>` | cursor `updatedAt` (ISO) chung cho Clip và ClipGroup | 442 |
| `sync_cursor_<space>_<Class>` | cursor riêng của TodoItem, NoteItem | 480 |
| `sync_meta_id_<space>` | `objectId` của `SyncMeta` | 314 |
| `sync_meta_bump_<space>` | JSON list các class còn chờ tăng bộ đếm, rỗng khi đã gửi | 315, 331-333, 360 |
| `sync_full_at_<space>` | millis của lần pull đầy đủ gần nhất | 316 |
| `sync_inflight` | JSON list `<Class>/<localId>` đã gửi nhưng chưa xác nhận | 301-302, 313 |
| `sync_last_at` | millis lúc chu kỳ sync gần nhất xong | 129 |
| `sync_req_YYYY-MM` | số request đã dùng trong tháng | 166-167 |
| `sync_auto` | `1`/`0`: lựa chọn sync tự động của máy này; chưa có key là chưa chỉnh, dùng `PARSE_AUTO_SYNC` | **key mới**, không có trong `sync_service.dart`; ghi ở `lib/core/sync/data/state_store_sync_preferences.dart` |

Ngân sách request/tháng (nhánh `feat/sync-budget`, xem [mục 4](#4-sync-engine))
không thêm, bớt hay đổi key nào: mức ngân sách tính từ `sync_req_YYYY-MM`, còn
ngân sách và số máy là hằng số trong code. Switch sync tự động (cùng nhánh, xem
[mục 4](#4-sync-engine)) chỉ thêm đúng một key mới là `sync_auto`, đọc ghi qua
`SyncStateStore`; mọi key cũ ở bảng trên giữ nguyên văn. Khoá 30 giây của
"Đồng bộ ngay" (cùng nhánh) chỉ nằm trong bộ nhớ, không thêm key nào.

### 8.4 Cầu nối todo ↔ nhắc nhở

- UI todo hiện không chỉ tra cứu nhắc nhở mà còn tạo, sửa, xoá, bật/tắt nhắc
  nhở và mở editor của nó (`lib/ui/todo_page.dart:58-164`). Interface
  `ReminderLookup` ở mục 2 bản cũ là không đủ.
- **Quyết định:**
  - `todos/domain`: entity `LinkedReminder` và `ReminderDraft` (dùng `TimeOfDay`
    của core); port `LinkedReminderRepository` (`find`, `setEnabled`,
    `remove`, `changes`); use case `DraftReminderFromTodo` (không có giờ thì
    08:00, hạn đã qua thì sang ngày mai, deadline báo trước 60 phút),
    `FindLinkedReminder`, `SetLinkedReminderEnabled`, `RemoveLinkedReminder`,
    `WatchLinkedReminders`.
  - `todos/presentation`: port `TodoReminderEditor` (`createFromDraft`, `open`),
    vì mở editor là việc của UI.
  - Implementation nằm ở `lib/app/di/bridges/`. Giai đoạn 3 viết adapter trên
    `ReminderStore` và `showReminderEditor` cũ (đổi `TimeOfDay` core ↔ Flutter).
    Giai đoạn 6 chỉ đổi adapter sang feature reminders mới.
  - Không file nào trong `lib/features/todos` import bất cứ thứ gì của reminders.

### 8.5 Thời gian, id và `TimeOfDay`

- `Clock`, `IdGenerator`, `Result`, `Failure`, `UseCase`/`NoParams` và
  `TimeOfDay` nằm ở `lib/core/domain/`, không import Flutter hay `dart:io`.
  `SystemClock` và `UuidIdGenerator` nằm ở `lib/core/data/`.
- `UuidIdGenerator` sinh uuid v4, cùng định dạng id hiện có của notes, todos,
  reminders và `deviceId` của P2P. Đây là file duy nhất trong `lib/core` được
  import `package:uuid`.
- Id của clip và nhóm có định dạng riêng `<micro base36>-<rand base36>`
  (`lib/clipboard/data/clip_repository.dart:19-20`). Giai đoạn 5 thêm
  `ClipIdGenerator` trong data của clipboard, lấy thời gian từ `Clock`, để giữ
  đúng định dạng này.
- `TimeOfDay` của core so sánh bằng theo giá trị và ném `RangeError` khi giờ
  ngoài 0–23 hoặc phút ngoài 0–59. File presentation dùng cả hai `TimeOfDay`
  thì import kèm alias hoặc `hide`, và đổi qua lại bằng một extension.

### 8.6 Mốc kiểm tra

- Mốc `flutter analyze` đo trên `dev` (commit `9799873`) trước giai đoạn 0:
  `No issues found!`. Mỗi giai đoạn không được thêm issue nào so với mốc này.
- `tool/check_layers.dart` chạy ở chế độ cảnh báo từ giai đoạn 0 (cờ `--strict`
  để bắt buộc, cờ `--warn` để giữ chế độ cảnh báo). Giai đoạn 8 đổi mặc định
  sang bắt buộc.
