import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: CareStore
    @Environment(\.scenePhase) private var phase
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var callError: String?

    private var visible: [CareCustomer] {
        guard !searchText.isEmpty else { return store.customers }
        return store.customers.filter { c in
            [c.cif, c.contract, c.name, c.phone].contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bách CRM").font(.system(size: 28, weight: .bold))
                            Text("CHĂM SÓC KHÁCH HÀNG").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title3)
                        }.accessibilityLabel("Cấu hình đồng bộ")
                    }
                    HStack(spacing: 10) {
                        metric("Đang theo dõi", value: store.customers.count, color: .primary)
                        metric("Đến hạn", value: store.customers.filter(\.isDue).count, color: .red)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: store.errorMessage == nil ? "checkmark.icloud" : "exclamationmark.icloud")
                        Text(store.errorMessage ?? (store.lastSync == nil ? "Đang kết nối..." : "Đã cập nhật danh sách"))
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.orange)
                }
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground))

                List {
                    ForEach(visible) { customer in
                        customerRow(customer)
                            .listRowBackground(customer.isDue ? Color.red.opacity(0.07) : Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Tên, mã KH, hợp đồng...")
                .refreshable { await store.refresh() }
                .overlay {
                    if visible.isEmpty && !store.isLoading {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 35)).foregroundStyle(.secondary)
                            Text("Chưa có khách chăm sóc").font(.headline)
                            Text("Đồng bộ từ CRM trên máy tính để hiện danh sách.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }.padding(24)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .alert("Không gọi được", isPresented: Binding(get: { callError != nil }, set: { if !$0 { callError = nil } })) {
                Button("Đóng", role: .cancel) { callError = nil }
            } message: { Text(callError ?? "") }
            .task { store.start() }
            .onAppear { if store.needsSetup { showingSettings = true } }
            .onChange(of: phase) { newValue in
                if newValue == .active { store.start(); Task { await store.refresh() } }
                else { store.stop() }
            }
            .onChange(of: store.needsSetup) { needed in if needed { showingSettings = true } }
        }
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(value)).font(.system(size: 25, weight: .bold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func customerRow(_ c: CareCustomer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(.headline)
                    Text("Mã KH: \(c.cif)  •  \(c.contract)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                if c.isDue {
                    Text("ĐẾN HẸN").font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dư nợ").font(.caption2).foregroundStyle(.secondary)
                    Text(money(c.debtVnd)).font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dự kiến trả").font(.caption2).foregroundStyle(.secondary)
                    Text(money(c.expectedVnd)).font(.subheadline.weight(.semibold))
                }
            }
            HStack {
                Label(c.appointmentLabel, systemImage: "calendar").foregroundStyle(c.isDue ? Color.red : Color.secondary)
                Spacer()
                Text("SNQH: \(c.overdueDays.map(String.init) ?? "—") ngày").foregroundStyle(.secondary)
            }.font(.caption)
            Button {
                guard let phone = CareCustomer.normalizedPhone(c.phone),
                      let url = URL(string: "tel:\(phone)") else {
                    callError = "Khách hàng chưa có số điện thoại hợp lệ. Hãy cập nhật trên CRM PC."
                    return
                }
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success { callError = "iPhone chưa thể mở ứng dụng Điện thoại." }
                }
            } label: {
                Label("TÁC ĐỘNG · GỌI BẰNG SIM", systemImage: "phone.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.vertical, 8)
    }

    private func money(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "vi_VN"))) + " đ"
    }
}