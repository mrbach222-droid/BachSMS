# Ký IPA 0.2.0

Ký app và Broadcast.appex, giữ quan hệ bundle identifier app và app.Broadcast. Không bỏ extension khi ký lại. Không yêu cầu com.apple.security.application-groups hoặc keychain-access-groups dùng chung; API key dùng Keychain mặc định do chữ ký của app cấp.

IPA từ CI chưa ký. Cần chữ ký Apple hợp lệ để cài. Không có chứng chỉ trong mã nguồn. Nếu đổi bundle ID khi ký, đổi ID của extension tương ứng. Trong app, bật PiP rồi dùng nút chia sẻ toàn màn hình và giữ mã QR hiện cho đến khi ghép nối tự động hoàn tất.
