---
title: "Wizard Keeper - Product Requirements Document"
created: 2026-07-10
modified: 2026-07-10
version: 1.1
author: Claude (claude-opus-4-8, claude-fable-5)
tags: [prd, ios, wizard, scorekeeper]
---

# Wizard Keeper — Product Requirements Document

| | |
|---|---|
| **Product** | Wizard Keeper — the family game-night scorepad for the Wizard card game |
| **Platform** | iOS (universal: **iPhone-first**, also iPad) |
| **Status** | v1.1 PRD — agreed 2026-07-10 (v1.1: design direction locked to Apple Native) |
| **Companion docs** | `Project Build Guide.md` (accounts, stack, iOS signing, device deployment — follow it, do not restate it) |

> **Revision Notes (2026-07-10, v1.1):** The visual direction changed from the handwritten-paper-scorecard aesthetic to **Apple Native** (pure iOS system design). Six HTML mockups were produced (three paper variants, three alternatives); Justin reviewed all six and picked **E: Apple Native**. §7 was rewritten accordingly; the paper direction is retired. Functional spec, scoring, and data model are unchanged.

## 1. Overview and Vision

**The problem.** The family plays Wizard on game night and keeps score on paper. Wizard's scoring is fiddly — each round every player *bids* how many tricks they'll take, and at the end of the round you score +20 plus +10 per trick **only if you hit your bid exactly**, otherwise you *lose* 10 points for every trick you were over or under. Someone has to do that math for 3–6 players across 10–20 rounds, keep a running total, and remember how many cards to deal each round. It's error-prone, slow, and the running totals are hard to read mid-game.

**The one-liner.** An iPad/iPhone scorepad that does Wizard's bid-and-trick math for you, keeps a live running scoreboard, and remembers who plays.

**Why this wins.** It stays a *scorepad*, not a video game — you still deal and play with real cards at the table, which is the fun part. The app removes exactly the two chores paper is bad at: the per-round scoring math and the legible running total. It remembers the family so setup is two taps, and it quietly tracks history so game night has bragging rights over time.

## 2. Users

Family game night at Justin's in-laws'. 3–6 players per game, **mostly adults** (kids sometimes play, but they aren't the design target).

- **The scorekeeper (primary user)** — one adult who has the single device in front of them and runs the scoring for the whole table. This is who the app is designed for. They want entry fast enough that it never slows the game: bids at the start of a round, tricks at the end, done — and they'll only keep using the app if it beats the paper pad on speed and effort.
- **The other players** — the rest of the table, mostly adults. They don't touch the app; they just want to glance at the standings on the iPad, or when the scorekeeper turns the phone toward them. No expectation that everyone is looking at a screen.
- **Legibility** still matters — running totals should be readable across the table on an iPad, and the person entering scores should be able to do it quickly and accurately without squinting — but framed for adults, not for young kids.

Device: **one device, the scorekeeper's** — an iPad on the table, or an iPhone in hand. There is no second device in the same game. Offline, in the living room, no accounts, no login.

## 3. Goals and Success Criteria

**Goals:**
- Replace the paper scorepad completely for Wizard.
- Make round entry so fast it never stalls the game.
- Make the running standings glanceable from across the table.
- Remember the family so starting a game is trivial.
- Quietly build a history the family enjoys (wins, records) without adding setup work.

**Success criteria (testable):**
- **The headline: scoring with the app is easier and faster than paper.** This is the whole point — if it isn't clearly less effort than the pad, the scorekeeper won't switch. Concretely: entering a full round (bids + tricks) for 4 players is **at least as fast as writing that round on paper**, with **zero manual math** (paper requires the scorekeeper to compute every player's ±score; the app must require none).
- A full 4-player game (15 rounds) can be scored start to finish using only the app, with **zero manual math**.
- Entering one round's bids and results for 4 players takes **under ~20 seconds** and no more than a few taps per player.
- Round scores and running totals are **always correct** per standard Wizard rules — verified by an engine test suite of worked examples.
- Starting a rematch with the same players takes **two taps or fewer**.
- A completed game is **automatically saved** to history with no explicit "save" step.
- The app **resumes an in-progress game** unchanged after being closed or backgrounded.
- The scoreboard's running totals are legible from ~6 feet on the iPad.

**The one-sentence test:** On family game night, the scorekeeper runs a complete game of Wizard on the app, and the moment the last trick is entered it shows who won — and at no point did reaching for the paper pad and a pen feel like it would have been easier.

## 4. Scope

**In scope (v1):**
- New game setup: pick 3–6 players from saved profiles or add new ones, set seating order.
- Automatic round structure: rounds run 1..N cards; total rounds derived from player count (60 ÷ players → 3:20, 4:15, 5:12, 6:10). Optional "quick game" with a custom, shorter round count.
- Per-round flow: **bidding step** (enter each player's bid) → **results step** (enter each player's tricks taken) → automatic scoring.
- Light helpers: prominent "**Deal N cards**" for the current round; running **bid tally** ("bids so far: X"); soft check that tricks taken sum to N (the number of tricks that actually exist that round).
- Live scoreboard: running totals, per-round hit/miss indication, current leader.
- Final results: ranked standings, winner celebration, one-tap rematch.
- Saved player profiles with a color, reused across games.
- Game history: browse past games, see final scorecard and per-round breakdown.
- Lifetime stats per player (games, wins, win %, average score, best game, exact-bid rate).
- Edit/undo: fix a mis-tapped bid or trick in the current or a past round; totals recompute.
- Settings with house-rule toggles (defaults match how the family plays).
- Universal iPad + iPhone, light and dark mode, fully offline, on-device storage.

**Out of scope (non-goals):**
- **Dealing or playing cards in the app.** By decision — the physical cards are the fun; the app is a scorepad.
- **The dealer's "hook" rule** (that total bids can't equal the number of tricks). The family doesn't use it. It exists only as an optional Settings toggle, defaulted OFF.
- **Mandatory dealer tracking.** Adds onboarding friction for little gain. Optional dealer-rotation highlight only, defaulted OFF.
- **Online/multiplayer, accounts, cloud sync, sharing.** No backend. Each device is standalone.
- **Multi-device games (a "host" device + "viewer" devices watching the same game).** By decision — only the scorekeeper has a device; there is no shared live game across phones. Interesting backlog idea, not v1.
- **Runtime AI / network calls.** None. (Art is generated design-time only per the Build Guide.)
- **App Store distribution.** Family-only, installed on the household's devices per the Build Guide — so no trademark/App-Review concerns; "Wizard Keeper" is an internal name.
- **Other card games.** Wizard only.

**Deferred (v2+ candidates):**
- Trump-suit memory aid per round (optional tap; nice-to-have, cut from v1 to stay scorepad-lean). Target: v2.
- iCloud sync / cross-device shared history. Target: v2 if the family wants it.
- Richer stats and charts (streaks, head-to-head grids, per-round-number tendencies). Target: v2.
- 2-player variant support. Target: v2 (standard Wizard is 3–6).
- Sound effects. Target: v2 (haptics in v1).

## 5. Product Principles

Tiebreakers when design tradeoffs come up:
1. **Scorepad, not game.** When in doubt, do less — record the game, don't run it.
2. **Speed at the table beats features.** Every extra tap during a round is a cost; justify it.
3. **Legible and quick for the scorekeeper.** Big numbers readable across the table, big tap targets, no fine print — optimized for one adult entering scores fast.
4. **Correct math is non-negotiable.** The scoring engine is tested independently and is never wrong.
5. **Remember, don't ask.** Reuse players, resume games, auto-save — the app should feel like it already knows the family.

## 6. Functional Requirements

Universal app; each screen must specify its empty, loading (minimal — local data, near-instant), and error states. Where iPad and iPhone differ, both layouts are described.

### Screen A — Home
- **Contents:** App title/wordmark; a large **New Game** button; a **Resume Game** card if an in-progress game exists (players + which round); entries to **History**, **Players**, **Settings**.
- **Behavior:** New Game → Screen B. Resume → Screen D at the saved round. History → F. Players → G. Settings → H.
- **Empty state (first launch):** no in-progress game, no history. Show a friendly intro line and make **New Game** the obvious primary action.
- **Error state:** if saved data fails to load, show a non-destructive message ("Couldn't load saved games") and still allow starting a new game.

### Screen B — New Game setup
- **Contents:** roster of saved players as tappable chips (name + color); tap to include/exclude; an **Add player** control (name + auto-assigned color, editable); selected players shown in **seating order** (drag to reorder); a derived summary: "**N players · R rounds**"; optional **Quick game** control to cap rounds; **Start game** button.
- **Behavior:** Enforce **3–6** players (Start disabled otherwise, with a hint). Round count R = 60 ÷ N unless Quick game overrides with a smaller number. Start → creates the Game, snapshots current settings, opens Screen D at round 1.
- **Empty state:** no saved players yet → inline "Add your first player" prompt; adding one immediately makes it selectable.
- **Error state:** duplicate/blank name → inline validation, block Start.

### Screen C — (folded into D) Round entry
Round entry is a focused two-step flow that lives on top of the scoreboard (Screen D), identical on both devices:

- **C1 — Bidding step:** Header shows "**Round X of R**" and "**Deal X cards each**." One row per player in seating order, each with a **bid stepper (0…X)**. A running **"Bids: total so far"** line updates live (informational only; no warning if it equals X). **Confirm bids** advances to C2.
- **C2 — Results step:** Same player rows, each with a **tricks-taken stepper (0…X)**. Live helper: "**Tricks entered: k of X**." If the total ≠ X when confirming, show a **soft, dismissible warning** ("Only X tricks exist this round — you entered k") but allow override. On confirm: compute each player's round score, reveal per-player **hit (+)** / **miss (−)** with the delta, update running totals, advance the game to round X+1 (or to Screen E after the final round).
- **Edge:** stepper is hard-capped at the round's card count, so no one can bid or be credited more tricks than exist.

### Screen D — Scoreboard (main game screen)
- **iPad:** a **scorepad grid** — rows = rounds (1..R), columns = players — mirroring the paper pad. Each filled cell shows the player's round delta and/or cumulative; the current round is highlighted; a bold **running-total row** stays visible. Tapping the current round opens the C1/C2 entry flow. A footer shows current standings.
- **iPhone:** a **standings-first** layout — players listed by current rank with **large running totals** and rank movement; a prominent **"Enter round X"** button opens the same C1/C2 flow; the full grid is reachable via a horizontally scrollable **Scorecard** view.
- **Behavior:** always reflects the latest totals; supports tapping any **completed** round to edit it (reopens C1/C2 for that round; confirming **recomputes all subsequent totals**). An **Undo** affordance reverts the last confirmed entry.
- **Empty/first-round state:** round 1 open, all cells empty, entry flow one tap away.
- **Error state:** none expected (local, deterministic); a recompute always yields a consistent board.

### Screen E — Final results
- **Contents:** ranked standings with the winner highlighted and a celebratory treatment; final scores; **ties shown as shared placement**; buttons: **Rematch (same players)**, **New game**, **Done** (→ Home). Game is **already saved** to history at this point.
- **Behavior:** Rematch → Screen D round 1 with the same roster/settings.
- **Empty/error state:** n/a (only reachable from a completed game).

### Screen F — History
- **Contents:** list of past games (date, players, winner, winning score), newest first. Tap → **game detail**: final scorecard plus the per-round breakdown (bids, tricks, deltas).
- **Empty state:** "No games yet — your finished games will show up here."
- **Error state:** partial/corrupt game record → show what's readable, label it, never crash.

### Screen G — Players
- **Contents:** list of saved players with their color and a headline stat (e.g., wins). Tap → profile: **games played, wins, win %, average score, best game, exact-bid rate**; edit name/color; delete.
- **Delete behavior:** deleting a player **does not alter past games** — historical games retain that player's name/score snapshot; the player just stops appearing in the roster.
- **Empty state:** "Add the people you play with."
- **Loading:** stats compute from local history instantly; if ever slow, show the profile with stats filling in.

### Screen H — Settings
- **House rules (default = how the family plays):**
  - **Dealer's hook** (bids can't total the tricks) — default **OFF**.
  - **Trick-total check** (warn when tricks entered ≠ cards dealt) — default **ON**.
  - **Show dealer rotation** (highlight whose deal it is) — default **OFF**.
  - **Default game length** — full (60 ÷ players) or a custom quick-game cap.
- **Feel:** haptics on/off (default on); appearance (system/light/dark).
- **About:** version, credit line.
- **Behavior:** rule settings are **snapshotted into each game at creation**, so changing a setting never rewrites an in-progress or past game.

### Cross-cutting
- **Steppers** everywhere for number entry: big +/− buttons and a tappable number; capped to valid range; large targets for fast, accurate taps.
- **Resume:** the single in-progress game is always restorable from Home after backgrounding/quit.
- **Navigation:** shallow — Home is the hub; the active game is always one tap from Home while it exists.

## 7. Visual and Design Spec

Prescriptive. **Chosen direction (locked 2026-07-10): Apple Native** — pure iOS system design language, as if Apple shipped a Wizard scorekeeper. The discipline IS the design: nothing off-system, no theme, no decoration beyond what a first-party app would carry. Reference: `_review/mockup-E-apple-native.html` (Justin's pick from six candidates) — **match the mockup.**

- **Tone words:** first-party, crisp, quiet, instantly familiar. Apple's own simple utilities (Reminders, Fitness, Journal) — not a game UI, not a themed app.
- **Color:** iOS system palette only. Grouped-list backgrounds (`systemGroupedBackground`), white cards/rows, label/secondaryLabel text, hairline separators. **One accent: system indigo** (`#5856D6`), used with discipline for interactive elements (buttons, steppers, current-round tint). Score semantics use system colors: **hit green** (`systemGreen`), **miss red** (`systemRed`), **leader/winner gold star** (`systemYellow`). Nothing decorative.
- **Dark mode:** free and automatic — system colors adapt. Both modes fully supported from day one.
- **Typography:** SF Pro via system text styles (large-title navigation headers, headline rows, `monospacedDigit`/tabular numerals for all scores). Score numbers are the biggest type on screen — semibold/bold per iOS conventions. No custom or decorative fonts anywhere.
- **Components:** stock SwiftUI throughout — inset grouped lists, standard steppers (or stepper-styled ± controls at ≥44pt), pill/filled buttons, disabled-state conventions for incomplete input (e.g., Confirm Bids disabled until every player has a bid, per the mockup). Custom drawing only where stock has no equivalent (the iPad scorepad grid).
- **Per-player colors:** a fixed ~8-color palette drawn from the iOS system colors (indigo, teal, orange, pink, purple, blue, green, brown) as player identity chips — used sparingly, Apple-style, not as row floods.
- **Layout intent:** generous spacing, large tap targets (min 44pt), minimal chrome — one adult entering scores quickly; standings glanceable across the table. iPhone: standings-first list. **iPad (decided 2026-07-10 after Justin reviewed the first grid build): a two-pane layout** — a large-type standings panel (ranks, delta chips, ~36pt totals, deal helper + Enter Round button) beside the scorepad grid, scaled for the 13" canvas rather than ported from the mockup's small frame. The mockup defines structure and hierarchy; **type sizes scale up from the mockup's pixel values** (Justin found the literal sizes too small on both devices — totals ~32pt on iPhone, grid deltas ~18pt on iPad).
- **Motion:** standard iOS transitions and subtle number-change animations; a brief, restrained winner moment (confetti-free by default — a gold star and a spring animation is enough). Haptics on confirm and on winning.
- **Reference app (inspiration, not a spec):** *Wizard Scorecery* (App Store, Coobro LLC) — good bar for fast entry and a clean scoreboard; we go further with saved profiles, lifetime stats, and house-rule toggles.
- **Polish pass (resolved 2026-07-10):** Justin reviewed two texture candidates and picked **"Paper Whisper"** (`_review/texture-A-paper-whisper.html`): page backgrounds warm from system gray to cream `#F4F0E8` with a ~3.5% paper-grain tile, **light mode only** — dark mode stays pure system, cards/rows/components untouched. **App icon (final): the wizard hat** (`_review/icon-1-hat.png`), white hat + gold star on deep indigo.
- **Retired direction:** the full handwritten-paper-scorecard concept (candidates A/B/C in `_review/`) was explored in mockups and not chosen. Do not reintroduce handwritten fonts or analog flourishes; texture, if any, arrives only via the deferred polish pass above.

## 8. Data Model

On-device via **SwiftData** (see §9). Entities and invariants:

- **Player**
  - `id`, `name`, `colorId` (index into the fixed palette), `createdAt`.
  - Lifetime stats are **derived** from completed games, not stored as source of truth (may be cached for speed).
- **Game**
  - `id`, `createdAt`, `completedAt?`, `status` (`inProgress` | `completed`).
  - `participants`: ordered list of `{ playerId, displayNameSnapshot, colorSnapshot }` in seating order (snapshot so deleting/renaming a Player never corrupts past games).
  - `totalRounds` (R), `rulesSnapshot` (the Settings in force when the game began).
  - `rounds`: ordered list of **Round**.
  - `winnerPlayerIds`: computed at completion (a set, to represent ties).
  - *Invariant:* at most **one** Game has `status == inProgress` at a time.
- **Round**
  - `roundNumber` (= cards dealt this round, 1..R), `phase` (`bidding` | `results` | `complete`).
  - `entries`: per participant `{ playerId, bid: Int?, tricksTaken: Int? }`.
  - `optional dealerPlayerId` (only if dealer rotation is on).
  - *Invariants:* `0 ≤ bid ≤ roundNumber`; `0 ≤ tricksTaken ≤ roundNumber`; a completed round has all bids and tricks set. The round score per entry is **derived** (see below), not stored, so the engine is the single source of truth.
- **AppSettings** (single record)
  - `hookRuleEnabled` (default false), `trickTotalCheckEnabled` (default true), `dealerRotationEnabled` (default false), `defaultGameLength` (full | custom N), `hapticsEnabled` (default true), `appearance`.

**Scoring (the engine — locked, standard Wizard):**
- For a completed round entry: if `bid == tricksTaken` → `score = 20 + 10 × bid`; else → `score = −10 × |bid − tricksTaken|`.
- Running total for a player = sum of their round scores through the latest completed round.
- Final ranking = highest running total after round R; equal totals share placement (tie).
- Worked examples (must appear as engine tests): bid 2 / took 2 → **+40**; bid 0 / took 0 → **+20**; bid 3 / took 1 → **−20**; bid 1 / took 4 → **−30**.

## 9. Tech Stack and Architecture

Follow the Build Guide's iOS section for signing, XcodeGen, sim-verify, and device deployment; project-specific choices only here:

- **UI:** SwiftUI (universal iPhone + iPad, adaptive layouts). Rationale: native, fast, best fit for big-touch-target number entry and light/dark.
- **Persistence:** **SwiftData** on-device. Rationale: matches the Build Guide's "on-device storage / SwiftData models for apps," no backend, offline-first. (Considered and rejected: any hosted DB/sync — no backend by decision for v1.)
- **Scoring engine:** pure Foundation Swift in `Sources/Engine/`, **UI-independent and unit-tested** without Xcode via the Build Guide's engine-test recipe. Rationale: correctness is principle #4; the math must be provable in isolation.
- **Project:** XcodeGen (`project.yml` source of truth). **Bundle ID `com.levelup.wizardkeeper`** (unique, per convention). `DEVELOPMENT_TEAM 6A4J2GTB6F`. `ITSAppUsesNonExemptEncryption: NO` (offline, no custom crypto).
- **No** networking, analytics, accounts, or third-party runtime dependencies. Generated art (icon, empty-state/winner illustration) is design-time only, curated into the bundle.

## 10. Build Phases

**Execution approach (how Claude Code should run the build):** act as **lead planner**. Break each phase into clear work packages and **delegate routine, token-heavy execution to lower-cost worker models** (via subagents with a cheaper model override) — e.g. boilerplate SwiftUI views, repetitive model/CRUD code, test scaffolding, asset wrangling. **Keep strategic decisions, architecture, quality checks, and course corrections at the lead level**, and **review each worker's output before it lands** in the final result. The scoring engine (§8/§9) and any correctness-critical logic are reviewed by the lead, not delegated blindly.

Each phase ends in something verifiable; UI phases end with a sim-verify screenshot for Justin's approval before moving on. Riskiest/foundational work first.

1. **Scoring engine.** Pure-Swift round scoring, running totals, final ranking with ties, range validation. *Exit:* engine smoke test with the §8 worked examples (and more) all green via the swiftc engine-test recipe.
2. **Data model + persistence.** SwiftData Player/Game/Round/Settings; create game, add rounds, complete, resume in-progress, snapshot-on-delete. *Exit:* create a game in a test harness, add rounds, relaunch, data persists and resumes correctly.
3. **Core game flow (iPhone — primary).** New Game setup → C1/C2 round entry → live standings-first scoreboard → final results, tuned for phone and one-handed use. *Exit:* iPhone sim-verify screenshots of setup, a mid-game scoreboard, entry flow, and the winner screen.
4. **iPad scorepad grid.** Adapt Screen D to the full rounds × players grid on iPad; verify setup/entry/winner read well on the larger screen. *Exit:* iPad sim-verify screenshots.
5. **Players, history, stats.** Saved profiles, history list + game detail, lifetime stats, rematch. *Exit:* sim-verify: finish a game, see it in history with correct detail; profile stats correct.
6. **Settings, edit/undo, polish.** House-rule toggles (snapshotting), edit past rounds with full recompute, undo, empty states, haptics, reveal/winner motion. *Exit:* sim-verify: toggle a rule, edit a past round and watch totals recompute, trigger the win celebration.
7. **Art & theme pass.** Design-time generated art (icon, empty states, winner) into `_review/` for pick, then bundled; final light/dark polish. *Exit:* Justin approves art; then device deploy per the Build Guide's standing rule (sim-verify → approval → deploy).

## 11. Acceptance Criteria

Verifiable against the running app:
- [ ] Can create a game with 3, 4, 5, and 6 players; round count is 20/15/12/10 respectively; Quick game caps rounds correctly.
- [ ] Bidding step shows "Deal N cards" and a live bid tally; results step shows the tricks-remaining helper.
- [ ] Round scores match standard Wizard for hit and miss cases (spot-check the §8 examples); running totals are correct every round.
- [ ] Tricks-taken total ≠ N triggers a dismissible warning (when the check is on) but can be overridden.
- [ ] Steppers cannot exceed the round's card count for bids or tricks.
- [ ] Final screen ranks players correctly, highlights the winner, and shows ties as shared placement.
- [ ] Completed games auto-save; history shows date, players, winner, and a correct per-round breakdown.
- [ ] Editing a past round recomputes all later totals and the final result.
- [ ] Undo reverts the last confirmed entry.
- [ ] Closing and reopening the app resumes an in-progress game unchanged.
- [ ] Saved players are reusable; deleting a player leaves past games intact.
- [ ] Player stats (games, wins, win %, avg, best, exact-bid rate) are correct against known history.
- [ ] House-rule toggles behave and are snapshotted per game; the hook rule defaults off, trick-check defaults on.
- [ ] Layout is correct and legible on iPad and iPhone, in light and dark mode.
- [ ] Numbers are readable from across a table on the iPad.

## 12. Risks and Open Questions

**Risks:**
- *iPhone scoreboard density with 6 players* → mitigate with the standings-first layout + horizontally scrollable scorecard rather than forcing the full grid onto a phone.
- *Fast entry vs. accuracy* → the two-step bid/results flow plus range-capped steppers keeps entry quick while preventing impossible values; the trick-total check catches slips without blocking.
- *Editing a mid-game round corrupting totals* → totals are always **derived** from the engine over stored bids/tricks, so any edit is a clean recompute, never a manual patch.
- *Kids' iPad deployment friction* (under-13 Apple IDs need Ad Hoc IPA) → handled by the Build Guide's Recipe B; no new risk, just follow it.

**Open questions (non-blocking — Claude Code should ask, not silently decide, if it reaches one):**
- Exact set of lifetime stats to surface on the player profile (start with the §7/§8 list; confirm before adding more).
- Whether "Quick game" should cap the number of rounds or also change which card counts are used (default assumption: play rounds 1..cap).
- App-icon art direction (the one remaining generated asset; resolve during the Phase 7 `_review/` pick).
- Whether a light trump-suit memory aid is wanted after using v1 (currently deferred to v2).
