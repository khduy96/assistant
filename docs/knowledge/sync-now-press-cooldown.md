---
title: pressSyncNow là lối vào của người bấm, syncNow không có khoá
tags: [sync, presentation, testing]
updated: 2026-10-26
sources:
  - lib/core/sync/presentation/sync_controller.dart:32-35
  - lib/core/sync/presentation/sync_controller.dart:127-130
  - lib/core/sync/presentation/sync_controller.dart:180-205
  - lib/core/sync/presentation/sync_controller.dart:415-439
  - lib/features/clipboard/presentation/clip_actions.dart:42-75
  - lib/features/clipboard/presentation/pages/clip_tabs.dart:262-287
  - lib/features/clipboard/presentation/pages/clip_tabs.dart:317-319
  - lib/app/shell/home_page.dart:252
  - lib/app/shell/home_page.dart:259
  - test/core/sync/simulation/sync_simulation_harness.dart:416-420
  - .ai-runs/20261024-1749-feature-sync-now-cooldown
---

# `pressSyncNow` là lối vào của người bấm, `syncNow` không có khoá

**Sự thật:** `SyncController` có hai lối chạy đồng bộ tay:

- `pressSyncNow()` (`sync_controller.dart:420-439`): dùng cho nút và menu "Đồng
  bộ ngay". Khoá `manualSyncCooldown` = 30 giây tính từ lúc bấm (`:180-182`),
  kéo dài tới khi chu kỳ của lần bấm đó xong, kể cả lượt xếp hàng sau chu kỳ
  đang chạy. Khoá được nhận **trước `await` đầu tiên**, nên hai lần bấm liền chỉ
  tốn một chu kỳ. Đang khoá thì trả `null`, không gửi request.
- `syncNow({full})` (`:415-418`): không có khoá, mọi lần gọi đều được nhận.

Khoá tính theo `Clock` được inject (`manualSyncLocked`,
`manualSyncCooldownLeft`, `:184-205`) và chỉ nằm trong bộ nhớ (`_pressedAt`,
`_pressRunning`, `:127-130`): không key settings nào, mở lại app là bấm được ngay.
Giờ bị chỉnh lùi về trước lúc bấm thì `manualSyncCooldownLeft` về 0 (`:202`), nên
phần khoá theo giờ không bao giờ quá 30 giây; phần "chu kỳ còn chạy" giữ nguyên.
Controller không giữ `Timer` cho khoá; listener được báo lúc nhận khoá và lúc chu
kỳ xong, nhưng không được báo lúc hết giờ.

## Ai gọi cái nào

- UI: `runSync` gọi `pressSyncNow` và im lặng khi nhận `null`
  (`clip_actions.dart:42-49`); menu ⚙ đi qua `runSync`
  (`home_page.dart:252`, `:259`). Mục menu đọc `manualSyncLocked` lúc dựng menu
  (`clip_actions.dart:75`); `_SyncButton` tự hẹn `Timer` theo
  `manualSyncCooldownLeft` để vẽ lại khi hết khoá (`clip_tabs.dart:284`, `:317-319`),
  và vẽ lại khi app resume (`:275-280`), vì `Timer` có thể không đếm lúc máy ngủ.
- Harness mô phỏng ngân sách gọi thẳng `syncNow(full: true)`
  (`sync_simulation_harness.dart:416-420`), và phần lớn test của controller cũng
  vậy. Vì thế bảng chi phí trong `docs/sync-server-triggers.md` không đổi khi
  thêm khoá.

## Quy tắc

- Mọi lối bấm mới của người dùng phải đi qua `pressSyncNow`, không gọi
  `syncNow` trực tiếp, nếu không sẽ lọt khoá.
- Trigger tự động và test/mô phỏng dùng `syncNow`; đừng thêm khoá vào `syncNow`,
  vì sẽ làm đổi kết quả mô phỏng và các test đang gọi nó liên tiếp.
- Test hành vi khoá nằm riêng ở `test/core/sync/presentation/manual_sync_cooldown_test.dart`.
