# Thiết kế 0.2.0

App chính: giao diện SwiftUI, Keychain mặc định, Gemini REST, PiP AVSampleBufferDisplayLayer, TCP loopback 127.0.0.1:49213.

SetupUI extension: người dùng nhập mã 6 số. /pair kiểm tra mã trong 120 giây, tối đa 5 lần, dùng một lần. Trả settings và token ngẫu nhiên riêng cho phiên, không trả API key. setupInfo của ReplayKit chuyển token và settings sang Broadcast extension.

Broadcast extension: ReplayKit video -> Vision OCR (tối đa 1 khung/giây); tùy chọn lời nói -> Speech nhận dạng tại chỗ. Heartbeat/chữ gửi /update bằng Bearer token, chỉ trên loopback. App chính trả lệnh tạm dừng/dừng/trạng thái foreground. Dừng qua /finish thu hồi token. Phiên hết hạn sau 30 phút.

App chính: nhận chữ -> dedupe/latest-only/throttle/backoff -> Gemini -> cập nhật PiP. Khi app chính hiện trước màn hình, không dịch để tránh đọc cài đặt/API key. Không có API xuất khóa, hình, âm thanh hoặc bản chép lời. HTTP parser giới hạn byte/header/body, từ chối chunked, duplicate length, route lạ và pipelining. Listener chỉ loopback; tối đa 8 kết nối, timeout 4 giây.

PiP hoạt động nền và luồng ReplayKit cần kiểm tra trên iPhone thật. Không xem thành công XCTest/compile là bằng chứng chạy được trong Douyin/TikTok/YouTube.
