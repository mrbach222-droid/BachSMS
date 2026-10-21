# Bách SMS 1.2.0 / CRM 1.4.14.45 — Cloudflare

Nhánh này bổ sung chuyển khách đã chọn từ hai vai trò CRM Windows sang Bách SMS qua Internet, dùng Cloudflare Workers và D1. Có nhận từng trang, lưu cục bộ trước khi xác nhận nhận, hàng chờ thử lại theo mã gói, và khóa riêng cho từng kết nối.

Đọc [hướng dẫn cấu hình Cloudflare](Cloudflare/HUONG_DAN_CAU_HINH.md). iPhone dùng màn hình Kết nối Bách CRM → Liên kết Cloudflare; Android Cloud cài song song với app Android cũ.

Mã nguồn: `CRMCloud/`, `Cloudflare/`, `BachSMS/App/`, `BachSMSAndroid/`. Các workflow build tương ứng nằm trong `.github/workflows/`. CRM v44 được giữ riêng tại `CRMCloud/baseline` để đối chiếu, không thay đổi các nhánh baseline trước.

Thông tin nền tảng và tính năng đã chốt trước đây được giữ dưới đây.

## Bách SMS iOS 1.0.3 — Mẫu gợi ý

## Bản nền đã chốt — 08/10/2026

Người dùng đã xác nhận bản Bách SMS **v1.0.2 (build 3)** hoạt động và chốt làm nền tảng cho các lần nâng cấp tiếp theo.

- Nhánh lưu bản nền: `baseline-v1.0.2`.
- Commit đã tạo IPA được chốt: `f408d80d60ec1252d5b407963283ea29173ca4ae`.
- IPA: `BachSMS_v1.0.2_native_fix_unsigned.ipa`.
- SHA-256 của IPA: `8011c8cb852572254eda94fb61f82ac353cd88c56422412d41efbcbeb81b6008`.
- GitHub Actions run: `37757934346`; build thành công, 6 kiểm tra nhập Excel/CSV đạt.

Mọi sửa đổi tiếp theo phải bắt đầu từ bản nền này, giữ khả năng đọc dữ liệu đã lưu và các tính năng đã được chốt, trừ khi người dùng yêu cầu thay đổi. Giữ nhánh `baseline-v1.0.2` tại commit trên để có thể đối chiếu và khôi phục đúng bản đã được duyệt.

## Mẫu gợi ý v1.0.3

Bổ sung 9 mẫu trong 3 nhóm: nhắc khách hàng, khách sai hẹn và nhờ người nhà chuyển lời. Mỗi nhóm có 3 mức độ, xem toàn bộ nội dung rồi bấm Dùng mẫu. Nội dung vẫn chỉnh sửa được trước khi gửi và `{ten}` tự thay theo tên trong danh sách.

Mẫu người nhà chỉ nhờ chuyển lời liên hệ, không tiết lộ khoản nợ hoặc yêu cầu trả thay. Với nhóm này, tên trong danh sách là tên khách cần chuyển lời, còn số điện thoại là số người nhà được phép liên hệ.

Dữ liệu và nội dung người dùng đã lưu được đọc theo cùng định dạng; mã mẫu đã chọn là trường tùy chọn bổ sung. Không tự thay nội dung đang soạn khi cập nhật app.

Based on v1.0.1, retaining its local storage key and original recipient/compose/review flow.

- Present MFMessageComposeViewController with UIKit present/dismiss and full-screen bounds. End editing before presentation; deliver cancel/send/fail only after dismissal completes.
- Import files with a native document picker in copy mode, then make a coordinated local copy before background parsing. Allows selection from Files and third-party providers; validates xlsx/csv/tsv on import.
- Read inline/shared/rich-text Excel cells, skip blank cover sheets, fix AA+ column indexes, support numeric/scientific phone cells, and accept phone-only headers.
- Parse Windows CRLF, UTF-8 BOM, UTF-16, semicolon CSV and TSV. Deduplicate phones and report newly added recipients accurately.
- Build IPA in GitHub Actions after six Swift regression tests. SMS send/cancel and keyboard alignment require an iPhone with a SIM for final validation.

Old binary .xls files must be saved as .xlsx before import. This app requires the user to tap Send for each message. Existing saved data is retained with the same bundle identifier and UserDefaults key.

