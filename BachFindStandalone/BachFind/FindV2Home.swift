import SwiftUI
import Photos
import UIKit

private enum FindStyle {
    static let background = Color(red: 0.025, green: 0.055, blue: 0.125)
    static let panel = Color(red: 0.070, green: 0.125, blue: 0.225)
    static let cyan = Color(red: 0.35, green: 0.89, blue: 1.0)
    static let muted = Color(red: 0.65, green: 0.74, blue: 0.84)
    static let line = Color.white.opacity(0.12)
    static var gradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.04, green: 0.12, blue: 0.24),
            background, Color(red: 0.02, green: 0.045, blue: 0.095)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct FindPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FindStyle.panel.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(FindStyle.line, lineWidth: 0.75)
                    )
            )
    }
}
private extension View {
    func findPanel() -> some View { modifier(FindPanel()) }
}

private struct FindThumbnail: View {
    let id: String
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(FindStyle.cyan.opacity(0.11))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 58, height: 62).clipped()
            } else {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(FindStyle.cyan)
            }
        }
        .frame(width: 58, height: 62).clipShape(RoundedRectangle(cornerRadius: 11))
        .onAppear {
            guard image == nil else { return }
            let found = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = found.firstObject else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 144, height: 144),
                contentMode: .aspectFill, options: options
            ) { loaded, _ in
                if let loaded { DispatchQueue.main.async { self.image = loaded } }
            }
        }
    }
}

struct FindV2Home: View {
    @StateObject private var store = PhotoIndex()
    @State private var tab = 0
    @State private var selected: IndexedPhoto?
    @State private var clearDialog = false
    @State private var collection = "Tất cả"
    @FocusState private var searchFocused: Bool
    private let tabs: [(String, String)] = [
        ("Tìm kiếm", "magnifyingglass"), ("Thư viện", "photo.on.rectangle.angled"),
        ("Phân loại", "square.grid.2x2"), ("Cài đặt", "gearshape")
    ]
    var body: some View {
        ZStack {
            FindStyle.gradient.ignoresSafeArea()
            VStack(spacing: 0) {
                brandHeader
                Group {
                    switch tab {
                    case 0: searchPage
                    case 1: libraryPage
                    case 2: categoryPage
                    default: settingsPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomTabs
            }
        }
        .preferredColorScheme(.dark)
        .tint(FindStyle.cyan)
         .task {
            store.refreshPermission()
            if store.permission == .notDetermined {
                await store.askAndScan()
            } else if store.allowed && store.items.isEmpty {
                store.scan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            let previousPermission = store.permission
            store.refreshPermission()
            if store.allowed && previousPermission != store.permission && !store.scanning {
                store.scan()
            }
        }
        .sheet(item: $selected) { FindPhotoDetail(photo: $0) }
        .confirmationDialog("Xóa toàn bộ chỉ mục OCR?", isPresented: $clearDialog) {
            Button("Xóa chỉ mục", role: .destructive) { store.clear() }
        } message: {
            Text("Ảnh gốc trên iPhone sẽ không bị xóa.")
        }
    }
    private var brandHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [FindStyle.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("B").font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.01, green: 0.07, blue: 0.16))
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white).offset(x: 12, y: 12)
            }.frame(width: 43, height: 43)
            VStack(alignment: .leading, spacing: 1) {
                Text("B Find")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(0.1)
                Text("BÁCH APP  /  PHOTO SEARCH")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.25).foregroundStyle(FindStyle.muted)
            }
            Spacer(minLength: 0)
            if store.scanning {
                ProgressView().tint(FindStyle.cyan).padding(10)
            } else {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 17))
                    .foregroundStyle(FindStyle.cyan)
                    .frame(width: 35, height: 35)
                    .background(.white.opacity(0.06), in: Circle())
            }
        }
        .padding(.horizontal, 19).padding(.top, 7).padding(.bottom, 11)
    }
    private func sectionTitle(_ text: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(FindStyle.muted)
            }
        }
    }
    private var searchPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 7) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mọi nội dung, một lần tìm.")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Tìm đúng chữ hoặc con số có trong ảnh")
                            .font(.system(size: 11)).foregroundStyle(FindStyle.muted)
                    }
                    Spacer(minLength: 1)
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 29, weight: .ultraLight))
                        .foregroundStyle(FindStyle.cyan)
                        .frame(width: 48, height: 48)
                        .background(FindStyle.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                }
                searchInput
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(["Hóa đơn", "Tài khoản", "Biển số", "Vận đơn", "Hợp đồng"], id: \.self) { keyword in
                            Button(keyword) {
                                store.query = keyword
                                searchFocused = false
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FindStyle.muted)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(FindStyle.panel, in: Capsule())
                            .overlay(Capsule().stroke(FindStyle.line, lineWidth: 0.5))
                        }
                    }
                }
                HStack(spacing: 10) {
                    statCell("Ảnh đã lập chỉ mục", value: "\(store.items.count)", icon: "photo.stack")
                    statCell("Kết quả phù hợp", value: store.query.isEmpty ? "—" : "\(store.matches.count)", icon: "checkmark.circle")
                }
                scanningPanel
                sectionTitle(store.query.isEmpty ? "Ảnh gần đây" : "Kết quả tìm kiếm",
                             subtitle: store.query.isEmpty ? "Mới nhất" : "\(store.matches.count) ảnh")
                resultRows(Array((store.query.isEmpty ? sortedPhotos : store.matches).prefix(60)))
            }
            .padding(.horizontal, 19).padding(.top, 9).padding(.bottom, 22)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    private var searchInput: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 18))
                .foregroundStyle(FindStyle.cyan)
            TextField("Tìm chữ hoặc con số trong ảnh...", text: $store.query)
                .font(.system(size: 13))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.search)
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FindStyle.muted)
                }
            }
        }
        .padding(.horizontal, 14).frame(height: 49)
        .background(FindStyle.panel.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15)
                    .stroke(FindStyle.cyan.opacity(0.35), lineWidth: 1))
    }
    private func statCell(_ caption: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(FindStyle.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(caption).font(.system(size: 10)).foregroundStyle(FindStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).findPanel()
    }
    private var scanningPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: store.allowed ? "sparkle.magnifyingglass" : "lock.shield")
                    .foregroundStyle(FindStyle.cyan)
                Text(store.scanning ? "Đang nhận dạng ảnh..." : (store.allowed ? "Lập chỉ mục trên iPhone" : "Cho phép truy cập ảnh"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if store.scanning { Text("\(Int(store.progress * 100))%").font(.system(size: 11)).foregroundStyle(FindStyle.cyan) }
            }
            Text(store.scanning
                 ? "Đã kiểm tra \(store.scanned)/\(store.total) ảnh · Có chữ: \(store.items.count)"
                 : store.status)
                .font(.system(size: 10)).foregroundStyle(FindStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            if store.scanning {
                ProgressView(value: store.progress).tint(FindStyle.cyan)
            }
            Button {
                if !store.allowed {
                    if store.permission == .denied || store.permission == .restricted {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        Task { await store.askAndScan() }
                    }
                } else if store.scanning {
                    store.cancel()
                } else {
                    store.scan()
                }
            } label: {
                Label(!store.allowed
                      ? (store.permission == .denied || store.permission == .restricted ? "Mở Cài đặt để cấp quyền" : "Cấp quyền ảnh")
                      : (store.scanning ? "Tạm dừng" : "Quét ảnh mới"),
                      systemImage: store.scanning ? "pause.fill" : "viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 35)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.015, green: 0.10, blue: 0.16))
            .background(FindStyle.cyan, in: RoundedRectangle(cornerRadius: 10))
        }.findPanel()
    }
    private var sortedPhotos: [IndexedPhoto] {
        store.items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    private func resultRows(_ photos: [IndexedPhoto]) -> some View {
        LazyVStack(spacing: 8) {
            if photos.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: store.allowed ? "photo.on.rectangle.angled" : "lock.shield")
                        .font(.system(size: 25)).foregroundStyle(FindStyle.cyan)
                    Text(store.query.isEmpty ? "Chưa có ảnh nào được quét." : "Chưa tìm thấy nội dung phù hợp.")
                        .font(.system(size: 12)).foregroundStyle(FindStyle.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(FindStyle.panel.opacity(0.45), in: RoundedRectangle(cornerRadius: 15))
            }
            ForEach(photos) { photo in
                Button { selected = photo; searchFocused = false } label: {
                    HStack(spacing: 11) {
                        FindThumbnail(id: photo.id)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(photo.text.replacingOccurrences(of: "\n", with: "  "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 5) {
                                Image(systemName: "text.viewfinder")
                                Text("Nội dung OCR")
                                if let date = photo.date {
                                    Text("·")
                                    Text(date, style: .date)
                                }
                            }
                            .font(.system(size: 9)).foregroundStyle(FindStyle.muted)
                        }
                        Spacer(minLength: 3)
                        Image(systemName: "chevron.right").font(.system(size: 10))
                            .foregroundStyle(FindStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(FindStyle.panel.opacity(0.75), in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(FindStyle.line, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }
    private var libraryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("Thư viện ảnh", subtitle: "\(store.items.count) ảnh")
                Text("Ảnh đã được nhận dạng, lưu riêng trên thiết bị.")
                    .font(.system(size: 11)).foregroundStyle(FindStyle.muted)
                scanningPanel
                resultRows(sortedPhotos)
            }.padding(.horizontal, 19).padding(.top, 9).padding(.bottom, 20)
        }
    }
    private func belongs(_ photo: IndexedPhoto, _ type: String) -> Bool {
        let text = PhotoIndex.normalize(photo.text)
        switch type {
        case "Hóa đơn": return text.contains("hoa don") || text.contains("tong tien") || text.contains("thanh tien")
        case "Ngân hàng": return text.contains("ngan hang") || text.contains("chuyen khoan") || text.contains("tai khoan")
        case "Vận đơn": return text.contains("van don") || text.contains("giao hang") || text.contains("shopee")
        default: return true
        }
    }
    private var categoryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("Phân loại nhanh", subtitle: "Gợi ý từ OCR")
                Text("Nhóm dựa theo chữ nhận dạng, có thể chưa chính xác.")
                    .font(.system(size: 11)).foregroundStyle(FindStyle.muted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(["Tất cả", "Hóa đơn", "Ngân hàng", "Vận đơn"], id: \.self) { type in
                        Button { collection = type } label: {
                            HStack {
                                Text(type).font(.system(size: 12, weight: .medium))
                                Spacer(minLength: 3)
                                Text("\(store.items.filter { belongs($0, type) }.count)")
                                    .font(.system(size: 11)).foregroundStyle(FindStyle.cyan)
                            }
                            .padding(13)
                            .background(collection == type ? FindStyle.cyan.opacity(0.17) : FindStyle.panel,
                                        in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(collection == type ? FindStyle.cyan.opacity(0.6) : FindStyle.line))
                        }.buttonStyle(.plain)
                    }
                }
                resultRows(sortedPhotos.filter { belongs($0, collection) })
            }.padding(.horizontal, 19).padding(.top, 9).padding(.bottom, 20)
        }
    }
    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Riêng tư & dữ liệu")
                VStack(alignment: .leading, spacing: 13) {
                    Label("OCR xử lý trực tiếp trên iPhone", systemImage: "iphone.gen3")
                    Label("Không tải ảnh lên máy chủ", systemImage: "lock.shield")
                    Label("\(store.items.count) ảnh đang có trong chỉ mục", systemImage: "externaldrive")
                }
                .font(.system(size: 12)).findPanel()
                Text("Quyền ảnh: \(store.allowed ? (store.permission == .limited ? "Chỉ ảnh đã chọn" : "Đã cấp quyền") : "Chưa cấp")")
                    .font(.system(size: 12)).foregroundStyle(FindStyle.muted)
                if !store.allowed {
                    Button("Mở cài đặt quyền ảnh") {
                        if let link = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(link) }
                    }.font(.system(size: 12))
                }
                Button(role: .destructive) { clearDialog = true } label: {
                    Label("Xóa toàn bộ chỉ mục OCR", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .findPanel()
                }
                Text("Việc nhận dạng có thể đọc nhầm ký tự hoặc con số. Đối chiếu với ảnh gốc trước khi sử dụng.")
                    .font(.system(size: 11)).foregroundStyle(FindStyle.muted)
                Text("B Find · v0.2 · Bách App")
                    .font(.system(size: 10)).foregroundStyle(FindStyle.muted.opacity(0.7))
            }.padding(.horizontal, 19).padding(.top, 9)
        }
    }
    private var bottomTabs: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button {
                    searchFocused = false
                    tab = index
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].1)
                            .font(.system(size: 18, weight: tab == index ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tabs[index].0).font(.system(size: 10, weight: tab == index ? .semibold : .medium))
                    }
                    .foregroundStyle(tab == index ? FindStyle.cyan : FindStyle.muted)
                    .frame(maxWidth: .infinity).frame(height: 49)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
        .background {
            FindStyle.background.opacity(0.93)
                .overlay(alignment: .top) { FindStyle.line.frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
