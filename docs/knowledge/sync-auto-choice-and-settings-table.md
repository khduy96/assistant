---
title: Bảng settings giữ cả state của engine lẫn lựa chọn sync_auto của máy
tags: [sync, data, settings, sqlite]
updated: 2026-10-26
sources:
  - lib/core/sync/domain/sync_state_store.dart:1-17
  - lib/core/data/sqlite_sync_state_store.dart:6-48
  - lib/core/sync/data/state_store_sync_preferences.dart:4-23
  - lib/core/sync/domain/sync_preferences.dart:1-9
  - lib/core/sync/domain/usecases/get_auto_sync_choice.dart:8-22
  - lib/core/sync/presentation/sync_controller.dart:77-85
  - lib/core/sync/presentation/sync_controller.dart:213-240
  - lib/core/sync/presentation/sync_controller.dart:290-319
  - lib/core/sync/data/parse_config.dart:46-55
  - lib/core/sync/data/parse_sync_engine.dart:166
  - docs/architecture.md (mục 8.3)
  - .ai-runs/20261024-1545-feature-auto-sync-toggle
  - .ai-runs/20261024-1747-bugfix-sync-now-mid-cycle
---

# Bảng `settings` giữ cả state của engine lẫn lựa chọn `sync_auto` của máy

**Sự thật:** bảng SQLite `settings(key, value)`, đọc ghi qua `SyncStateStore`
(`lib/core/sync/domain/sync_state_store.dart:1-17`, implement ở
`lib/core/data/sqlite_sync_state_store.dart`), chứa hai loại dữ liệu:

1. State của engine: cursor, bộ đếm `rev`, `sync_inflight`, `sync_req_YYYY-MM`…
   (danh sách đầy đủ ở `docs/architecture.md` mục 8.3). Engine nạp **toàn bộ**
   bảng một lần mỗi chu kỳ (`parse_sync_engine.dart:166`).
2. Lựa chọn riêng của từng máy: key `sync_auto`, giá trị `'1'`/`'0'`, chưa có key
   là chưa chỉnh. Chỉ `StateStoreSyncPreferences` đọc ghi key này
   (`state_store_sync_preferences.dart:9-23`). Không đồng bộ qua Back4App.

**Hệ quả:** reset state của engine thì chỉ được xoá key của engine, **không**
xoá cả bảng hay mọi key bắt đầu bằng `sync_`, vì `sync_auto` dùng chung tiền tố
đó (doc của `SyncStateStore` và `SqliteSyncStateStore` đều ghi điều này).

## Thứ tự ưu tiên khi quyết định sync tự động

`SyncController._applyChoice` (`sync_controller.dart:234-240`):
`autoSync = _choice ?? _built.autoSync`.

- `_built` là giá trị build `PARSE_AUTO_SYNC` (không đặt hoặc khác `'0'` là bật,
  `parse_config.dart:46-55`).
- `_choice` là lựa chọn đã lưu của máy; đã chỉnh thì **thắng giá trị build**,
  theo cả hai chiều.
- UI đọc `SyncController.autoSyncEnabled`/`settings`; `SyncSettings.autoSync`
  lấy từ DI vẫn là giá trị build.

## Đọc lỗi thì coi như tắt (fail-closed)

`GetAutoSyncChoice` đổi exception thành `Err` (`get_auto_sync_choice.dart:14-21`).
`_load` gặp `Err` thì đặt `_choice = false` (`sync_controller.dart:225-228`):
phiên đó tắt sync tự động bất kể giá trị build, và **không ghi gì** xuống store,
nên lựa chọn đã lưu vẫn còn cho lần mở sau, người dùng vẫn bật lại được qua
`setAutoSync`.

Vì sao: trước bản sửa, đọc lỗi để `_choice = null` và rơi về giá trị build, tức
có thể chạy sync tự động (tốn request) trái với lựa chọn người dùng đã tắt
(`.ai-runs/20261024-1747-bugfix-sync-now-mid-cycle/diagnose.handoff.yaml`, kịch
bản E). Ghi đè lựa chọn khi đọc lỗi thì làm mất lựa chọn thật.

## Ghi lựa chọn

`setAutoSync` (`sync_controller.dart:290-319`) lưu trước, chỉ áp dụng khi lưu
thành công; lưu lỗi thì không đổi gì và trả `false`. Các lần gọi chạy tuần tự.
Bản thân thao tác bật/tắt không gửi request.
