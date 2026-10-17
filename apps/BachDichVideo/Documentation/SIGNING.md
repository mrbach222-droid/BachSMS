# Ký bản IPA unsigned

App chính và Broadcast extension phải được ký cùng team, có cùng App Group đã đăng ký `group.vn.bach.BachDichVideo` hoặc định danh thay thế được cập nhật đồng bộ.

Bản 0.1.1 build 3 dùng chính định danh App Group làm Keychain Access Group. Theo tài liệu Apple, quyền App Groups cấp quyền dùng nhóm này cho Keychain mà không cần tiền tố Team ID và không cần thêm một Keychain Access Group riêng. Cách này tránh lỗi Info.plist của IPA unsigned chứa giá trị AppIdentifierPrefix chưa được mở rộng.

Cả hai Info.plist dùng SharedGroup và SharedKeychainGroup cùng một giá trị. Nếu công cụ ký đổi tên App Group thì phải cập nhật cả hai trường này trong cả hai bundle, cùng entitlements và profile tương ứng.

Nếu công cụ ký bỏ App Group hoặc profile không cấp nhóm, app sẽ hiện lỗi cấu hình thay vì lưu key vào tệp thường. Không thể khắc phục thiếu quyền nhóm chỉ bằng đổi đuôi file hoặc chỉnh tên app.

Nguồn chính thức: https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
