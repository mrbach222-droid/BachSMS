# Kết quả kiểm tra · 0.1.0

Môi trường tạo mã nguồn: Linux, không có Swift toolchain, Xcode, iOS SDK hay iPhone được kết nối.

## Đã chạy

- Parser tree-sitter-swift: toàn bộ 14 tệp Swift, không có nút lỗi cú pháp. Đây **không phải** kiểm tra kiểu hoặc biên dịch Swift.
- Parse `project.yml`: hợp lệ, có target app và Broadcast extension, dependency nhúng extension, cấu hình plist/entitlements riêng.
- Parse 4 plist/entitlements và 2 privacy manifests: hợp lệ.
- `bash -n` cho script build: hợp lệ.
- Python `py_compile` cho script đóng gói: hợp lệ.
- Kiểm tra ZIP bàn giao bằng CRC, danh sách tệp và SHA-256: có báo cáo `VALIDATION.json` và bảng SHA-256 từng tệp `SHA256SUMS.txt`.

## Đã viết nhưng chưa chạy

6 XCTest trong `Tests/TranslationPolicyTests.swift`: chỉ lấy câu mới nhất, không chạy đồng thời, tần suất và trùng câu, giới hạn đếm cả lỗi, 429/backoff, xóa câu chờ khi pause, mặc định không đồng ý cloud và không có API key trong JSON.

Chạy bằng `swift test` trên Mac hoặc workflow. Không ghi là pass khi chưa chạy.

## Chưa thực hiện

| Hạng mục | Trạng thái |
|---|---|
| Swift typecheck / Xcode build | Chưa chạy |
| GitHub Actions | Chưa chạy, chưa có repository đích cho dự án mới |
| IPA | Chưa tạo |
| Ký app và extension | Chưa thực hiện |
| PiP thực tế | Chưa kiểm thử |
| OCR + dịch end-to-end | Chưa kiểm thử, chưa có API key thử |
| Speech trong extension | Chưa kiểm thử; rủi ro bộ nhớ và hỗ trợ ngôn ngữ |
| YouTube / TikTok / Douyin | Cả ba chưa kiểm thử |
| iOS 27 / ScreenCaptureKit | Chưa có adapter và chưa kiểm thử |
| Pin, nhiệt, RAM, độ trễ | Chưa đo |

## Checklist trên iPhone cho vòng thử đầu

1. Ghi model iPhone, iOS, phiên bản app nguồn và tên model Gemini.
2. Bật Chữ mẫu: renderer có chữ mẫu và PiP mở được. Xác nhận chữ mẫu không bị tính là bản dịch thật.
3. Nhập key hợp lệ, kiểm tra API. Thử key sai/model sai: app báo lỗi dễ hiểu và không tự gọi lặp vô hạn.
4. Chia sẻ màn hình, chuyển sang video phụ đề tiếng Trung/Anh. Kiểm tra thời điểm nhận hình và bản dịch.
5. Lặp lại lần lượt YouTube, TikTok, Douyin; thử 5 phút mỗi app, dọc/ngang, chuyển video và pause video.
6. Đổi vị trí PiP ngoài vùng OCR, kiểm tra không đọc lặp bản dịch. Thử các vùng đọc với chữ giao diện TikTok.
7. Pause dịch: số yêu cầu ngừng tăng, tệp không còn câu dịch; ghi màn hình vẫn hiển thị cho đến khi Stop.
8. Đóng PiP: xử lý tạm dừng. Bật lại và tiếp tục chỉ sau thao tác người dùng.
9. Stop: biểu tượng phát màn hình tắt, không còn request mạng, câu gốc/bản dịch được xóa.
10. Mất mạng/429: yêu cầu được giãn cách, không xếp hàng dài, không tràn cap.
11. Chuyển chế độ Speech: quyền hợp lệ, locale được hỗ trợ; phát video có tiếng, kiểm tra audioApp có dữ liệu trước khi đánh giá ASR.
12. Ngôn ngữ không hỗ trợ: hướng dẫn chuyển sang phụ đề, không tự mở micro hay gửi âm thanh ra ngoài.
13. Video không cấp capture, khóa máy, app bị kill: không hiển thị phụ đề cũ như thể đang dịch.
14. Đo RAM extension bằng Xcode Instruments; nếu bị jetsam thì giảm OCR hoặc chuyển kiến trúc Speech sang host/ScreenCaptureKit.

Chỉ gọi là bản dùng ổn định sau khi có kết quả build, chữ ký và checklist thiết bị tương ứng.
