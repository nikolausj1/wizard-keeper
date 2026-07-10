# Wizard Keeper

The family game-night scorepad for the [Wizard card game](https://en.wikipedia.org/wiki/Wizard_(card_game)) — an iPhone-first (universal iPhone + iPad) SwiftUI app that does the bid-and-trick math, keeps a live running scoreboard, and remembers who plays.

**Scorepad, not a game**: you deal and play with real cards; the app replaces the paper score sheet.

## Project layout

- `project.yml` — XcodeGen source of truth (`xcodegen generate` after adding files; `WizardKeeper.xcodeproj` is generated and gitignored)
- `Sources/Engine/` — pure Foundation scoring engine, UI-independent, the single source of truth for all score math
- `Sources/Models/` — SwiftData persistence layer (scores are always derived through the engine, never stored)
- `Sources/App/` — SwiftUI app
- `Tests/SmokeTest.swift` — engine smoke test, runnable without Xcode:

```sh
xattr -cr Sources && cp Tests/SmokeTest.swift /tmp/main.swift \
  && swiftc -O Sources/Engine/*.swift /tmp/main.swift -o /tmp/t && /tmp/t
```

## Scoring (standard Wizard)

Hit your bid exactly: **+20, plus +10 per trick bid**. Miss: **−10 per trick over or under**. Rounds run 1..R cards with R = 60 ÷ players (3→20, 4→15, 5→12, 6→10). House-rule variants are Settings toggles, snapshotted per game.

See `Wizard Keeper PRD.md` for the full product spec.
