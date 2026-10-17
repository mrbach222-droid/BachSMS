# API và tương thích

Tra cứu ngày 17/10/2026. Chỉ dùng tài liệu chính thức để quyết định API; mã nguồn app được viết mới, không lấy mã của app khác.

## Thu nội dung

Bản 0.2.0 dùng Broadcast Upload Extension với `RPBroadcastSampleHandler` và `RPSystemBroadcastPickerView`, phù hợp để làm nhánh thử tương thích iOS cũ. Extension nhận `.video` và `.audioApp`; bỏ `.audioMic`.

Tài liệu Apple hiện đánh dấu ReplayKit deprecated trong SDK iOS 27 và khuyến nghị ScreenCaptureKit. Vì vậy chưa coi nhánh ReplayKit là giải pháp dài hạn cho iOS mới. Chưa triển khai adapter ScreenCaptureKit: cần build trên SDK mới, cấu hình `screen-capture` background mode và thử trên iOS 27 thật trước. Không thêm API mới chưa được kiểm chứng vào build cũ.

Nguồn:

- https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler
- https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview
- https://support.apple.com/guide/security/replaykit-security-seca5fc039dd/web
- https://developer.apple.com/documentation/screencapturekit
- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developer.apple.com/documentation/xcode/configuring-background-execution-modes

## Hiển thị

PiP dựa trên `AVSampleBufferDisplayLayer` và `AVPictureInPictureSampleBufferPlaybackDelegate`, không dùng private API hoặc cửa sổ tự ý đè lên app khác. Renderer 640×300 ở 2 khung/giây. Cấu hình audio `.mixWithOthers`; vẫn cần thử xung đột audio session với từng app.

- https://developer.apple.com/documentation/avkit/avpictureinpicturesamplebufferplaybackdelegate
- https://support.apple.com/guide/iphone/multitask-with-picture-in-picture-iphcc3587b5d/ios

## Nhận dạng và dịch

Vision nhận diện chữ tại máy. Speech chỉ chạy khi đã cấp quyền và `supportsOnDeviceRecognition` là true; yêu cầu `requiresOnDeviceRecognition = true`. Không có fallback gửi tiếng lên server trong code này. Nhánh Speech trong extension là thử nghiệm và cần đo bộ nhớ thực tế.

Gemini gọi REST `generateContent` qua HTTPS bằng header `x-goog-api-key`. Câu OCR/ASR là dữ liệu không đáng tin cậy; system instruction yêu cầu chỉ dịch và bỏ qua chỉ dẫn nằm trong câu được đọc. Không bảo đảm tuyệt đối chống prompt injection hoặc bản dịch sai.

- https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest
- https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
- https://ai.google.dev/api/generate-content
- https://ai.google.dev/gemini-api/docs/models

## Chia sẻ dữ liệu và chữ ký

Bản 0.2.0 bỏ App Groups và Keychain Access Group chung. API key chỉ nằm trong Keychain mặc định của app chính, không gắn kSecAttrAccessGroup. Cài đặt JSON ghi atomic trong Application Support riêng. App và extension nối qua TCP 127.0.0.1, ghép nối một lần bằng QR hiện trên màn hình app; token chỉ nằm trong RAM và không chuyển API key sang extension. Không có SetupUI extension hoặc yêu cầu setupInfo, để giữ luồng thu toàn màn hình RPSystemBroadcastPickerView.

Chữ ký vẫn cần hợp lệ cho app và Broadcast.appex. Các kiểm tra TCP/QR trên macOS không thay thế kiểm thử ReplayKit/PiP và Keychain trên iPhone thật.

- https://developer.apple.com/documentation/xcode/configuring-app-groups
- https://developer.apple.com/documentation/xcode/configuring-keychain-sharing
- https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
- https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

PrivacyInfo là template ban đầu của dự án, cần rà soát theo cách phân phối và điều khoản nhà cung cấp thực tế trước khi phát hành.
