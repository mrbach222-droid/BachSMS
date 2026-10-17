# Bách Dịch Video · 0.1.0

Ứng dụng iOS thử nghiệm: mở khung phụ đề nổi, bật chia sẻ màn hình rồi chuyển sang YouTube, TikTok hoặc Douyin để dịch nội dung sang tiếng Việt.

**Gói này là mã nguồn, chưa phải IPA cài được. Chưa biên dịch bằng Xcode hoặc kiểm thử trên iPhone.**

## Tính năng đã viết

| Tính năng | Phạm vi bản 0.1.0 |
|---|---|
| Dịch chữ/phụ đề | Đọc chữ tại máy bằng Vision; Gemini tự xác định ngôn ngữ và dịch sang Việt |
| Vùng đọc | Giữa, nửa dưới hoặc nửa trên màn hình; chừa cạnh phải để giảm nút giao diện |
| Nghe dịch | Thử nghiệm nhận dạng tại máy, chọn Trung/Anh/Nhật/Hàn; chỉ nhận tiếng video qua chia sẻ màn hình |
| Khung nổi | Picture in Picture với bản dịch, tùy chọn câu gốc, cỡ chữ 20–36 |
| API | Nhập API key, chỉnh model, kiểm tra kết nối bằng một câu mẫu |
| Tiết kiệm lượt | Không dịch lại câu giống nhau, chỉ giữ câu mới nhất; mặc định ít nhất 3 giây/yêu cầu |
| Điều khiển | Tạm dừng, tiếp tục, kết thúc; đóng khung nổi sẽ tạm dừng gửi yêu cầu |
| Trạng thái | Số yêu cầu, số bản dịch, thời gian API, lần cuối nhận hình/tiếng |
| Dữ liệu | API key trong Keychain; không lưu video, chỉ ghi đè kết quả gần nhất vào tệp tạm dùng chung |
| Build | Có cấu hình XcodeGen, script build và GitHub Actions tạo IPA unsigned khi biên dịch thành công |

Những dòng trên mô tả mã nguồn đã triển khai, không phải kết quả đã xác nhận trên thiết bị.

## Điều kiện cài thử

- iPhone/iPad iOS 17 trở lên, hỗ trợ Picture in Picture. Đường thu màn hình trong bản này ưu tiên thử trên iOS 17–26.
- Cần máy Mac/Xcode để build, hoặc chạy workflow đi kèm trên GitHub Actions.
- App chính và Broadcast extension phải được ký cùng Apple Developer team, có App Group và Keychain Sharing phù hợp. Dùng provisioning profile cấp được các quyền này.
- Cần Gemini API key có quyền gọi model đã chọn. Gói Gemini Pro/Advanced không đồng nghĩa API không giới hạn hoặc miễn phí.
- Model mặc định `gemini-flash-latest` là tên có thể thay đổi theo nhà cung cấp. Có thể sửa model trong app nếu tài khoản chưa được truy cập.

**Lưu ý iOS mới:** tài liệu Apple hiện đánh dấu luồng ReplayKit là deprecated từ SDK iOS 27 và khuyến nghị ScreenCaptureKit. Gói 0.1.0 chưa có adapter ScreenCaptureKit và chưa xác nhận chạy trên iOS 27. Deprecated không tự chứng minh API đã ngừng hoạt động, nhưng không nên cam kết tương thích khi chưa build/test bằng SDK và máy tương ứng. Xem `Documentation/API_NOTES.md`.

## Build trên Mac

1. Mở Terminal tại thư mục có `project.yml`.
2. Cài công cụ và tạo project:

```bash
brew install xcodegen
xcodegen generate
open BachDichVideo.xcodeproj
```

3. Trong `Config.xcconfig`, đổi các định danh thành định danh đã đăng ký của bạn; đặt `DEVELOPMENT_TEAM`.
4. Trong Xcode → Signing & Capabilities, kiểm tra **cả hai target** `BachDichVideo` và `Broadcast`:
   - Cùng team.
   - Cùng App Group với giá trị `BACH_APP_GROUP`.
   - Cùng Keychain Sharing, tên `BACH_KEYCHAIN_ID` (Xcode tự thêm tiền tố AppIdentifierPrefix).
   - Bundle ID extension bằng Bundle ID app thêm `.Broadcast`.
5. Chọn iPhone thật và Run. Nếu ký lỗi quyền, sửa provisioning profile trước khi thử chức năng.
6. Muốn kiểm tra logic điều phối độc lập, chạy `swift test`.

Để tạo gói unsigned sau khi compile:

```bash
bash Scripts/build_unsigned.sh
```

Đầu ra khi thành công: `build/BachDichVideo_v0.1.0_UNSIGNED.ipa`.

Script chỉ đóng gói khi archive có binary Mach-O và đúng version; không đổi đuôi ZIP mã nguồn thành IPA. IPA unsigned cần ký hợp lệ cho cả app và extension. Việc công cụ ký thông thường bỏ App Groups/Keychain Sharing sẽ làm app không hoạt động đúng.

## Build qua GitHub trên Windows

1. Tạo repository riêng, ví dụ `BachDichVideo`.
2. Giải nén gói này. Đưa **nội dung bên trong thư mục BachDichVideo** vào gốc repository: phải thấy `project.yml`, `App`, `Shared`, `Broadcast`, `Scripts` và `.github` ngay ở gốc.
3. Nếu tải file qua web mà thư mục `.github` chưa lên, tạo file `.github/workflows/build-ios.yml` và dùng đúng nội dung file đi kèm.
4. Mở Actions → **Build Bach Dich Video iOS** → Run workflow.
5. Khi workflow xanh, tải artifact `BachDichVideo-v0.1.0-UNSIGNED`. Nếu đỏ, xem bước Compile, test and package.

Workflow chưa được chạy trong phiên tạo mã nguồn này. GitHub có thể áp dụng hạn mức build macOS. Workflow tạo unsigned để kiểm tra build; không tự có quyền ký/cài lên máy.

## Dùng sau khi đã cài bản ký hợp lệ

1. Cài đặt → nhập API key → bật đồng ý gửi chữ → Kiểm tra API bằng câu mẫu.
2. Chọn **Chữ/phụ đề** để thử trước; chọn vùng khớp vị trí phụ đề.
3. Bấm **Lưu và chuẩn bị phiên dịch**, quay sang tab Dịch video.
4. Bấm **Bật khung dịch nổi**. Có thể dùng Chữ mẫu để thử riêng phần hiển thị; chữ mẫu được ghi rõ và không phải dịch thật.
5. Bấm nút **Chia sẻ màn hình** → chọn Bách Dịch Video → Bắt đầu phát.
6. Mở app xem video và phát nội dung. Nếu YouTube có phụ đề gốc, bật phụ đề gốc để chế độ đọc chữ có dữ liệu.
7. Kéo khung nổi ra ngoài vùng đọc. Khi dùng nửa dưới, đặt khung nổi phía trên. Khung nổi không trong suốt và chịu giới hạn vị trí/kích thước của iOS.
8. Muốn thử nghe dịch: dừng phiên, chọn Lời nói, chọn ngôn ngữ và cấp quyền nhận dạng, lưu rồi bắt đầu phiên mới.
9. Kết thúc bằng Dừng phiên hoặc dừng phát/ghi màn hình trong Trung tâm điều khiển. Tạm dừng dịch chưa tắt chia sẻ màn hình.

## Giới hạn cần kiểm chứng

- Chưa biết PiP và capture có cùng tồn tại ổn định với từng phiên bản YouTube/TikTok/Douyin. Nội dung được bảo vệ có thể không cấp hình hoặc tiếng.
- OCR đọc chữ trong vùng chọn, chưa phân biệt phụ đề với bình luận/tên tài khoản. Đổi vùng để tránh các chữ giao diện.
- Chế độ nghe dùng Speech nhận dạng tại máy trong extension. Có thể thiếu model ngôn ngữ, hết bộ nhớ extension hoặc bị iOS giới hạn. Chưa tự đoán ngôn ngữ lời nói.
- Bản dịch cần mạng và có độ trễ. Không đồng bộ chính xác theo timecode; không có lồng tiếng Việt.
- Mặc định tối đa 120 yêu cầu/phiên và 30 phút/phiên; mức tối đa chỉnh trong app là 600 yêu cầu. Các giới hạn này không vượt được quota của Google.
- Chỉ giữ kết quả gần nhất; dừng bình thường sẽ xóa câu gốc/bản dịch. Nếu tiến trình bị tắt đột ngột, tệp gần nhất có thể còn đến lần mở/phiên sau; app dọn nội dung phiên mất tín hiệu quá 60 giây khi được chạy.
- Khóa màn hình có thể kết thúc phiên do dữ liệu tạm và API key chỉ truy cập khi máy mở khóa. Không tự khởi động lại việc thu màn hình.
- Đây là bản thử kỹ thuật; chưa khẳng định được App Store duyệt mục đích dùng PiP cho phụ đề dịch.

## Tài liệu kèm theo

- `Documentation/THIET_KE.md`: thiết kế, mục tiêu và các giai đoạn.
- `Documentation/KIEM_THU.md`: kết quả kiểm tra thực sự đã chạy và checklist thiết bị.
- `Documentation/API_NOTES.md`: API, nguồn chính thức và hướng nâng cấp iOS mới.

Version: **0.1.0 / build 1** · Ngày chuẩn bị: **17/10/2026**.
