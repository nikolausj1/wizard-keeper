import AVFoundation
import Combine
import Foundation
import SwiftData

/// Announcer voice pack — see `tools/generate_announcer.py` for the
/// ElevenLabs voice IDs and generated clip naming convention
/// (`name_<slug>.mp3`, `inarow_<n>.mp3`, `tail_<style>_<kind>_<i>.mp3`, ...).
enum AnnouncerVoice: String, CaseIterable, Identifiable {
    // Jessica retired 2026-07-12 (Justin: drop the female voice); her clip
    // pack was removed from the bundle. Stored "jessica" settings fall back
    // to Charlie via the `?? .charlie` in `announcerVoiceSelection`.
    case charlie

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .charlie: return "Charlie"
        }
    }
}

/// Announcer commentary intensity. Spicy uses mild-to-real profanity and is
/// adults-only — see `AppGame.config.allowsSpicyTier` and the corpus split
/// below for how it's kept out of the two clean, all-ages targets.
/// Three listener-facing tiers, each now a purpose-written bucket of its
/// own (the corpus is being regenerated as three tiers instead of five —
/// the old five-tone corpus needed merging two buckets per tier to get
/// enough variety; that merging is retired along with the five-bucket
/// layout): Classic = bucket 1, Fun = bucket 2, Spicy = bucket 3
/// (adults-only: expletives — ships only in the TrashTalkKeeper target's
/// `AnnouncerSpicy/` clip pack, never in WizardKeeper's or OhHellKeeper's
/// bundle, and never selectable there — see `allowsSpicyTier`).
enum AnnouncerStyle: Int, CaseIterable, Identifiable {
    case classic = 1
    case fun = 2
    case spicy = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .fun: return "Fun"
        case .spicy: return "Spicy"
        }
    }

    /// The on-disk clip-style bucket this tier draws from
    /// (tail_<bucket>_<kind>_<i>). One bucket per tier now — no more
    /// merging two buckets into one tier's pool.
    var buckets: [Int] {
        switch self {
        case .classic: return [1]
        case .fun: return [2]
        case .spicy: return [3]
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
        get {
            // Stored raw = AnnouncerStyle.rawValue (1 Classic, 2 Fun,
            // 3 Spicy). Only 4 Vicious / 5 Unhinged remain from the
            // original five-tier storage → Spicy. The old "3 Scorched →
            // Fun" migration is gone: it collided with the new Spicy
            // rawValue 3, snapping every Spicy pick back to Fun (the
            // "can't choose anything but Fun" bug). Do NOT touch this
            // 1/2/3 raw mapping again — see the bug above.
            let decoded = AnnouncerStyle(rawValue: announcerStyle) ?? (announcerStyle >= 4 ? .spicy : .classic)
            // Clean targets (WizardKeeper, OhHellKeeper) hide Spicy from
            // Settings and never bundle its clips — see
            // `AppGame.config.allowsSpicyTier`. A store that already has
            // 3 saved (e.g. carried over from a device that once ran
            // TrashTalkKeeper, or a future re-toggle) reads back as Fun on
            // a clean target instead. The stored raw value is left alone
            // here — only the getter's return value downgrades — so
            // switching back to a spicy-capable target later doesn't need
            // the user to reselect Spicy.
            if decoded == .spicy, !AppGame.config.allowsSpicyTier { return .fun }
            return decoded
        }
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

    /// The last broadcast that actually started playing, in play order —
    /// each clip's basename (filename minus ".mp3", the same key
    /// `captions.json` uses) paired with its resolved bundle URL. `ShareCall`
    /// turns this into the exported MP4. Only replaced when a NEW broadcast
    /// starts (see `play(urls:attempted:)`); deliberately NOT cleared by
    /// `stop()`, so the "Share the Call" button stays live after a broadcast
    /// finishes or is stopped.
    private(set) var lastBroadcast: [(basename: String, url: URL)] = []

    /// Mirrors whether `lastBroadcast` holds anything shareable. Published so
    /// the "Share the Call" button can appear/disappear live alongside
    /// `isPlaying`; the tuple array itself can't be `@Published` cleanly, so
    /// this Bool is its observable shadow.
    @Published private(set) var hasShareableBroadcast = false

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
        /// Score-grammar lead-ins: listener TIER (as string, "1"..."3",
        /// mapping directly from `AnnouncerStyle.rawValue`) -> kind name ->
        /// variant count. Optional so an in-flight/older `manifest.json`
        /// without this key still decodes — lead-in lookups then just find
        /// a zero count and skip gracefully, same as any other missing clip.
        let leadins: [String: [String: Int]]?
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

        if let lastPlaceName, style.rawValue >= AnnouncerStyle.fun.rawValue {
            attempted += 1
            if let u = nameURL(lastPlaceName, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = tailURL(kindName: "lastPlace", style: style, voice: voiceRaw) { urls.append(u) }
        }

        return play(urls: urls, attempted: attempted)
    }

    /// Plays the "Score Rundown" broadcast: a round stamp, then every
    /// player's name and total in standings order (best to worst), then
    /// exactly one punchline. Replaces the old insight-driven broadcast
    /// (up to 4 stories stitched together with random intro/transition/
    /// outro connective clips) — game-night feedback was that the
    /// connectives made every broadcast feel padded, and that what the
    /// table actually wanted to hear was just "where does everyone stand",
    /// read out loud, fast.
    ///
    /// `standings` must already be sorted best to worst — callers reuse
    /// `StandingsCalculator` (`Theme.swift`) rather than this method
    /// re-deriving totals itself, so the broadcast and the on-screen
    /// standings list never disagree. `insights` is still the ranked list
    /// `GameTrends` computes; only its FIRST qualifying entry is spoken
    /// here, as the punchline.
    ///
    /// Assembly:
    /// 1. Round stamp: `round_<roundNumber>`.
    /// 2. The leader (`standings[0]`): name + lead-in + a 400ms beat +
    ///    their total, shouted. The lead-in is "leadNew" (and the number
    ///    gets the shouted `numx_` treatment via `emphasized`) when
    ///    `insights` has a `.leadChange` insight for THIS player — they
    ///    just took over the top spot this round — otherwise it's the
    ///    flatter "leaderTotal" lead-in, read naturally.
    /// 3. Everyone else, in standings order: name + a 200ms beat + their
    ///    total, read naturally (never shouted — only the leader's number
    ///    is a big moment). Two equal totals back to back need to be SAID,
    ///    not just implied, so a tie against the PREVIOUS player swaps the
    ///    bare beat for the "tiedAt" lead-in on the second of the pair.
    /// 4. The punchline: exactly one tail clip, preferring the highest-
    ///    ranked "juice" insight (perfect/streaks/big swings/table-wide
    ///    extremes), falling back to a `.leadChange` insight, falling back
    ///    to nothing. A named punchline speaks the player's name first;
    ///    the nameless table-wide kinds (everybodyHit, carnage) are the
    ///    tail alone.
    ///
    /// `round_<n>`/`silence_200` are newer additions to
    /// `tools/generate_announcer.py` and may not be generated yet — missing
    /// clips are skipped silently, same graceful-skip philosophy as every
    /// other clip. Same return-count behavior as `announce`/`announceWinner`.
    @discardableResult
    func announceRoundUpdate(
        roundNumber: Int,
        standings: [(name: String, total: Int)],
        insights: [GameInsights.Insight],
        voice: AnnouncerVoice,
        style: AnnouncerStyle
    ) -> Int {
        beginAssembly()
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = resolvedURL(basename: "round_\(roundNumber)", voice: voiceRaw) { urls.append(u) }

        guard let leader = standings.first else { return play(urls: urls, attempted: attempted) }

        // Did the leader just take over the top spot THIS round? Drives
        // both the lead-in kind and whether the number gets shouted.
        let leaderJustTookLead = insights.contains { $0.kind == .leadChange && $0.playerName == leader.name }

        attempted += 1
        if let u = nameURL(leader.name, voice: voiceRaw) { urls.append(u) }

        attempted += 1
        var leaderLeadinResolved = false
        if let u = leadinURL(kindName: leaderJustTookLead ? "leadNew" : "leaderTotal", style: style, voice: voiceRaw) {
            urls.append(u)
            leaderLeadinResolved = true
        }
        // Same engineered dramatic pause as the score-grammar segments
        // below (see `leadinNumSegments`): only inserted once the lead-in
        // actually resolved, and deliberately not counted in `attempted`
        // — it's pacing, not a content segment.
        if leaderLeadinResolved, let pause = resolvedURL(basename: "silence_400", voice: voiceRaw) {
            urls.append(pause)
        }

        attempted += 1
        if let u = numClipURL(score: leader.total, voice: voiceRaw, emphasized: leaderJustTookLead) {
            urls.append(u)
        }

        var previousTotal = leader.total
        for player in standings.dropFirst() {
            attempted += 1
            if let u = nameURL(player.name, voice: voiceRaw) { urls.append(u) }

            // One "beat" slot per player: the bare 200ms pause, unless
            // they're tied with whoever was just read, in which case the
            // tie needs to be spoken.
            attempted += 1
            if player.total == previousTotal {
                if let u = leadinURL(kindName: "tiedAt", style: style, voice: voiceRaw) { urls.append(u) }
            } else if let u = resolvedURL(basename: "silence_200", voice: voiceRaw) {
                urls.append(u)
            }

            attempted += 1
            if let u = numClipURL(score: player.total, voice: voiceRaw) { urls.append(u) }

            previousTotal = player.total
        }

        let juiceKinds: Set<GameInsights.Kind> = [
            .perfect, .hotStreak, .coldStreak, .bigRound, .nosedive,
            .zeroSpecialist, .boldestBidder, .everybodyHit, .carnage,
        ]
        let punchline = insights.first { juiceKinds.contains($0.kind) }
            ?? insights.first { $0.kind == .leadChange }
        if let punchline {
            if !punchline.playerName.isEmpty {
                attempted += 1
                if let u = nameURL(punchline.playerName, voice: voiceRaw) { urls.append(u) }
            }
            attempted += 1
            if let u = tailURL(kindName: punchline.kind.rawValue, style: style, voice: voiceRaw) { urls.append(u) }
        }

        return play(urls: urls, attempted: attempted)
    }

    /// Plays a completed-game wrap-up: winner name + winner tail +
    /// winnerBy (winner name again + lead-in + final-margin number, only
    /// when a `.winnerBy` insight with a positive `score` is present —
    /// skipped on ties) + up to 2 of `insights`' segments via
    /// `segments(for:style:voice:attachTail:)` (the game's "story" —
    /// perfect records, streaks, round-of-the-game, etc., same insights
    /// `FinalResultsView`'s "Game Story" section shows; `.winnerBy` itself
    /// is excluded from this pool since it's already spoken above) + last
    /// place (name + tail, Spicy+ only, same gating as `announceWinner`).
    /// Replaces the bare `announceWinner` call `FinalResultsView` used
    /// before the Game Story feature. Story-beat tails are NOT subject to
    /// `announceRoundUpdate`'s one-punchline-per-broadcast rule — same
    /// existing behavior as before (every selected story insight gets its
    /// own tail attempt). No intro/outro connectives (removed along with
    /// the rest of that machinery — see `announceRoundUpdate`). Same
    /// graceful-skip and return-count behavior as every other `announce*`
    /// method.
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
        if let u = nameURL(winnerName, voice: voiceRaw) { urls.append(u) }
        attempted += 1
        if let u = tailURL(kindName: "winner", style: style, voice: voiceRaw) { urls.append(u) }

        if let winnerByInsight = insights.first(where: { $0.kind == .winnerBy }),
           let margin = winnerByInsight.score, margin > 0 {
            attempted += 1
            if let u = nameURL(winnerName, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = leadinURL(kindName: "winnerBy", style: style, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = numClipURL(score: margin, voice: voiceRaw) { urls.append(u) }
        }

        let selected = insights.filter { $0.kind != .winnerBy }.prefix(2)
        for insight in selected {
            let (segs, segAttempted) = segments(for: insight, style: style, voice: voiceRaw, attachTail: true)
            attempted += segAttempted
            urls.append(contentsOf: segs)
        }

        if let lastPlaceName, style.rawValue >= AnnouncerStyle.fun.rawValue {
            attempted += 1
            if let u = nameURL(lastPlaceName, voice: voiceRaw) { urls.append(u) }
            attempted += 1
            if let u = tailURL(kindName: "lastPlace", style: style, voice: voiceRaw) { urls.append(u) }
        }

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

    /// Plays a short sample of the given voice/style for the Settings
    /// "Preview Voice" button: the "winner" tail clip alone. Simplified
    /// down from [seg intro] + [tail winner] now that the connective
    /// machinery is gone — see `announceRoundUpdate`. Callers
    /// (`SettingsView`) handle the stop-if-playing toggle themselves via
    /// `isPlaying`/`stop()` — this method just plays.
    @discardableResult
    func preview(voice: AnnouncerVoice, style: AnnouncerStyle) -> Int {
        beginAssembly()
        let voiceRaw = voice.rawValue
        var urls: [URL] = []
        let attempted = 1

        if let u = tailURL(kindName: "winner", style: style, voice: voiceRaw) { urls.append(u) }

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
    func toggleRoundUpdate(
        roundNumber: Int,
        standings: [(name: String, total: Int)],
        insights: [GameInsights.Insight],
        voice: AnnouncerVoice,
        style: AnnouncerStyle
    ) {
        if isPlaying {
            stop()
        } else {
            announceRoundUpdate(roundNumber: roundNumber, standings: standings, insights: insights, voice: voice, style: style)
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
        default:
            // The score-grammar kinds (leaderTotal, leadGrew, chase,
            // tiedAt, onTopStreak, earlyGame, ...) never use the old
            // stat-burst clips — they're resolved by `segments(for:)`
            // instead. This also future-proofs against any new `Kind`
            // case the engine adds that isn't explicitly listed above.
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
        // Flat index space over every (bucket, variant) pair in the tier's
        // pool. Each tier now maps to exactly one purpose-written bucket
        // (see `AnnouncerStyle.buckets`) rather than the retired five-
        // bucket layout's two-bucket merge, but the pool shape is kept
        // general so a tier could still span more than one bucket later.
        var pool: [(bucket: Int, variant: Int)] = []
        for bucket in style.buckets {
            let count = manifest?.styles[String(bucket)]?[kindName] ?? 0
            for v in 0..<count { pool.append((bucket, v)) }
        }
        guard !pool.isEmpty else { return nil }
        let flat = pickVariant(category: "tail_\(kindName)", count: pool.count, styleRaw: style.rawValue)
        let pick = pool[flat]
        if let url = resolvedURL(basename: "tail_\(pick.bucket)_\(kindName)_\(pick.variant)", voice: voice) {
            return url
        }
        // Fallback: first pool entry (generation may still be in flight).
        let first = pool[0]
        if flat != 0, let url = resolvedURL(basename: "tail_\(first.bucket)_\(kindName)_\(first.variant)", voice: voice) {
            return url
        }
        return nil
    }

    // MARK: - Score-grammar clip resolution (NAME! + lead-in + number)

    /// Picks a no-repeat lead-in variant for (tier, kind) from the
    /// manifest's `leadins` counts and falls back to variant 0 if the
    /// chosen file isn't on disk yet, same pattern as `tailURL`. Unlike
    /// `tailURL`'s merged five-bucket pool, `tier` maps DIRECTLY from
    /// `AnnouncerStyle.rawValue` (classic=1, fun=2, spicy=3) — lead-ins
    /// carry facts, not spice, so there's no bucket merging here.
    private func leadinURL(kindName: String, style: AnnouncerStyle, voice: String) -> URL? {
        let tier = style.rawValue
        let count = manifest?.leadins?[String(tier)]?[kindName] ?? 0
        guard count > 0 else { return nil }
        let variant = pickVariant(category: "leadin_\(kindName)", count: count, styleRaw: tier)
        if let url = resolvedURL(basename: "leadin_\(tier)_\(kindName)_\(variant)", voice: voice) {
            return url
        }
        if variant != 0, let url = resolvedURL(basename: "leadin_\(tier)_\(kindName)_0", voice: voice) {
            return url
        }
        return nil
    }

    /// `num_<n>` / `num_m<n>` (tens family, Wizard) or `num1_<n>` (integer
    /// family, Oh Hell) — bare terminal numbers (leader totals, gaps, point
    /// deltas). Family is picked by `AppGame.config.announcerUsesTensClips`:
    /// tens mode requires `score` be a multiple of 10 (Wizard scores always
    /// are) and clamps into the generated −100...300 range, alternating
    /// between the natural `num_` and shouted `numx_` sets per
    /// `emphasized`; integer mode has no shouted set (natural only —
    /// `emphasized` is ignored, a wrong number is worse than no emphasis)
    /// and clamps into 0...160 (Oh Hell never goes negative). Either way a
    /// clip that isn't on disk yet just resolves to nil and gets skipped
    /// upstream, same as any other missing clip.
    private func numClipURL(score: Int, voice: String, emphasized: Bool = false) -> URL? {
        if AppGame.config.announcerUsesTensClips {
            guard score % 10 == 0 else { return nil }
            let clamped = max(-100, min(300, score))
            // Shouted `numx_` set only for big moments (a mix, per Justin —
            // natural delivery is the default); fall back across sets so a
            // missing clip never silences the number.
            let prefixes = emphasized ? ["numx_", "num_"] : ["num_", "numx_"]
            for prefix in prefixes {
                if let u = resolvedURL(basename: "\(prefix)\(numSlug(clamped))", voice: voice) { return u }
            }
            return nil
        }
        let clamped = max(0, min(160, score))
        return resolvedURL(basename: "num1_\(clamped)", voice: voice)
    }

    private func numSlug(_ n: Int) -> String {
        n < 0 ? "m\(-n)" : "\(n)"
    }

    /// `back_<n>` (tens family, Wizard) or `back1_<n>` (integer family, Oh
    /// Hell) — "<N> back!", the margin behind the leader (`chase`). Tens
    /// mode clamps into the generated 10...150 range; integer mode clamps
    /// into 1...40.
    private func backClipURL(score: Int, voice: String) -> URL? {
        if AppGame.config.announcerUsesTensClips {
            guard score % 10 == 0 else { return nil }
            let clamped = max(10, min(150, score))
            // Chase margins always use the natural read — the hunt is
            // tension, not a celebration (`backx_` stays reserved for
            // future use).
            for prefix in ["back_", "backx_"] {
                if let u = resolvedURL(basename: "\(prefix)\(clamped)", voice: voice) { return u }
            }
            return nil
        }
        let clamped = max(1, min(40, score))
        return resolvedURL(basename: "back1_\(clamped)", voice: voice)
    }

    /// `ontop_<n>` — consecutive rounds leading (`onTopStreak`). Clamps
    /// into 2...10.
    private func onTopClipURL(value: Int, voice: String) -> URL? {
        resolvedURL(basename: "ontop_\(max(2, min(10, value)))", voice: voice)
    }

    /// `basement_<n>` — "since round N" (`basementSince`). Clamps into
    /// 2...14.
    private func basementClipURL(value: Int, voice: String) -> URL? {
        resolvedURL(basename: "basement_\(max(2, min(14, value)))", voice: voice)
    }

    /// Per-insight segment resolution for the score-speaking grammar (NAME!
    /// + lead-in ending mid-sentence + number burst) that
    /// `announceRoundUpdate`/`announceGameWrap` assemble broadcasts from.
    /// Dispatches on `insight.kind` to the right shape; every kind not
    /// listed here (the pre-existing streak/table-wide kinds — perfect,
    /// hotStreak, coldStreak, zeroSpecialist, boldestBidder, leading/
    /// chasing/trailing, everybodyHit/carnage/tightRace, reigningChamp/
    /// freshGame) keeps the original name + stat-burst + tail shape via
    /// `legacySegments`, unchanged. Returns the resolved URLs alongside how
    /// many clip lookups were attempted so callers can fold both into their
    /// own running totals, same bookkeeping as before this was extracted.
    private func segments(
        for insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        switch insight.kind {
        case .leaderTotal, .leadChange, .leadGrew, .leadShrank, .bottomDeeper, .bottomClimb,
             .bigRound, .nosedive, .mover, .tiedAt, .winnerBy:
            return leadinNumSegments(insight: insight, style: style, voice: voice, attachTail: attachTail)
        case .chase:
            return chaseSegments(insight: insight, style: style, voice: voice, attachTail: attachTail)
        case .onTopStreak:
            return onTopSegments(insight: insight, style: style, voice: voice, attachTail: attachTail)
        case .basementSince:
            return basementSegments(insight: insight, style: style, voice: voice, attachTail: attachTail)
        case .leadStatic, .bottomStatic:
            return completeLineSegments(insight: insight, style: style, voice: voice, attachTail: attachTail)
        case .earlyGame, .lateGame:
            return namelessLeadinSegments(insight: insight, style: style, voice: voice)
        default:
            return legacySegments(insight: insight, style: style, voice: voice, attachTail: attachTail)
        }
    }

    /// leaderTotal, leadChange (lead-in kind name "leadNew" — see the
    /// contract), leadGrew, leadShrank, bottomDeeper, bottomClimb,
    /// bigRound, nosedive, mover, tiedAt (BOTH player names), winnerBy:
    /// name(s) + lead-in + number. Falls back to the pre-existing
    /// stat-burst-or-tail behavior when `score` is nil or not a clampable
    /// multiple of 10 (out-of-sync data or generation gap).
    private func leadinNumSegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voice) { urls.append(u) }

        if insight.kind == .tiedAt {
            attempted += 1
            if let u = nameURL(insight.playerName2, voice: voice) { urls.append(u) }
        }

        let leadinKind = insight.kind == .leadChange ? "leadNew" : insight.kind.rawValue
        // The shouted variant is seasoning, not the meal: only the genuine
        // fist-pump moments get the yell.
        let emphasized = [.leadChange, .bigRound, .winnerBy].contains(insight.kind)
        if let score = insight.score, let numURL = numClipURL(score: score, voice: voice, emphasized: emphasized) {
            attempted += 1
            if let u = leadinURL(kindName: leadinKind, style: style, voice: voice) {
                urls.append(u)
                // The engineered DRAMATIC PAUSE: lead-in tails are trimmed
                // of ragged silence at generation time, so this fixed
                // 400ms beat is the entire gap before the shouted number
                // ("Stretching the lead to" … beat … "ONE-EIGHTY!").
                // Only inserted when the lead-in actually resolved — the
                // number should never play after dead air alone.
                if let pause = resolvedURL(basename: "silence_400", voice: voice) { urls.append(pause) }
            }
            attempted += 1
            urls.append(numURL)
        } else {
            attempted += 1
            if let statBasename = statBasename(kind: insight.kind, value: insight.value),
               let u = resolvedURL(basename: statBasename, voice: voice) {
                urls.append(u)
            } else if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) {
                urls.append(u)
            }
        }

        if attachTail {
            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        }

        return (urls, attempted)
    }

    /// chase: name + lead-in + `back_<n>` (margin behind the leader, from
    /// `score`). No stat-burst-or-tail fallback is specified for this kind
    /// — a missing/out-of-range `score` just silently drops the number
    /// segment, same graceful-skip philosophy as everywhere else.
    private func chaseSegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voice) { urls.append(u) }

        attempted += 1
        var chaseLeadinResolved = false
        if let u = leadinURL(kindName: "chase", style: style, voice: voice) {
            urls.append(u)
            chaseLeadinResolved = true
        }

        attempted += 1
        if let score = insight.score, let u = backClipURL(score: score, voice: voice) {
            // Same engineered dramatic pause as `leadinNumSegments` —
            // "Second place" … beat … "THIRTY BACK!".
            if chaseLeadinResolved, let pause = resolvedURL(basename: "silence_400", voice: voice) {
                urls.append(pause)
            }
            urls.append(u)
        }

        if attachTail {
            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        }

        return (urls, attempted)
    }

    /// onTopStreak: name + `ontop_<n>` (consecutive rounds leading, from
    /// the pre-existing `value` field, NOT `score` — no lead-in needed,
    /// `ontop_<n>` is a complete phrase on its own).
    private func onTopSegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voice) { urls.append(u) }

        attempted += 1
        if let value = insight.value, let u = onTopClipURL(value: value, voice: voice) { urls.append(u) }

        if attachTail {
            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        }

        return (urls, attempted)
    }

    /// basementSince: name + `basement_<n>` (round number, from `value`,
    /// NOT `score`) — same no-lead-in shape as `onTopSegments`.
    private func basementSegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voice) { urls.append(u) }

        attempted += 1
        if let value = insight.value, let u = basementClipURL(value: value, voice: voice) { urls.append(u) }

        if attachTail {
            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        }

        return (urls, attempted)
    }

    /// leadStatic, bottomStatic: name + lead-in — the lead-in clip IS the
    /// complete sentence, no number follows.
    private func completeLineSegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voice) { urls.append(u) }

        attempted += 1
        if let u = leadinURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }

        if attachTail {
            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        }

        return (urls, attempted)
    }

    /// earlyGame, lateGame: the lead-in clip ALONE — nameless, no tail ever
    /// (there's no `attachTail` parameter here on purpose: these are pure
    /// garnish per the contract, never the broadcast's one tail slot).
    private func namelessLeadinSegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        let attempted = 1
        if let u = leadinURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        return (urls, attempted)
    }

    /// Every pre-score-grammar kind (perfect, hotStreak, coldStreak,
    /// zeroSpecialist, boldestBidder, leading/chasing/trailing,
    /// everybodyHit/carnage/tightRace, reigningChamp/freshGame): unchanged
    /// shape — name + stat burst (if `statBasename` has one for this kind/
    /// value) + tail (only when `attachTail`).
    private func legacySegments(
        insight: GameInsights.Insight,
        style: AnnouncerStyle,
        voice: String,
        attachTail: Bool
    ) -> (urls: [URL], attempted: Int) {
        var urls: [URL] = []
        var attempted = 0

        attempted += 1
        if let u = nameURL(insight.playerName, voice: voice) { urls.append(u) }

        if let statBasename = statBasename(kind: insight.kind, value: insight.value) {
            attempted += 1
            if let u = resolvedURL(basename: statBasename, voice: voice) { urls.append(u) }
        }

        if attachTail {
            attempted += 1
            if let u = tailURL(kindName: insight.kind.rawValue, style: style, voice: voice) { urls.append(u) }
        }

        return (urls, attempted)
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
    /// baked into the resource name. Then, if neither hit, retries both
    /// layouts again under `AnnouncerSpicy` — spicy-bucket clips
    /// (tail_3_*, leadin_3_*) ship in that separate folder, which only the
    /// 18+ TrashTalkKeeper target bundles (see project.yml and
    /// `GameVariant.allowsSpicyTier`). In WizardKeeper/OhHellKeeper the
    /// folder simply isn't in the bundle, so these two lookups just miss
    /// like any other absent clip — no special-casing needed at the call
    /// site.
    private func resolvedURL(basename: String, voice: String) -> URL? {
        if let url = Bundle.main.url(forResource: basename, withExtension: "mp3", subdirectory: "Announcer/\(voice)") {
            return url
        }
        if let url = Bundle.main.url(forResource: "\(voice)/\(basename)", withExtension: "mp3", subdirectory: "Announcer") {
            return url
        }
        if let url = Bundle.main.url(forResource: basename, withExtension: "mp3", subdirectory: "AnnouncerSpicy/\(voice)") {
            return url
        }
        if let url = Bundle.main.url(forResource: "\(voice)/\(basename)", withExtension: "mp3", subdirectory: "AnnouncerSpicy") {
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

        // Record this as the shareable broadcast — only reached once
        // `urls` is non-empty (the guard above returned otherwise), so a
        // no-op announcement never overwrites a previously shareable one.
        // Basenames come straight off the resolved URLs so `ShareCall` and
        // `captions.json` agree on the key.
        lastBroadcast = urls.map { url in
            (basename: (url.lastPathComponent as NSString).deletingPathExtension, url: url)
        }
        hasShareableBroadcast = true

        isPlaying = true
        player.play()
        return urls.count
    }
}
