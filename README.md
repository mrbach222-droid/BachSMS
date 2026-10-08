# Bách SMS iOS 1.0.3 — Mẫu gợi ý

## Bản nền hiện tại đã chốt — 08/10/2026

Người dùng đã duyệt và chốt **Bách SMS v1.0.3 (build 4)** làm bản nền mới cho các lần nâng cấp tiếp theo.

- Nhánh lưu bản nền: `baseline-v1.0.3`.
- Commit đã tạo IPA được chốt: `96aab950203091d85e96c82130e669d6d0e74f8a`.
- IPA: `BachSMS_v1.0.3_message_templates_unsigned.ipa`.
- SHA-256 của IPA: `718ec9cf71eeb1b8b832dccdfc661294a8235ff8c502157a325f42559dd41fac`.
- GitHub Actions run: `37762608535`; build thành công, 6 kiểm tra nhập Excel/CSV đạt.
- Bản này gồm 9 mẫu gợi ý theo 3 tình huống và 3 mức độ; kế thừa sửa lỗi nhập file, bàn phím và hủy SMS của v1.0.2.

Mọi sửa đổi tiếp theo phải bắt đầu từ bản nền **v1.0.3**, giữ khả năng đọc dữ liệu đã lưu và các tính năng đã được chốt, trừ khi người dùng yêu cầu thay đổi. Giữ nhánh `baseline-v1.0.3` tại đúng commit trên để đối chiếu và khôi phục bản đã được duyệt.

## Bản nền trước đó — v1.0.2

Bản v1.0.2 (build 3) đã được duyệt trước khi bổ sung mẫu gợi ý. Giữ lại `baseline-v1.0.2` tại commit `f408d80d60ec1252d5b407963283ea29173ca4ae` để tham chiếu lịch sử.

- IPA: `BachSMS_v1.0.2_native_fix_unsigned.ipa`.
- SHA-256: `8011c8cb852572254eda94fb61f82ac353cd88c56422412d41efbcbeb81b6008`.
- GitHub Actions run: `37757934346`.

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
