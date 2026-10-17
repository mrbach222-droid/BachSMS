# Ký IPA 0.2.0

Ký ứng dụng và cả hai extension Broadcast.appex, SetupUI.appex. Giữ quan hệ bundle identifier: app, app.Broadcast và app.SetupUI. Không bỏ extension khi ký lại. Phiên bản này không yêu cầu com.apple.security.application-groups hoặc keychain-access-groups dùng chung; API key dùng Keychain mặc định do chữ ký của app cấp.

IPA build bằng CI là bản chưa ký. Cần chữ ký Apple hợp lệ để cài lên iPhone. Không có chứng chỉ trong mã nguồn. Nếu công cụ ký đổi bundle ID, cần đổi tương ứng ID của cả hai extension. Không bắt đầu phiên từ Trung tâm điều khiển; dùng nút ghép nối trong app để ReplayKit truyền thông tin phiên.
