import UIKit
import ReplayKit

final class BroadcastSetupViewController: UIViewController {
    private let codeField = UITextField()
    private let message = UILabel()
    private let connect = UIButton(type: .system)
    private let client = BridgeClient()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = "Ghép nối Bách Dịch Video"
        title.font = .boldSystemFont(ofSize: 24); title.numberOfLines = 0
        let detail = UILabel()
        detail.text = "Nhập mã 6 số đang hiện trong app chính. Mã dùng một lần, hết hạn sau 2 phút."
        detail.numberOfLines = 0; detail.textColor = .secondaryLabel
        codeField.placeholder = "Mã 6 số"; codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode; codeField.borderStyle = .roundedRect
        codeField.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        codeField.textAlignment = .center
        codeField.accessibilityLabel = "Mã ghép nối 6 số"
        connect.setTitle("Ghép nối và bắt đầu", for: .normal)
        connect.titleLabel?.font = .boldSystemFont(ofSize: 18)
        connect.addTarget(self, action: #selector(pair), for: .touchUpInside)
        let cancel = UIButton(type: .system); cancel.setTitle("Hủy", for: .normal)
        cancel.addTarget(self, action: #selector(cancelPairing), for: .touchUpInside)
        message.numberOfLines = 0; message.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [title, detail, codeField, connect, message, cancel])
        stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            codeField.heightAnchor.constraint(equalToConstant: 58)
        ])
    }
    @objc private func pair() {
        let code = (codeField.text ?? "").filter(\.isNumber)
        guard code.count == 6 else { message.text = "Nhập đủ 6 số trong app chính."; return }
        codeField.resignFirstResponder(); connect.isEnabled = false; message.text = "Đang ghép nối trong máy…"
        client.post(["code": code], path: "/pair") { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connect.isEnabled = true
                switch result {
                case .success(let reply):
                    guard reply.ok, let token = reply.token, let settings = reply.settings,
                          let data = try? JSONEncoder().encode(settings) else {
                        self.message.text = reply.message; return
                    }
                    let info: [String: NSCoding & NSObjectProtocol] = [
                        "token": token as NSString, "settings": data.base64EncodedString() as NSString
                    ]
                    self.extensionContext?.completeRequest(withBroadcast: URL(string: LocalBridge.origin)!, setupInfo: info)
                case .failure:
                    self.message.text = "Không kết nối được app chính. Quay lại app, bấm Lưu để tạo mã mới rồi thử lại."
                }
            }
        }
    }
    @objc private func cancelPairing() {
        extensionContext?.cancelRequest(withError: NSError(domain: "BachDichVideo", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Bạn đã hủy ghép nối."]))
    }
}
