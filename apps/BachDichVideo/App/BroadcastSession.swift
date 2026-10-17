import SwiftUI
import ReplayKit

final class BroadcastSession: NSObject, ObservableObject, RPBroadcastActivityViewControllerDelegate, RPBroadcastControllerDelegate {
    @Published var presenting = false
    @Published var message = ""
    private var controller: RPBroadcastController?
    var onFinished: (() -> Void)?
    func begin(from presenter: UIViewController) {
        guard !presenting else { return }
        presenting = true
        let setupID = (Bundle.main.bundleIdentifier ?? "") + ".SetupUI"
        RPBroadcastActivityViewController.load(withPreferredExtension: setupID) { [weak self, weak presenter] activity, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let activity = activity, let presenter = presenter else {
                    self.presenting = false; self.message = "Không mở được phần ghép nối. Kiểm tra bản ký có giữ cả hai extension."; return
                }
                activity.delegate = self
                activity.modalPresentationStyle = .formSheet
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                }
                presenter.present(activity, animated: true)
            }
        }
    }
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController,
                                         didFinishWith broadcastController: RPBroadcastController?, error: Error?) {
        broadcastActivityViewController.dismiss(animated: true) {
            self.presenting = false
            guard let broadcastController = broadcastController, error == nil else {
                self.message = "Chưa bắt đầu. Nếu đã dùng mã, bấm Lưu trong app để tạo mã mới."; return
            }
            self.controller = broadcastController; broadcastController.delegate = self
            broadcastController.startBroadcast { [weak self] error in
                DispatchQueue.main.async {
                    self?.message = error == nil ? "Đã bắt đầu. Quay sang video cần dịch." : "Không bật được thu màn hình. Kiểm tra bản ký của extension."
                }
            }
        }
    }
    func broadcastController(_ broadcastController: RPBroadcastController, didFinishWithError error: Error?) {
        DispatchQueue.main.async { self.controller = nil; self.message = "Phần thu màn hình đã kết thúc."; self.onFinished?() }
    }
    func stop() {
        controller?.finishBroadcast { [weak self] _ in
            DispatchQueue.main.async { self?.controller = nil; self?.onFinished?() }
        }
    }
}

struct BroadcastLaunchButton: UIViewControllerRepresentable {
    @ObservedObject var session: BroadcastSession
    var enabled: Bool
    func makeUIViewController(context: Context) -> LauncherViewController {
        let controller = LauncherViewController()
        controller.action = { [weak controller] in if let controller = controller { session.begin(from: controller) } }
        return controller
    }
    func updateUIViewController(_ uiViewController: LauncherViewController, context: Context) {
        uiViewController.button.isEnabled = enabled && !session.presenting
        uiViewController.button.alpha = enabled ? 1 : 0.4
    }
}

final class LauncherViewController: UIViewController {
    let button = UIButton(type: .system)
    var action: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        button.setTitle("3. Ghép nối / bắt đầu chia sẻ", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor), button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    @objc private func tapped() { action?() }
}
