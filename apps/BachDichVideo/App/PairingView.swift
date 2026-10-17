import SwiftUI
import ReplayKit

struct PairingCodeView: View {
    let code: String
    @State private var qrImage: CGImage?
    var body: some View {
        VStack(spacing: 8) {
            Text("Mã nối trong máy · không cần nhập").font(.caption)
            if let image = qrImage {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
                    .frame(width: 144, height: 144).accessibilityLabel("Mã ghép nối một lần")
            }
            Text("Bấm chia sẻ bên dưới rồi giữ mã này hiện trên màn hình đến khi báo đã nối.")
                .font(.caption).multilineTextAlignment(.center)
            Text("Nếu mã bị khung nổi che, kéo khung ra góc. Mã hết hạn sau 2 phút.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.privacySensitive().padding(14).frame(maxWidth: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .task(id: code) { qrImage = PairingQR.image(code: code) }
    }
}

struct BroadcastPicker: UIViewRepresentable {
    var enabled: Bool
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 54, height: 54))
        view.preferredExtension = (Bundle.main.bundleIdentifier ?? "") + ".Broadcast"
        view.showsMicrophoneButton = false
        view.tintColor = .white
        view.accessibilityLabel = "Bắt đầu hoặc dừng chia sẻ toàn màn hình cho Bách Dịch Video"
        return view
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.isUserInteractionEnabled = enabled
        uiView.alpha = enabled ? 1 : 0.35
    }
}
