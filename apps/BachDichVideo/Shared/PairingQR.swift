import Foundation
import CoreImage
import Vision
import ImageIO

/// The pairing code is shown by the host and read locally from its ReplayKit frame.
/// It contains no API key. A system-wide broadcast can start without App Groups/setupInfo.
enum PairingQR {
    private static let prefix = "BDV-PAIR:"
    static func code(from payload: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let code = String(payload.dropFirst(prefix.count))
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return code
    }
    static func image(code: String) -> CGImage? {
        guard Self.code(from: prefix + code) != nil,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data((prefix + code).utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let qr = filter.outputImage else { return nil }
        let background = CIImage(color: .white).cropped(to: qr.extent.insetBy(dx: -4, dy: -4))
        let output = qr.composited(over: background).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent)
    }
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> String? {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue.flatMap { code(from: $0) } }.first
    }
}
