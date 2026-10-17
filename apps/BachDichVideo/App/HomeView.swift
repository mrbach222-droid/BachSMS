import SwiftUI

struct HomeView: View {
    @ObservedObject var model: SessionModel
    @ObservedObject var pip: CaptionPiPController
    @ObservedObject var broadcast: BroadcastSession
    @State private var selectedTab = 0
    private let mint = Color(red: 0.39, green: 0.9, blue: 0.78)

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero
                        preview
                        controls
                        if !model.issue.isEmpty {
                            Label(model.issue, systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                        }
                        diagnostics
                    }.padding(20)
                }
                .background(Color(red: 0.025, green: 0.04, blue: 0.07))
                .navigationTitle("Bách Dịch Video")
                .navigationBarTitleDisplayMode(.inline)
            }.tabItem { Label("Dịch video", systemImage: "captions.bubble.fill") }.tag(0)
            settings.tabItem { Label("Cài đặt", systemImage: "slider.horizontal.3") }.tag(1)
            help.tabItem { Label("Cách dùng", systemImage: "questionmark.circle") }.tag(2)
        }.tint(mint)
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("XEM THẾ GIỚI\nHIỂU TIẾNG VIỆT")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Phụ đề dịch trong khung nổi, bên cạnh video bạn đang xem.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(["YouTube", "TikTok", "Douyin"], id: \.self) { app in
                    Text(app).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.07), in: Capsule())
                }
            }
            Text("BẢN THỬ 0.2.0 · sửa kết nối khi cài bằng IPA")
                .font(.caption2).foregroundStyle(mint)
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.live ? "Phiên đang chạy" : (model.previewOnly ? "CHỮ MẪU" : "Xem trước khung dịch"),
                      systemImage: model.live ? "record.circle" : "rectangle.inset.filled")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Circle().fill(model.live ? mint : .gray).frame(width: 7, height: 7)
            }
            CaptionPreview(controller: pip).aspectRatio(640.0 / 300, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(pip.message).font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
    }
    private var controls: some View {
        VStack(spacing: 14) {
            if !model.live {
                Button { selectedTab = 1 } label: {
                    Label("1. Thiết lập dịch", systemImage: "key.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            Button {
                if !model.previewOnly { model.pause(false) }
                pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly)
                pip.start()
            } label: {
                Label("2. Bật khung dịch nổi", systemImage: "pip.enter")
                    .fontWeight(.bold).frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).disabled(!model.ready && !model.live && !model.previewOnly)
            if !model.pairingCode.isEmpty {
                VStack(spacing: 6) {
                    Text("Mã ghép nối của phiên này").font(.caption).foregroundStyle(.secondary)
                    Text(model.pairingCode).font(.system(size: 34, weight: .bold, design: .monospaced))
                        .privacySensitive().foregroundStyle(mint)
                    Text("Nhớ 6 số này để nhập ở bước tiếp theo. Mã dùng một lần, hết hạn sau 2 phút.")
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity)
                    .background(mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            BroadcastLaunchButton(session: broadcast, enabled: model.ready && !model.previewOnly && !model.live && pip.active)
                .frame(height: 52)
            if !broadcast.message.isEmpty { Text(broadcast.message).font(.caption).foregroundStyle(.secondary) }
            if model.live {
                HStack {
                    Button(model.snapshot.paused ? "Tiếp tục" : "Tạm dừng") { model.pause(!model.snapshot.paused) }
                        .buttonStyle(.bordered)
                    Button("Dừng phiên", role: .destructive) { model.stop(); pip.stop() }.buttonStyle(.bordered)
                }
            } else {
                Button("Xem thử chữ mẫu · không dùng API") {
                    model.demo(); pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly)
                }.font(.footnote)
            }
        }
    }
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trạng thái thực tế").font(.headline)
            Text(model.snapshot.active && !model.live ? "Phiên mất tín hiệu. Kiểm tra biểu tượng ghi màn hình." : model.snapshot.message)
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                metric("Yêu cầu", "\(model.snapshot.requests)")
                Spacer(); metric("Bản dịch", "\(model.snapshot.translations)")
                Spacer(); metric("Thời gian API", String(format: "%.1fs", model.snapshot.latency))
            }
            if model.live {
                Text("Khung hình: \(age(model.snapshot.lastVideoAt)) · Tiếng video: \(age(model.snapshot.lastAudioAt))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(mint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func age(_ date: Date?) -> String {
        guard let date = date else { return "chưa nhận" }
        return "\(Int(max(0, Date().timeIntervalSince(date))))s trước"
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("Chế độ dịch") {
                    Picker("Nguồn nội dung", selection: $model.settings.mode) {
                        ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
                    }
                    if model.settings.mode == .subtitles {
                        Picker("Vùng đọc chữ", selection: $model.settings.region) {
                            ForEach(SubtitleRegion.allCases) { Text($0.title).tag($0) }
                        }
                        Text("Tự nhận diện ngôn ngữ. Đặt khung nổi ngoài vùng đọc để tránh đọc lại bản dịch.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Ngôn ngữ trong video", selection: $model.settings.speechLocale) {
                            ForEach(AppSettings.speechLanguages.keys.sorted(), id: \.self) { key in
                                Text(AppSettings.speechLanguages[key] ?? key).tag(key)
                            }
                        }
                        Button("Cấp quyền nhận dạng lời nói") { model.authorizeSpeech() }
                        Text(model.speechPermission).font(.caption)
                        Text("Thử nghiệm: cần máy và ngôn ngữ hỗ trợ nhận dạng tại chỗ. App không mở micro và không gửi âm thanh lên Gemini.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(model.live || model.preparing)
                Section("Dịch sang tiếng Việt · Gemini") {
                    SecureField("Gemini API key", text: $model.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    TextField("Model", text: $model.settings.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Link("Mở Google AI Studio để lấy API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    Text("Tài khoản Gemini trả phí và hạn mức Gemini API là hai việc khác nhau. Tần suất và chi phí phụ thuộc API key/model của bạn.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Cho phép gửi chữ đã nhận diện đến Gemini để dịch", isOn: $model.settings.cloudConsent)
                    Button(model.checkingAPI ? "Đang kiểm tra…" : "Kiểm tra API bằng một câu mẫu") { model.checkAPI() }
                        .disabled(model.checkingAPI || !model.settings.cloudConsent)
                    Text("Chỉ phần chữ đã nhận diện được gửi đến Google. API key lưu riêng trong app; phần thu màn hình kết nối bằng mã một lần ngay trên iPhone. App không lưu video.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(model.live || model.preparing)
                Section("Khung dịch và tần suất") {
                    Toggle("Hiện cả câu gốc", isOn: $model.settings.showOriginal)
                    HStack { Text("Cỡ chữ"); Slider(value: $model.settings.fontSize, in: 20...36, step: 2) }
                    Stepper("Cách nhau ít nhất \(Int(model.settings.minimumInterval)) giây", value: $model.settings.minimumInterval, in: 2...10, step: 1)
                    Stepper("Tối đa \(model.settings.sessionLimit) yêu cầu/phiên", value: $model.settings.sessionLimit, in: 10...600, step: 10)
                    Text("Mặc định 120 yêu cầu/phiên, tối thiểu 3 giây/lần. Đây là giới hạn trong app; không thay đổi hạn mức Google.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(model.live || model.preparing)
                Section {
                    Button(model.preparing ? "Đang chuẩn bị…" : "Lưu và chuẩn bị phiên dịch") { model.save(); pip.update(model.displaySnapshot, settings: model.settings, previewOnly: model.previewOnly) }
                        .disabled(model.live || model.preparing)
                    Button("Xóa API key", role: .destructive) { model.deleteKey() }.disabled(model.live)
                    if !model.issue.isEmpty { Text(model.issue).font(.footnote) }
                }
            }.navigationTitle("Cài đặt")
                .onChange(of: model.settings) { model.configurationChanged() }
                .onChange(of: model.apiKey) { model.configurationChanged() }
        }
    }
    private var help: some View {
        NavigationStack {
            List {
                Section("Bắt đầu một phiên") {
                    Text("1. Nhập API key, chọn chế độ, bật đồng ý gửi chữ và lưu.")
                    Text("2. Bật khung dịch nổi. Nếu chỉ muốn kiểm tra hiển thị, dùng Chữ mẫu trước.")
                    Text("3. Ghi nhớ mã 6 số, bấm Ghép nối / bắt đầu chia sẻ rồi nhập mã trong màn hình ghép nối. Không bắt đầu trực tiếp từ Trung tâm điều khiển.")
                    Text("4. Mở YouTube, TikTok hoặc Douyin và phát video. Với chế độ phụ đề, bật phụ đề gốc nếu video có.")
                    Text("5. Kéo khung nổi ra ngoài vùng đọc chữ. Thử đổi vùng đọc nếu TikTok/Douyin có nhiều chữ giao diện.")
                }
                Section("Tạm dừng và kết thúc") {
                    Text("Nút tạm dừng chỉ ngừng xử lý và gửi yêu cầu dịch. Chia sẻ màn hình vẫn bật.")
                    Text("Đóng khung nổi sẽ tạm dừng dịch. Muốn dịch lại, bấm Bật khung dịch nổi trong app.")
                    Text("Để kết thúc hoàn toàn, bấm Dừng phiên hoặc dừng ghi/phát màn hình trong Trung tâm điều khiển.")
                }
                Section("Giới hạn của bản thử") {
                    Text("Chưa xác nhận tương thích trên thiết bị thật với cả ba app. Nội dung được bảo vệ có thể không cung cấp hình hoặc tiếng.")
                    Text("Nhận dạng lời nói trong extension và việc duy trì khung nổi cần kiểm tra trên iPhone. Nếu lỗi, dùng chế độ đọc chữ hoặc báo lại trạng thái hiển thị.")
                    Text("Khung nổi có nền kín và vị trí/kích thước do iOS quản lý. Bản dịch có độ trễ, có thể sai tên hoặc ngữ cảnh.")
                    Text("Bản này dùng kết nối trong máy, không yêu cầu App Groups/Keychain chung. Cần giữ khung nổi hoạt động; nếu iOS dừng app chính, phiên dịch sẽ dừng theo. Mỗi phiên tối đa 30 phút.")
                }
            }.navigationTitle("Cách dùng")
        }
    }
}
