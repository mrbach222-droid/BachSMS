import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// An iOS document picker in IMPORT/COPY mode.
/// Single selection intentionally bypasses the multi-select "Mở" toolbar
/// that some Files/iCloud providers leave disabled or unresponsive.
/// Users can repeat the action to queue more than one file.
struct BSendNativeFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let file = urls.first else {
                onCancel()
                return
            }
            // Deliver the temporary imported file immediately, while its
            // security-scoped access is still valid. SendModel.add makes an
            // app-owned copy synchronously, independent of Files/iCloud.
            onPick(file)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
