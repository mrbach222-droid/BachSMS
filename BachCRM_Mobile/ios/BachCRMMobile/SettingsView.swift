import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CareStore
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = SecureSettings.read(SecureSettings.endpointKey)
    @State private var token = SecureSettings.read(SecureSettings.tokenKey)

    var body: some View {
        NavigationStack {
            Form {
                Section("Đồng bộ bảo mật") {
                    TextField("https://crm.your-approved-domain.vn", text: $endpoint)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Mã chỉ đọc của iPhone", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Text("Ứng dụng chỉ đọc danh sách khách chăm sóc. Thay đổi hồ sơ và báo cáo thực hiện trên CRM Windows/FPT.")
                    Text("Khi ứng dụng đang mở, dữ liệu cập nhật qua kết nối thời gian thực và kiểm tra dự phòng. Khi chạy nền, iOS không bảo đảm cập nhật liên tục.")
                }.font(.footnote).foregroundStyle(.secondary)
                Button("LƯU & KẾT NỐI") {
                    if store.configure(endpoint: endpoint, readToken: token) { dismiss() }
                }.frame(maxWidth: .infinity)
            }
            .navigationTitle("Cấu hình")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}