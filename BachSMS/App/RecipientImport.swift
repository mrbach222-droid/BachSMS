import Foundation
import CoreXLSX

struct SMSRecipient: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var phone: String
    var status: RecipientStatus = .pending
}

enum RecipientStatus: String, Codable {
    case pending
    case sent
    case skipped
}

enum RecipientParser {
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
        if source.hasPrefix("'") { source.removeFirst() }
        if source.range(of: #"^\d+(?:\.\d+)?[eE][+-]?\d+$"#, options: .regularExpression) != nil,
           let number = Double(source), number.isFinite, number.rounded() == number {
            source = String(format: "%.0f", number)
        } else if source.range(of: #"^\d+\.0+$"#, options: .regularExpression) != nil {
            source = String(source.prefix(while: { $0 != "." }))
        }
        guard source.range(of: #"^\+?[0-9][0-9 ()\.-]*$"#, options: .regularExpression) != nil else { return nil }
        var digits = source.filter { $0.isASCII && $0.isNumber }
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

enum SpreadsheetImporter {
    static func parse(url: URL) throws -> [SMSRecipient] {
        let ext = url.pathExtension.lowercased()
        if ext == "csv" || ext == "tsv" {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw ImportError.unsupported("Không đọc được bảng CSV. Hãy lưu CSV UTF-8 rồi nhập lại.")
            }
            return RecipientParser.parseLinesFromDelimited(text, delimiter: ext == "tsv" ? "\t" : nil)
        }
        guard ext == "xlsx" else {
            throw ImportError.unsupported("Bản native nhận .xlsx, .csv và .tsv. Hãy lưu tệp .xls thành .xlsx rồi nhập lại.")
        }
        guard let file = XLSXFile(filepath: url.path) else {
            throw ImportError.invalidFile
        }
        let workbooks = try file.parseWorkbooks()
        guard !workbooks.isEmpty else { throw ImportError.noSheet }
        let shared = try file.parseSharedStrings()
        // The first worksheet may be a cover, instructions or completely empty.
        for workbook in workbooks {
            for sheetInfo in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                let sheet = try file.parseWorksheet(at: sheetInfo.path)
                let rows: [[Int: String]] = (sheet.data?.rows ?? []).map { row in
                    var values: [Int: String] = [:]
                    for cell in row.cells {
                        let column = Self.columnIndex(cell.reference.column.value)
                        let value: String
                        if cell.type == .sharedString, let shared,
                           let index = cell.value.flatMap(Int.init), shared.items.indices.contains(index) {
                            let item = shared.items[index]
                            value = item.text ?? item.richText.compactMap(\.text).joined()
                        } else {
                            value = cell.inlineString?.text ?? cell.value ?? ""
                        }
                        values[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return values
                }
                let recipients = parseRows(rows)
                if !recipients.isEmpty { return recipients }
            }
        }
        return []
    }

    static func columnIndex(_ letters: String) -> Int {
        // Excel columns use one-based base 26; subtract once at the end (AA = 26).
        letters.uppercased().reduce(0) { ($0 * 26) + (Int($1.asciiValue ?? 64) - 64) } - 1
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
            if let phone {
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
            let candidateColumns = Set(nonEmpty.flatMap { $0.keys }).sorted()
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
        text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: #"[_\s]+"#, with: " ", options: .regularExpression)
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

extension RecipientParser {
    static func parseLinesFromDelimited(_ text: String, delimiter explicitDelimiter: Character?) -> [SMSRecipient] {
        let firstLine = text.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? ""
        let delimiter = explicitDelimiter ?? [Character(","), Character(";"), Character("\t")].max { lhs, rhs in
            firstLine.filter { $0 == lhs }.count < firstLine.filter { $0 == rhs }.count
        }!
        let rows = parseCSV(text, delimiter: delimiter)
        return SpreadsheetImporter.parseDelimitedRows(rows)
    }

    static func parseCSV(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [[]]
        var cell = ""
        var quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
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

extension SpreadsheetImporter {
    static func parseDelimitedRows(_ rows: [[String]]) -> [SMSRecipient] {
        let mapped = rows.map { row in Dictionary(uniqueKeysWithValues: row.enumerated().map { ($0.offset, $0.element) }) }
        return parseRows(mapped)
    }
}

