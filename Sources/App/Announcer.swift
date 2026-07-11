import AVFoundation
import Foundation
import SwiftData

/// Announcer voice pack — see `tools/generate_announcer.py` for the
/// ElevenLabs voice IDs and generated clip naming convention
/// (`name_<slug>.mp3`, `inarow_<n>.mp3`, `tail_<style>_<kind>_<i>.mp3`, ...).
enum AnnouncerVoice: String, CaseIterable, Identifiable {
    case charlie
    case jessica

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .charlie: return "Charlie"
        case .jessica: return "Jessica"
        }
    }
}

/// Announcer commentary intensity. Styles 4 (Vicious) and 5 (Unhinged) use
/// mild-to-real profanity — see `tools/generate_announcer.py`'s header
/// comment — and are adults-only; strip them before any App Store
/// submission.
enum AnnouncerStyle: Int, CaseIterable, Identifiable {
    case classic = 1
    case spicy = 2
    case scorched = 3
    case vicious = 4
    case unhinged = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .spicy: return "Spicy"
        case .scorched: return "Scorched"
        case .vicious: return "Vicious"
        case .unhinged: return "Unhinged"
        }
    }
}

/// Convenience enum accessors over `AppSettings`'s raw storage. Defined
/// here (App layer) rather than in `Models/AppSettings.swift` so the
/// Models layer never has to import an App-layer enum.
extension AppSettings {
    var announcerVoiceSelection: AnnouncerVoice {
        get { AnnouncerVoice(rawValue: announcerVoiceRaw) ?? .charlie }
        set { announcerVoiceRaw = newValue.rawValue }
    }

    var announcerStyleSelection: AnnouncerStyle {
        get { AnnouncerStyle(rawValue: announcerStyle) ?? .classic }
        set { announcerStyle = newValue.rawValue }
    }
}

/// Plays sequences of pre-generated MP3 clips — name callout, optional stat
/// burst, flavor tail — for mid-game `GameInsights.Insight`s and end-of-game
/// results.
///
/// Design-time generation (`tools/generate_announcer.py`, driven by
/// ElevenLabs) may still be filling in `Sources/App/Resources/Announcer/`
/// when this ships to a build. Every lookup here gracefully skips a clip
/// that isn't present yet rather than failing, and if an entire sequence
/// resolves to zero segments, calling `announce`/`announceWinner` is a
/// silent no-op. Never blocks on or validates clip existence up front —
/// resolution happens lazily, per call, against whatever is in the bundle.
final class AnnouncerPlayer {
    static let shared = AnnouncerPlayer()

    /// Strong reference to the in-flight playback. A new `announce`/
    /// `announceWinner` call simply replaces this, which stops (and, once
    /// nothing else retains it, deallocates) whatever was playing before.
    private var queuePlayer: AVQueuePlayer?

    private struct Manifest: Decodable {
        let voices: [String]
        /// style number (as string, "1"..."5") -> kind name -> variant count.
        let styles: [String: [String: Int]]
        let names: [String]
        let aliases: [String: String]
        let inarow: [Int]
        let perfect: [Int]
        let points: [Int]
        let zeros: [Int]
    }

    private let manifest: Manifest?

    private init() {
        manifest = Self.loadManifest()
        if manifest == nil {
            print("Announcer: manifest.json not found or unreadable — announcer will be silent")
        }
    }

    private static func loadManifest() -> Manifest? {
        guard let url = resourceURL(basename: "manifest", ext: "json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - Public API

    /// Plays [name] + [stat, if applicable] + [tail] for a mid-game
    /// insight. Any segment whose clip can't be resolved is skipped.
    /// Returns the number of segments actually queued for playback (0 if
    /// nothing resolved), which is also printed to the console alongside
    /// the miss count for on-device verification.
    @discardableResult
    func announce(insight: GameInsights.Insight, voice: AnnouncerVoice, style: AnnouncerStyle) -> Int {
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voiceRaw) { urls.append(u) }

        if let statBasename = statBasename(kind: insight.kind, value: insight.value) {
            attempted += 1
            if let u = resolvedURL(basename: statBasename, voice: voiceRaw) { urls.append(u) }
        }

        attempted += 1
        if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voiceRaw) { urls.append(u) }

        return play(urls: urls, attempted: attempted)
    }

    /// Plays [name] + [tail winner]; if `lastPlaceName` is given and
    /// `style` is Spicy (2) or above, appends [name] + [tail lastPlace].
    /// Same graceful-skip and return-count behavior as `announce`.
    @discardableResult
    func announceWinner(name: String, lastPlaceName: String?, voice: AnnouncerVoice, style: AnnouncerStyle) -> Int {
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(name, voice: voiceRaw) { urls.append(u) }
        attempted += 1
        if let u = tailURL(kindName: "winner", style: style, voice: voiceRaw) { urls.append(u) }

        if let lastPlaceName, style.rawValue >= AnnouncerStyle.spicy.rawValue {
            attempted += 1
            if let u = nameURL(lastPlaceName, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = tailURL(kindName: "lastPlace", style: style, voice: voiceRaw) { urls.append(u) }
        }

        return play(urls: urls, attempted: attempted)
    }

    // MARK: - Segment basenames (filename minus ".mp3")

    private func nameURL(_ playerName: String, voice: String) -> URL? {
        resolvedURL(basename: "name_\(slug(for: playerName))", voice: voice)
    }

    /// The stat clip basename for an insight's kind/value, or `nil` when
    /// the kind carries no stat clip by design (boldest bidder) or the
    /// value falls outside the generated range — both are silent skips,
    /// not misses.
    private func statBasename(kind: GameInsights.Kind, value: Int?) -> String? {
        guard let value else { return nil }
        switch kind {
        case .hotStreak, .coldStreak:
            guard (2...15).contains(value) else { return nil }
            return "inarow_\(value)"
        case .perfect:
            guard (3...15).contains(value) else { return nil }
            return "perfect_\(value)"
        case .bigRound:
            guard (40...220).contains(value), value % 10 == 0 else { return nil }
            return "points_\(value)"
        case .zeroSpecialist:
            guard (3...10).contains(value) else { return nil }
            return "zeros_\(value)"
        case .boldestBidder:
            return nil
        }
    }

    /// Picks a random tail variant for (style, kind) from the manifest's
    /// variant count, resolves it, and falls back to variant 0 if the
    /// randomly-chosen file isn't on disk yet (generation may still be in
    /// progress). Returns `nil` only if neither is resolvable.
    private func tailURL(kindName: String, style: AnnouncerStyle, voice: String) -> URL? {
        guard let count = manifest?.styles[String(style.rawValue)]?[kindName], count > 0 else { return nil }
        let variant = Int.random(in: 0..<count)
        if let url = resolvedURL(basename: "tail_\(style.rawValue)_\(kindName)_\(variant)", voice: voice) {
            return url
        }
        if variant != 0, let url = resolvedURL(basename: "tail_\(style.rawValue)_\(kindName)_0", voice: voice) {
            return url
        }
        return nil
    }

    // MARK: - Name slugging

    /// Lowercased, trimmed, diacritic-folded, then run through the
    /// manifest's aliases (e.g. "nicky" -> "nikki") so callers can pass
    /// whatever display name is on file.
    private func slug(for playerName: String) -> String {
        let folded = playerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        return manifest?.aliases[folded] ?? folded
    }

    // MARK: - File resolution

    /// Tries both plausible bundling layouts for a voice-scoped clip,
    /// since Xcode's handling of nested folder references vs. flattened
    /// groups can differ: `Announcer/<voice>/<basename>.mp3` as a true
    /// subdirectory, and `Announcer` as the subdirectory with `<voice>/`
    /// baked into the resource name.
    private func resolvedURL(basename: String, voice: String) -> URL? {
        if let url = Bundle.main.url(forResource: basename, withExtension: "mp3", subdirectory: "Announcer/\(voice)") {
            return url
        }
        if let url = Bundle.main.url(forResource: "\(voice)/\(basename)", withExtension: "mp3", subdirectory: "Announcer") {
            return url
        }
        return nil
    }

    /// Same dual-layout fallback as `resolvedURL`, for the top-level
    /// `manifest.json` (no voice subdirectory).
    private static func resourceURL(basename: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: basename, withExtension: ext, subdirectory: "Announcer") {
            return url
        }
        return Bundle.main.url(forResource: basename, withExtension: ext)
    }

    // MARK: - Playback

    /// Queues `urls` on a fresh `AVQueuePlayer`, replacing any playback in
    /// progress. Prints a resolved/missing/attempted summary either way so
    /// a launch-arg smoke test (see `-announcerTest` in `WizardKeeperApp`)
    /// can be verified from console logs alone. Session deactivation after
    /// the queue ends is intentionally skipped — optional per spec, and
    /// one less thing to get wrong before a demo.
    @discardableResult
    private func play(urls: [URL], attempted: Int) -> Int {
        let missing = attempted - urls.count
        print("Announcer: \(urls.count) segment(s) resolved, \(missing) missing (of \(attempted) attempted)")
        guard !urls.isEmpty else { return 0 }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        let items = urls.map { AVPlayerItem(url: $0) }
        let player = AVQueuePlayer(items: items)
        queuePlayer = player
        player.play()
        return urls.count
    }
}
