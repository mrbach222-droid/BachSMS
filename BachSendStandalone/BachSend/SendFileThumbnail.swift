import SwiftUI
import AVFoundation
import ImageIO
import UIKit

/// Compact, locally generated preview. Never uploads media or preview data.
struct SendFileThumbnail: View {
    let url: URL
    var width: CGFloat = 48
    var height: CGFloat = 52

    @State private var preview: UIImage?
    @State private var length: String?
    @State private var isVideo = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.10, green: 0.20, blue: 0.31))
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    Image(systemName: isVideo ? "video.fill" : iconName)
                        .font(.system(size: 21))
                        .foregroundStyle(Color(red: 0.39, green: 0.88, blue: 1))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let length {
                Text(length)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(3)
            } else if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.7), in: Circle())
                    .padding(3)
            }
        }
        .frame(width: width, height: height)
        .task(id: url) {
            isVideo = Self.videos.contains(url.pathExtension.lowercased())
            let data = await Task.detached(priority: .utility) {
                await Self.generate(url)
            }.value
            preview = data.0
            length = data.1
        }
    }

    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        if Self.images.contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc.fill"
    }

    private static let images: Set<String> = ["jpg","jpeg","png","heic","heif","webp","gif","tiff","bmp"]
    private static let videos: Set<String> = ["mp4","mov","m4v","avi","mkv","webm"]

    private static func formatTime(_ secs: Double) -> String? {
        guard secs.isFinite && secs >= 0 else { return nil }
        let seconds = Int(secs.rounded())
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, rest)
        }
        return String(format: "%02d:%02d", minutes, rest)
    }

    private static func generate(_ file: URL) async -> (UIImage?, String?) {
        let ext = file.pathExtension.lowercased()
        if images.contains(ext) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return (nil,nil) }
            let opts: [CFString:Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
                return (nil,nil)
            }
            return (UIImage(cgImage:cg),nil)
        }
        if videos.contains(ext) {
            let asset = AVURLAsset(url: file)
            let duration = try? await asset.load(.duration)
            let time = duration.map { formatTime(CMTimeGetSeconds($0)) } ?? nil
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 180, height: 180)
            let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.15, preferredTimescale: 600),
                                                actualTime: nil)
            return (cg.map(UIImage.init(cgImage:)),time)
        }
        return (nil,nil)
    }
}
