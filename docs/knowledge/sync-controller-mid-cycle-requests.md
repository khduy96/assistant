---
title: SyncController - yêu cầu đến giữa chu kỳ được ghi theo loại
tags: [sync, presentation, concurrency]
updated: 2026-10-26
sources:
  - lib/core/sync/presentation/sync_controller.dart:111-125
  - lib/core/sync/presentation/sync_controller.dart:331-367
  - lib/core/sync/presentation/sync_controller.dart:401-415
  - lib/core/sync/presentation/sync_controller.dart:449-543
  - lib/features/clipboard/presentation/clip_actions.dart:46-64
  - .ai-runs/20261024-1747-bugfix-sync-now-mid-cycle (diagnose, fix, verify)
---

# SyncController: yêu cầu đến giữa chu kỳ được ghi theo loại

**Sự thật:** khi một chu kỳ đang chạy, `SyncController` không gộp mọi yêu cầu
mới vào một cờ `bool`. Mỗi loại có chỗ ghi riêng
(`lib/core/sync/presentation/sync_controller.dart:111-125`):

| Trường | Loại yêu cầu | Xử lý khi chu kỳ hiện tại xong |
|---|---|---|
| `_current`, `_currentManualFull` | chu kỳ đang chạy và nó có phải lượt bấm tay full không | lượt bấm tay full đến sau thì nhận luôn future này |
| `_pushAgain` | trigger tự động (sửa local, timer) | `_requestPush()`, đẩy sau `pushDelay` |
| `_resumeAgain` | người dùng bật lại sync tự động | `_resumeAutoSync()` nếu vẫn đang bật |
| `_manualAgain` (`Completer`), `_manualAgainFull` | bấm tay khi chu kỳ khác đang chạy | đúng **một** lượt bấm tay chạy ngay, full nếu có lần bấm nào full |

Quy tắc trong `_cycle` (`:449-476`):

- Tự động: đặt `_pushAgain`, trả status hiện tại.
- Bấm tay khi lượt bấm tay full đang chạy: trả `_current`, nhận kết quả của
  lượt đó, không tốn request.
- Bấm tay khi chu kỳ khác (tự động, hoặc bấm tay không full) đang chạy: mọi lần
  bấm chờ chung một `_manualAgain`, rồi nhận kết quả của lượt chạy tiếp.

Cuối `_runCycle` (`:513-542`): `_current` được xoá **trước** khi chạy lượt
tiếp. Nếu có `_manualAgain` thì lượt đó chạy bất kể công tắc tự động và ngân
sách, đồng thời xoá `_pushAgain` (lượt bấm tay đẩy hết thứ đang chờ). Nếu
không có thì mới hẹn timer dự phòng, xử lý `_pushAgain` rồi `_resumeAgain`.
`_haltAutoSync` xoá `_resumeAgain` (`:331-336`), và `_resumeAutoSync` đặt cờ đó
khi gặp chu kỳ đang chạy (`:342-359`).

## Vì sao

Bản trước dùng một cờ `_syncAgain` (`.ai-runs/20261024-1747-bugfix-sync-now-mid-cycle/diagnose.handoff.yaml`).
Cách đó gây các lỗi đã tái hiện:

- Bấm "Đồng bộ ngay" giữa chu kỳ thì nhận ngay status `running`, và toast vẫn báo
  "Đã đồng bộ — đẩy 0, nhận 0 mục" (`runSync` dựng toast từ giá trị trả về,
  `clip_actions.dart:46-64`).
- Lượt chạy tiếp bị ép qua `_requestPush`, vốn chỉ dành cho tự động: nó thành
  push không full, hoặc bị bỏ hẳn khi sync tự động tắt hay đã hết ngân sách.
- Bật lại sync tự động giữa chu kỳ thì thay đổi đang chờ phải đợi timer dự
  phòng (2 giờ) thay vì `pushDelay`.

Khi thêm một loại trigger mới, hãy thêm chỗ ghi riêng cho nó, đừng tái dùng cờ
của loại khác: mỗi loại có cổng khác nhau (công tắc, ngân sách, full hay không).

## Hệ quả đã chấp nhận

- Người ghép vào lượt bấm tay full đang chạy nhận kết quả của một chu kỳ đã
  chụp danh sách cần đẩy từ trước khi họ bấm; bản sửa làm trong khoảng đó đi ở
  lần đẩy sau (diagnose, mục `risk`).
- Bấm trong lúc chu kỳ tự động chạy tốn thêm một chu kỳ full.
