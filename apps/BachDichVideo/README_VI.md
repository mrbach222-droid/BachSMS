# Bách Dịch Video 0.2.0 — bản thử cho iOS 17+

Bản sửa lỗi Keychain -34018 ở bản 0.1.1: API key lưu trong Keychain riêng của app. Không sử dụng App Groups hoặc Keychain dùng chung. App chính và ReplayKit nối với nhau qua 127.0.0.1, có mã ghép nối một lần; API key không chuyển vào extension.

## Cách dùng trên iPhone

1. Ký và cài IPA, giữ cả Broadcast.appex và SetupUI.appex. Mở Cài đặt trong app, nhập Gemini API key, bật đồng ý gửi chữ, chọn Chữ / phụ đề và bấm Lưu.
2. Trở về Dịch video, bật khung dịch nổi, ghi nhớ mã 6 số.
3. Bấm Ghép nối / bắt đầu chia sẻ, nhập mã 6 số trong màn hình hệ thống. Không bắt đầu trực tiếp từ Trung tâm điều khiển vì phiên cần mã ghép nối.
4. Mở Douyin, TikTok hoặc YouTube, phát video có chữ/phụ đề gốc. Kéo khung nổi ra ngoài vùng đọc chữ. Có thể đổi vùng đọc ở Cài đặt sau khi dừng phiên.
5. Dừng phiên trong app hoặc dừng ghi/phát màn hình qua Trung tâm điều khiển.

Mã hết hạn sau 2 phút, dùng một lần, khóa sau 5 lần sai. Nếu hủy sau khi nhập mã, bấm Lưu để tạo phiên mới. Phiên tối đa 30 phút. Giữ khung nổi hoạt động để app chính tiếp tục xử lý; nếu iOS dừng app thì phiên sẽ mất kết nối.

## Giới hạn cần kiểm tra trên thiết bị thật

Đây là bản thử. Build và kiểm tra TCP trên macOS không chứng minh hoạt động trong ba app trên iPhone. ReplayKit, khung nổi và nhận dạng lời nói tại chỗ cần kiểm tra thực tế. Video được bảo vệ có thể không cho hình/tiếng. Khung nổi có nền kín, vị trí/kích thước do iOS quản lý. Khi quay vào app chính, phần dịch tạm ngưng để tránh đọc nội dung cài đặt. Không đảm bảo dịch lời nói nếu video không có chữ: chế độ Lời nói vẫn là thử nghiệm và phụ thuộc hỗ trợ nhận dạng tại chỗ của máy/ngôn ngữ.

## Dữ liệu và giới hạn API

Chỉ chữ được nhận diện gửi đến Gemini bằng API key của người dùng. Không ghi video, không mở micro, không gửi âm thanh lên Gemini. Cài đặt nằm trong vùng dữ liệu riêng, không chứa API key. Dữ liệu phiên ở RAM. Endpoint chỉ nhận ghép nối, chữ/trạng thái và kết thúc; không có endpoint đọc bản dịch hay API key. Mặc định cách nhau ít nhất 3 giây, 120 yêu cầu/phiên; lỗi cũng tính vào số yêu cầu. Hạn mức/chi phí Gemini phụ thuộc API key và model của bạn.

## Build

Trên macOS với Xcode và XcodeGen: `bash Scripts/build_unsigned.sh`. Script chạy XCTest, archive thiết bị arm64 không ký, kiểm tra cả ba bundle và đóng gói `build/BachDichVideo_v0.2.0_UNSIGNED.ipa`. File này cần được ký để cài. Không có chứng chỉ/provisioning profile riêng trong repository.
