import SwiftUI
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
    @State private var selectedTab = 0
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var copied = false
    @State private var removeAll = false

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
                    case 0: sharePage
                    case 1: receivedPage
                    default: settingsPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
        }
        .tint(SendStyle.accent)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): store.add(urls)
            case .failure(let error): store.message = "Không thể chọn file: \(error.localizedDescription)"
            }
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
                Text("BÁCH APP  /  LOCAL TRANSFER")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.2).foregroundStyle(SendStyle.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(store.active ? Color.green : SendStyle.secondary)
                    .frame(width: 6, height: 6)
                Text(store.active ? "Đang mở" : "Ngoại tuyến")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SendStyle.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(.white.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 19).padding(.top, 7).padding(.bottom, 11)
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
                                Image(systemName: icon(for: file.url))
                                    .font(.system(size: 20))
                                    .foregroundStyle(SendStyle.accent)
                                    .frame(width: 38, height: 42)
                                    .background(SendStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.active ? .white : Color(red: 0.01, green: 0.11, blue: 0.20))
            .background(store.active ? Color.red.opacity(0.65) : SendStyle.accent,
                        in: RoundedRectangle(cornerRadius: 13))
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
                }
                Text("File nhận qua mạng nội bộ được lưu trên iPhone.")
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
                            Image(systemName: icon(for: file.url))
                                .font(.system(size: 20)).foregroundStyle(SendStyle.accent)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name).font(.system(size: 12, weight: .medium))
                                    .lineLimit(1).truncationMode(.middle)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.system(size: 10)).foregroundStyle(SendStyle.secondary)
                            }
                            Spacer(minLength: 0)
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
                Text("B Send · v0.3 LAN · Bách App")
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
