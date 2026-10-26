---
title: Liên kết todo -> deadline và chiều ngược qua port LinkedTodos
tags: [todos, reminders, architecture, di]
updated: 2026-10-26
sources:
  - lib/features/todos/domain/entities/todo.dart:46
  - lib/features/todos/todos_injection.dart:51-59
  - lib/app/di/bridges/linked_reminder_bridge.dart
  - lib/app/di/bridges/todo_reminder_editor_bridge.dart
  - docs/architecture.md (mục 2 "Quy tắc phụ thuộc", mục 8.4)
  - event_notice-deadline worktree, branch feat/deadline-done: lib/features/reminders/domain/ports/linked_todos.dart:1-17
  - event_notice-deadline worktree, branch feat/deadline-done: lib/app/di/bridges/linked_todos_bridge.dart:6-27
  - event_notice-deadline worktree, branch feat/deadline-done: lib/app/di/injection.dart:120-136
  - event_notice-deadline worktree, branch feat/deadline-done: lib/features/todos/domain/usecases/find_open_todos_linked_to.dart:7-23
  - event_notice-deadline worktree, branch feat/deadline-done: lib/features/reminders/presentation/reminders_controller.dart:37-48
  - event_notice-deadline worktree, branch feat/deadline-done: lib/features/reminders/presentation/reminders_controller.dart:268-306
  - event_notice-deadline worktree, branch feat/deadline-done: lib/features/reminders/presentation/pages/reminders_tab.dart:111-118
  - lib/features/reminders/data/repositories/reminder_repository_impl.dart:10-15
  - .ai-runs/20261024-1759-feature-deadline-done-action
  - .ai-runs/20261026-1356-builders-deadline-minors/deadline-minors.handoff.yaml
---

# Liên kết todo -> deadline và chiều ngược qua port `LinkedTodos`

**Sự thật:** liên kết chỉ được lưu **một chiều**, ở `Todo.reminderId`
(`lib/features/todos/domain/entities/todo.dart:46`). Entity của reminders không
có trường nào trỏ về todo (không có chữ `todo` trong
`lib/features/reminders/domain/entities/`). Muốn biết deadline nào có todo nào
thì phải quét danh sách todo theo `reminderId`.

## Hai chiều đi qua `app/di/bridges/`

Feature không được import lẫn nhau (`docs/architecture.md`, mục 2), nên mỗi chiều
là một port khai báo trong feature cần nó, và adapter ở `lib/app/di/bridges/`:

- **todos -> reminders** (có trên nhánh hiện tại): port `LinkedReminderRepository`
  và `TodoReminderEditor` của todos, adapter `linked_reminder_bridge.dart` và
  `todo_reminder_editor_bridge.dart` (chi tiết ở `docs/architecture.md` mục 8.4).
- **reminders -> todos** (nhánh `feat/deadline-done`, worktree
  `D:/Felix/flutter/event_notice-deadline`, chưa có trên `feat/sync-budget`
  lúc ghi): port `LinkedTodos` ở `lib/features/reminders/domain/ports/linked_todos.dart`
  (`openTitlesFor`, `completeFor`, không ném lỗi), adapter `LinkedTodosBridge`
  ở `lib/app/di/bridges/linked_todos_bridge.dart`, đăng ký trong
  `_registerReminderBridges` (`lib/app/di/injection.dart:120-136`). Phía todos
  cung cấp `FindOpenTodosLinkedTo` (lọc `!done && reminderId == id`) và
  `CompleteTodosLinkedTo`.

## Bridge gọi use case, không gọi `TodosController`

`TodosController` được đăng ký bằng `registerFactory`
(`lib/features/todos/todos_injection.dart:51-59`), tức mỗi màn hình có một bản
mới. Bridge lấy controller từ DI sẽ được một bản khác với bản đang hiện, nên
`LinkedTodosBridge` gọi thẳng use case của todos (doc của lớp,
`linked_todos_bridge.dart:6-11`). Danh sách todo trên màn hình tự cập nhật vì
controller lắng nghe `changes` của repository, và todo tick qua đường này được
đóng dấu thời gian, xếp hàng sync như tick tay.

Ngược lại, hai bridge todos -> reminders dùng `RemindersController` mà app shell
hiển thị, để chỉ có một hàng đợi alert và một lịch báo của hệ điều hành
(`injection.dart:120-122` trong worktree).

## Luồng "Đã thực hiện" trên deadline

`RemindersController.markDone` (worktree, `reminders_controller.dart:296-306`)
tick các todo liên kết **trước**, rồi mới xoá deadline qua `remove()`. Hàm trả
enum `MarkDoneResult` (`:37-48`) cho biết bước nào lỗi:

- `done`: đã tick todo và đã xoá deadline.
- `todosNotTicked`: tick lỗi, deadline được giữ để người dùng thử lại.
- `deadlineNotRemoved`: đã tick todo nhưng không lưu được việc xoá deadline.
  `remove()` trả `Future<bool>`, `false` khi xoá không lưu được (`:268-285`).

Tab deadline hiện SnackBar riêng cho từng trường hợp lỗi
(`reminders_tab.dart:111-118`). Với `deadlineNotRemoved`, câu chỉ nói "không lưu
được việc gỡ deadline", không hứa deadline còn đó: repository của reminders giữ
thay đổi trong bộ nhớ khi ghi lỗi (`reminder_repository_impl.dart:10-15`), nên
thẻ có thể biến mất dù file vẫn còn deadline (suy luận từ code, chưa chạy thử
với repository thật).

Vì repository của todos cũng giữ thay đổi trong bộ nhớ khi ghi lỗi,
`CompleteTodosLinkedTo` phải tự đặt lại todo khi lưu lỗi; xem
[repository-failed-write-semantics.md](repository-failed-write-semantics.md).
