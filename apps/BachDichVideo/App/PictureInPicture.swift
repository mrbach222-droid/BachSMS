import SwiftUI
import AVKit
import AVFoundation
import UIKit

final class CaptionSurface: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}

struct CaptionPreview: UIViewRepresentable {
    let controller: CaptionPiPController
    func makeUIView(context: Context) -> CaptionSurface { controller.surface }
    func updateUIView(_ uiView: CaptionSurface, context: Context) {}
}

final class CaptionPiPController: NSObject, ObservableObject,
                                  AVPictureInPictureControllerDelegate,
                                  AVPictureInPictureSampleBufferPlaybackDelegate {
    let surface = CaptionSurface()
    @Published var possible = false
    @Published var active = false
    @Published var message = "Khung nổi chưa bật"
    private var controller: AVPictureInPictureController?
    private var observation: NSKeyValueObservation?
    private var timer: Timer?
    private var timebase: CMTimebase?
    private var pool: CVPixelBufferPool?
    private var snapshot = CaptureSnapshot()
    private var settings = AppSettings()
    private var previewOnly = false
    var onPause: ((Bool) -> Void)?

    override init() {
        super.init()
        surface.backgroundColor = .black
        surface.displayLayer.videoGravity = .resizeAspect
        surface.accessibilityLabel = "Xem trước phụ đề dịch"
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase = timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1)
            surface.displayLayer.controlTimebase = timebase
        }
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 300,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            message = "Thiết bị này chưa hỗ trợ Picture in Picture."; return
        }
        let content = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: surface.displayLayer, playbackDelegate: self)
        controller = AVPictureInPictureController(contentSource: content)
        controller?.delegate = self
        controller?.requiresLinearPlayback = true
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        observation = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            DispatchQueue.main.async { self?.possible = pip.isPictureInPicturePossible }
        }
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.render() }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
    }
    deinit { timer?.invalidate() }
    func update(_ state: CaptureSnapshot, settings: AppSettings, previewOnly: Bool = false) {
        snapshot = state; self.settings = settings; self.previewOnly = previewOnly
    }
    func start() {
        do {
            // Mix with the source app; don't deliberately interrupt YouTube/TikTok audio.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            render()
            guard possible else { message = "Khung nổi chưa sẵn sàng. Chờ một chút rồi bấm lại."; return }
            message = "Đang mở khung nổi…"
            controller?.startPictureInPicture()
        } catch { message = "Không chuẩn bị được âm thanh cho khung nổi." }
    }
    func stop() { controller?.stopPictureInPicture() }

    private func render() {
        guard let pool = pool else { return }
        let layer = surface.displayLayer
        if layer.status == .failed { layer.flush() }
        guard layer.isReadyForMoreMediaData else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer = buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 300,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        context.translateBy(x: 0, y: 300); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        UIColor(red: 0.035, green: 0.06, blue: 0.1, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 640, height: 300))
        draw("BÁCH DỊCH  ·  VIỆT", in: CGRect(x: 24, y: 16, width: 590, height: 25),
             font: 16, color: UIColor(red: 0.35, green: 0.89, blue: 0.79, alpha: 1))
        let usable = previewOnly || (snapshot.isFresh && !snapshot.paused &&
            Date().timeIntervalSince(snapshot.translatedAt ?? .distantPast) < 12)
        let text = usable && !snapshot.translation.isEmpty ? snapshot.translation :
            (snapshot.active && !snapshot.isFresh ? "Mất tín hiệu phiên dịch. Mở app để kiểm tra." : snapshot.message)
        let height: CGFloat = settings.showOriginal && usable ? 145 : 210
        draw(text, in: CGRect(x: 24, y: 54, width: 592, height: height),
             font: CGFloat(settings.fontSize), color: .white)
        if settings.showOriginal && usable {
            draw(snapshot.source, in: CGRect(x: 24, y: 214, width: 592, height: 64), font: 19,
                 color: UIColor(white: 0.67, alpha: 1))
        }
        UIGraphicsPopContext()
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format) == noErr, let format = format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescription: format, sampleTiming: &timing,
            sampleBufferOut: &sample) == noErr, let sample = sample else { return }
        layer.enqueue(sample)
    }
    private func draw(_ text: String, in rect: CGRect, font: CGFloat, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 5
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: font, weight: .semibold),
                         .foregroundColor: color, .paragraphStyle: paragraph], context: nil)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        active = true; message = "Khung nổi đã bật"
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        active = false; message = "Khung nổi đã đóng"
        // Closing the floating window also pauses processing, so hidden API requests don't continue.
        onPause?(true)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        active = false; message = "iOS chưa mở được khung nổi. Thử trên iPhone thật và bật Picture in Picture trong Cài đặt."
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        onPause?(!playing)
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        snapshot.paused
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
