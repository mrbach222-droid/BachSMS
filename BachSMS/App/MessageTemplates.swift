import Foundation

enum SMSTemplateGroup: String, CaseIterable, Identifiable {
    case reminder
    case missedPromise
    case family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reminder: return "Nhắc khách hàng"
        case .missedPromise: return "Khách sai hẹn"
        case .family: return "Nhờ người nhà chuyển lời"
        }
    }

    var guidance: String {
        switch self {
        case .reminder:
            return "Nhắc lịch → xác nhận mốc → yêu cầu phản hồi rõ ràng."
        case .missedPromise:
            return "Dùng khi đã qua lịch hẹn. Kiểm tra kết quả thanh toán trước khi gửi."
        case .family:
            return "Tên trong danh sách là tên khách cần chuyển lời; số điện thoại là số người nhà. Chỉ chuyển lời khi được phép liên hệ, không yêu cầu trả thay."
        }
    }
}

struct SMSSuggestedTemplate: Identifiable {
    let id: String
    let group: SMSTemplateGroup
    let level: Int
    let title: String
    let body: String

    var levelTitle: String {
        if group == .family {
            switch level {
            case 1: return "Mức 1 · Lịch sự"
            case 2: return "Mức 2 · Liên hệ sớm"
            default: return "Mức 3 · Mốc phản hồi rõ"
            }
        }
        switch level {
        case 1: return "Mức 1 · Nhẹ nhàng"
        case 2: return "Mức 2 · Rõ yêu cầu"
        default: return "Mức 3 · Kiên quyết"
        }
    }
}

enum SMSTemplateLibrary {
    static let all: [SMSSuggestedTemplate] = [
        .init(id: "reminder-1", group: .reminder, level: 1, title: "Nhắc lịch thanh toán",
              body: "Chào {ten}, em là Bách. Em xin nhắc anh/chị kiểm tra lịch thanh toán đã thống nhất và chuẩn bị thực hiện đúng hạn. Nếu đã thanh toán, anh/chị vui lòng phản hồi để em đối chiếu. Cảm ơn anh/chị."),
        .init(id: "reminder-2", group: .reminder, level: 2, title: "Xác nhận thời điểm cụ thể",
              body: "Chào {ten}, em là Bách. Đề nghị anh/chị xác nhận thời điểm thanh toán cụ thể trong hôm nay để em theo dõi đúng lịch. Nếu có vướng mắc, anh/chị vui lòng trao đổi trực tiếp để thống nhất phương án phù hợp."),
        .init(id: "reminder-3", group: .reminder, level: 3, title: "Đề nghị phản hồi rõ ràng",
              body: "Kính gửi {ten}, tôi là Bách. Đề nghị anh/chị thực hiện nghĩa vụ thanh toán theo lịch đã thống nhất và phản hồi rõ thời gian xử lý trong hôm nay. Trường hợp chưa thể thực hiện, vui lòng nêu lý do và đề xuất thời điểm cụ thể để trao đổi trực tiếp."),

        .init(id: "missed-1", group: .missedPromise, level: 1, title: "Kiểm tra sau lịch hẹn",
              body: "Chào {ten}, em là Bách. Theo lịch hẹn đã thống nhất, thời điểm thanh toán đã đến nhưng em chưa xác nhận được kết quả. Anh/chị kiểm tra và phản hồi giúp em; nếu đã thanh toán, vui lòng cung cấp thông tin cần thiết để đối chiếu."),
        .init(id: "missed-2", group: .missedPromise, level: 2, title: "Yêu cầu giải thích và mốc mới",
              body: "Chào {ten}, tôi là Bách. Lịch thanh toán anh/chị đã hẹn chưa được xác nhận hoàn tất. Đề nghị anh/chị phản hồi trong hôm nay, nêu rõ lý do chậm và thời gian có thể thực hiện. Cần một mốc hẹn cụ thể để tiếp tục theo dõi."),
        .init(id: "missed-3", group: .missedPromise, level: 3, title: "Chốt phương án thực hiện",
              body: "Kính gửi {ten}, tôi là Bách. Lịch hẹn thanh toán đã qua nhưng chưa có xác nhận hoàn tất. Đề nghị anh/chị chủ động liên hệ trong hôm nay và đưa ra phương án thực hiện cụ thể. Vui lòng chỉ xác nhận mốc mới sau khi đã cân đối khả năng thực hiện."),

        .init(id: "family-1", group: .family, level: 1, title: "Nhờ chuyển lời liên hệ",
              body: "Chào anh/chị, em là Bách. Nếu thuận tiện, nhờ anh/chị chuyển lời tới {ten} liên hệ trực tiếp với em qua số đang nhắn. Em cần trao đổi một nội dung riêng với người cần liên hệ. Cảm ơn anh/chị."),
        .init(id: "family-2", group: .family, level: 2, title: "Nhờ liên hệ lại trong hôm nay",
              body: "Chào anh/chị, tôi là Bách. Tôi đang cần liên hệ trực tiếp với {ten}. Nhờ anh/chị chuyển lời để {ten} phản hồi cho tôi trong hôm nay nếu thuận tiện. Nội dung sẽ được trao đổi riêng với người cần liên hệ. Cảm ơn anh/chị."),
        .init(id: "family-3", group: .family, level: 3, title: "Làm rõ đầu mối và mốc phản hồi",
              body: "Chào anh/chị, tôi là Bách. Tôi cần nhận phản hồi trực tiếp từ {ten} trong hôm nay để thống nhất nội dung trao đổi. Nếu có thể, nhờ anh/chị chuyển lời giúp và để {ten} chủ động liên hệ qua số này. Nếu đây không phải đầu mối phù hợp, anh/chị vui lòng báo lại để tôi cập nhật.")
    ]

    static func templates(in group: SMSTemplateGroup) -> [SMSSuggestedTemplate] {
        all.filter { $0.group == group }.sorted { $0.level < $1.level }
    }

    static func template(id: String?) -> SMSSuggestedTemplate? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
