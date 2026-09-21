# Nhắc việc (event_notice)

App báo thức / nhắc lịch họp cho Windows desktop, viết bằng Flutter.
Sinh ra để giải quyết đúng một vấn đề: đang làm việc quên mất giờ và vào họp trễ.

## Cách hoạt động

- Mỗi giây app kiểm tra danh sách nhắc nhở. Tới giờ, cửa sổ co lại thành popup
  520x480, ghim **always-on-top**, hiện **đồng hồ chạy realtime**, kèm chuông lặp.
- Tắt chuông bằng nút **Tắt chuông**, hoãn bằng **Báo lại N phút**, hoặc đóng cửa
  sổ (X) — đóng cũng là tắt chuông.
- Đóng cửa sổ chính (X) khi không có chuông thì app **thu nhỏ xuống khay hệ thống**
  và vẫn canh giờ. Chuột trái vào icon khay để mở lại, chuột phải để **Thoát hẳn**.
- Bật **Tự mở khi khởi động Windows** trong menu ⚙ để app tự chạy nền mỗi lần bật máy
  (ghi vào `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, chạy kèm cờ
  `--minimized` nên không bung cửa sổ lúc boot).

## Kiểu lịch

| Kiểu | Ví dụ |
|---|---|
| Một lần | 14:00 ngày 14/09 họp khách hàng |
| Hàng ngày | 9:00 mỗi ngày daily standup |
| Hàng tuần | 14:00 các thứ 2, 5 |

Ngoài ra mỗi nhắc nhở có thể **lặp lại trong ngày**: bật "Lặp lại trong ngày",
chọn **Nhắc lại mỗi** (30 phút / 1 / 1,5 / 2 / 3 / 4 giờ) và **Dừng lúc**. Ví dụ
10:00, mỗi 2 giờ, dừng lúc 22:00 sẽ báo 10:00, 12:00, 14:00, 16:00, 18:00, 20:00,
22:00 rồi nghỉ tới 10:00 hôm sau.

Mỗi nhắc nhở còn có **Nhắc trước** (0/5/10/15/30 phút — báo thêm một lần trước giờ
để kịp chuẩn bị) và **Báo lại sau** (thời gian snooze).

Nếu máy tắt/đóng app đúng lúc tới giờ, khi mở lại app vẫn báo bù nếu trễ dưới 30 phút
(`ReminderStore.catchUpWindow`).

## Đếm ngược deadline

Tab **Deadline** dành cho những việc có hạn chót cố định. Mỗi deadline hiển thị
đồng hồ đếm ngược sống ("2 ngày 03:22:44") kèm thanh tiến độ tính từ lúc tạo tới
hạn, đổi màu theo mức gấp: xanh khi còn trên 1 ngày, cam khi dưới 24 giờ, đỏ và
ghi "QUÁ HẠN" khi đã trễ. Danh sách tự xếp deadline gần nhất lên đầu.

Deadline vẫn là một mục trong cùng hệ thống báo giờ: tới hạn nó rung chuông như
nhắc nhở thường, và có thể đặt **Báo trước hạn** (mặc định 1 giờ). Khác biệt duy
nhất là nó không lặp lại — một hạn chót chỉ tới một lần.

Trên Windows, rê chuột vào icon khay sẽ thấy deadline gần nhất còn bao lâu.

## Truyền tệp ngang hàng (tab "Gửi tệp")

Chuyển tệp giữa điện thoại và máy tính **không qua internet, không qua Back4App**:
hai máy nói chuyện thẳng với nhau trong cùng mạng Wi-Fi/LAN.

- **Tự tìm nhau**: mỗi 3 giây app hét một gói JSON nhỏ tới `255.255.255.255:45699`
  (tên máy, id, cổng HTTP), gửi riêng qua từng card mạng của máy. Dùng broadcast
  "hạn cục bộ" chứ không phải `x.y.z.255` vì Dart không cho biết mặt nạ mạng —
  đoán /24 sẽ trượt trên mạng /22 hay /16. Máy nào nghe được thì hiện trong danh
  sách và **chào lại riêng (unicast)** để hai bên thấy nhau ngay; nhờ vậy điện
  thoại Android vẫn được tìm thấy dù Wi-Fi của máy có lọc gói broadcast. Thiết bị
  im lặng quá 15 giây là tự biến mất khỏi danh sách.
- **Truyền**: mỗi máy mở một HTTP server nhỏ ở cổng `45700` (kẹt thì thử 45701…).
  Gửi tệp là một `POST /upload`, thân request chính là nội dung tệp — chảy thành
  luồng chứ không nạp cả tệp vào RAM, nên gửi file vài GB cũng được.
- **Phải bấm "Nhận"**: tệp lạ gõ cửa thì hiện thẻ hỏi kèm tên máy gửi và dung
  lượng; không trả lời trong 90 giây là tự từ chối. Bật "Tự nhận, không hỏi"
  trong menu ⋮ nếu tin mạng nhà.
- Ghi ra `.part` rồi mới đổi tên, trùng tên thì thành `tên (1).ext` — không bao
  giờ đè tệp cũ. Huỷ giữa chừng thì phần đã ghi bị xoá.
- Nơi lưu: Windows/macOS/Linux vào `Downloads\Trợ lý` (đổi được trong menu ⋮).
  Android ghi tạm vào thư mục riêng của app rồi **chuyển tiếp ra
  `Download/Trợ lý` bằng MediaStore** — app Files và mọi trình quản lý tệp đều
  thấy, và không phải xin quyền bộ nhớ nào. Lý do phải làm vậy: từ Android 11
  Google chặn đường `Android/data/<gói>` khỏi app Files, để tệp nằm đó thì
  người dùng không lấy ra được. Android 9 trở xuống không có MediaStore kiểu
  này nên tệp vẫn nằm trong thư mục riêng của app.
- Nút 📂 cạnh dòng "Tệp nhận được lưu ở" mở thư mục đó (desktop) hoặc màn hình
  Tải xuống của hệ thống (Android); mỗi lượt nhận xong còn có nút mở thẳng tệp.

Cần cả hai máy **cùng một mạng** và Wi-Fi đó **không bật AP isolation**. Lần đầu
chạy trên Windows, Firewall sẽ hỏi — phải cho phép ở mạng Private, không thì máy
khác không gửi vào được.

### Khi mạng chặn gói dò tìm

Mạng công ty, mạng campus và Wi-Fi khách thường chặn gói broadcast giữa các máy,
nên hai bên không tự thấy nhau dù vẫn gọi nhau được. Hai lối thoát trong tab:

- Nút 🔄 **Tìm lại** ngoài việc quảng bá còn **chào riêng từng địa chỉ** trong dải
  /24 của máy (254 gói unicast) — qua được phần lớn kiểu chặn broadcast.
- Nút 🔗 **Thêm thiết bị bằng IP**: gõ địa chỉ đọc được trên thẻ trạng thái của máy
  kia (thêm `:cổng` nếu khác 45700). App gọi `GET /info` để xác nhận, rồi giữ mục
  đó trong danh sách và tự hỏi lại mỗi 15 giây. Danh sách này được lưu lại.

## Chạy và build

```bash
flutter run -d windows          # chạy thử
flutter build windows --release # bản cài: build\windows\x64\runner\Release\event_notice.exe
flutter test                    # test logic lịch báo
```

Lưu ý: bật tự khởi động sẽ đăng ký **đúng file exe đang chạy**. Nên bật ở bản
Release đã copy về chỗ cố định, đừng bật lúc chạy `flutter run` (exe debug nằm trong
thư mục build, xoá đi là entry hỏng).

## Cấu trúc

- `lib/models/reminder.dart` — model + toàn bộ logic tính lần báo kế tiếp
- `lib/services/reminder_store.dart` — bộ đếm giờ 1 giây, hàng đợi chuông, lưu trữ
- `lib/services/alarm_sound.dart` — phát chuông lặp qua `PlaySound` (winmm) bằng FFI
- `lib/services/startup_service.dart` — bật/tắt tự khởi động cùng Windows
- `lib/ui/alarm_screen.dart` — popup báo thức có đồng hồ
- `lib/ui/home_page.dart`, `lib/ui/reminder_editor.dart` — danh sách và form tạo/sửa
- `lib/p2p/services/discovery_service.dart` — dò thiết bị trong LAN bằng UDP broadcast
- `lib/p2p/services/file_server.dart`, `file_sender.dart` — hai đầu của đường truyền HTTP
- `lib/p2p/state/p2p_store.dart`, `lib/p2p/ui/p2p_tab.dart` — trạng thái và tab "Gửi tệp"
- `tool/gen_assets.dart` — sinh `assets/sounds/alarm.wav` (chạy: `dart run tool/gen_assets.dart`)
- `tool/gen_logo.dart` — sinh toàn bộ icon app từ logo (chạy: `flutter test tool/gen_logo.dart`)

Dữ liệu lưu tại `%APPDATA%\com.example\event_notice\reminders.json`.

## Android

Cùng một codebase, nhưng cơ chế báo khác hẳn desktop: trên điện thoại app thường
không chạy nền, nên **hệ điều hành giữ lịch chuông** chứ không phải Dart timer.

- Mỗi lần lưu/sửa nhắc nhở (và mỗi lần mở lại app), app nạp tối đa 48 lần báo gần
  nhất vào `AlarmManager` qua `flutter_local_notifications`, dùng
  `exactAllowWhileIdle` nên vẫn đúng giờ khi máy đang Doze.
- App chạy **foreground service** (`flutter_foreground_task`) với thông báo thường
  trực "Nhắc việc đang canh giờ — lần báo kế tiếp: ...", giữ tiến trình sống và tự
  bật lại sau khi khởi động máy. Vai trò giống icon khay trên Windows.
- Thông báo chuông dùng kênh riêng phát **đúng file `assets/sounds/alarm.wav`**
  (đóng gói ở `res/raw/alarm.wav`) theo luồng âm lượng báo thức, cờ `FLAG_INSISTENT`
  (kêu lặp tới khi xử lý) và `fullScreenIntent` — màn hình khoá bung thẳng giao diện
  báo thức có đồng hồ như bản desktop.
- Bấm vào thông báo mở app kèm payload `reminderId|thời điểm|isLead`, app dựng lại
  đúng lần báo đó và hiện nút **Tắt chuông** / **Báo lại**. Khi full-screen intent tự
  mở app (không qua thao tác chạm) Android không truyền payload, nên app tra bảng
  `schedule_index.json` (id thông báo → payload) để biết chuông nào đang kêu.
- Sau khi khởi động lại máy, `ScheduledNotificationBootReceiver` đặt lại lịch.
- Lần đầu chạy app xin quyền thông báo và "Báo thức & nhắc nhở" (exact alarm).
  Xin lại bất cứ lúc nào ở menu ⚙ → **Cấp quyền thông báo & báo đúng giờ**.

```bash
flutter run -d <android-device>
flutter build apk --release
```

Lưu ý về pin: một số hãng (Xiaomi, Oppo, Vivo, Samsung) tắt báo thức của app bị
"tối ưu pin". Nếu chuông không kêu, vào Cài đặt → Pin → bỏ tối ưu cho app này.

### Khác nhau giữa hai nền tảng

| | Windows | Android |
|---|---|---|
| Ai giữ lịch | Dart timer trong app (chạy nền ở khay) | AlarmManager của hệ thống |
| Giao diện báo | Cửa sổ popup always-on-top | Thông báo full-screen + màn hình báo thức |
| Chuông | `PlaySound` (winmm) lặp file WAV | Cùng file WAV qua kênh báo thức, lặp bằng `FLAG_INSISTENT` |
| Chạy nền | Thu nhỏ xuống khay hệ thống | Foreground service + thông báo thường trực |
| Tự chạy khi bật máy | Registry `Run` + cờ `--minimized` | Boot receiver + service tự bật lại |

## Logo

Logo là **vòng đếm ngược quanh mặt đồng hồ**: vành cam = thời gian còn lại trước
khi chuông reo, kim trắng đọc rõ ngay cả ở 16px trong khay hệ thống. Màu nền dùng
chính seed color của app (`#2563EB`), điểm nhấn hổ phách `#F59E0B`.

- Bản vector gốc: `assets/branding/logo.svg` (1024x1024)
- Bản PNG gốc: `assets/branding/logo.png`

Sửa logo bằng cách chỉnh `tool/gen_logo.dart` rồi chạy `flutter test tool/gen_logo.dart`
— lệnh này ghi lại toàn bộ icon (nhớ cập nhật `logo.svg` cho khớp):

| Đích | File |
|---|---|
| Khay hệ thống Windows | `assets/icons/tray.ico` (16→64px) |
| File .exe Windows | `windows/runner/resources/app_icon.ico` (16→256px) |
| Android launcher | `android/app/src/main/res/mipmap-*/ic_launcher.png` |
| Web / PWA | `web/favicon.png`, `web/icons/Icon-*.png` |

Ở 16–24px generator dùng biến thể `logoSmall` — bỏ vành mờ và làm dày kim, vì bản
đầy đủ bị nhoè ở kích thước đó. Bản `logoMaskable` (Android adaptive / PWA maskable)
tràn viền và thu hình vào vùng an toàn 78%.

Bộ ảnh kiểm tra ở mọi kích thước: `build/logo/sheet.png`.
