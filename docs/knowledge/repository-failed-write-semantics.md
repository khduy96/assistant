---
title: Repository giữ thay đổi trong bộ nhớ khi ghi file lỗi
tags: [todos, notes, reminders, data, persistence]
updated: 2026-10-26
sources:
  - lib/features/todos/data/repositories/todo_repository_impl.dart:74-84
  - lib/features/todos/data/repositories/todo_repository_impl.dart:156-164
  - lib/features/todos/data/mappers/todo_mapper.dart:36
  - lib/features/notes/data/repositories/note_repository_impl.dart:150-158
  - lib/features/reminders/data/repositories/reminder_repository_impl.dart:10-15
  - lib/features/reminders/domain/repositories/reminder_repository.dart:4-8
  - lib/features/todos/domain/repositories/todo_repository.dart:4-23
  - lib/core/data/json_file_store.dart:66-107
  - .ai-runs/20261024-1759-feature-deadline-done-action (fix/1, fix/2)
  - lib/features/todos/data/sync/todo_sync_collection.dart:77-80
  - event_notice-deadline worktree, branch feat/deadline-done: lib/features/todos/domain/usecases/complete_todos_linked_to.dart:41-65
  - .ai-runs/20261026-1356-builders-deadline-minors/deadline-minors.handoff.yaml
---

# Repository giữ thay đổi trong bộ nhớ khi ghi file lỗi

**Sự thật:** `TodoRepositoryImpl`, `NoteRepositoryImpl` và `ReminderRepositoryImpl`
đổi danh sách trong bộ nhớ trước, rồi mới ghi file. Ghi file lỗi thì bộ nhớ
**vẫn giữ** thay đổi, listener vẫn được báo (`_persist` phát sự kiện trong
`finally`), và người gọi nhận `Err(StorageFailure)`. Lần ghi thành công kế tiếp
ghi cả danh sách, nên mang thay đổi đó xuống đĩa.

- Todos: `save()` sửa `_todos` rồi `await _persist(...)`
  (`todo_repository_impl.dart:74-84`); `_persist` phát `changes`/`localChanges`
  trong `finally` (`:156-164`). Mapper luôn đặt `dirty: true`
  (`todo_mapper.dart:36`), nên sync vẫn đẩy được thay đổi kể cả khi đĩa lỗi lâu.
- Notes: cùng khuôn (`note_repository_impl.dart:150-158`).
- Reminders: ghi rõ trên interface (`reminder_repository.dart:4-8`) và doc của
  lớp (`reminder_repository_impl.dart:10-15`): giữ bộ nhớ để alert đã xử lý
  không báo lại.
- Interface `TodoRepository` **không** ghi ngữ nghĩa này
  (`todo_repository.dart:4-23`); chỉ có doc của `_persist` (private).

## Quy tắc

Luồng nào cần chắc chắn thay đổi đã nằm trên đĩa thì **tự xử lý lỗi lưu ngay
trong luồng đó**. Không đổi hành vi chung của repository.

Ví dụ: "Đã thực hiện" trên deadline (AC11 của run deadline-done). Nếu tick todo
bị lỗi ghi mà bộ nhớ vẫn giữ `done = true`, lần thử lại sẽ không thấy todo nào
còn mở và gỡ deadline trong khi file vẫn ghi todo chưa xong.
`CompleteTodosLinkedTo._untick` (nhánh `feat/deadline-done`,
`complete_todos_linked_to.dart:41-65`) đọc lại bản trong bộ nhớ và đặt todo về
như cũ, nhưng **chỉ khi** bản đó khác bản gốc đúng ở `done`/`completedAt`/`updatedAt`,
để không xoá một bản sửa khác chen vào. Bản đặt lại được đóng dấu
`updatedAt = Clock.now()` (`:64`), không giữ `updatedAt` cũ. Đây là best effort:
lỗi ở bước này không thay lỗi gốc.

## Vì sao không đổi repository sang "hoàn tác khi ghi lỗi"

Vòng fix 1 của run deadline-done đã thử cho `TodoRepositoryImpl.save` hoàn tác
bộ nhớ khi ghi lỗi. Bước confirm tái hiện được việc **mất dữ liệu người dùng mà
không báo gì** (`.ai-runs/20261024-1759-feature-deadline-done-action/fix/1/fix-confirm.handoff.yaml`):

- Editor todo đóng trước khi gọi save, ô thêm nhanh xoá chữ trước khi gọi add;
  ghi lỗi thì nội dung vừa gõ biến mất, và không UI nào hiện
  `TodosController.failure`.
- `linkReminder` lỗi thì `reminderId` mất hẳn trong khi SnackBar vẫn báo "Đã tạo
  deadline", dễ tạo deadline trùng.
- Không còn bản `dirty` nào để sync đẩy lên.
- Sinh thêm các ca biên: hai lần save chồng nhau cùng lỗi, lần ghi lỗi lọt
  xuống đĩa qua lần ghi xếp sau (`JsonFileStore` dựng nội dung ngay lúc gọi và
  ghi tuần tự, `json_file_store.dart:66-107`), `save` và `deleteAll` xử lý lỗi khác nhau.

Vòng fix 2 hoàn nguyên repository và chuyển cách xử lý vào use case.

## Vì sao `_untick` đóng dấu `updatedAt` mới

Khi kéo về, bản local thắng nếu còn `dirty` hoặc có `updatedAt` mới hơn bản tới
(`todo_sync_collection.dart:77-80`). Bản đặt lại đi qua mapper nên luôn `dirty`
(`todo_mapper.dart:36`) và sẽ được đẩy lên. Nếu nó mang `updatedAt` cũ thì có
thể đè lên server một bản sửa mới hơn của máy khác, rồi máy kia, vốn thấy bản
của mình mới hơn, không bao giờ nhận lại bản này, và hai máy lệch nhau mãi. Đóng
dấu "sửa lúc này" khiến bản đặt lại được coi là lần sửa mới nhất, nên mọi máy
hội tụ về cùng một bản (doc của `_untick`, `complete_todos_linked_to.dart:41-51`;
run `20261026-1356-builders-deadline-minors`).

## Hệ quả còn lại (suy luận, chưa kiểm bằng test sync)

Sync vẫn tốn thêm một lần đẩy cho todo đã đặt lại. Nếu máy khác vừa sửa đúng todo
đó mà máy này chưa kéo về, bản đặt lại vẫn thắng vì có dấu mới hơn, nên bản sửa
kia bị thay. Bù lại, các máy không còn lệch nhau. Chỉ xảy ra khi ghi
`todos.json` lỗi đúng lúc bấm "Đã thực hiện".
