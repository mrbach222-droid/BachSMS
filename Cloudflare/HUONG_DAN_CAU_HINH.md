# Bách CRM → Bách SMS qua Cloudflare

Gói này dùng CRM **v1.4.14.45**, Bách SMS iPhone **v1.2.0** và Bách SMS Cloud Android **v1.2.0**. Hai thiết bị chỉ cần có Internet, có thể dùng khác Wi-Fi hoặc 4G/5G. Điện thoại có thể nhận sau khi PC đã chuyển thành công rồi tắt.

**Dịch vụ Cloudflare chưa được triển khai sẵn vào tài khoản của anh.** Làm phần A một lần, sau đó ghép PC/điện thoại theo phần B. Các bản CRM trước được giữ riêng.

## A. Tạo dịch vụ Cloudflare — thực hiện một lần

### 1. Chuẩn bị CRM và đăng nhập Cloudflare

- Giải nén toàn bộ gói vào một thư mục mới trên PC.
- Quản lý mở `Windows/CRM_1_Quan_Ly/BachCRMExcel.exe`; nhân viên mở `Windows/CRM_2_Nhan_Vien/BachCRMExcel.exe`.
- Giữ đủ **5 DLL** cạnh EXE: `BachCRMActivity.dll`, `BachCRMContactDate.dll`, `BachCRMCoverage.dll`, `BachCRMReportExport.dll`, `BachCRMCloud.dll`.
- Tiêu đề CRM phải hiện **v1.4.14.45 BÁCH SMS CLOUD**.
- Mở <https://dash.cloudflare.com/> và đăng nhập hoặc tạo tài khoản. Có thể bắt đầu thử bằng gói miễn phí trong hạn mức Cloudflare; không cần mua tên miền riêng cho URL `workers.dev`.

### 2. Tạo cơ sở dữ liệu D1

Trong bảng điều khiển Cloudflare, mở **Storage & databases → D1 SQL database → Create database**. Tên gợi ý: `bach-crm-sms`. Nếu menu khác tên, dùng ô tìm kiếm của Cloudflare để tìm **D1**.

Mở cơ sở dữ liệu vừa tạo → **Console**. Trên PC, mở `Cloudflare/schema.sql` bằng Notepad, sao chép toàn bộ nội dung, dán vào Console và chạy. Nếu Console chỉ cho chạy một câu lệnh mỗi lần, chạy lần lượt từng câu, phân cách bằng dấu `;`.

Kết quả cần có bốn bảng: `channels`, `batches`, `jobs`, `events`. Có thể kiểm tra bằng:

```sql
SELECT name FROM sqlite_master WHERE type='table';
```

### 3. Tạo Worker và dán mã dịch vụ

Mở **Workers & Pages → Create application → Create Worker** hoặc **Start with Hello World**, đặt tên gợi ý `bach-crm-sms`, rồi Deploy.

Mở Worker → **Edit code**. Mở `Cloudflare/worker.mjs` bằng Notepad, sao chép toàn bộ, thay hết nội dung Worker mẫu rồi bấm **Deploy**. Mã dùng dạng JavaScript module `export default`; không dán vào trang HTML hoặc Pages tĩnh.

Ghi lại URL Worker, ví dụ:

```text
https://bach-crm-sms.ten-tai-khoan.workers.dev
```

Đây là ví dụ, anh phải dùng URL Cloudflare cấp cho tài khoản của mình. Dùng URL triển khai chính thức, không dùng URL Preview.

### 4. Gắn D1 vào Worker

Trong Worker, mở **Bindings → Add binding → D1 database**:

| Ô cấu hình | Giá trị |
| --- | --- |
| Variable name / Binding name | `DB` — đúng hai chữ hoa |
| D1 database | Chọn `bach-crm-sms` đã tạo |

Lưu và Deploy. Nếu giao diện nằm trong **Settings → Bindings**, cấu hình tương tự.

### 5. Tạo khóa ADMIN_KEY

Trên CRM, bấm **CẤU HÌNH CLOUDFLARE / MÃ GHÉP** ở thanh mới trên cùng.

1. Nhập URL Worker vào ô đầu tiên.
2. Bấm **Tạo & sao chép khóa mới để đặt vào Cloudflare**. CRM tạo khóa ngẫu nhiên và sao chép vào clipboard. Giữ cửa sổ này đang mở.
3. Chuyển sang Cloudflare → Worker → **Settings → Variables and Secrets → Add**.
4. Chọn kiểu **Secret**, tên **`ADMIN_KEY`**, giá trị là khóa vừa sao chép.
5. Lưu/Deploy. Khóa có 64 ký tự; tối thiểu dịch vụ yêu cầu 32 ký tự.

Đây là khóa riêng của dịch vụ Bách CRM; **không lấy Global API Key hoặc API Token của tài khoản Cloudflare để điền vào đây**. Không cần gửi khóa vào cuộc trò chuyện hoặc đưa cho nhân viên dùng điện thoại.

Nếu anh đã có ADMIN_KEY cho dịch vụ này, nhập chính khóa đó trong CRM, không bấm tạo khóa mới để thay nhầm khóa đang dùng.

### 6. Đặt lịch dọn dữ liệu

Trong Worker, vào **Settings → Triggers / Cron Triggers → Add** và nhập:

```text
0 * * * *
```

Đây là lịch dọn mỗi giờ. Gói chưa được nhận hết hạn sau 24 giờ; khi hết hạn sẽ không tải được nữa và lần dọn kế tiếp xóa các trường cá nhân. Điện thoại xác nhận đã lưu thì dịch vụ xóa ngay các trường cá nhân trong bản chờ. Metadata mã gói/trạng thái được giữ tối đa khoảng 30 ngày để xử lý gửi lại và chống trùng. Bản sao khôi phục của nhà cung cấp có thời hạn riêng, không nên hiểu đây là xóa tức thì khỏi mọi bản sao lưu của Cloudflare.

### 7. Kiểm tra dịch vụ

Mở URL Worker và thêm `/health`, ví dụ:

```text
https://bach-crm-sms.ten-tai-khoan.workers.dev/health
```

Kết quả cần có:

```json
{"service":"BachCRM-BachSMS","version":"1.0.0","ready":true}
```

Nếu báo thiếu DB, kiểm tra bước 4. Nếu thiếu schema, kiểm tra bước 2. Nếu thiếu ADMIN_KEY, kiểm tra bước 5. Phải sửa các lỗi này trước khi chuyển khách.

## B. Ghép PC và điện thoại — thực hiện một lần cho mỗi người

### 8. Tạo kết nối trên CRM

Quay lại cửa sổ cấu hình CRM đang mở:

1. Kiểm tra URL Worker và ADMIN_KEY.
2. Nhập tên người dùng/thiết bị, ví dụ `Bách - Quản lý`.
3. Bấm **TẠO KẾT NỐI & LẤY MÃ CHO ĐIỆN THOẠI**.
4. Bấm **SAO CHÉP MÃ** trong cửa sổ mới. Mã bắt đầu bằng **`bachsms1.`** và khá dài; sao chép đủ cả chuỗi.

Mỗi PC/tài khoản Windows tạo một kết nối riêng. Khóa quản trị dùng lúc tạo kết nối; khóa thiết bị được CRM lưu có bảo vệ theo tài khoản Windows đang dùng. Sau này bấm **CẤU HÌNH CLOUDFLARE / MÃ GHÉP** để xem lại mã điện thoại.

Hai máy dùng cùng tài khoản Windows và dùng chung thư mục hồ sơ Windows sẽ dùng chung cấu hình này. Nếu một PC dùng cho nhiều nhân viên, nên dùng tài khoản Windows riêng cho từng người. Hai bản Quản lý/Nhân viên trên cùng một tài khoản Windows sử dụng cùng kết nối Cloudflare của tài khoản đó.

### 9. Cài Bách SMS trên iPhone hoặc Android

**iPhone:** Dùng `iPhone/BachSMS_v1.2.0_Cloudflare_unsigned.ipa`. IPA chưa ký, cần ký/cài bằng công cụ anh đang dùng, như các bản IPA trước. Giữ cùng tài khoản ký và cài cập nhật nếu muốn giữ dữ liệu ứng dụng cũ; không cần gỡ app cũ để thử.

Mở Bách SMS → **Kết nối Bách CRM**. Trong phần **Nhận khách qua Internet**, dán mã `bachsms1.…` → **Liên kết Cloudflare**. Sau khi liên kết, bấm **Nhận khách từ CRM**. Không nhập IP nội bộ, không cần Tailscale.

**Android:** Cài `Android/BachSMS_Android_v1.2.0_Cloudflare.apk`. Bản này tên **Bách SMS Cloud**, cài song song với Bách SMS Android cũ. Dán mã `bachsms1.…` vào ô mã, bấm **GHÉP CRM**, sau đó **TẢI KHÁCH TỪ CRM**. Địa chỉ Cloudflare được tự điền. Quyền gửi SMS chỉ cần khi anh chủ động dùng chức năng gửi tin.

Mã ghép là khóa nhận dữ liệu của đúng kết nối; gửi mã riêng đến điện thoại của mình, không đăng công khai. Cài lại hoặc ngắt ghép thì cần dán lại mã. Không cần ghép lại cho từng lần chuyển khách.

## C. Sử dụng hằng ngày

1. Trên CRM, mở file Excel quản lý như thường lệ.
2. Bấm **CHUYỂN SANG BÁCH SMS** ở thanh mới trên cùng, hoặc dùng mục cùng tên trong menu chuột phải của bảng khách.
3. Trong cửa sổ chọn khách, tích những dòng muốn chuyển. Ô tìm kiếm lọc theo CIF, tên, SĐT; **Chọn đang xem** tích toàn bộ dòng đang lọc; **Bỏ chọn** xóa lựa chọn.
4. Mỗi dòng là một CIF/số điện thoại. Nhiều hợp đồng cùng CIF/số điện thoại được gộp thành một dòng. Số cập nhật `NewPhone` hợp lệ được ưu tiên; không có thì dùng số khách hiện tại. Chỉ chuyển số di động Việt Nam hợp lệ.
5. Bấm **CHUYỂN KHÁCH**. Chờ CRM báo **Cloudflare đã nhận đủ khách**. Lúc đó có thể tắt PC.
6. Trên điện thoại, mở Bách SMS và bấm nhận khách. iPhone: tích các khách muốn dùng rồi bấm **Đưa … khách vào danh sách gửi**. Android: danh sách đã tải xuất hiện và được chọn sẵn để anh kiểm tra.
7. Nhập/chọn mẫu tin và kiểm tra người nhận trước khi dùng luồng gửi SMS có sẵn trong app.

Danh sách đã nhận được lưu trên điện thoại trước khi xác nhận với cloud. Vì vậy có thể tiếp tục xem/dùng khi mất mạng. Mỗi mã công việc được nhập một lần; bấm tải lại không nhân đôi cùng gói. Nếu chủ động chuyển cùng khách thành một gói mới trên CRM thì đó là lượt giao mới.

Cloudflare truyền danh sách; cách gửi SMS vẫn theo khả năng của thiết bị và ứng dụng. iPhone tiếp tục mở trình soạn SMS để anh kiểm tra và bấm gửi. Trên Android, luồng gửi có sẵn chỉ chạy sau thao tác xác nhận của anh.

## D. Nếu gặp lỗi

| Hiện tượng | Cách xử lý |
| --- | --- |
| CRM chưa có thanh Bách SMS | Kiểm tra đang mở đúng EXE v1.4.14.45 và có đủ 5 DLL trong cùng thư mục. |
| Worker báo thiếu `DB` | Gắn đúng D1 binding tên `DB`, rồi Deploy. |
| Worker báo thiếu bảng | Chạy đầy đủ `schema.sql`, kiểm tra đủ bốn bảng. |
| Lỗi khóa quản trị | ADMIN_KEY trong CRM phải trùng Secret của Worker; không có dấu cách thừa. |
| Điện thoại báo mã chưa hợp lệ | Sao chép lại nguyên chuỗi `bachsms1.…`; không nhập mã CRM LAN sáu ký tự vào phần Cloudflare. |
| PC báo không kết nối được / gửi dở | Giữ hàng chờ trên máy và bấm **THỬ GỬI LẠI**. Mã gói được giữ nguyên, không cần chọn và chuyển lại khách. |
| Không thấy khách mới trên điện thoại | Bấm nhận lại, kiểm tra PC đã báo chuyển đủ. Danh sách chưa nhận chỉ chờ 24 giờ. Kiểm tra đang dùng đúng mã của PC/người giao khách. |
| Điện thoại nhận được nhưng chưa ở danh sách gửi iPhone | Chọn khách trong màn hình CRM và bấm **Đưa … khách vào danh sách gửi**. |
| Mất Internet sau khi nhận | Danh sách lưu trên điện thoại vẫn còn. Trạng thái chờ được đồng bộ khi kết nối lại. |
| Worker hết hạn mức miễn phí | Xem Usage của Workers và D1. Chờ hạn mức phục hồi hoặc chủ tài khoản tự chọn gói phù hợp; chương trình không tự mua gói. |
| Mạng công ty chặn Cloudflare | Thử mở URL `/health` từ trình duyệt trên PC; nếu cũng bị chặn, cần dùng mạng được phép truy cập dịch vụ này. |

### Lưu cấu hình và hàng chờ trên PC

CRM lưu cấu hình và gói chưa chuyển xong trong `%LOCALAPPDATA%\BachCRM\CloudSMS`, được bảo vệ theo tài khoản Windows. Không cần chép hoặc xóa thư mục này khi giải nén bản cập nhật. Không sao chép sang tài khoản Windows khác vì khóa bảo vệ khác nhau.

### Ngắt một điện thoại thất lạc

Mã nhận được thiết kế cho một điện thoại tin cậy của mỗi kết nối. Nếu mã bị lộ, xóa kết nối tương ứng trong bảng D1 `channels` sẽ vô hiệu khóa; các bảng con dùng ràng buộc xóa theo kết nối. Sao lưu cần thiết trước khi tự xóa dữ liệu. Người triển khai có thể dùng API `DELETE /api/v1/channel` với khóa ghi của đúng kết nối để thu hồi. Không chia sẻ khóa ghi hoặc ADMIN_KEY với điện thoại.

## E. Phạm vi kiểm thử và mã nguồn

Đã biên dịch app iPhone trên macOS/Xcode và app Android bằng bộ công cụ Android. Dịch vụ được kiểm tra bằng Worker sản xuất cùng SQLite: phân quyền từng kết nối, 130 khách chia nhiều trang, gửi lại không trùng, xác nhận nhận và dọn dữ liệu, hết hạn, thu hồi khóa. CRM được biên dịch/kiểm tra .NET Framework trên Windows, kèm kiểm tra lại AF, lưu báo cáo/Phủ lại và xuất báo cáo.

Chưa triển khai vào tài khoản Cloudflare của anh hoặc thử truyền trên điện thoại/Excel thật của anh. Sau khi cấu hình, anh nên chuyển thử một vài khách đã chọn để kiểm tra tên/số trước khi dùng hằng ngày. Các kết quả kiểm tra cụ thể đi kèm trong gói phát hành.

Mã nguồn và các bản build trên nhánh riêng:
<https://github.com/mrbach222-droid/BachSMS/tree/bachsms-cloudflare-v1.2.0-20261021>

Tài liệu Cloudflare tham chiếu:
- <https://developers.cloudflare.com/d1/get-started/>
- <https://developers.cloudflare.com/d1/best-practices/remote-development/>
- <https://developers.cloudflare.com/workers/configuration/secrets/>
- <https://developers.cloudflare.com/workers/configuration/cron-triggers/>
- <https://developers.cloudflare.com/workers/platform/limits/>
