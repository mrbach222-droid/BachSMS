import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum SendStyle {
    static let bg = Color(red: 0.022, green: 0.052, blue: 0.12)
    static let card = Color(red: 0.069, green: 0.131, blue: 0.23)
    static let accent = Color(red: 0.36, green: 0.90, blue: 1)
    static let secondary = Color(red: 0.67, green: 0.76, blue: 0.86)
    static let border = Color.white.opacity(0.12)
    static let gradient = LinearGradient(colors: [
        Color(red: 0.04, green: 0.12, blue: 0.25),
        bg, Color(red: 0.015, green: 0.040, blue: 0.09)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
}
private struct SendGlass: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SendStyle.card.opacity(0.87))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SendStyle.border, lineWidth: 0.7))
            )
    }
}
private extension View {
    func sendGlass() -> some View { modifier(SendGlass()) }
}

struct SendV2Home: View {
    @StateObject private var store = SendModel()
    @StateObject private var online = BSendOnlineModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var transferMode = 1
    @State private var selectedTab = 0
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var copied = false
    @State private var showPrivateLinkQR = false
    @State private var removeAll = false
    @State private var showPurgeEverything = false
    @State private var mediaSavingURL: URL?
    @State private var mediaSaveResult = ""
    @State private var showMediaSaveResult = false

    private let menu: [(String, String)] = [
        ("Chia sẻ", "arrow.up.right.square"),
        ("Đã nhận", "tray.and.arrow.down"),
        ("Cài đặt", "gearshape")
    ]
    var body: some View {
        ZStack {
            SendStyle.gradient.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Group {
                    switch selectedTab {
                    case 0:
                        if transferMode == 1 { onlinePage }
                        else { sharePage }
                    case 1: receivedPage
                    default: settingsPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
        }
        .onAppear {
            online.didReceive = { store.refresh() }
            online.didUpload = { id in store.remove(id) }
            store.purgeExpiredIfIdle(onlineBusy: online.busy)
            store.refresh()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            guard !online.busy && !store.active else { return }
            store.purgeExpiredIfIdle(onlineBusy: online.busy)
            store.refresh()
        }
        .onChange(of: selectedTab) { _, _ in showPrivateLinkQR = false }
        .onChange(of: transferMode) { _, _ in showPrivateLinkQR = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                showPrivateLinkQR = false
                online.pauseForBackground()
            }
            if phase == .active {
                online.resumeAfterBackground()
                if !online.busy { store.purgeExpiredIfIdle(); store.refresh() }
            }
        }
        .tint(SendStyle.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFiles) {
            BSendNativeFilePicker(
                onPick: { url in
                    // Copy to our local staging directory before the iOS
                    // picker dismisses its temporary iCloud/Files document.
                    store.add([url])
                    showFiles = false
                },
                onCancel: { showFiles = false }
            )
        }
        .onChange(of: photoItems) { newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let file = try? await item.loadTransferable(type: PickerTransfer.self) {
                        store.add([file.url])
                        try? FileManager.default.removeItem(at: file.url)
                    }
                }
                photoItems = []
            }
        }
        .confirmationDialog("Xóa toàn bộ file đang chọn?", isPresented: $removeAll) {
            Button("Xóa file đã chọn", role: .destructive) {
                for file in store.outgoing { store.remove(file.id) }
            }
        } message: {
            Text("Chỉ xóa bản sao trong B Send, không xóa file gốc.")
        }
        .confirmationDialog("Xóa toàn bộ bản sao trong B Send?", isPresented: $showPurgeEverything) {
            Button("Dừng truyền và Xóa tất cả", role: .destructive) {
                online.stop()
                store.clearAllManagedFiles()
            }
        } message: {
            Text("Chỉ xóa file nằm trong vùng lưu của B Send. File gốc trong Ảnh/Tệp và file bạn đã lưu trên PC không bị xóa.")
        }
        .alert("Lưu vào ứng dụng Ảnh", isPresented: $showMediaSaveResult) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(mediaSaveResult)
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [SendStyle.accent, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("B")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.17))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .offset(x: 12, y: -12)
            }.frame(width: 43, height: 43)
            VStack(alignment: .leading, spacing: 1) {
                Text("B Send").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("BÁCH APP  /  HYBRID TRANSFER")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.2).foregroundStyle(SendStyle.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(transferMode == 1 ? (online.connected ? Color.green : SendStyle.secondary) : (store.active ? Color.green : SendStyle.secondary))
                    .frame(width: 6, height: 6)
                Text(transferMode == 1 ? (online.connected ? "Online" : "Chờ mở") : (store.active ? "LAN mở" : "LAN tắt"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SendStyle.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(.white.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 19).padding(.top, 7).padding(.bottom, 11)
    }

    private var modePicker: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { idx in
                Button {
                    transferMode = idx
                } label: {
                    Label(idx == 1 ? "Online · Khác mạng" : "LAN · Cùng mạng",
                          systemImage: idx == 1 ? "globe" : "wifi")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .foregroundStyle(transferMode == idx ?
                            Color(red: 0.01, green: 0.1, blue: 0.18) : SendStyle.secondary)
                        .background(transferMode == idx ? SendStyle.accent : SendStyle.card,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var onlinePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                modePicker
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Truyền file qua Internet.")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text("PC dùng LAN, iPhone dùng Wi-Fi riêng vẫn kết nối.")
                            .font(.system(size: 11)).foregroundStyle(SendStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 25, weight: .ultraLight)).foregroundStyle(SendStyle.accent)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                        Text("Phòng riêng từng iPhone · Mã hóa đầu cuối")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("AES-256-GCM").font(.system(size: 10))
                            .foregroundStyle(SendStyle.accent)
                    }
                    if online.shortCode != nil {
                        VStack(spacing: 11) {
                            Label("ĐÃ MỞ CHIA SẺ ONLINE", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                            Label("Đang kết nối bằng phòng riêng",
                                  systemImage: "lock.shield.fill")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(SendStyle.accent)
                            Text("PC đã liên kết: chỉ cần mở web và chọn tên iPhone. Nếu cần thêm PC mới, hãy mở mã QR trong thời gian ngắn.")
                                .font(.system(size: 11))
                                .foregroundStyle(SendStyle.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            if let link = online.privateDeviceURL {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showPrivateLinkQR.toggle()
                                    }
                                    copied = false
                                } label: {
                                    Label(showPrivateLinkQR ? "Ẩn mã liên kết" : "Thêm PC mới · Hiện mã QR",
                                          systemImage: showPrivateLinkQR ? "eye.slash.fill" : "qrcode.viewfinder")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(maxWidth: .infinity).frame(height: 42)
                                        .foregroundStyle(SendStyle.accent)
                                        .background(SendStyle.accent.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                if showPrivateLinkQR {
                                    SendQR(text: link)
                                        .frame(width: 154, height: 154)
                                        .padding(8)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                                    Button {
                                        UIPasteboard.general.string = link
                                        copied = true
                                        withAnimation { showPrivateLinkQR = false }
                                    } label: {
                                        Label(copied ? "Đã sao chép" : "Sao chép mã liên kết ẩn",
                                              systemImage: copied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 11, weight: .semibold))
                                            .frame(maxWidth: .infinity).frame(height: 38)
                                    }
                                    .buttonStyle(.plain)
                                    .background(SendStyle.accent.opacity(0.15),
                                                in: RoundedRectangle(cornerRadius: 10))
                                    Label("Mã QR chứa khóa ghép nối bí mật. Chỉ quét trên PC tin tưởng. Bấm Ẩn ngay sau khi dùng.",
                                          systemImage: "exclamationmark.shield")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            HStack(spacing: 8) {
                                Text("Tên thiết bị")
                                    .font(.system(size: 10))
                                    .foregroundStyle(SendStyle.secondary)
                                TextField("iPhone của tôi", text: $online.deviceName)
                                    .font(.system(size: 12))
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .onSubmit {
                                        UserDefaults.standard.set(String(online.deviceName.prefix(48)),
                                                                  forKey: "bsend.deviceDisplayName")
                                    }
                            }
                            .padding(9)
                            .background(SendStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            if let expiry = online.expiry {
                                Label("Phiên hết hạn lúc \(expiry.formatted(date: .omitted, time: .shortened))",
                                      systemImage: "clock")
                                    .font(.system(size: 10))
                                    .foregroundStyle(SendStyle.secondary)
                            }
                        }.frame(maxWidth: .infinity)
                    } else {
                        Label("Bật chia sẻ để PC có link riêng kết nối đúng iPhone này. Bạn vẫn phải chấp nhận yêu cầu ở phiên mới.",
                              systemImage: "network")
                            .font(.system(size: 11))
                            .foregroundStyle(SendStyle.secondary)
                            .frame(maxWidth: .infinity, minHeight: 55)
                    }
                    if online.pendingVerification {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("PC yêu cầu ghép nối", systemImage: "shield.lefthalf.filled")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(SendStyle.accent)
                            Text("Một máy tính muốn gửi và nhận file qua B Send. Chỉ bấm Chấp nhận nếu chính bạn yêu cầu kết nối. Nếu không, hãy Từ chối.")
                                .font(.system(size: 11))
                                .foregroundStyle(SendStyle.secondary)
                            Label("Cho phép máy tính truy cập phiên chia sẻ?",
                                  systemImage: "desktopcomputer.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SendStyle.accent)
                            HStack(spacing: 8) {
                                Button { online.rejectPairing() } label: {
                                    Text("Từ chối")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(maxWidth: .infinity).frame(height: 37)
                                }
                                .buttonStyle(.plain)
                                .background(.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                                Button { online.approvePairing() } label: {
                                    Label("Chấp nhận", systemImage: "checkmark.shield")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(maxWidth: .infinity).frame(height: 37)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color(red: 0.01, green: 0.11, blue: 0.19))
                                .background(SendStyle.accent, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(12)
                        .background(SendStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    }
                    HStack {
                        Circle()
                            .fill(online.peerOnline ? Color.green :
                                  (online.connected ? SendStyle.accent : SendStyle.secondary))
                            .frame(width: 7, height: 7)
                        Text(online.pendingVerification ? "PC đang yêu cầu kết nối" : (online.pairingApproved ? "Đã chấp nhận PC" : (online.peerOnline ? "PC đang kết nối" :
                             (online.connected ? "Đang chờ PC mở link" :
                              (online.connecting ? "Đang kết nối Cloudflare..." : "Chưa mở phiên")))))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    Button {
                        if online.canClose { online.stop() }
                        else { online.start() }
                    } label: {
                        Label(online.canClose ? "Dừng chia sẻ Online" : "Bật chia sẻ Online",
                              systemImage: online.canClose ? "stop.fill" : "link.badge.plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(online.canClose ? .white : Color(red: 0.01, green: 0.10, blue: 0.19))
                        .background(online.canClose ? Color.red.opacity(0.7) : SendStyle.accent,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    Text(online.message)
                        .font(.system(size: 11))
                        .foregroundStyle(SendStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if online.lastBackgroundSeconds > 0 {
                        Label("Lần chuyển ứng dụng gần nhất: \(online.lastBackgroundSeconds) giây",
                              systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(SendStyle.accent)
                    }
                    if online.busy || online.progress > 0 {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(online.progressTitle)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(Int(online.progress * 100))%")
                                    .foregroundStyle(SendStyle.accent)
                            }
                            .font(.system(size: 10))
                            ProgressView(value: online.progress).tint(SendStyle.accent)
                            HStack {
                                Text(String(format: "%.2f MB/s", online.uploadMBps))
                                    .foregroundStyle(SendStyle.accent)
                                Spacer()
                                Text("ETA: \(Int(max(0, online.remainingSeconds))) giây")
                                    .foregroundStyle(SendStyle.secondary)
                            }
                            .font(.system(size: 10, design: .monospaced))
                        }
                    }
                }
                .sendGlass()

                HStack {
                    Text("Chọn file để gửi Online")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(store.outgoing.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(SendStyle.accent)
                    Button { showPurgeEverything = true } label: {
                        Label("Xóa hết", systemImage: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("Turbo Transfer", systemImage: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SendStyle.accent)
                        Spacer()
                        Text("Tối ưu theo kết nối").font(.system(size: 10))
                            .foregroundStyle(SendStyle.secondary)
                    }
                    Picker("Chế độ upload", selection: $online.turboMode) {
                        Text("Tự động").tag("Tự động")
                        Text("Turbo").tag("Turbo")
                        Text("Ổn định").tag("Ổn định")
                    }
                    .pickerStyle(.segmented)
                    .disabled(online.busy)
                }.sendGlass()
                HStack(spacing: 9) {
                    Button { showFiles = true } label: {
                        Label("Chọn từ Tệp", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .background(SendStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 15,
                                 matching: .any(of: [.images, .videos])) {
                        Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 42)
                    }
                    .background(SendStyle.card, in: RoundedRectangle(cornerRadius: 12))
                }
                Text("File gửi tạm tự xóa khi PC nhận đủ. File đã nhận và bản sao còn lại tự dọn sau 60 phút khi app hoạt động.")
                    .font(.system(size: 10))
                    .foregroundStyle(SendStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Chọn một tệp mỗi lần · có thể chọn tiếp để thêm nhiều tệp.")
                    .font(.system(size: 10))
                    .foregroundStyle(SendStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.message)
                    .font(.system(size: 10))
                    .foregroundStyle(SendStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.outgoing.isEmpty {
                    Label("Chưa chọn file. Truyền theo từng phần, phụ thuộc thời gian phiên và dung lượng thiết bị.",
                          systemImage: "doc.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(SendStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sendGlass()
                } else {
                    LazyVStack(spacing: 7) {
                        ForEach(store.outgoing) { file in
                            HStack(spacing: 10) {
                                SendFileThumbnail(url: file.url, width: 46, height: 51)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.name).font(.system(size: 11, weight: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                        .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                                }
                                Spacer()
                                Button { store.remove(file.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(SendStyle.secondary)
                                }
                            }.sendGlass()
                        }
                    }
                }
                Button {
                    online.send(files: store.outgoing)
                } label: {
                    Label("Gửi \(store.outgoing.count) file sang PC",
                          systemImage: "paperplane.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 43)
                        .foregroundStyle(Color(red: 0.01, green: 0.1, blue: 0.19))
                        .background(SendStyle.accent.opacity(online.maySend && !store.outgoing.isEmpty ? 1 : 0.4),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!online.maySend || store.outgoing.isEmpty)

                Text("Bản thử nghiệm chưa qua kiểm toán bảo mật. Chỉ thử file không nhạy cảm; không gửi dữ liệu khách hàng hoặc tài liệu công ty.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Quick Background: bấm Home trả lời tin nhắn, B Send sẽ cố giữ WebSocket trong thời gian iOS cấp, kể cả lúc chờ file từ PC. Thử quay lại sau 15/30/60 giây. iOS có thể ngắt sớm; không bảo đảm duy trì đủ 1 phút.")
                    .font(.system(size: 10))
                    .foregroundStyle(SendStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 19).padding(.top, 8).padding(.bottom, 25)
        }
    }

    private var sharePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gửi file thật dễ dàng.")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("iPhone ↔ Máy tính · Android · iPhone")
                            .font(.system(size: 11)).foregroundStyle(SendStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "wifi.circle.fill")
                        .font(.system(size: 29, weight: .ultraLight))
                        .foregroundStyle(SendStyle.accent)
                }
                modePicker
                qrCard
                if let url = store.shareURL {
                    linkCard(url)
                }
                actionButtons
                lanInstructions
                HStack {
                    Text("File đã chọn")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("\(store.outgoing.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SendStyle.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(SendStyle.accent.opacity(0.11), in: Capsule())
                    Spacer()
                    if !store.outgoing.isEmpty {
                        Button { removeAll = true } label: {
                            Label("Xóa tất cả", systemImage: "trash")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.red.opacity(0.85))
                        }
                    }
                }
                if store.outgoing.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus").font(.system(size: 19))
                            .foregroundStyle(SendStyle.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chưa chọn file").font(.system(size: 12, weight: .semibold))
                            Text("Chọn ảnh, video, PDF hoặc file bất kỳ.")
                                .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                        }
                        Spacer()
                    }.sendGlass()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(store.outgoing) { file in
                            HStack(spacing: 11) {
                                SendFileThumbnail(url: file.url, width: 47, height: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.name).font(.system(size: 12, weight: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                        .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                                }
                                Spacer(minLength: 2)
                                Button { store.remove(file.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(SendStyle.secondary)
                                }
                            }
                            .sendGlass()
                        }
                    }
                }
                Text("PC có thể dùng dây LAN, iPhone dùng Wi-Fi cùng router. Giữ B Send mở khi truyền.")
                    .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
            }
            .padding(.horizontal, 19).padding(.top, 8).padding(.bottom, 22)
        }
    }
    private var qrCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.active ? "Quét QR để nhận file" : "Chia sẻ qua Wi-Fi")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(store.active ? "Mở Camera trên thiết bị nhận" : "Bật chia sẻ để tạo mã QR")
                        .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                }
                Spacer()
                Text(store.active ? "ĐANG CHIA SẺ" : "SẴN SÀNG")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(store.active ? Color.green : SendStyle.accent)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.white.opacity(0.07), in: Capsule())
            }
            if let url = store.shareURL {
                SendQR(text: url)
                    .frame(width: 150, height: 150)
                    .padding(9)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityLabel("Mã QR chia sẻ file qua Wi-Fi")
                Text("Chỉ dùng trong phiên chia sẻ đang mở")
                    .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(SendStyle.accent.opacity(0.07))
                    Image(systemName: "qrcode")
                        .font(.system(size: 74, weight: .ultraLight))
                        .foregroundStyle(SendStyle.accent.opacity(0.70))
                }
                .frame(maxWidth: .infinity).frame(height: 104)
            }
            if let progress = store.transferProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(store.transferTitle).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("\(Int(progress * 100))%")
                            .fontWeight(.semibold).foregroundStyle(SendStyle.accent)
                    }
                    .font(.system(size: 10))
                    ProgressView(value: progress).tint(SendStyle.accent)
                }
            }
            if !store.message.isEmpty {
                Text(store.message).font(.system(size: 10))
                    .foregroundStyle(SendStyle.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity).sendGlass()
    }
    private var lanInstructions: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer.and.arrow.down")
                    .foregroundStyle(SendStyle.accent)
                Text("PC dây LAN + iPhone Wi-Fi")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("HỖ TRỢ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
            }
            Text("Hai thiết bị không bắt buộc cùng loại kết nối; chỉ cần nằm trong mạng nội bộ có thể liên lạc với nhau.")
                .font(.system(size: 10))
                .foregroundStyle(SendStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let address = store.wifiIP {
                HStack {
                    Text("IP iPhone")
                    Spacer()
                    Text(address)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SendStyle.accent)
                }.font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
            } else {
                Label("Chưa phát hiện IP Wi-Fi của iPhone", systemImage: "wifi.slash")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "1.circle.fill").foregroundStyle(SendStyle.accent)
                Text("PC cắm dây vào router; iPhone kết nối Wi-Fi của cùng router.")
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "2.circle.fill").foregroundStyle(SendStyle.accent)
                Text("Bật chia sẻ trên iPhone, nhập nguyên link hiện ra vào Chrome/Edge trên PC.")
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "3.circle.fill").foregroundStyle(SendStyle.accent)
                Text("Tải file xuống hoặc chọn file trên PC để gửi ngược vào iPhone.")
            }
            .font(.system(size: 10))
            Text("Nếu trang không mở: kiểm tra Guest Wi-Fi / AP Isolation / VLAN; không phải cứ có Internet là hai máy nhìn thấy nhau.")
                .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10))
        .sendGlass()
    }
    private func linkCard(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Địa chỉ chia sẻ nội bộ", systemImage: "link")
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                Text(link).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SendStyle.accent)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                } label: {
                    Label(copied ? "Đã chép" : "Sao chép",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).fixedSize()
                }
                .buttonStyle(.plain)
            }
        }.sendGlass()
    }
    private var actionButtons: some View {
        HStack(spacing: 9) {
            Button { showFiles = true } label: {
                Label("Chọn file", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 43)
            }
            .buttonStyle(.plain)
            .background(SendStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(SendStyle.border))
            PhotosPicker(selection: $photoItems, maxSelectionCount: 30,
                         matching: .any(of: [.images, .videos])) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18))
                    .frame(width: 46, height: 43)
            }
            .background(SendStyle.card, in: RoundedRectangle(cornerRadius: 13))
            Button { store.active ? store.stop() : store.start() } label: {
                Label(store.active ? "Dừng" : "Bật chia sẻ",
                      systemImage: store.active ? "stop.fill" : "wifi")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 43)
                .foregroundStyle(store.active ? .white : Color(red: 0.01, green: 0.11, blue: 0.20))
                .background(store.active ? Color.red.opacity(0.65) : SendStyle.accent,
                            in: RoundedRectangle(cornerRadius: 13))
                .contentShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
    }
    private func icon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "webp"].contains(ext) { return "photo.fill" }
        if ["mp4", "mov", "m4v"].contains(ext) { return "play.rectangle.fill" }
        if ["zip", "rar", "7z"].contains(ext) { return "archivebox.fill" }
        if ext == "pdf" { return "doc.richtext.fill" }
        return "doc.fill"
    }
    private var receivedPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("File đã nhận").font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Button { store.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14))
                    }
                    Button { showPurgeEverything = true } label: {
                        Label("Xóa tất cả", systemImage: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
                Text("File nhận chỉ lưu tạm trong B Send, tự dọn sau 60 phút khi app hoạt động. Hãy lưu ảnh/video vào Ảnh hoặc xuất ra Tệp nếu muốn giữ.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 11)).foregroundStyle(SendStyle.secondary)
                if store.incoming.isEmpty {
                    Label("Chưa có file được nhận", systemImage: "tray")
                        .font(.system(size: 12)).foregroundStyle(SendStyle.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .sendGlass()
                }
                LazyVStack(spacing: 8) {
                    ForEach(store.incoming) { file in
                        HStack(spacing: 11) {
                            SendFileThumbnail(url: file.url, width: 44, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name).font(.system(size: 12, weight: .medium))
                                    .lineLimit(1).truncationMode(.middle)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                            }
                            Spacer(minLength: 0)
                            if BSendMediaLibrary.isSupported(file) {
                                Button {
                                    Task { await saveMediaToPhotos(file) }
                                } label: {
                                    if mediaSavingURL == file.url {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .foregroundStyle(SendStyle.accent)
                                    }
                                }
                                .disabled(mediaSavingURL != nil)
                                .accessibilityLabel("Lưu \(file.name) vào Ảnh")
                            }
                            ShareLink(item: file.url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Button(role: .destructive) { store.delete(file) } label: {
                                Image(systemName: "trash")
                            }
                        }.sendGlass()
                    }
                }
            }.padding(.horizontal, 19).padding(.top, 10).padding(.bottom, 24)
        }
        .onAppear { store.refresh() }
    }
    private func saveMediaToPhotos(_ file: SharedTransferFile) async {
        guard mediaSavingURL == nil else { return }
        mediaSavingURL = file.url
        defer { mediaSavingURL = nil }
        do {
            try await BSendMediaLibrary.save(file)
            store.delete(file)
            mediaSaveResult = "Đã lưu \(file.name) vào thư viện Ảnh và xóa bản sao tạm trong B Send."
        } catch {
            mediaSaveResult = "Chưa lưu được \(file.name): \(error.localizedDescription)"
        }
        showMediaSaveResult = true
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text("Kết nối & riêng tư").font(.system(size: 20, weight: .bold, design: .rounded))
                VStack(alignment: .leading, spacing: 11) {
                    Label("PC dùng LAN + iPhone dùng Wi-Fi cùng mạng", systemImage: "network")
                    Label("Không cần tài khoản đăng nhập", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Mã phiên thay đổi khi bật lại chia sẻ", systemImage: "lock.shield")
                }.font(.system(size: 12)).sendGlass()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Bảo mật kết nối", systemImage: "exclamationmark.shield")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.yellow)
                    Text("Bản v0.3 sử dụng HTTP nội bộ chưa mã hóa. Chỉ dùng trên Wi-Fi tin cậy; không gửi CCCD, tài liệu ngân hàng, dữ liệu khách hàng hoặc thông tin nhạy cảm.")
                        .font(.system(size: 11)).foregroundStyle(SendStyle.secondary)
                    Text("File tối đa 1 GiB. Giữ B Send ở màn hình trước trong lúc truyền. Một số Wi-Fi công cộng chặn liên lạc giữa thiết bị.")
                        .font(.system(size: 11)).foregroundStyle(SendStyle.secondary)
                }.sendGlass()
                VStack(alignment: .leading, spacing: 11) {
                    Label("Không lưu file trên Cloudflare", systemImage: "icloud.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SendStyle.accent)
                    Text("Relay chỉ chuyển tiếp dữ liệu mã hóa. File đã nhận được giữ tạm trong B Send tối đa 60 phút (dọn khi app hoạt động). File gửi được dọn ngay sau khi xác nhận truyền thành công. File gốc không bị xóa.")
                        .font(.system(size: 11)).foregroundStyle(SendStyle.secondary)
                    Button { showPurgeEverything = true } label: {
                        Label("Xóa toàn bộ dữ liệu tạm", systemImage: "trash.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .foregroundStyle(.white)
                            .background(.red.opacity(0.73), in: RoundedRectangle(cornerRadius: 11))
                            .contentShape(RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain)
                }.sendGlass()
                Text("B Send · v0.6.1 Hidden Private Link · Bách App")
                    .font(.system(size: 10)).foregroundStyle(SendStyle.secondary.opacity(0.75))
            }.padding(.horizontal, 19).padding(.top, 10)
        }
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<menu.count, id: \.self) { idx in
                Button {
                    selectedTab = idx
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: menu[idx].1)
                            .font(.system(size: 18, weight: selectedTab == idx ? .semibold : .regular))
                            .frame(height: 22)
                        Text(menu[idx].0)
                            .font(.system(size: 10, weight: selectedTab == idx ? .semibold : .medium))
                    }
                    .foregroundStyle(selectedTab == idx ? SendStyle.accent : SendStyle.secondary)
                    .frame(maxWidth: .infinity).frame(height: 49)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
        .background {
            SendStyle.bg.opacity(0.94)
                .overlay(alignment: .top) { SendStyle.border.frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
