# Bách SMS iOS 1.0.1 — Native

Bản native SwiftUI thay giao diện webview. Có nhập danh sách `.xlsx`, `.csv`, `.tsv`, dán tên và số, cá nhân hóa `{ten}`, xem trọn nội dung từng SMS trước khi mở trình soạn iOS, gửi từng người và lưu trạng thái cục bộ.

Ứng dụng không tự gửi SMS. Người dùng phải kiểm tra nội dung và chạm **Gửi** trong giao diện Tin nhắn. Trạng thái `Đã gửi` phản ánh kết quả trả về từ iOS, không xác nhận tin đã được nhận.

## Build

GitHub Actions trên nhánh `v1.0.1-native-fullscreen` tạo IPA unsigned. Cần macOS, XcodeGen, Xcode và kết nối Internet để lấy CoreXLSX.

Tệp `.xls` cũ cần được lưu thành `.xlsx`; CoreXLSX đọc `.xlsx` và tệp CSV/TSV được hỗ trợ trực tiếp.
