import SwiftUI
import UIKit
import MessageUI
import UniformTypeIdentifiers

// Present Apple's controllers as modals, never as the SwiftUI cover's content.
// This gives the system SMS service the actual window bounds and keyboard lifecycle.
struct NativePresentation: UIViewControllerRepresentable {
    @Binding var showFilePicker: Bool
    @Binding var showSMS: Bool
    let recipient: String
    let message: String
    let onFile: (Result<URL, Error>) -> Void
    let onSMS: (MessageComposeResult) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> NativePresentationController {
        NativePresentationController()
    }

    func updateUIViewController(_ controller: NativePresentationController, context: Context) {
        controller.requestFilePicker = showFilePicker
        controller.requestSMS = showSMS
        controller.recipient = recipient
        controller.message = message
        controller.onFile = { result in
            showFilePicker = false
            if let result { onFile(result) }
        }
        controller.onSMS = { result in
            showSMS = false
            onSMS(result)
        }
        controller.onError = { text in
            showSMS = false
            showFilePicker = false
            onError(text)
        }
        // SwiftUI may update before the host is attached to its window.
        DispatchQueue.main.async { controller.presentRequestedController() }
    }
}

final class NativePresentationController: UIViewController, MFMessageComposeViewControllerDelegate,
    UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    var requestFilePicker = false
    var requestSMS = false
    var recipient = ""
    var message = ""
    var onFile: ((Result<URL, Error>?) -> Void)?
    var onSMS: ((MessageComposeResult) -> Void)?
    var onError: ((String) -> Void)?
    private enum Modal { case file, sms }
    private var activeModal: Modal?
    private var finishing = false

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentRequestedController()
    }

    func presentRequestedController() {
        guard viewIfLoaded?.window != nil, activeModal == nil,
              presentedViewController == nil, !isBeingDismissed else { return }
        if requestSMS {
            guard MFMessageComposeViewController.canSendText(), !recipient.isEmpty else {
                requestSMS = false
                onError?("iPhone chưa sẵn sàng gửi SMS. Hãy kiểm tra SIM và thử lại.")
                return
            }
            view.window?.endEditing(true)
            let composer = MFMessageComposeViewController()
            composer.messageComposeDelegate = self
            composer.recipients = [recipient]
            composer.body = message
            composer.modalPresentationStyle = .fullScreen
            activeModal = .sms
            finishing = false
            present(composer, animated: true)
        } else if requestFilePicker {
            view.window?.endEditing(true)
            // .item lets files supplied by third-party providers remain selectable.
            // The importer validates the extension after selection.
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            activeModal = .file
            finishing = false
            present(picker, animated: true)
            picker.presentationController?.delegate = self
        }
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        guard activeModal == .sms, !finishing else { return }
        finishing = true
        requestSMS = false
        controller.view.endEditing(true)
        // UIKit dismissal is mandatory; deliver the result only after it completes.
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.onSMS?(result)
            self.activeModal = nil
            self.finishing = false
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard activeModal == .file, !finishing else { return }
        let result: Result<URL, Error>?
        if let url = urls.first {
            result = Result { try Self.copyImport(url) }
        } else {
            result = nil
        }
        finishFilePicker(controller, result: result)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishFilePicker(controller, result: nil)
    }

    private func finishFilePicker(_ controller: UIViewController, result: Result<URL, Error>?) {
        guard activeModal == .file, !finishing else { return }
        finishing = true
        requestFilePicker = false
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.onFile?(result)
            self.activeModal = nil
            self.finishing = false
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard activeModal == .file, !finishing else { return }
        requestFilePicker = false
        onFile?(nil)
        activeModal = nil
    }

    private static func copyImport(_ url: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do { try FileManager.default.copyItem(at: readableURL, to: destination) }
            catch { copyError = error }
        }
        if let error = coordinationError ?? (copyError as NSError?) {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return destination
    }
}
