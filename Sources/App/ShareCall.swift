import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// "Share the Call": turns a recorded announcer broadcast (see
/// `AnnouncerPlayer.lastBroadcast`) into a vertical 1080x1920 MP4 — the
/// announcer audio played over a simple branded card whose caption swaps to
/// the current clip's spoken line — then hands it to the system share sheet.
/// The group-chat / TikTok artifact of a big call.
///
/// Caption timing is deliberately coarse: the card changes ONLY at clip
/// boundaries (no per-word karaoke). Each clip's spoken text comes from
/// `captions.json` (built by `tools/build_captions.py` from the same corpus
/// the clips were generated from), keyed by the clip's basename. Clips with
/// no caption entry — the `silence_200`/`silence_400` beats, or anything the
/// corpus doesn't cover — just hold the previous card, exactly as the audio
/// holds a pause.
final class ShareCallRenderer {
    private let width = 1080
    private let height = 1920
    private let fps: Int32 = 24

    // Dark-theme palette as fixed hex (Theme.swift's `Color`s are SwiftUI and
    // theme-tracking; the export is a fixed brand card, so it pins the dark
    // look): background #1E1915, cream text #EFE6D3, brass accent #A0721E.
    private static let bgColor = UIColor(red: 30 / 255, green: 25 / 255, blue: 21 / 255, alpha: 1)
    private static let textColor = UIColor(red: 239 / 255, green: 230 / 255, blue: 211 / 255, alpha: 1)
    private static let brassColor = UIColor(red: 160 / 255, green: 114 / 255, blue: 30 / 255, alpha: 1)

    /// The per-target display name ("Wizard Keeper" / "Oh Hell Keeper" /
    /// "Trash Talk"). `AppGame.config.displayName` can't be used here —
    /// TrashTalk reuses Wizard's game config, so its variant name is still
    /// "Wizard Keeper"; the bundle's `CFBundleDisplayName` is the real name.
    private static let appName: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Wizard Keeper"

    /// basename (no ".mp3") -> spoken text, loaded once from the bundled
    /// `Announcer/captions.json`. Same dual-layout fallback as
    /// `AnnouncerPlayer.loadManifest` (folder reference vs. flattened group).
    private static let captions: [String: String] = {
        let url = Bundle.main.url(forResource: "captions", withExtension: "json", subdirectory: "Announcer")
            ?? Bundle.main.url(forResource: "captions", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }()

    // Cancellation is advisory: `cancel()` flips the flag, and the render
    // loop checks it at every clip and every frame so a torn-down UI never
    // leaves a runaway encode behind. Guarded because the flag is read on the
    // background render queue and written from the main thread.
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock(); isCancelled = true; lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return isCancelled
    }

    /// Renders `broadcast` to an `.mp4` in the temporary directory and calls
    /// `completion` on the MAIN queue with the file URL (or `nil` on failure
    /// or cancellation). All encoding runs on a background queue — the
    /// calling thread is never blocked.
    func render(broadcast: [(basename: String, url: URL)],
                completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = self?.renderSync(broadcast: broadcast)
            DispatchQueue.main.async { completion(url) }
        }
    }

    // MARK: - Render pipeline

    private struct Segment {
        let range: CMTimeRange
        let caption: String
    }

    /// Full synchronous pipeline, run off the main thread: (1) concatenate
    /// the clips' audio into one composition, tracking a caption segment per
    /// clip; (2) render a video-only intermediate whose card changes at those
    /// segment boundaries; (3) mux audio + video into the final `.mp4`.
    private func renderSync(broadcast: [(basename: String, url: URL)]) -> URL? {
        guard !broadcast.isEmpty, !cancelled else { return nil }

        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }

        var cursor = CMTime.zero
        var segments: [Segment] = []
        var currentCaption = ""

        for clip in broadcast {
            if cancelled { return nil }
            let asset = AVURLAsset(url: clip.url)
            let duration = asset.duration
            guard duration.isValid, duration.seconds > 0 else { continue }
            if let track = asset.tracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration), of: track, at: cursor)
            }
            // A captioned clip swaps the card; a caption-less one (silence
            // beat, or a clip the corpus doesn't know) holds the last card.
            if let text = Self.captions[clip.basename] { currentCaption = text }
            segments.append(Segment(range: CMTimeRange(start: cursor, duration: duration), caption: currentCaption))
            cursor = cursor + duration
        }

        let totalDuration = cursor
        guard totalDuration.seconds > 0, !cancelled else { return nil }

        guard let videoURL = renderVideoTrack(segments: segments, totalDuration: totalDuration) else { return nil }
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let videoAsset = AVURLAsset(url: videoURL)
        if let vTrack = videoAsset.tracks(withMediaType: .video).first,
           let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compVideo.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoAsset.duration), of: vTrack, at: .zero)
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-call-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)

        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        export.outputURL = outURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        let sema = DispatchSemaphore(value: 0)
        export.exportAsynchronously { sema.signal() }
        sema.wait()

        guard export.status == .completed, !cancelled else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        return outURL
    }

    /// Writes the video-only intermediate (H.264, 1080x1920, `fps`). The card
    /// is static within a clip, so one pixel buffer is rendered per DISTINCT
    /// caption and reused across that segment's frames rather than redrawing
    /// every 24fps tick.
    private func renderVideoTrack(segments: [Segment], totalDuration: CMTime) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-call-video-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        var bufferCache: [String: CVPixelBuffer] = [:]
        func buffer(for caption: String) -> CVPixelBuffer? {
            if let cached = bufferCache[caption] { return cached }
            guard let pool = adaptor.pixelBufferPool,
                  let made = makePixelBuffer(pool: pool, caption: caption) else { return nil }
            bufferCache[caption] = made
            return made
        }

        let totalFrames = max(1, Int((totalDuration.seconds * Double(fps)).rounded(.up)))
        let queue = DispatchQueue(label: "com.levelup.sharecall.video")
        let sema = DispatchSemaphore(value: 0)
        var ok = true
        var frameIndex = 0

        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self else { input.markAsFinished(); sema.signal(); return }
            while input.isReadyForMoreMediaData {
                if self.cancelled { ok = false; input.markAsFinished(); sema.signal(); return }
                if frameIndex >= totalFrames { input.markAsFinished(); sema.signal(); return }
                let time = CMTime(value: CMTimeValue(frameIndex), timescale: self.fps)
                let caption = self.caption(at: time, in: segments)
                guard let pb = buffer(for: caption), adaptor.append(pb, withPresentationTime: time) else {
                    ok = false; input.markAsFinished(); sema.signal(); return
                }
                frameIndex += 1
            }
        }
        sema.wait()

        let finish = DispatchSemaphore(value: 0)
        writer.finishWriting { finish.signal() }
        finish.wait()

        guard ok, writer.status == .completed, !cancelled else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// The caption on screen at `time`: the segment containing it, falling
    /// back to the last segment's caption for the final boundary frame (whose
    /// timestamp equals the total duration and so sits in no half-open range).
    private func caption(at time: CMTime, in segments: [Segment]) -> String {
        for segment in segments where segment.range.containsTime(time) {
            return segment.caption
        }
        return segments.last?.caption ?? ""
    }

    // MARK: - Frame drawing

    private func makePixelBuffer(pool: CVPixelBufferPool, caption: String) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess,
              let pixelBuffer = out,
              let cgImage = drawCard(caption: caption) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // The card image is drawn in UIKit's top-left origin; the pixel
        // buffer context is bottom-left, so flip before blitting.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return pixelBuffer
    }

    /// Draws one frame: deep-charcoal fill, the app name small at top, the big
    /// centered caption in the middle band (auto-shrunk to fit), and a small
    /// "made with <app>" footer.
    private func drawCard(caption: String) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            Self.bgColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let margin: CGFloat = 96
            let contentWidth = size.width - margin * 2

            // Top: app name.
            drawCentered(
                Self.appName.uppercased(),
                font: .systemFont(ofSize: 46, weight: .semibold),
                color: Self.brassColor,
                width: contentWidth, x: margin, y: 150, kern: 3)

            // Middle: the caption, biggest text on the card, auto-fit.
            let capFont = fittedFont(for: caption, width: contentWidth, maxHeight: size.height * 0.5)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byWordWrapping
            let capAttrs: [NSAttributedString.Key: Any] = [
                .font: capFont, .foregroundColor: Self.textColor, .paragraphStyle: para,
            ]
            let bounds = (caption as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: size.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: capAttrs, context: nil)
            let capRect = CGRect(
                x: margin, y: (size.height - bounds.height) / 2,
                width: contentWidth, height: bounds.height)
            (caption as NSString).draw(
                with: capRect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: capAttrs, context: nil)

            // Footer: made with <app>.
            drawCentered(
                "made with \(Self.appName)",
                font: .systemFont(ofSize: 34, weight: .medium),
                color: Self.brassColor.withAlphaComponent(0.85),
                width: contentWidth, x: margin, y: size.height - 170, kern: 1)
        }
        return image.cgImage
    }

    /// Largest weight-heavy font from a descending ladder whose one-or-more
    /// wrapped lines fit `width` x `maxHeight`; the smallest is used if none
    /// fit (a very long caption simply wraps small rather than clipping).
    private func fittedFont(for text: String, width: CGFloat, maxHeight: CGFloat) -> UIFont {
        let sizes: [CGFloat] = [150, 132, 116, 100, 86, 72, 60]
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        for pointSize in sizes {
            let font = UIFont.systemFont(ofSize: pointSize, weight: .heavy)
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: para], context: nil)
            if bounds.width <= width, bounds.height <= maxHeight { return font }
        }
        return UIFont.systemFont(ofSize: sizes.last ?? 60, weight: .heavy)
    }

    private func drawCentered(_ text: String, font: UIFont, color: UIColor,
                              width: CGFloat, x: CGFloat, y: CGFloat, kern: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern,
        ]
        (text as NSString).draw(
            with: CGRect(x: x, y: y, width: width, height: font.lineHeight * 1.4),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }
}

/// The "Share the Call" button: renders the last broadcast to an MP4 (brief
/// spinner while it encodes), then presents the system share sheet. Self-
/// gating — it observes `AnnouncerPlayer` and shows nothing unless a
/// broadcast is shareable and not currently playing — so call sites can drop
/// it in without their own visibility check.
struct ShareCallButton: View {
    @ObservedObject private var announcer = AnnouncerPlayer.shared

    @State private var isRendering = false
    @State private var renderer: ShareCallRenderer?
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        if announcer.hasShareableBroadcast && !announcer.isPlaying {
            Button(action: startRender) {
                Group {
                    if isRendering {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Preparing…")
                        }
                    } else {
                        Label("Share the Call", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.appTint)
            .disabled(isRendering)
            .sheet(isPresented: $showShare) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
            .onDisappear { renderer?.cancel() }
        }
    }

    private func startRender() {
        guard !isRendering else { return }
        isRendering = true
        let renderer = ShareCallRenderer()
        self.renderer = renderer
        renderer.render(broadcast: announcer.lastBroadcast) { url in
            isRendering = false
            self.renderer = nil
            if let url {
                shareURL = url
                showShare = true
            }
        }
    }
}

/// Thin `UIActivityViewController` wrapper for the async-produced file URL —
/// `ShareLink` needs its item up front, but the MP4 only exists after the
/// render finishes, so the sheet is presented once `shareURL` is ready.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
