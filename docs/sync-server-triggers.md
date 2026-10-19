# Đồng bộ: chuyển bộ đếm thay đổi sang trigger trên Back4App

> Trạng thái: **để dành, chưa làm** (ghi lại ngày 19/10/2026).
> Làm khi gặp một trong các điều kiện ở mục [Khi nào nên làm](#khi-nào-nên-làm).

## Hiện tại đang chạy thế nào

Code: `lib/clipboard/sync/sync_service.dart`, `lib/clipboard/state/clipboard_store.dart`.

- Mỗi space có một object `SyncMeta` giữ bộ đếm `rev_<Class>` cho từng class
  (`Clip`, `ClipGroup`, `TodoItem`, `NoteItem`).
- **Push:** đẩy các bản ghi `dirty`, rồi **client** gửi một PUT `Increment` lên
  `SyncMeta` cho những class vừa đổi. Server trả về giá trị mới. Nếu giá trị đó chỉ
  lớn hơn đúng 1 so với lần trước máy này thấy, máy này biết không có ai khác vừa
  ghi, nên không kéo lại chính dữ liệu mình vừa đẩy.
- **Pull:** đọc `SyncMeta` (1 request). Class nào có bộ đếm không đổi thì bỏ qua.
  Class nào đổi thì query theo cursor `updatedAt`, rồi **tải toàn bộ danh sách
  `localId`** (`keys=localId`) để phát hiện bản ghi đã bị máy khác xoá.
- Cứ 24 giờ, hoặc khi bấm "Đồng bộ ngay", pull đầy đủ mọi class, phòng trường hợp
  có máy chạy bản cũ không tăng bộ đếm.
- Lịch kích hoạt: đẩy sau 30 giây kể từ lần sửa cuối, pull khi focus app (nếu lần
  sync trước đã cách hơn 10 phút). Timer 2 giờ/lần chỉ chạy khi máy còn thay đổi
  chưa đẩy được.
- Clip tạm không được đồng bộ.

Hạn chế:

1. Máy chạy bản cũ đẩy dữ liệu mà không tăng bộ đếm. Máy khác chỉ thấy thay đổi đó
   ở lần pull đầy đủ, tức là trễ tối đa 24 giờ.
2. Bước đối chiếu xoá tốn thêm 1 request cho mỗi 500 bản ghi của class, **ở mọi lần
   pull class đó**. Dữ liệu càng nhiều thì càng tốn.

## Đề xuất

1. **Trigger `afterSave` / `afterDelete`** trên `Clip`, `ClipGroup`, `TodoItem`,
   `NoteItem` tự tăng `rev_<Class>` trong `SyncMeta` của space tương ứng. Client
   không gửi PUT bộ đếm nữa.
2. **`afterDelete` ghi tombstone** `{space, className, localId, deletedAt}` vào một
   class chung, ví dụ `SyncTombstone`. Khi pull, chỉ đọc tombstone mới hơn cursor
   thay vì tải toàn bộ danh sách id.
3. Client vẫn quyết định **push dựa trên cờ `dirty`**. Không thêm bảng thời gian ở
   local.

### Những cách làm đã cân nhắc và loại bỏ

- **So thời gian "bên nào mới hơn thì lấy bên đó".** Hai máy có thể cùng có thay
  đổi trong một lúc, ví dụ máy A sửa khi offline còn máy B đã đẩy lên. Chọn một
  chiều sẽ làm mất thay đổi của bên kia. Push và pull phải là hai quyết định độc lập.
- **So đồng hồ của máy với đồng hồ server.** Đồng hồ trên máy có thể lệch. Giá trị
  từ server chỉ dùng như một mã phiên bản, và chỉ so với giá trị server mà máy này
  đã thấy lần trước.
- **Dùng thời gian làm mã phiên bản.** Hai lần ghi trong cùng một mili giây sẽ cho
  ra cùng giá trị, khiến máy khác bỏ sót. Nên dùng bộ đếm `Increment`.

## So sánh

Chi phí cho từng thao tác (số request):

| Thao tác | Hiện tại | Trigger không bị tính | Trigger bị tính |
|---|---|---|---|
| Kiểm tra khi không có thay đổi | 1 | 1 | 1 |
| Push N bản ghi trong một lượt | N + 2 | N + 1 | 2N + 1 |
| Pull `Clip` + `ClipGroup` (dưới 500 dòng) | 5 | 4 | 4 |
| Pull `Clip` + `ClipGroup` (~3.000 dòng) | 10 | 4 | 4 |
| Pull đầy đủ 24 giờ/lần, mỗi máy | 9 trở lên | 0 | 0 |

Ước tính theo tháng. Giả định: 2 máy, 20 lần sửa mỗi ngày, mỗi máy khoảng 20 lần
focus app mỗi ngày.

| Lượng dữ liệu | Hiện tại | Trigger không bị tính | Trigger bị tính |
|---|---|---|---|
| Dưới 500 clip đã lưu | ~4.400 | ~3.200 (−28%) | ~3.800 (−14%) |
| ~3.000 clip đã lưu | ~5.700 | ~3.200 (−44%) | ~3.800 (−33%) |

Ngoài số request:

| | Hiện tại | Đề xuất |
|---|---|---|
| Máy chạy bản cũ | Trễ tối đa 24 giờ | Không bị ảnh hưởng |
| PUT bộ đếm lỗi sau khi push | Thử lại ở lần sync sau | Không xảy ra |
| Trigger lỗi | Không áp dụng | Bộ đếm không tăng mà không có lỗi nào báo về client |
| Tombstone tích tụ | Không áp dụng | Phải dọn định kỳ |
| Nơi chứa logic | Chỉ trong app | App + Cloud Code |

## Khi nào nên làm

Làm khi gặp một trong ba điều kiện:

- Bộ đếm request (rê chuột vào nút đồng bộ) cho thấy số dùng vượt khoảng
  **60–70% hạn mức tháng**. Kiểm tra hạn mức thật trên dashboard: các nguồn bên
  thứ ba ghi gói free là 25.000 request/tháng, nhưng chưa xác nhận được.
- Số clip đã lưu, todo hoặc ghi chú lên tới **hàng nghìn**.
- Thường xuyên có máy chạy bản cũ gây sai lệch dữ liệu.

## Câu hỏi phải trả lời trước

1. **Trigger có bị Back4App tính là request không?** Tài liệu của Back4App chỉ nói
   mọi lời gọi qua SDK/REST và lời gọi cloud function đều bị tính, không nói gì về
   `afterSave`. Cách đo: deploy một `afterSave` đơn giản trên một class thử, ghi 10
   lần, rồi xem số request trên dashboard tăng 10 hay 20. Nên đo cả trường hợp
   trigger ghi sang class khác qua `Parse.Object.save` trong Cloud Code.
2. Tài khoản có quyền deploy Cloud Code (`main.js`) lên app Back4App này không?
3. Giữ tombstone trong bao lâu (ví dụ 30 ngày), và dọn bằng cách nào: Cloud Job
   (xem job có bị tính request không) hay dọn ngay trong trigger.

## Các bước khi làm

1. Đo theo câu hỏi 1. Nếu trigger bị tính **2 request trở lên** cho mỗi lần ghi
   thì cân nhắc lại.
2. Viết Cloud Code:
   - `afterSave` / `afterDelete` cho 4 class: tăng `rev_<Class>` bằng `increment()`
     (atomic). Không đọc giá trị ra, sửa rồi ghi lại, vì sẽ sai khi hai lần ghi
     chạy song song.
   - `afterDelete`: ghi thêm `SyncTombstone`.
   - Tìm `SyncMeta` theo `space`, lấy object cũ nhất (giống `_findMeta` ở client).
3. Client (`sync_service.dart`):
   - Bỏ `_bumpMeta` và các key `sync_meta_bump_*`.
   - Thay `_reconcileDeletes` / `_reconcileCollection` bằng việc đọc
     `SyncTombstone` theo cursor riêng. Có thể đọc chung một lần cho mọi class.
   - Bỏ pull đầy đủ 24 giờ/lần, nhưng **vẫn đối chiếu đầy đủ** khi máy offline lâu
     hơn thời gian giữ tombstone (lưu thời điểm pull gần nhất để biết).
   - Giữ lại phần "không kéo lại thứ chính máy này vừa đẩy". Cách làm: sau khi
     push, đọc `SyncMeta`; nếu bộ đếm chỉ tăng đúng bằng số lần ghi của chính máy
     này thì bỏ qua pull class đó. Logic này phức tạp hơn hiện tại; nếu không đáng
     thì chấp nhận kéo lại.
4. Test: `test/clipboard/fake_parse_server.dart` cần giả lập trigger (tự tăng
   `rev_*` và ghi tombstone khi nhận POST/PUT/DELETE trên 4 class).

## Phương án ở giữa (không cần Cloud Code)

Client tự ghi `SyncTombstone` mỗi khi xoá (thêm 1 request cho mỗi lần xoá) và đọc
tombstone thay cho việc tải toàn bộ id. Cách này lấy được phần lợi lớn nhất khi dữ
liệu nhiều. Đổi lại, máy chạy bản cũ không ghi tombstone, nên **vẫn phải giữ** pull
đầy đủ 24 giờ/lần.
