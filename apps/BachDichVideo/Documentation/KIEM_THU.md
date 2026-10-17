# Kiểm tra 0.2.0

CI chạy các test quản lý yêu cầu dịch và xác thực kết nối cục bộ: mã sai/hết hạn/đã dùng, khóa sau 5 lần sai, thu hồi/hết hạn token, token phiên cũ, HTTP phân mảnh/oversize/smuggling/route lạ, cấu trúc phản hồi không chứa API key, tạo QR và giải mã bằng Vision thật, TCP thật qua Network + URLSession từ ghép nối đến kết thúc. Không gọi Google trong XCTest.

Archive iOS bao gồm app + Broadcast.appex. Package script kiểm tra Mach-O, phiên bản, số build, cấu hình ReplayKit và không còn SharedGroup/SharedKeychainGroup.

Cần thử trên iPhone: lưu key không lỗi -34018; kiểm tra API mẫu bằng key thực; bật PiP; chia sẻ toàn màn hình, giữ QR hiện đến khi nối; sang video có chữ Trung Quốc; nhận bản dịch; tạm dừng; đóng khung nổi; dừng phiên; không tiếp tục gọi API sau dừng. Chế độ lời nói cần thử riêng trên thiết bị/ngôn ngữ hỗ trợ. Chưa xác nhận các kiểm tra thiết bị này.
