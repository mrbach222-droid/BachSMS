import Foundation
import Photos

enum BSendMediaLibrary {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp"
    ]
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mpeg", "mpg", "3gp"
    ]

    static func isSupported(_ file: SharedTransferFile) -> Bool {
        let ext = file.url.pathExtension.lowercased()
        return imageExtensions.contains(ext) || videoExtensions.contains(ext)
    }

    static func save(_ file: SharedTransferFile) async throws {
        let ext = file.url.pathExtension.lowercased()
        let isImage = imageExtensions.contains(ext)
        let isVideo = videoExtensions.contains(ext)
        guard isImage || isVideo else {
            throw NSError(domain: "BSendPhotos", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Định dạng này không phải ảnh/video được hỗ trợ."])
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "BSendPhotos", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Chưa cấp quyền thêm ảnh. Vào Cài đặt → B Send → Ảnh và cho phép thêm ảnh."])
        }
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            throw NSError(domain: "BSendPhotos", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy file gốc trong B Send."])
        }
        try await PHPhotoLibrary.shared().performChanges {
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file.url)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file.url)
            }
        }
    }
}
