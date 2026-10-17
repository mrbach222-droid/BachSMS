# Thiết kế 0.2.0

App chính: SwiftUI, Keychain riêng mặc định, Gemini REST, PiP AVSampleBufferDisplayLayer, TCP loopback 127.0.0.1:49213. Không có App Groups hoặc shared Keychain.

Bắt đầu thu toàn màn hình bằng RPSystemBroadcastPickerView. Khi chưa ghép nối, Broadcast chỉ tìm QR dạng BDV-PAIR: với 6 số trong khung hình, không chạy OCR phụ đề/Speech và không gọi Gemini. QR do app chính tạo, có vùng trắng, người dùng giữ mã hiện sau khi chấp nhận chia sẻ. /pair kiểm tra mã trong 120 giây, tối đa 5 lần, dùng một lần. Trả settings và token ngẫu nhiên riêng của phiên, không trả API key. Không cần setupInfo hoặc SetupUI extension.

Sau khi ghép nối: ReplayKit video -> Vision OCR (tối đa 1 khung/giây); chế độ lời nói -> Speech nhận dạng tại chỗ thử nghiệm. Chữ/heartbeat gửi /update bằng Bearer token. App chính trả lệnh tạm dừng/dừng/trạng thái foreground. /finish thu hồi token. Phiên hết hạn sau 30 phút; ghép nối không thành công sau 45 giây thì tự kết thúc capture.

App chính: dedupe/latest-only/throttle/backoff -> Gemini -> PiP. Khi app chính ở foreground, không dịch để tránh đọc cài đặt/API key. Không có API xuất khóa, hình, âm thanh hoặc bản chép lời. HTTP giới hạn byte/header/body, từ chối chunked, duplicate length, route lạ và pipelining. Listener chỉ loopback, tối đa 8 kết nối, timeout 4 giây.

PiP và thu toàn màn hình cần kiểm tra trên iPhone. Không xem thành công XCTest/compile là bằng chứng chạy được trong Douyin/TikTok/YouTube.
