# Thiết kế Bách Dịch Video

Mục tiêu: người dùng xem video trong app gốc, bản dịch tiếng Việt nằm trong khung nổi. Không yêu cầu tải video hoặc dán link cho mỗi video.

## Giao diện

Ba tab: **Dịch video · Cài đặt · Cách dùng**. Nền xanh đen, điểm nhấn xanh bạc hà, thao tác lớn vừa đủ trên iPhone, hỗ trợ dọc/ngang. Tab đầu có khung xem trước thật từ cùng renderer dùng cho PiP, ba bước khởi động và chỉ số nhận hình/tiếng. Chữ mẫu phải có nhãn rõ ràng.

## Luồng bản đầu

1. Thiết lập dịch, kiểm tra API, xác nhận gửi phần chữ đến Gemini.
2. Khởi động PiP qua nút do người dùng bấm.
3. Người dùng bật chia sẻ màn hình bằng giao diện hệ thống.
4. Chuyển sang app xem video. Chặn xử lý khi app Bách Dịch ở trước màn hình để tránh dịch giao diện của chính mình.
5. Extension nhận hình/tiếng; chỉ xử lý nguồn của chế độ đã chọn.
6. Vision OCR hoặc nhận dạng tại máy → chữ → Gemini → kết quả gần nhất trong container dùng chung → render thành video caption cho PiP.
7. Pause dừng xử lý và yêu cầu mới. Stop giải phóng OCR, Speech, mạng và tệp câu dịch; đóng PiP cũng kích hoạt pause.

## Quyết định cho bản 0.1.1

- Hai chế độ tách biệt để dễ xác định lỗi nguồn hình/tiếng, không dùng đồng thời và không dịch trùng một câu qua hai nguồn.
- Giới hạn OCR một khung/giây và một khung đang xử lý, thu nhỏ hình xuống cạnh dài tối đa 960 trước OCR.
- Không giữ hàng đợi dài; chỉ một yêu cầu đang chạy và một câu mới nhất chờ dịch.
- Kiểm tra giới hạn trước mỗi yêu cầu, đếm cả yêu cầu thất bại; 429 chờ ít nhất 15 giây, lỗi tạm tăng dần tối đa 60 giây nếu server không yêu cầu lâu hơn.
- Không thay model ngầm, không kèm API key trong mã nguồn, log, JSON tạm hoặc ZIP.
- Câu dịch chậm quá 12 giây bị bỏ; OCR không hiển thị kết quả của câu đã bị thay thế. Chữ lâu không còn được nhận sẽ được dọn để tránh hiện phụ đề cũ.
- Dữ liệu tạm được file protection và loại khỏi backup; API key là WhenUnlockedThisDeviceOnly.

## Thứ tự phát triển tiếp

| Giai đoạn | Điều kiện hoàn thành |
|---|---|
| Build | Compile cả hai target và chạy unit tests trên Mac |
| Kiểm tra nền tảng | Khung nổi + chia sẻ màn hình cùng chạy ít nhất 5 phút trên iPhone |
| Kiểm tra ba app | Có video mẫu, thử dọc/ngang, qua lại app, dừng/resume, nội dung không cấp capture |
| iOS mới | Tách adapter ScreenCaptureKit cho iOS 27, so sánh với đường ReplayKit cũ |
| Nghe dịch | Đo khả năng hỗ trợ ngôn ngữ, bộ nhớ và độ trễ; nếu extension không đủ thì đổi kiến trúc |
| Trải nghiệm | Chọn vùng chính xác hơn, tránh chữ giao diện và OCR đọc lại PiP |
| Bản phát hành | Chữ ký/profile hợp lệ, đo pin/nhiệt, kiểm tra quyền riêng tư và yêu cầu phân phối |

Các ý tưởng sau chỉ triển khai khi nền tảng hoạt động: nhận diện ngôn ngữ lời nói, dịch hai chiều, lưu câu học từ vựng do người dùng chọn, dịch tệp video và lồng tiếng. Chưa nằm trong bản 0.1.1.
