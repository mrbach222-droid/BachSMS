import Foundation

struct CareCustomer: Codable, Identifiable, Hashable {
    let cif: String
    let contract: String
    let name: String
    let phone: String
    let debtVnd: Int?
    let overdueDays: Int?
    let appointmentDate: String?
    let expectedVnd: Int?

    var id: String { cif + "|" + contract }

    enum CodingKeys: String, CodingKey {
        case cif, contract, name, phone
        case debtVnd = "debt_vnd"
        case overdueDays = "overdue_days"
        case appointmentDate = "appointment_date"
        case expectedVnd = "expected_vnd"
    }

    var appointment: Date? {
        guard let appointmentDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: appointmentDate)
    }

    var isDue: Bool {
        guard let appointment else { return false }
        return Calendar.current.startOfDay(for: appointment) <= Calendar.current.startOfDay(for: Date())
    }

    var appointmentLabel: String {
        guard let appointment else { return "Chưa có lịch hẹn" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: appointment)
    }

    static func normalizedPhone(_ raw: String) -> String? {
        let s = raw.filter { $0.isNumber || $0 == "+" }
        let number: String
        if s.hasPrefix("+84") { number = "0" + s.dropFirst(3) }
        else if s.hasPrefix("84") && s.count == 11 { number = "0" + s.dropFirst(2) }
        else if s.count == 9 { number = "0" + s }
        else { number = s }
        return number.count == 10 && number.allSatisfy(\.isNumber) && number.hasPrefix("0") ? number : nil
    }
}

struct CareSnapshot: Decodable {
    let revision: String
    let updatedAt: String
    let customers: [CareCustomer]
    enum CodingKeys: String, CodingKey {
        case revision, customers
        case updatedAt = "updated_at"
    }
}