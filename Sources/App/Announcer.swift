import AVFoundation
import Combine
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
final class AnnouncerPlayer: ObservableObject {
    static let shared = AnnouncerPlayer()

    /// Strong reference to the in-flight playback. A new `announce`/
    /// `announceWinner`/`announceRoundUpdate` call simply replaces this,
    /// which stops (and, once nothing else retains it, deallocates)
    /// whatever was playing before.
    private var queuePlayer: AVQueuePlayer?

    /// Observes the last queued `AVPlayerItem`'s end-of-playback
    /// notification so `isPlaying` flips back to `false` once the whole
    /// sequence has finished (not just the first clip). Torn down and
    /// replaced on every new `play(urls:attempted:)` call and in `stop()`.
    private var endOfQueueObserver: NSObjectProtocol?

    /// One observer per queued `AVPlayerItem` for
    /// `.AVPlayerItemFailedToPlayToEndTime` — a mid-queue decode/IO failure
    /// otherwise leaves `isPlaying` stuck `true` forever, since it never
    /// fires the last item's normal end-of-playback notification. Torn down
    /// and replaced on every new `play(urls:attempted:)` call and in
    /// `stop()`, same lifecycle as `endOfQueueObserver`.
    private var failureObservers: [NSObjectProtocol] = []

    /// Observes `AVAudioSession.interruptionNotification` so an incoming
    /// call/Siri/alarm that interrupts playback also stops us cleanly
    /// instead of leaving `isPlaying` stuck `true` with a silently-paused
    /// player. Registered once (see `init`) and never torn down — it
    /// outlives any individual playback session.
    private var interruptionObserver: NSObjectProtocol?

    /// Whether a clip sequence is currently queued/playing. Drives the
    /// Trends section's Announce/Stop toggle button in `GameView`.
    @Published private(set) var isPlaying = false

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
        registerInterruptionObserver()
    }

    /// Registered once at init: on `.began` (interruption starting — a
    /// call, Siri, an alarm, another app grabbing the session), stop
    /// playback so `isPlaying` doesn't stay stuck `true` while the system
    /// has already silently paused us. `.ended` is intentionally not
    /// resumed automatically — the announcer is a one-shot callout, not a
    /// music player.
    private func registerInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                  type == .began else { return }
            self?.stop()
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
        beginAssembly()
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

    /// Plays a single short broadcast covering the table's current trends,
    /// replacing the old one-speaker-button-per-row UX: an optional random
    /// intro connective, then — for up to the first 3 `insights`, in the
    /// order given — that insight's `[name, stat?, tail]` segments (same
    /// resolution logic as `announce`), separated by a random transition
    /// connective between insights (never after the last), then an
    /// optional random outro connective.
    ///
    /// The connective clips (`seg_<style>_intro_<i>`, `_trans_<i>`,
    /// `_outro_<i>`) are a newer addition to `tools/generate_announcer.py`
    /// and may not exist yet for some/all styles — missing ones are
    /// skipped silently, same as any other clip. Same return-count
    /// behavior as `announce`/`announceWinner`.
    @discardableResult
    func announceRoundUpdate(insights: [GameInsights.Insight], voice: AnnouncerVoice, style: AnnouncerStyle) -> Int {
        beginAssembly()
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = connectiveURL(kind: "intro", style: style, voice: voiceRaw) { urls.append(u) }

        let selected = Array(insights.prefix(3))
        for (index, insight) in selected.enumerated() {
            attempted += 1
            if let u = nameURL(insight.playerName, voice: voiceRaw) { urls.append(u) }

            if let statBasename = statBasename(kind: insight.kind, value: insight.value) {
                attempted += 1
                if let u = resolvedURL(basename: statBasename, voice: voiceRaw) { urls.append(u) }
            }

            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voiceRaw) { urls.append(u) }

            if index < selected.count - 1 {
                attempted += 1
                if let u = connectiveURL(kind: "trans", style: style, voice: voiceRaw) { urls.append(u) }
            }
        }

        attempted += 1
        if let u = connectiveURL(kind: "outro", style: style, voice: voiceRaw) { urls.append(u) }

        return play(urls: urls, attempted: attempted)
    }

    /// Plays a completed-game wrap-up: [intro?] + winner name + winner tail
    /// + up to 2 of `insights`' `[name, stat?, tail]` segments (the game's
    /// "story" — perfect records, streaks, round-of-the-game, etc., same
    /// insights `FinalResultsView`'s "Game Story" section shows) + last
    /// place (name + tail, Spicy+ only, same gating as `announceWinner`) +
    /// [outro?]. Replaces the bare `announceWinner` call `FinalResultsView`
    /// used before the Game Story feature: capped at 2 insights (not 3, per
    /// `announceRoundUpdate`) so the combined sequence stays at or under 12
    /// segments — 1 intro + 2 winner + up to 6 for two 3-segment insights +
    /// 2 last-place + 1 outro. Same graceful-skip and return-count behavior
    /// as every other `announce*` method.
    @discardableResult
    func announceGameWrap(
        winnerName: String,
        lastPlaceName: String?,
        insights: [GameInsights.Insight],
        voice: AnnouncerVoice,
        style: AnnouncerStyle
    ) -> Int {
        beginAssembly()
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = connectiveURL(kind: "intro", style: style, voice: voiceRaw) { urls.append(u) }

        attempted += 1
        if let u = nameURL(winnerName, voice: voiceRaw) { urls.append(u) }
        attempted += 1
        if let u = tailURL(kindName: "winner", style: style, voice: voiceRaw) { urls.append(u) }

        let selected = Array(insights.prefix(2))
        for insight in selected {
            attempted += 1
            if let u = nameURL(insight.playerName, voice: voiceRaw) { urls.append(u) }

            if let statBasename = statBasename(kind: insight.kind, value: insight.value) {
                attempted += 1
                if let u = resolvedURL(basename: statBasename, voice: voiceRaw) { urls.append(u) }
            }

            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voiceRaw) { urls.append(u) }
        }

        if let lastPlaceName, style.rawValue >= AnnouncerStyle.spicy.rawValue {
            attempted += 1
            if let u = nameURL(lastPlaceName, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = tailURL(kindName: "lastPlace", style: style, voice: voiceRaw) { urls.append(u) }
        }

        attempted += 1
        if let u = connectiveURL(kind: "outro", style: style, voice: voiceRaw) { urls.append(u) }

        return play(urls: urls, attempted: attempted)
    }

    /// The short round-zero call (game-night feedback: the full broadcast
    /// was too long when "there's not much to say"): acknowledge the
    /// reigning champ if one is seated, one quick joke, then point to the
    /// deal. No intro, no transitions — roughly 6–8 seconds:
    /// [champ name + reigningChamp tail]? + [freshGame tail] + [kickoff tail].
    @discardableResult
    func announcePregame(champName: String?, voice: AnnouncerVoice, style: AnnouncerStyle) -> Int {
        beginAssembly()
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        var attempted = 0

        if let champName {
            attempted += 1
            if let u = nameURL(champName, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = tailURL(kindName: "reigningChamp", style: style, voice: voiceRaw) { urls.append(u) }
        }

        attempted += 1
        if let u = tailURL(kindName: "freshGame", style: style, voice: voiceRaw) { urls.append(u) }

        attempted += 1
        if let u = tailURL(kindName: "kickoff", style: style, voice: voiceRaw) { urls.append(u) }

        return play(urls: urls, attempted: attempted)
    }

    /// Toggle helper for the round-zero pregame call — same stop-if-playing
    /// behavior as `toggleRoundUpdate`.
    func togglePregame(champName: String?, voice: AnnouncerVoice, style: AnnouncerStyle) {
        if isPlaying {
            stop()
        } else {
            announcePregame(champName: champName, voice: voice, style: style)
        }
    }

    /// Toggle helper for call sites (the Trends section's Announce/Stop
    /// button): stops playback if a broadcast is already in progress,
    /// otherwise starts one via `announceRoundUpdate`.
    func toggleRoundUpdate(insights: [GameInsights.Insight], voice: AnnouncerVoice, style: AnnouncerStyle) {
        if isPlaying {
            stop()
        } else {
            announceRoundUpdate(insights: insights, voice: voice, style: style)
        }
    }

    /// Stops any in-flight playback immediately, flips `isPlaying` back to
    /// `false`, and deactivates the audio session (`.notifyOthersOnDeactivation`
    /// so ducked background music resumes).
    func stop() {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        if let endOfQueueObserver {
            NotificationCenter.default.removeObserver(endOfQueueObserver)
        }
        endOfQueueObserver = nil
        for observer in failureObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        failureObservers.removeAll()
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            // Widened from 2...15: a 3-player game runs 20 rounds, and the
            // lead can legitimately generate inarow_16..20 clips.
            guard (2...20).contains(value) else { return nil }
            return "inarow_\(value)"
        case .perfect:
            // Widened from 3...15 — same 20-round 3-player ceiling as above.
            guard (3...20).contains(value) else { return nil }
            return "perfect_\(value)"
        case .bigRound:
            guard (40...220).contains(value), value % 10 == 0 else { return nil }
            return "points_\(value)"
        case .zeroSpecialist:
            guard (3...10).contains(value) else { return nil }
            return "zeros_\(value)"
        case .boldestBidder:
            return nil
        case .leading, .trailing, .leadChange:
            // Reuses the same `points_<n>` clip family as `.bigRound` — the
            // value here IS the player's own point total (leader's total,
            // trailer's total, or the new leader's total on a lead change),
            // so the clip reads correctly as "their score". Values outside
            // the generated range just skip the stat clip, same as any
            // other out-of-range value.
            guard (40...220).contains(value), value % 10 == 0 else { return nil }
            return "points_\(value)"
        case .chasing, .nosedive:
            // Deliberately no stat clip: `.chasing`'s value is the GAP to
            // the leader and `.nosedive`'s is the trailing total, neither
            // of which is "this player's own score" — reusing `points_<n>`
            // here is audibly ambiguous ("Sam! Forty points! Right on the
            // leader's heels!" reads as Sam scoring 40, not trailing by 40).
            // The on-screen text still carries the number; the tail clip
            // carries what it means.
            return nil
        case .reigningChamp, .freshGame, .everybodyHit, .carnage, .tightRace:
            // No stat clip by design — these are framing lines ("X won the
            // last game", "fresh scorepad"), not numeric callouts.
            return nil
        }
    }

    /// Variant bookkeeping (game-night bug: the same clip played twice in
    /// one broadcast). `usedInAssembly` is cleared at the start of every
    /// announce* call and guarantees no clip repeats within a single
    /// announcement; `lastVariant` persists across announcements so the
    /// next broadcast avoids opening with the identical line when there's
    /// an alternative.
    private var usedInAssembly: Set<String> = []
    private var lastVariant: [String: Int] = [:]

    /// Called at the top of every announce* assembly.
    private func beginAssembly() {
        usedInAssembly.removeAll()
    }

    /// Draws a variant index for a category without repeating within the
    /// current announcement, and avoiding the previous announcement's pick
    /// when an alternative exists. Falls back to reuse only when every
    /// variant is already spent (better a repeat than silence).
    private func pickVariant(category: String, count: Int, styleRaw: Int) -> Int {
        let key = "\(styleRaw)_\(category)"
        let pool = Array(0..<count)
        var candidates = pool.filter { !usedInAssembly.contains("\(key)_\($0)") }
        if candidates.isEmpty { candidates = pool }
        if candidates.count > 1, let last = lastVariant[key] {
            let withoutLast = candidates.filter { $0 != last }
            if !withoutLast.isEmpty { candidates = withoutLast }
        }
        let chosen = candidates.randomElement() ?? 0
        usedInAssembly.insert("\(key)_\(chosen)")
        lastVariant[key] = chosen
        return chosen
    }

    /// Picks a no-repeat tail variant for (style, kind) from the manifest's
    /// variant count, and falls back to variant 0 if the chosen file isn't
    /// on disk yet (generation may still be in progress). Returns `nil`
    /// only if nothing is resolvable.
    private func tailURL(kindName: String, style: AnnouncerStyle, voice: String) -> URL? {
        guard let count = manifest?.styles[String(style.rawValue)]?[kindName], count > 0 else { return nil }
        let variant = pickVariant(category: "tail_\(kindName)", count: count, styleRaw: style.rawValue)
        if let url = resolvedURL(basename: "tail_\(style.rawValue)_\(kindName)_\(variant)", voice: voice) {
            return url
        }
        if variant != 0, let url = resolvedURL(basename: "tail_\(style.rawValue)_\(kindName)_0", voice: voice) {
            return url
        }
        return nil
    }

    /// Random connective clip lookup for `announceRoundUpdate` —
    /// `seg_<style>_<kind>_<i>` for `kind` in `"intro"`, `"trans"`,
    /// `"outro"`. These files are a newer, still-in-progress addition to
    /// `tools/generate_announcer.py` (see its header comment) and may not
    /// exist for every style, or at all, yet. Unlike `tailURL` there's no
    /// manifest-backed variant count to consult, so this just tries a
    /// shuffled 0..<3 index order and returns the first that resolves —
    /// `nil`, silently, if none do.
    private func connectiveURL(kind: String, style: AnnouncerStyle, voice: String) -> URL? {
        let cacheKey = "\(voice)_\(style.rawValue)_\(kind)"
        let count: Int
        if let cached = connectiveCounts[cacheKey] {
            count = cached
        } else {
            var probed = 0
            while probed < 8, resolvedURL(basename: "seg_\(style.rawValue)_\(kind)_\(probed)", voice: voice) != nil {
                probed += 1
            }
            connectiveCounts[cacheKey] = probed
            count = probed
        }
        guard count > 0 else { return nil }
        let variant = pickVariant(category: "seg_\(kind)", count: count, styleRaw: style.rawValue)
        return resolvedURL(basename: "seg_\(style.rawValue)_\(kind)_\(variant)", voice: voice)
    }

    /// On-disk connective variant counts, probed once per (voice, style,
    /// kind) — connectives aren't in the manifest's tail counts.
    private var connectiveCounts: [String: Int] = [:]

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
    /// can be verified from console logs alone. The session is set up with
    /// `.duckOthers` so backgrounded music (e.g. Spotify/Music) ducks
    /// instead of getting killed outright, and is deactivated with
    /// `.notifyOthersOnDeactivation` — both when the queue finishes
    /// naturally and in `stop()` — so that music comes back up afterward.
    @discardableResult
    private func play(urls: [URL], attempted: Int) -> Int {
        let missing = attempted - urls.count
        print("Announcer: \(urls.count) segment(s) resolved, \(missing) missing (of \(attempted) attempted)")
        guard !urls.isEmpty else { return 0 }

        if let endOfQueueObserver {
            NotificationCenter.default.removeObserver(endOfQueueObserver)
            self.endOfQueueObserver = nil
        }
        for observer in failureObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        failureObservers.removeAll()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        let items = urls.map { AVPlayerItem(url: $0) }
        let player = AVQueuePlayer(items: items)
        queuePlayer = player

        // Observe the LAST item specifically (not just any item finishing)
        // so `isPlaying` stays true through a multi-clip sequence and only
        // flips false once the whole broadcast has played out. Also
        // deactivates the session (ducked music resumes) now that playback
        // is genuinely done.
        endOfQueueObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: items.last,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        // A mid-queue decode/IO failure never fires the last item's normal
        // end-of-playback notification, which would otherwise leave
        // `isPlaying` stuck `true` forever — one observer per queued item
        // routes any of them failing through the same `stop()` cleanup
        // (removes observers, deactivates the session, flips `isPlaying`).
        failureObservers = items.map { item in
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.stop()
            }
        }

        isPlaying = true
        player.play()
        return urls.count
    }
}
