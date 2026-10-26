# Knowledge index

## Data và lưu trữ

- [Repository giữ thay đổi trong bộ nhớ khi ghi file lỗi](repository-failed-write-semantics.md): todos/notes/reminders không hoàn tác khi ghi lỗi; luồng cần chắc chắn tự xử lý, đừng đổi repository

## Todos và reminders

- [Liên kết todo -> deadline và chiều ngược qua port LinkedTodos](todo-deadline-link.md): chỉ lưu Todo.reminderId; chiều ngược qua port + bridge gọi use case vì TodosController là factory; markDone trả MarkDoneResult

## Sync

- [SyncController - yêu cầu đến giữa chu kỳ được ghi theo loại](sync-controller-mid-cycle-requests.md): _pushAgain, _resumeAgain, _manualAgain, _current thay cho một cờ bool; bấm tay ghép vào lượt full đang chạy
- [pressSyncNow là lối vào của người bấm, syncNow không có khoá](sync-now-press-cooldown.md): khoá 30 giây theo Clock, chỉ trong bộ nhớ; harness và test gọi syncNow trực tiếp
- [Bảng settings giữ cả state của engine lẫn lựa chọn sync_auto của máy](sync-auto-choice-and-settings-table.md): lựa chọn đã lưu thắng PARSE_AUTO_SYNC; đọc lỗi thì tắt và không ghi đè; reset engine không được xoá sync_auto
