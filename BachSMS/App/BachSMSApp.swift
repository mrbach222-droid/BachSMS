import SwiftUI
import UniformTypeIdentifiers
import MessageUI
import CoreXLSX
import Combine

@main
struct BachSMSApp: App {
    var body: some Scene {
        WindowGroup {
            SMSRootView()
                .preferredColorScheme(.light)
        }
    }
}

private enum SMSPalette {
    static let background = Color(red: 0.95, green: 0.97, blue: 0.95)
    static let ink = Color(red: 0.08, green: 0.16, blue: 0.15)
    static let muted = Color(red: 0.39, green: 0.46, blue: 0.44)
    static let green = Color(red: 0.07, green: 0.48, blue: 0.37)
    static let paleGreen = Color(red: 0.89, green: 0.95, blue: 0.92)
    static let line = Color(red: 0.87, green: 0.91, blue: 0.88)
    static let card = Color.white
    static let preview = Color(red: 0.94, green: 0.98, blue: 0.96)
    static let warning = Color(red: 0.55, green: 0.35, blue: 0.15)
}

private struct SMSRecipient: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var phone: String
    var status: RecipientStatus = .pending
}

private enum RecipientStatus: String, Codable {
    case pending
    case sent
    case skipped
}

private enum SMSFlowStep: Int, Codable {
    case recipients
    case compose
    case review
    case complete
}

@MainActor
private final class SMSViewModel: ObservableObject {
    @Published var recipients: [SMSRecipient] { didSet { persist() } }
    @Published var template: String { didSet { persist() } }
    @Published var currentIndex: Int { didSet { persist() } }
    @Published var step: SMSFlowStep { didSet { persist() } }
    @Published var manualInput = ""
    @Published var alertText: String?
    @Published var isImporting = false

    private let storageKey = "bach.sms.native.v1.0.1"
    private let defaultTemplate = "Chào anh/chị {ten}, em là Bách. Em xin phép nhắc anh/chị về lịch thanh toán. Nếu anh/chị đã thanh toán, vui lòng bỏ qua tin nhắn này. Cảm ơn anh/chị."

    private struct SavedState: Codable {
        var recipients: [SMSRecipient]
        var template: String
        var currentIndex: Int
        var step: SMSFlowStep
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            recipients = saved.recipients
            template = saved.template
            currentIndex = min(saved.currentIndex, max(saved.recipients.count - 1, 0))
            step = saved.step
        } else {
            recipients = []
            template = defaultTemplate
            currentIndex = 0
            step = .recipients
        }
    }

    var currentRecipient: SMSRecipient? {
        recipients.indices.contains(currentIndex) ? recipients[currentIndex] : nil
    }

    var personalizedMessage: String {
        guard let currentRecipient else { return template.replacingOccurrences(of: "{ten}", with: "anh/chị") }
        return template.replacingOccurrences(of: "{ten}", with: currentRecipient.name)
    }

    var sentCount: Int { recipients.filter { $0.status == .sent }.count }
    var skippedCount: Int { recipients.filter { $0.status == .skipped }.count }
    var pendingCount: Int { recipients.filter { $0.status == .pending }.count }

    func addManualEntries() {
        let parsed = RecipientParser.parseLines(manualInput)
        guard !parsed.isEmpty else {
            alertText = "Mình chưa tìm thấy số điện thoại hợp lệ. Mỗi dòng nhập Tên, Số điện thoại hoặc chỉ nhập số."
            return
        }
        merge(parsed)
        manualInput = ""
    }

    func importFile(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let items = try await Task.detached(priority: .userInitiated) {
                try SpreadsheetImporter.parse(url: url)
            }.value
            guard !items.isEmpty else {
                alertText = "Tệp chưa có số điện thoại hợp lệ. Hãy kiểm tra tiêu đề cột Tên và Số điện thoại."
                return
            }
            merge(items)
            alertText = "Đã nhập \(items.count) liên hệ từ tệp."
        } catch {
            alertText = error.localizedDescription
        }
    }

    private func merge(_ newItems: [SMSRecipient]) {
        var seen = Set(recipients.map { RecipientParser.canonicalPhone($0.phone) })
        let unique = newItems.filter { seen.insert(RecipientParser.canonicalPhone($0.phone)).inserted }
        recipients.append(contentsOf: unique)
    }

    func removeRecipient(_ recipient: SMSRecipient) {
        recipients.removeAll { $0.id == recipient.id }
        currentIndex = min(currentIndex, max(recipients.count - 1, 0))
        if recipients.isEmpty {
            step = .recipients
        }
    }

    func beginCompose() {
        guard !recipients.isEmpty else {
            alertText = "Hãy thêm ít nhất một người nhận trước."
            return
        }
        step = .compose
    }

    func beginReview() {
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertText = "Hãy nhập nội dung tin nhắn trước."
            return
        }
        currentIndex = recipients.firstIndex(where: { $0.status == .pending }) ?? 0
        step = .review
    }

    func record(_ result: MessageComposeResult) {
        guard recipients.indices.contains(currentIndex) else { return }
        switch result {
        case .sent:
            recipients[currentIndex].status = .sent
            advanceToNext()
        case .cancelled:
            alertText = "Tin nhắn chưa được gửi. Người nhận vẫn giữ trạng thái chờ."
        case .failed:
            alertText = "iPhone báo gửi tin thất bại. Hãy thử lại sau."
        @unknown default:
            alertText = "Không đọc được kết quả gửi tin."
        }
    }

    func skipCurrent() {
        guard recipients.indices.contains(currentIndex) else { return }
        recipients[currentIndex].status = .skipped
        advanceToNext()
    }

    private func advanceToNext() {
        if let next = recipients.indices.first(where: { $0 > currentIndex && recipients[$0].status == .pending })
            ?? recipients.indices.first(where: { recipients[$0].status == .pending }) {
            currentIndex = next
        } else {
            step = .complete
        }
    }

    func resetProgress() {
        for index in recipients.indices { recipients[index].status = .pending }
        currentIndex = 0
        step = .recipients
    }

    func clearAll() {
        recipients = []
        currentIndex = 0
        step = .recipients
    }

    func previousStep() {
        switch step {
        case .recipients: break
        case .compose: step = .recipients
        case .review: step = .compose
        case .complete: step = .review
        }
    }

    private func persist() {
        let state = SavedState(recipients: recipients, template: template, currentIndex: currentIndex, step: step)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

fileprivate enum RecipientParser {
    static func parseLines(_ text: String) -> [SMSRecipient] {
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap { line in
            let pattern = #"\+?\d[\d\s().-]{6,}\d"#
            guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
            let token = String(line[range])
            guard let phone = normalizePhone(token) else { return nil }
            let name = line.replacingOccurrences(of: token, with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|\t")))
            let resolvedName = name.isEmpty ? "anh/chị" : name
            let key = canonicalPhone(phone)
            guard seen.insert(key).inserted else { return nil }
            return SMSRecipient(name: resolvedName, phone: phone)
        }
    }

    static func normalizePhone(_ value: String) -> String? {
        var source = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(source), source.range(of: #"^\d+(?:\.\d+)?[eE][+-]?\d+$"#, options: .regularExpression) != nil {
            source = String(format: "%.0f", number)
        }
        var digits = source.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        if digits.hasPrefix("00") { digits = String(digits.dropFirst(2)) }
        if digits.hasPrefix("0"), digits.count >= 9 {
            digits = "84" + digits.dropFirst()
        } else if digits.count == 9 {
            digits = "84" + digits
        }
        guard digits.count >= 10, digits.count <= 15 else { return nil }
        return "+" + digits
    }

    static func canonicalPhone(_ value: String) -> String {
        value.filter(\.isNumber)
    }
}

fileprivate enum SpreadsheetImporter {
    static func parse(url: URL) throws -> [SMSRecipient] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "csv" || ext == "tsv" {
            let text = try String(contentsOf: url, encoding: .utf8)
            return RecipientParser.parseLinesFromDelimited(text, delimiter: ext == "tsv" ? "\t" : nil)
        }
        guard ext == "xlsx" else {
            throw ImportError.unsupported("Bản native nhận .xlsx, .csv và .tsv. Hãy lưu tệp .xls thành .xlsx rồi nhập lại.")
        }
        guard let file = XLSXFile(filepath: url.path) else {
            throw ImportError.invalidFile
        }
        let workbook = try file.parseWorkbooks().first
        guard let workbook else { throw ImportError.noSheet }
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbook)
        guard let path = sheets.first?.path else { throw ImportError.noSheet }
        let sheet = try file.parseWorksheet(at: path)
        let shared = try file.parseSharedStrings()
        let rows: [[Int: String]] = (sheet.data?.rows ?? []).map { row in
            var values: [Int: String] = [:]
            for cell in row.cells {
                let column = Self.columnIndex(cell.reference.column.value)
                let value: String
                if let shared, let text = cell.stringValue(shared) {
                    value = text
                } else {
                    value = cell.value ?? ""
                }
                values[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return values
        }
        return parseRows(rows)
    }

    private static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().reduce(0) { ($0 * 26) + (Int($1.asciiValue ?? 64) - 64) - 1 }
    }

    private static func parseRows(_ rows: [[Int: String]]) -> [SMSRecipient] {
        let nonEmpty = rows.filter { $0.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
        guard !nonEmpty.isEmpty else { return [] }

        let phoneHeaders: Set<String> = ["sdt", "sdt kh", "sdt khach hang", "so dt", "so dien thoai", "dien thoai", "phone", "phone number", "mobile", "mobile number", "tel", "telephone"]
        let nameHeaders: Set<String> = ["ho ten", "ho va ten", "ten", "ten kh", "ten khach hang", "khach hang", "name", "full name", "customer", "customer name"]

        var headerRowIndex: Int?
        var phoneColumn: Int?
        var nameColumn: Int?

        for (rowIndex, row) in nonEmpty.enumerated() {
            let normalized = row.mapValues(normalizeHeader)
            let phone = normalized.first(where: { phoneHeaders.contains($0.value) })?.key
            let name = normalized.first(where: { nameHeaders.contains($0.value) })?.key
            if let phone, let name {
                headerRowIndex = rowIndex
                phoneColumn = phone
                nameColumn = name
                break
            }
        }

        let bodyRows: ArraySlice<[Int: String]>
        if let headerRowIndex {
            bodyRows = nonEmpty.dropFirst(headerRowIndex + 1)
        } else {
            bodyRows = nonEmpty[...]
            let candidateColumns = Set(nonEmpty.flatMap { $0.keys })
            phoneColumn = candidateColumns.max(by: { lhs, rhs in
                let left = nonEmpty.filter { RecipientParser.normalizePhone($0[lhs] ?? "") != nil }.count
                let right = nonEmpty.filter { RecipientParser.normalizePhone($0[rhs] ?? "") != nil }.count
                return left < right
            })
            if let phoneColumn {
                nameColumn = candidateColumns.filter { $0 != phoneColumn }.max(by: { lhs, rhs in
                    let left = nonEmpty.filter {
                        let value = ($0[lhs] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return !value.isEmpty && RecipientParser.normalizePhone(value) == nil
                    }.count
                    let right = nonEmpty.filter {
                        let value = ($0[rhs] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return !value.isEmpty && RecipientParser.normalizePhone(value) == nil
                    }.count
                    return left < right
                })
            }
        }

        guard let phoneColumn else { return [] }
        var result: [SMSRecipient] = []
        var seen = Set<String>()
        for row in bodyRows {
            guard let phone = RecipientParser.normalizePhone(row[phoneColumn] ?? "") else { continue }
            let nameValue = nameColumn.flatMap { row[$0] }
            let name = nameValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : "anh/chị"
            let key = RecipientParser.canonicalPhone(phone)
            if seen.insert(key).inserted { result.append(SMSRecipient(name: resolvedName, phone: phone)) }
        }
        return result
    }

    private static func normalizeHeader(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ImportError: LocalizedError {
        case invalidFile
        case noSheet
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Không đọc được tệp Excel. Hãy thử lưu lại thành .xlsx."
            case .noSheet: return "Tệp Excel không có trang tính dữ liệu."
            case .unsupported(let message): return message
            }
        }
    }
}

fileprivate extension RecipientParser {
    static func parseLinesFromDelimited(_ text: String, delimiter explicitDelimiter: Character?) -> [SMSRecipient] {
        let delimiter = explicitDelimiter ?? (text.components(separatedBy: .newlines).first?.filter { $0 == ";" }.count ?? 0 >
            (text.components(separatedBy: .newlines).first?.filter { $0 == "," }.count ?? 0) ? ";" : ",")
        let rows = parseCSV(text, delimiter: delimiter)
        return SpreadsheetImporter.parseDelimitedRows(rows)
    }

    static func parseCSV(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [[]]
        var cell = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"", index + 1 < chars.count, chars[index + 1] == "\"" {
                    cell.append("\"")
                    index += 1
                } else if char == "\"" {
                    quoted = false
                } else {
                    cell.append(char)
                }
            } else if char == "\"" {
                quoted = true
            } else if char == delimiter {
                rows[rows.count - 1].append(cell)
                cell = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
                rows[rows.count - 1].append(cell)
                cell = ""
                rows.append([])
            } else {
                cell.append(char)
            }
            index += 1
        }
        rows[rows.count - 1].append(cell)
        return rows
    }
}

fileprivate extension SpreadsheetImporter {
    static func parseDelimitedRows(_ rows: [[String]]) -> [SMSRecipient] {
        let mapped = rows.map { row in Dictionary(uniqueKeysWithValues: row.enumerated().map { ($0.offset, $0.element) }) }
        return parseRows(mapped)
    }
}

private struct SMSRootView: View {
    @StateObject private var model = SMSViewModel()
    @State private var showFileImporter = false
    @State private var showComposer = false
    @State private var composeResult: MessageComposeResult?
    @State private var fileImporterError: String?

    private var importTypes: [UTType] {
        [.spreadsheet, .commaSeparatedText, .plainText, .data]
    }

    var body: some View {
        ZStack {
            SMSPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch model.step {
                        case .recipients: recipientScreen
                        case .compose: composeScreen
                        case .review: reviewScreen
                        case .complete: completeScreen
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.importFile(url) }
            case .failure(let error):
                fileImporterError = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showComposer, onDismiss: {
            if let result = composeResult {
                composeResult = nil
                model.record(result)
            }
        }) {
            if let recipient = model.currentRecipient {
                SMSComposer(recipient: recipient.phone, message: model.personalizedMessage) { result in
                    composeResult = result
                    showComposer = false
                }
                .interactiveDismissDisabled()
            }
        }
        .alert("Bách SMS", isPresented: Binding(
            get: { model.alertText != nil || fileImporterError != nil },
            set: { if !$0 { model.alertText = nil; fileImporterError = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.alertText = nil; fileImporterError = nil }
        } message: {
            Text(model.alertText ?? fileImporterError ?? "")
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SMSPalette.green)
                Text("B").font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bách SMS").font(.system(size: 17, weight: .bold)).foregroundStyle(SMSPalette.ink)
                Text("Gửi có kiểm soát").font(.system(size: 12)).foregroundStyle(SMSPalette.muted)
            }
            Spacer()
            if model.step != .recipients {
                Button { model.previousStep() } label: {
                    Label("Quay lại", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SMSPalette.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(SMSPalette.card, in: Capsule())
                        .overlay(Capsule().stroke(SMSPalette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Label("Trên iPhone", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SMSPalette.muted)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(SMSPalette.card, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: 660)
        .frame(maxWidth: .infinity)
        .background(SMSPalette.background)
    }

    private var recipientScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                stepLabel("BƯỚC 1 TRÊN 3")
                Text("Danh sách nhận").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(SMSPalette.ink)
                Text("Nhập Excel hoặc dán danh sách. Tên và số sẽ được ghép thành từng người nhận.")
                    .font(.system(size: 14)).foregroundStyle(SMSPalette.muted)
            }

            Button { showFileImporter = true } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SMSPalette.paleGreen)
                        Image(systemName: "tablecells").font(.system(size: 22, weight: .semibold)).foregroundStyle(SMSPalette.green)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isImporting ? "Đang đọc tệp…" : "Chọn file Excel")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(SMSPalette.ink)
                        Text(".xlsx · .csv · .tsv").font(.system(size: 12)).foregroundStyle(SMSPalette.muted)
                    }
                    Spacer()
                    if model.isImporting { ProgressView().tint(SMSPalette.green) }
                    else { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(SMSPalette.green) }
                }
                .padding(16)
                .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SMSPalette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.isImporting)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hoặc dán nhanh").font(.system(size: 15, weight: .semibold)).foregroundStyle(SMSPalette.ink)
                    Spacer()
                    Text("Tên   Số điện thoại").font(.system(size: 11, weight: .medium)).foregroundStyle(SMSPalette.muted)
                }
                ZStack(alignment: .topLeading) {
                    if model.manualInput.isEmpty {
                        Text("Nguyễn An, 0912345678\nTrần Bình, 0909123456")
                            .font(.system(size: 14))
                            .foregroundStyle(SMSPalette.muted.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    }
                    TextEditor(text: $model.manualInput)
                        .font(.system(size: 14))
                        .frame(minHeight: 94, maxHeight: 150)
                        .padding(7)
                }
                .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(SMSPalette.line, lineWidth: 1))

                Button { model.addManualEntries() } label: {
                    Label("Thêm vào danh sách", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SMSPalette.green)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SMSPalette.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Người nhận").font(.system(size: 17, weight: .bold)).foregroundStyle(SMSPalette.ink)
                    Spacer()
                    Text("\(model.recipients.count) người")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SMSPalette.green)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(SMSPalette.paleGreen, in: Capsule())
                }
                if model.recipients.isEmpty {
                    Text("Danh sách bạn nhập sẽ hiện ở đây để kiểm tra trước khi gửi.")
                        .font(.system(size: 13)).foregroundStyle(SMSPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(model.recipients) { person in
                        recipientRow(person)
                    }
                }
                if !model.recipients.isEmpty {
                    Button("Xóa toàn bộ danh sách", role: .destructive) { model.clearAll() }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.top, 3)
                }
            }
        }
    }

    private var composeScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                stepLabel("BƯỚC 2 TRÊN 3")
                Text("Soạn tin nhắn").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(SMSPalette.ink)
                Text("Dùng {ten} để tự thay bằng tên tương ứng trong danh sách.")
                    .font(.system(size: 14)).foregroundStyle(SMSPalette.muted)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Nội dung mẫu").font(.system(size: 15, weight: .semibold)).foregroundStyle(SMSPalette.ink)
                    Spacer()
                    Button("Mẫu gợi ý") {
                        model.template = "Chào anh/chị {ten}, em là Bách. Em xin phép nhắc anh/chị về lịch thanh toán. Nếu anh/chị đã thanh toán, vui lòng bỏ qua tin nhắn này. Cảm ơn anh/chị."
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SMSPalette.green)
                }
                TextEditor(text: $model.template)
                    .font(.system(size: 15))
                    .frame(minHeight: 170, maxHeight: 280)
                    .padding(10)
                    .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(SMSPalette.line, lineWidth: 1))
                Text("\(model.template.count) ký tự · Nội dung được lưu trên iPhone")
                    .font(.system(size: 11)).foregroundStyle(SMSPalette.muted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Xem trước theo khách").font(.system(size: 15, weight: .semibold)).foregroundStyle(SMSPalette.ink)
                if let first = model.recipients.first {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 20)).foregroundStyle(SMSPalette.green)
                        Text(first.name).font(.system(size: 14, weight: .medium)).foregroundStyle(SMSPalette.ink)
                        Spacer()
                        Text(first.phone).font(.system(size: 12)).foregroundStyle(SMSPalette.muted)
                    }
                    .padding(13)
                    .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 14))
                    Text(model.template.replacingOccurrences(of: "{ten}", with: first.name))
                        .font(.system(size: 14))
                        .foregroundStyle(SMSPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(SMSPalette.preview, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SMSPalette.line, lineWidth: 1))
                }
            }
        }
    }

    private var reviewScreen: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 7) {
                stepLabel("BƯỚC 3 TRÊN 3")
                Text("Kiểm tra & gửi").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(SMSPalette.ink)
                Text("\(model.sentCount + model.skippedCount + 1) / \(model.recipients.count) · Bạn xác nhận từng tin")
                    .font(.system(size: 14)).foregroundStyle(SMSPalette.muted)
            }
            ProgressView(value: Double(model.sentCount + model.skippedCount), total: Double(max(model.recipients.count, 1)))
                .tint(SMSPalette.green)

            if let person = model.currentRecipient {
                HStack(spacing: 13) {
                    ZStack {
                        Circle().fill(SMSPalette.paleGreen)
                        Text(String(person.name.prefix(1)).uppercased())
                            .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(SMSPalette.green)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(.system(size: 16, weight: .bold)).foregroundStyle(SMSPalette.ink)
                        Text(person.phone).font(.system(size: 13, weight: .medium)).foregroundStyle(SMSPalette.muted)
                    }
                    Spacer()
                    Text(person.status == .sent ? "ĐÃ GỬI" : "ĐÚNG SỐ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SMSPalette.green)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(SMSPalette.paleGreen, in: Capsule())
                }
                .padding(15)
                .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(SMSPalette.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("NỘI DUNG TIN NHẮN").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(SMSPalette.green)
                        Spacer()
                        Image(systemName: "eye").foregroundStyle(SMSPalette.green)
                    }
                    Text(model.personalizedMessage)
                        .font(.system(size: 15))
                        .foregroundStyle(SMSPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(17)
                .background(SMSPalette.preview, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(SMSPalette.line, lineWidth: 1))

                Text("Nội dung trên được cá nhân hóa theo đúng người nhận. Khi mở Tin nhắn, bạn kiểm tra lại rồi tự chạm Gửi.")
                    .font(.system(size: 12))
                    .foregroundStyle(SMSPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    guard MFMessageComposeViewController.canSendText() else {
                        model.alertText = "iPhone chưa sẵn sàng gửi SMS. Hãy kiểm tra SIM và thử lại."
                        return
                    }
                    showComposer = true
                } label: {
                    Label("Mở trong Tin nhắn", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 17)
                        .background(SMSPalette.green, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button { model.skipCurrent() } label: {
                        Label("Bỏ qua", systemImage: "forward.end")
                            .frame(maxWidth: .infinity)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SMSPalette.muted)
                            .padding(.vertical, 14)
                            .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tiến độ").font(.system(size: 12, weight: .semibold)).foregroundStyle(SMSPalette.ink)
                    Text("\(model.sentCount) đã gửi · \(model.pendingCount) chờ gửi · \(model.skippedCount) bỏ qua")
                        .font(.system(size: 12)).foregroundStyle(SMSPalette.muted)
                    Text("“Đã gửi” chỉ ghi nhận kết quả iPhone trả về, không xác nhận SMS đã đến máy người nhận.")
                        .font(.system(size: 11)).foregroundStyle(SMSPalette.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 15))
            } else {
                Text("Không còn người nhận đang chờ.")
                    .foregroundStyle(SMSPalette.muted)
            }
        }
    }

    private var completeScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(SMSPalette.green)
                .padding(.top, 40)
            Text("Đã xử lý danh sách")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(SMSPalette.ink)
            Text("\(model.sentCount) tin đã gửi · \(model.skippedCount) bỏ qua")
                .font(.system(size: 14)).foregroundStyle(SMSPalette.muted)
            Text("Tiến độ được lưu trên iPhone. Trạng thái gửi không đồng nghĩa người nhận đã nhận được tin.")
                .font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(SMSPalette.muted)
                .padding(.horizontal, 12)
            Button("Gửi lại danh sách") { model.resetProgress() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Tạo danh sách mới", role: .destructive) { model.clearAll() }
                .font(.system(size: 14, weight: .medium))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var bottomBar: some View {
        Group {
            switch model.step {
            case .recipients:
                Button { model.beginCompose() } label: {
                    VStack(spacing: 3) {
                        Text("Bắt đầu soạn tin").font(.system(size: 16, weight: .semibold))
                        Text("\(model.recipients.count) người nhận").font(.system(size: 11, weight: .medium)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.vertical, 11)
                    .background(SMSPalette.green, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(model.recipients.isEmpty)
                .opacity(model.recipients.isEmpty ? 0.55 : 1)
            case .compose:
                Button { model.beginReview() } label: {
                    Text("Xem người nhận đầu tiên")
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                        .background(SMSPalette.green, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            case .review, .complete:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 660)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(SMSPalette.line).frame(height: 1) }
    }

    private func recipientRow(_ person: SMSRecipient) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(SMSPalette.paleGreen)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(SMSPalette.green)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(SMSPalette.ink).lineLimit(1)
                Text(person.phone).font(.system(size: 12)).foregroundStyle(SMSPalette.muted)
            }
            Spacer(minLength: 4)
            statusBadge(person.status)
            Button { model.removeRecipient(person) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(SMSPalette.muted.opacity(0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xóa \(person.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(SMSPalette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SMSPalette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func statusBadge(_ status: RecipientStatus) -> some View {
        switch status {
        case .pending:
            Text("Chờ").foregroundStyle(SMSPalette.muted).padding(.horizontal, 9).padding(.vertical, 6).background(SMSPalette.background, in: Capsule())
        case .sent:
            Text("Đã gửi").foregroundStyle(SMSPalette.green).padding(.horizontal, 9).padding(.vertical, 6).background(SMSPalette.paleGreen, in: Capsule())
        case .skipped:
            Text("Bỏ qua").foregroundStyle(SMSPalette.warning).padding(.horizontal, 9).padding(.vertical, 6).background(Color.orange.opacity(0.12), in: Capsule())
        }
    }

    private func stepLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(SMSPalette.green)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(SMSPalette.green.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct SMSComposer: UIViewControllerRepresentable {
    let recipient: String
    let message: String
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = [recipient]
        composer.body = message
        return composer
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result)
        }
    }
}

