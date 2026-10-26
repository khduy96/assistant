# Đồng bộ: ngân sách request/tháng và phương án trigger trên Back4App

> Trạng thái phương án trigger: **đã loại bỏ** (cập nhật 23/10/2026, ghi lần đầu
> 19/10/2026).
>
> Lý do: trên Back4App, mỗi lần ghi một object có `afterSave` bị tính **ít nhất 2
> request** (1 API request + 1 Cloud Code request). Nếu trigger tự save thêm
> object khác (tăng `SyncMeta`, ghi `SyncTombstone`) thì còn bị tính nhiều hơn.
> Như vậy trigger làm chi phí tăng chứ không giảm. Kết luận này do người dùng tự
> tra, **chưa đo lại** trên dashboard (xem
> [Câu hỏi phải trả lời trước](#câu-hỏi-phải-trả-lời-trước)).
>
> Thay vào đó, client tự giữ số request trong một
> [ngân sách request/tháng do người dùng đặt](#ngân-sách-requesttháng-do-người-dùng-đặt).

## Hiện tại đang chạy thế nào

Code:

- `lib/core/sync/data/parse_sync_engine.dart`: một chu kỳ đẩy/kéo, đếm request
  và chặn theo ngân sách.
- `lib/core/sync/presentation/sync_controller.dart`: lúc nào thì chạy chu kỳ
  (timer, focus, thay đổi local, nút "Đồng bộ ngay").
- `lib/core/sync/domain/entities/sync_budget.dart`: ngân sách và mọi mốc suy ra
  từ nó.
- `lib/core/sync/presentation/sync_status_text.dart`: tooltip của nút đồng bộ.
- Test: `test/core/sync/fake_parse_server.dart` (Parse server giả, có chế độ
  in-memory) và `test/core/sync/simulation/` (mô phỏng 30 ngày với 3 máy).

Cách chạy:

- Mỗi space có một object `SyncMeta` giữ bộ đếm `rev_<Class>` cho từng class
  (`Clip`, `ClipGroup`, `TodoItem`, `NoteItem`).
- **Push:** đẩy các bản ghi `dirty`, rồi **client** gửi một PUT `Increment` lên
  `SyncMeta` cho những class vừa đổi. Server trả về giá trị mới. Nếu giá trị đó chỉ
  lớn hơn đúng 1 so với lần trước máy này thấy, máy này biết không có ai khác vừa
  ghi, nên không kéo lại chính dữ liệu mình vừa đẩy.
- **Chu kỳ chỉ-đẩy:** khi một thay đổi local tới hạn đẩy mà lượt kiểm server gần
  nhất chưa cách quá mốc R (xem bảng bên dưới), chu kỳ chỉ đẩy và tăng bộ đếm,
  không hỏi server có gì mới. Chu kỳ này không dời mốc R.
- **Pull:** đọc `SyncMeta` (1 request). Class nào có bộ đếm không đổi thì bỏ qua.
  Class nào đổi thì kéo theo một trong hai cách:
  - **Kéo một lượt:** class có dưới 500 bản ghi đã đồng bộ ở máy này
    (`onePassMaxRows`) được tải cả class trong một query. Các dòng mới hơn cursor
    là thay đổi, còn danh sách `localId` của cả class cho biết bản ghi nào đã bị
    máy khác xoá. Đổi lại, mỗi lần kéo tải lại cả những dòng máy đã có.
  - Class từ 500 bản ghi trở lên: query theo cursor `updatedAt`, rồi tải toàn bộ
    danh sách `localId` (`keys=localId`, 500 dòng mỗi request) để phát hiện bản
    ghi đã bị xoá.
- **Pull đầy đủ:** kéo mọi class bất kể bộ đếm, khi lần pull đầy đủ trước đã cũ
  hơn `fullPullEvery` (21 giờ ở ngân sách mặc định) hoặc khi bấm "Đồng bộ ngay".
  Đây là lưới an toàn cho máy chạy bản cũ không tăng bộ đếm, hoặc lần tăng bộ đếm
  bị lỗi.
- Lịch kích hoạt, ở mức bình thường: chạy một chu kỳ khi app khởi động; đẩy sau
  30 giây kể từ lần sửa cuối; pull khi focus/restore/resume app nếu lượt kiểm
  server gần nhất đã cách ít nhất R (14 phút ở mặc định). Timer dự phòng 2 giờ/lần
  chỉ chạy chu kỳ khi máy còn thay đổi chưa đẩy được.
- Clip tạm không được đồng bộ.

Hạn chế:

1. Máy chạy bản cũ đẩy dữ liệu mà không tăng bộ đếm. Máy khác chỉ thấy thay đổi đó
   ở lần pull đầy đủ: trễ tối đa 21 giờ ở mức bình thường, 84 giờ ở mức cảnh báo,
   và không tự tới khi máy đã hết phần ngân sách.
2. Class từ 500 bản ghi trở lên vẫn tốn thêm 1 request cho mỗi 500 bản ghi ở mọi
   lần pull class đó. Class nhỏ hơn thì tốn băng thông vì tải lại cả class.

## Ngân sách request/tháng do người dùng đặt

Đây là ngân sách **người dùng tự đặt** cho toàn bộ các máy trong một space, không
phải hạn mức của Back4App. Tài liệu này không dựa vào hạn mức thật của gói
Back4App nào.

### Nằm ở đâu và sửa thế nào

Trong `lib/core/sync/domain/entities/sync_budget.dart`:

- `userMonthlyRequestBudget = 10000`: số request mỗi tháng cho mọi máy trong
  space cộng lại.
- `expectedSyncDevices = 3`: số máy dùng chung ngân sách đó.

Muốn đổi thì sửa hai hằng số này rồi build lại. Không phải sửa chỗ nào khác: mọi
ngưỡng và khoảng thời gian bên dưới đều tính từ hai giá trị này, ngân sách lớn
hơn thì không khoảng nào dài hơn và không ngưỡng nào thấp hơn
(`test/core/sync/domain/sync_budget_test.dart`). Tìm `10000` trong `lib/` chỉ
thấy đúng chỗ này.

### Phần của mỗi máy và các ngưỡng

Các máy không báo cho nhau mình đã dùng bao nhiêu, nên mỗi máy tự giữ phần của
mình:

- **Phần của mỗi máy** = ngân sách / số máy = 10.000 / 3 = **3.333** request/tháng.
- **Ngưỡng cảnh báo** = 70% phần của máy = **2.333**.
- **Ngưỡng dừng** = 100% phần của máy = **3.333**.

Số request đã dùng được đếm theo tháng dương lịch trong key `sync_req_YYYY-MM`
của bảng `settings`. Mọi request đều được đếm, kể cả request lỗi và request của
lần đồng bộ tay. Sang tháng mới thì đếm lại từ 0.

Các mốc thời gian ở ngân sách mặc định:

| Mốc | Bình thường (< 2.333) | Cảnh báo (≥ 2.333) | Đã hết (≥ 3.333) |
|---|---|---|---|
| Đẩy sau lần sửa cuối | 30 giây | 2 phút | không tự đẩy |
| R: focus/resume kéo nếu lượt kiểm gần nhất đã cách | 14 phút | 56 phút | không tự kéo |
| Pull đầy đủ khi lần trước đã cũ hơn | 21 giờ | 84 giờ | không tự kéo |
| Timer dự phòng | 2 giờ | 8 giờ | 2 giờ, chỉ xem đã sang tháng chưa |

Cách tính (doc comment trong `sync_budget.dart`), với
`phần mỗi ngày = phần của máy / 31`:

- R = `720 / (0,5 × phần mỗi ngày)` phút, làm tròn lên: các lượt kiểm khi quay
  lại app, rải trên 720 phút dùng app mỗi ngày, tiêu tối đa một nửa phần mỗi ngày.
- Pull đầy đủ = `24 × 9 / (0,1 × phần mỗi ngày)` giờ, làm tròn lên: pull đầy đủ,
  coi như 9 request mỗi lần, tiêu tối đa 10% phần mỗi ngày.
- Đẩy sau 30 giây và timer dự phòng 2 giờ là mốc cố định ở mức bình thường.
- Ở mức cảnh báo, mọi khoảng dài gấp 4.

### Khi gần hết hoặc đã hết

- **Gần hết (từ 2.333):** sync tự động vẫn chạy nhưng thưa hơn (bảng trên).
  Tooltip nút đồng bộ có thêm dòng "Sắp hết ngân sách request tháng này nên sync
  tự động thưa hơn".
- **Đã hết (từ 3.333):**
  - Focus/resume, thay đổi local và timer không chạy chu kỳ tự động nào nữa, cả
    đẩy lẫn kéo, cho tới khi sang tháng.
  - Nếu chu kỳ tự động đang chạy dở mà chạm ngưỡng, engine dừng ngay trước request
    sẽ vượt ngưỡng. Phần chưa gửi vẫn nằm chờ: bản ghi vẫn `dirty`, lệnh xoá vẫn
    trong hàng chờ, lần tăng bộ đếm chưa gửi vẫn trong `sync_meta_bump_<space>`.
  - Nút đồng bộ đổi sang icon `sync_disabled_rounded` (không tô đỏ, vẫn bấm
    được). Tooltip ghi lý do: đã hết ngân sách request tháng này của máy này, sync
    tự động tạm dừng tới tháng sau, vẫn bấm để đồng bộ tay được.
  - **"Đồng bộ ngay" vẫn chạy đủ một chu kỳ** (kèm pull đầy đủ) và vẫn được đếm.
  - Thay đổi làm trong lúc này được đẩy ở lần sync kế tiếp được phép: lần bấm tay,
    hoặc trigger đầu tiên của tháng sau (focus, sửa, hoặc tick dự phòng, chậm nhất
    2 giờ sau khi sang tháng).

Ở mọi mức, khi đã đọc được số đếm, tooltip hiện
`x / 3333 request tháng này (máy này)`.

### Ước tính chi phí

Số đo từ mô phỏng `test/core/sync/simulation/sync_budget_simulation_test.dart`:
3 máy, 30 ngày (1–30/10/2026), engine và controller thật, Parse server giả
in-memory. Đây là số request mà app gửi đi trong mô phỏng, chưa đối chiếu với
dashboard Back4App.

Workload thường: 20 lượt sửa/ngày cho cả space, 20 lần focus/máy/ngày, 1 lần
bấm "Đồng bộ ngay"/máy/ngày, mỗi class khởi đầu 150 bản ghi.

| Máy | Tổng tháng | Mỗi ngày | Tự động | Bấm tay | % phần của máy |
|---|---|---|---|---|---|
| Máy 1 | 1.875 | 62,5 | 1.725 | 150 | 56,3% |
| Máy 2 | 1.837 | 61,2 | 1.687 | 150 | 55,1% |
| Máy 3 | 1.784 | 59,5 | 1.634 | 150 | 53,5% |
| **Cả 3 máy** | **5.496** | 183,2 | | | **55,0% ngân sách** |

Không máy nào chạm ngưỡng cảnh báo 2.333. Thay đổi local lên server chậm nhất
30 giây sau lần sửa cuối.

Workload nặng: 100 lượt sửa/ngày, 200 lần focus/máy/ngày, cùng số lần bấm tay.
Cả 3 máy chạm ngưỡng cảnh báo vào ngày 11 và hết phần vào ngày 18. Request của
các chu kỳ tự động trên mỗi máy không vượt 3.333 (cao nhất 3.248). Tổng cả tháng
khoảng 12.700 (127%), phần vượt là request bấm tay, vốn không bị chặn. Dữ liệu
vẫn hội tụ sau khi các máy đồng bộ tay.

## Phương án trigger (đã loại)

Phần dưới đây giữ lại để biết vì sao không làm.

### Đề xuất (đã loại)

1. **Trigger `afterSave` / `afterDelete`** trên `Clip`, `ClipGroup`, `TodoItem`,
   `NoteItem` tự tăng `rev_<Class>` trong `SyncMeta` của space tương ứng. Client
   không gửi PUT bộ đếm nữa.
2. **`afterDelete` ghi tombstone** `{space, className, localId, deletedAt}` vào một
   class chung, ví dụ `SyncTombstone`. Khi pull, chỉ đọc tombstone mới hơn cursor
   thay vì tải toàn bộ danh sách id.
3. Client vẫn quyết định **push dựa trên cờ `dirty`**. Không thêm bảng thời gian ở
   local.

Đã loại vì mỗi lần ghi có trigger bị tính ít nhất 2 request, và cả hai trigger
đều tự save thêm object khác. Mọi thay đổi phía server (Cloud Code, class
`SyncTombstone`, Cloud Job dọn dẹp) đều không làm.

### Những cách làm đã cân nhắc và loại bỏ

- **So thời gian "bên nào mới hơn thì lấy bên đó".** Hai máy có thể cùng có thay
  đổi trong một lúc, ví dụ máy A sửa khi offline còn máy B đã đẩy lên. Chọn một
  chiều sẽ làm mất thay đổi của bên kia. Push và pull phải là hai quyết định độc lập.
- **So đồng hồ của máy với đồng hồ server.** Đồng hồ trên máy có thể lệch. Giá trị
  từ server chỉ dùng như một mã phiên bản, và chỉ so với giá trị server mà máy này
  đã thấy lần trước.
- **Dùng thời gian làm mã phiên bản.** Hai lần ghi trong cùng một mili giây sẽ cho
  ra cùng giá trị, khiến máy khác bỏ sót. Nên dùng bộ đếm `Increment`.

### So sánh

Chi phí cho từng thao tác (số request). Cột "Hiện tại" tính theo code của
`parse_sync_engine.dart`, với `SyncMeta` đã biết `objectId`. Cột "Trigger" dùng
kết luận ở [câu hỏi 1](#câu-hỏi-phải-trả-lời-trước): mỗi lần ghi có trigger tính
ít nhất 2 request, chưa kể các lần trigger tự save object khác.

| Thao tác | Hiện tại | Trigger (đã loại) |
|---|---|---|
| Kiểm tra khi không có thay đổi | 1 | 1 |
| Push N bản ghi, chu kỳ chỉ-đẩy | N + 1 | 2N trở lên, cộng thêm các lần trigger save `SyncMeta` / `SyncTombstone` |
| Push N bản ghi, có kiểm server | N + 2 | 2N + 1 trở lên, như trên |
| Pull `Clip` + `ClipGroup` (dưới 500 dòng mỗi class) | 3 | 4 |
| Pull `Clip` + `ClipGroup` (~3.000 clip) | khoảng 9–10 | 4 |
| Pull đầy đủ (4 class dưới 500 dòng), mỗi máy | 5, mỗi 21 giờ | 0 |

Với dữ liệu ít (trường hợp hiện tại), kéo một lượt đã rẻ hơn đọc tombstone, còn
trigger làm mọi lần ghi đắt gấp đôi trở lên. Trigger chỉ có lợi ở phần pull khi
một class có hàng nghìn bản ghi.

Ngoài số request:

| | Hiện tại | Trigger (đã loại) |
|---|---|---|
| Máy chạy bản cũ | Trễ tới lần pull đầy đủ (21 giờ ở mức bình thường) | Không bị ảnh hưởng |
| PUT bộ đếm lỗi sau khi push | Thử lại ở lần sync sau | Không xảy ra |
| Trigger lỗi | Không áp dụng | Bộ đếm không tăng mà không có lỗi nào báo về client |
| Tombstone tích tụ | Không áp dụng | Phải dọn định kỳ |
| Nơi chứa logic | Chỉ trong app | App + Cloud Code |

### Khi nào nên làm (đã loại)

Không còn điều kiện nào để làm phương án trigger. Việc giữ chi phí trong giới hạn
nay do [ngân sách request/tháng](#ngân-sách-requesttháng-do-người-dùng-đặt) đảm
nhận. Chỉ nên xem lại khi một trong hai điều sau xảy ra:

- Đo trên dashboard cho thấy kết luận ở câu hỏi 1 sai (trigger không bị tính).
- Một class lên tới hàng nghìn bản ghi và request đối chiếu xoá chiếm phần lớn
  ngân sách. Khi đó cân nhắc trước các cách chỉ sửa client.

### Câu hỏi phải trả lời trước

1. **Trigger có bị Back4App tính là request không?** **Có.** Một lần ghi object
   có `afterSave` bị tính ít nhất 2 request: 1 API request cho lần ghi và 1 Cloud
   Code request cho trigger. Nếu trigger tự save object khác (ví dụ tăng
   `SyncMeta` hay ghi `SyncTombstone` qua `Parse.Object.save`) thì còn bị tính
   thêm. Đây là kết luận người dùng tự tra (23/10/2026), **chưa đo lại** trên
   dashboard. Cách đo nếu cần: deploy một `afterSave` đơn giản trên một class thử,
   ghi 10 lần, rồi xem số request trên dashboard tăng 10 hay 20; đo thêm trường
   hợp trigger ghi sang class khác.
2. ~~Tài khoản có quyền deploy Cloud Code (`main.js`) lên app Back4App này
   không?~~ Không cần trả lời nữa vì đã loại phương án.
3. ~~Giữ tombstone trong bao lâu, và dọn bằng cách nào?~~ Không cần trả lời nữa
   vì đã loại phương án.

### Các bước khi làm (đã loại)

Giữ lại để tham khảo, đường dẫn đã sửa theo cấu trúc hiện tại. Bước 1 đã có câu
trả lời: trigger bị tính 2 request trở lên cho mỗi lần ghi, nên dừng ở đây.

1. Đo theo câu hỏi 1. Nếu trigger bị tính **2 request trở lên** cho mỗi lần ghi
   thì cân nhắc lại.
2. Viết Cloud Code:
   - `afterSave` / `afterDelete` cho 4 class: tăng `rev_<Class>` bằng `increment()`
     (atomic). Không đọc giá trị ra, sửa rồi ghi lại, vì sẽ sai khi hai lần ghi
     chạy song song.
   - `afterDelete`: ghi thêm `SyncTombstone`.
   - Tìm `SyncMeta` theo `space`, lấy object cũ nhất (giống `_findMeta` ở client).
3. Client (`lib/core/sync/data/parse_sync_engine.dart`):
   - Bỏ `_bumpMeta`, `_queueBump` và key `sync_meta_bump_*`.
   - Thay `_reconcile` bằng việc đọc `SyncTombstone` theo cursor riêng. Có thể
     đọc chung một lần cho mọi class.
   - Bỏ pull đầy đủ định kỳ, nhưng **vẫn đối chiếu đầy đủ** khi máy offline lâu
     hơn thời gian giữ tombstone (lưu thời điểm pull gần nhất để biết).
   - Giữ lại phần "không kéo lại thứ chính máy này vừa đẩy". Cách làm: sau khi
     push, đọc `SyncMeta`; nếu bộ đếm chỉ tăng đúng bằng số lần ghi của chính máy
     này thì bỏ qua pull class đó.
4. Test: `test/core/sync/fake_parse_server.dart` cần giả lập trigger (tự tăng
   `rev_*` và ghi tombstone khi nhận POST/PUT/DELETE trên 4 class).

### Phương án ở giữa (đã loại)

Client tự ghi `SyncTombstone` mỗi khi xoá (thêm 1 request cho mỗi lần xoá) và đọc
tombstone thay cho việc tải toàn bộ id. Máy chạy bản cũ không ghi tombstone, nên
vẫn phải giữ pull đầy đủ định kỳ.

Đã loại vì phải thêm một class Parse mới, và với dữ liệu dưới 500 bản ghi mỗi
class thì kéo một lượt đã bỏ được request đối chiếu xoá mà không cần tombstone.
