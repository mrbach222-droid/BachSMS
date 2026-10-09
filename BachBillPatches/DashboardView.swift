import SwiftUI
import PhotosUI
import UIKit

private enum BillStyle {
    static let accent = Color(red: 0.24, green: 0.92, blue: 0.74)
    static let background = Color(red: 0.035, green: 0.07, blue: 0.11)
    static let panel = Color(red: 0.085, green: 0.15, blue: 0.19)
}

private func displayVND(_ amount: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.maximumFractionDigits = 0
    return (formatter.string(from: NSNumber(value: amount)) ?? String(amount)) + "đ"
}

private struct BillShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct DashboardView: View {
    @StateObject private var store = ScanStore()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedRow: ScanRow?
    @State private var selectedUnresolved: UnresolvedImage?
    @State private var exportSheet: BillShareFile?
    @State private var askClear = false

    var body: some View {
        ZStack {
            BillStyle.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summary
                    imagePicker
                    reviewWarning
                    progressPanel
                    unresolvedPanel
                    invoiceList
                    exportPanel
                    Text("Dữ liệu và ảnh gốc lưu trên iPhone. Không chuyển lên máy chủ.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
                .padding(18)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedPhotos) { _, selection in
            Task {
                await store.importPhotos(selection)
                selectedPhotos = []
            }
        }
        .sheet(item: $selectedRow) { row in
            InvoiceReviewView(row: row, photoURL: store.photoURL(row)) { store.update($0) }
        }
        .sheet(item: $selectedUnresolved) { issue in
            UnreadableImageView(
                issue: issue,
                photoURL: store.photoURL(issue),
                onAdd: { store.addManual(from: issue) },
                onResolve: { store.dismissUnresolved(issue.id) }
            )
        }
        .sheet(item: $exportSheet) { file in
            BillActivityShareSheet(url: file.url)
        }
        .confirmationDialog("Xóa mọi hợp đồng và ảnh đã lưu?", isPresented: $askClear) {
            Button("Xóa toàn bộ", role: .destructive) { store.clear() }
        }
        .alert("Bách Bill", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(BillStyle.accent)
                .frame(width: 50, height: 50)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("BÁCH BILL").font(.system(size: 24, weight: .heavy, design: .rounded))
                Text("Quét ảnh · Kiểm tra số · Xuất Excel")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("TỔNG ĐÃ XÁC NHẬN", systemImage: "checkmark.shield.fill")
                .font(.caption.bold()).foregroundStyle(BillStyle.accent)
            Text(displayVND(store.total))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.55)
                .monospacedDigit()
            HStack(spacing: 10) {
                stat(store.rows.count, caption: "Đã nhận diện")
                stat(store.verified.count, caption: "Đã xác nhận")
                stat(store.pendingCount, caption: "Chờ kiểm tra")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BillStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(BillStyle.accent.opacity(0.3)))
    }

    private func stat(_ number: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(number)).font(.title2.bold()).monospacedDigit()
            Text(caption).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imagePicker: some View {
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 50, matching: .images) {
            HStack(spacing: 13) {
                Image(systemName: "plus.viewfinder").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chọn ảnh để quét").font(.headline)
                    Text("Tối đa 50 ảnh · OCR chạy trên iPhone").font(.caption)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
            }
            .padding(17)
            .foregroundStyle(BillStyle.background)
            .background(BillStyle.accent, in: RoundedRectangle(cornerRadius: 18))
        }
        .disabled(store.progress != nil)
    }

    private var reviewWarning: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.yellow)
            Text("Mỗi hợp đồng phải được đối chiếu với ảnh gốc rồi xác nhận. Số chưa xác minh không được cộng.")
                .font(.footnote).foregroundStyle(.white.opacity(0.8))
        }
    }

    @ViewBuilder private var progressPanel: some View {
        if let progress = store.progress {
            HStack(spacing: 12) {
                ProgressView().tint(BillStyle.accent)
                Text("Đang đọc ảnh \(progress.current)/\(progress.total)…")
                    .font(.subheadline)
            }
            .padding(12)
        }
    }

    private var unresolvedPanel: some View {
        VStack(spacing: 10) {
            if store.skippedDuplicates > 0 {
                Label("Đã bỏ qua \(store.skippedDuplicates) dòng trùng khớp.", systemImage: "doc.on.doc")
                    .font(.footnote).foregroundStyle(BillStyle.accent)
            }
            ForEach(store.unresolvedImages) { issue in
                Button { selectedUnresolved = issue } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.message).font(.footnote.bold())
                            Text("Mở ảnh gốc, nhập tay hoặc bỏ qua").font(.caption2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(14)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var invoiceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CHI TIẾT HỢP ĐỒNG").font(.caption.bold())
                Spacer()
                if !store.rows.isEmpty {
                    Button("Xóa tất cả", role: .destructive) { askClear = true }
                        .font(.caption)
                }
            }
            if store.rows.isEmpty {
                emptyState
            } else {
                ForEach(store.rows) { row in
                    Button { selectedRow = row } label: { invoiceRow(row) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 35)).foregroundStyle(BillStyle.accent)
            Text("Chưa có hóa đơn").font(.headline)
            Text("Chọn ảnh để tự nhận diện hợp đồng và số tiền.")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(BillStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func invoiceRow(_ row: ScanRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.excluded ? "minus.circle.fill" :
                  (row.reviewed ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
                .foregroundStyle(row.excluded ? Color.gray : (row.reviewed ? BillStyle.accent : Color.orange))
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.contractCode.isEmpty ? "Chưa rõ hợp đồng" : row.contractCode)
                    .font(.subheadline.bold())
                Text("#" + (row.orderCode.isEmpty ? "Chưa có mã đơn" : row.orderCode))
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(row.excluded ? "Đã loại khỏi tổng" :
                     (row.reviewed ? "Đã xác nhận" : "Chờ kiểm tra"))
                    .font(.caption2)
                    .foregroundStyle(row.reviewed ? BillStyle.accent : Color.orange)
            }
            Spacer(minLength: 6)
            Text(row.amount.map(displayVND) ?? "Chưa rõ")
                .font(.subheadline.bold()).monospacedDigit()
                .minimumScaleFactor(0.65).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
        .background(BillStyle.panel, in: RoundedRectangle(cornerRadius: 15))
    }

    private var exportPanel: some View {
        VStack(spacing: 10) {
            Button {
                do { exportSheet = BillShareFile(url: try store.exportExcel()) }
                catch { store.alertMessage = "Chưa thể xuất Excel. Hãy kiểm tra các hợp đồng." }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Xuất Excel (.xlsx)").bold()
                    Spacer()
                    Text("\(store.verified.count) đơn")
                }
                .padding(16)
                .foregroundStyle(store.canExport ? BillStyle.background : Color.white.opacity(0.55))
                .background(store.canExport ? BillStyle.accent : Color.white.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(!store.canExport)
            if !store.canExport && !store.rows.isEmpty {
                Text("Cần xác nhận hết các hợp đồng và xử lý ảnh chưa đọc được trước khi xuất Excel.")
                    .font(.caption).foregroundStyle(.white.opacity(0.58))
            }
        }
    }
}

private struct BillActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
