import SwiftUI

struct CRMSyncView: View {
    @ObservedObject var controller: CRMSyncController
    let onImport: ([CRMSyncJob]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var crmCode = ""
    @State private var deviceName = ""
    @State private var selectedJobIDs = Set<String>()

    var body: some View {
        NavigationView {
            List {
                connectionSection
                if controller.isPaired {
                    jobsSection
                    statusSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Kết nối Bách CRM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                serverURL = controller.settings.serverURL
                crmCode = controller.settings.crmCode
                deviceName = controller.settings.deviceName
                if controller.isPaired {
                    await controller.refresh()
                    selectPendingJobs()
                }
            }
            .onChange(of: controller.jobs) { _ in
                selectPendingJobs()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var connectionSection: some View {
        Section {
            TextField("Địa chỉ PC, ví dụ http://192.168.1.20:8765", text: $serverURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .disableAutocorrection(true)
            TextField("Mã CRM gồm 6 ký tự", text: $crmCode)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
            TextField("Tên thiết bị", text: $deviceName)

            Button {
                controller.configure(
                    serverURL: serverURL,
                    crmCode: crmCode,
                    deviceName: deviceName
                )
                Task { await controller.pair() }
            } label: {
                HStack {
                    Label(
                        controller.isPaired ? "Ghép lại thiết bị" : "Ghép với CRM",
                        systemImage: "link"
                    )
                    Spacer()
                    if controller.connectionState == .connecting {
                        ProgressView()
                    }
                }
            }
            .disabled(
                serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || crmCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || controller.connectionState == .connecting
            )

            if controller.isPaired {
                Button {
                    Task {
                        await controller.refresh()
                        selectPendingJobs()
                    }
                } label: {
                    Label("Làm mới danh sách", systemImage: "arrow.clockwise")
                }

                Button("Ngắt ghép nối", role: .destructive) {
                    controller.unpair()
                    selectedJobIDs.removeAll()
                }
            }
        } header: {
            Text("Ghép nối")
        } footer: {
            Text("PC và iPhone cần cùng mạng trong bản thử đầu tiên. Mã CRM hiển thị trong BachCRMSync trên Windows.")
        }
    }

    private var jobsSection: some View {
        Section {
            if controller.jobs.isEmpty {
                Text("CRM chưa giao khách SMS mới.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.jobs) { job in
                    Button {
                        if selectedJobIDs.contains(job.id) {
                            selectedJobIDs.remove(job.id)
                        } else {
                            selectedJobIDs.insert(job.id)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedJobIDs.contains(job.id)
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(selectedJobIDs.contains(job.id) ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.customerName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(job.phone)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text("CIF: \(job.cif)")
                                    if let contract = job.contractNumber, !contract.isEmpty {
                                        Text("HĐ: \(contract)")
                                    }
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let selected = controller.jobs.filter { selectedJobIDs.contains($0.id) }
                    onImport(selected)
                    dismiss()
                } label: {
                    Label(
                        "Đưa \(selectedJobIDs.count) khách vào danh sách gửi",
                        systemImage: "arrow.down.doc"
                    )
                }
                .disabled(selectedJobIDs.isEmpty)
            }
        } header: {
            HStack {
                Text("Khách từ CRM")
                Spacer()
                Text("\(controller.jobs.count)")
            }
        }
    }

    private var statusSection: some View {
        Section {
            stateRow
            if controller.pendingUploadCount > 0 {
                Label(
                    "\(controller.pendingUploadCount) trạng thái đang chờ đồng bộ",
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(.orange)
            }
            if let message = controller.lastMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Trạng thái")
        }
    }

    @ViewBuilder
    private var stateRow: some View {
        switch controller.connectionState {
        case .notConfigured:
            Label("Chưa ghép nối", systemImage: "link.badge.plus")
                .foregroundStyle(.secondary)
        case .connecting:
            Label("Đang kết nối…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
        case .connected:
            Label("Đã kết nối", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .offline:
            Label("Đang ngoại tuyến", systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Kết nối lỗi", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectPendingJobs() {
        selectedJobIDs = Set(controller.jobs.map(\.id))
    }
}
