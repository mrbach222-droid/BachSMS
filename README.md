# Bách SMS iOS 1.0.2 — Native fixes

## Bản nền đã chốt — 08/10/2026

Người dùng đã xác nhận bản Bách SMS **v1.0.2 (build 3)** hoạt động và chốt làm nền tảng cho các lần nâng cấp tiếp theo.

- Nhánh lưu bản nền: `baseline-v1.0.2`.
- Commit đã tạo IPA được chốt: `f408d80d60ec1252d5b407963283ea29173ca4ae`.
- IPA: `BachSMS_v1.0.2_native_fix_unsigned.ipa`.
- SHA-256 của IPA: `8011c8cb852572254eda94fb61f82ac353cd88c56422412d41efbcbeb81b6008`.
- GitHub Actions run: `37757934346`; build thành công, 6 kiểm tra nhập Excel/CSV đạt.

Mọi sửa đổi tiếp theo phải bắt đầu từ bản nền này, giữ khả năng đọc dữ liệu đã lưu và các tính năng đã được chốt, trừ khi người dùng yêu cầu thay đổi. Giữ nhánh `baseline-v1.0.2` tại commit trên để có thể đối chiếu và khôi phục đúng bản đã được duyệt.

Based on v1.0.1, retaining its local storage key and original recipient/compose/review flow.

- Present MFMessageComposeViewController with UIKit present/dismiss and full-screen bounds. End editing before presentation; deliver cancel/send/fail only after dismissal completes.
- Import files with a native document picker in copy mode, then make a coordinated local copy before background parsing. Allows selection from Files and third-party providers; validates xlsx/csv/tsv on import.
- Read inline/shared/rich-text Excel cells, skip blank cover sheets, fix AA+ column indexes, support numeric/scientific phone cells, and accept phone-only headers.
- Parse Windows CRLF, UTF-8 BOM, UTF-16, semicolon CSV and TSV. Deduplicate phones and report newly added recipients accurately.
- Build IPA in GitHub Actions after six Swift regression tests. SMS send/cancel and keyboard alignment require an iPhone with a SIM for final validation.

Old binary .xls files must be saved as .xlsx before import. This app requires the user to tap Send for each message. Existing saved data is retained with the same bundle identifier and UserDefaults key.
