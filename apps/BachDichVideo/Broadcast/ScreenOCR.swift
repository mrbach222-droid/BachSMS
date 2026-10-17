import Foundation
import Vision
import CoreImage
import ImageIO
import ReplayKit

final class ScreenOCR {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func pairingCode(_ sample: CMSampleBuffer) throws -> String? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let raw = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber
        let orientation = CGImagePropertyOrientation(rawValue: raw?.uint32Value ?? 1) ?? .up
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return try PairingQR.read(cgImage, orientation: orientation)
    }

    func recognize(_ sample: CMSampleBuffer, region: SubtitleRegion) throws -> String {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return "" }
        let raw = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString,
                                  attachmentModeOut: nil) as? NSNumber
        let orientation = CGImagePropertyOrientation(rawValue: raw?.uint32Value ?? 1) ?? .up
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let scale = min(1, 960 / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR", "vi-VN"]
            .filter { supported.contains($0) }
        let r = region.bounds
        request.regionOfInterest = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        request.minimumTextHeight = 0.012
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let lines = (request.results ?? []).filter { $0.confidence >= 0.3 }
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }.compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(900))
    }
}
