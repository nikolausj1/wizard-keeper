---
title: "STATUS - Wizard Keeper"
created: 2026-07-24
modified: 2026-07-25
version: 2.0
author: Claude Fable 5 (claude-fable-5)
tags:
---

# Wizard Keeper - Status

## Project

Wizard Keeper is a SwiftUI/SwiftData iOS scorekeeper family for trick-taking games, three apps from one codebase: Wizard Keeper and Oh Hell Keeper (clean, all-ages) plus Trash Talk (18+, Wizard variant with the profane Spicy announcer tier). Hero feature: an AI announcer that reads every player's name and score each round with one punchline, in Classic/Fun/Spicy tones.

## Stage

Active Development

## Health

🟢 On-track - the announcer overhaul executed overnight 2026-07-25: new score-rundown broadcast, full 3-tier corpus rewrite (760 clips regenerated, 0 failures), the new 18+ Trash Talk app built and deployed to Justin's iPhone.

## Waiting on Me

- [ ] **Play with the new announcer on your iPhone and judge it** (Trash Talk is installed; try all three tiers) (~30 min)
      - unblocks: the real quality gate for the rewrite; flag any clunker lines in the audit page (`_review/announcer-audit.html`, 847 clips)
- [ ] **Approve or override the Trash Talk icon** (candidate A, grawlix speech bubble, is live; all 4 in `_review/trashtalk-icon-*.png`) (~5 min)
      - unblocks: final branding for the 18+ SKU
- [ ] **Play a real game night with the new rundown** (does everyone light up when they hear their name and score?) (~1-2 hrs)
      - unblocks: WP5 sign-off and the go/no-go for App Store submission work

## Next Up

1. Review the overnight work: Share the Call feature (WP7) result, then commit the whole overhaul to git.
2. WP8 store readiness: ratings questionnaires (clean 9+, Trash Talk 18+), privacy policy, listing copy, screenshots per SKU.
3. Custom Name Pack IAP backend scoping (fast-follow after launch).

## Ideas Shelf

- **Sound effects** (S) - quick polish layered onto the voice pack system
- **Two-man booth** (L) - play-by-play + color commentator trading lines; backlogged by Justin 2026-07-24 as a future headline update
- **Trump-suit memory aid** (S) - small UI helper on the bid/trick entry screens
- **Richer stats/charts** (M) - win streaks and scoring trends across game nights
- **iCloud sync** (M) - cross-device history/stats

## Biggest Risk

The rewritten corpus has passed rules-checking but not real ears: if the new lines or the rundown pacing fall flat at an actual game night, the App Store push stalls until another writing pass.

---

## Deferred

- Kids' iPad rollout: structurally solved (clean apps no longer contain any Spicy clip, verified by `tools/check_clean_bundle.sh`); deploy whenever Justin says go (Ad Hoc recipe)
- Splitting announcer lines per-game (Wizard vs Oh Hell) if any shared line feels off for one game

## App Store Readiness

- Two-SKU structure DONE: clean targets (Wizard Keeper, Oh Hell Keeper, target 9+) bundle no profanity; Trash Talk (com.levelup.trashtalk, 18+) carries all three tiers via the AnnouncerSpicy folder split
- Business model locked: free + IAP (Custom Name Packs); 306-name expansion pack bundled for App Store strangers
- Still needed: ratings questionnaires, privacy policy, listing copy + screenshots per SKU (marketing must self-censor for Trash Talk), App Store Connect records, TestFlight, icon asset size checks
- `ITSAppUsesNonExemptEncryption` already false in project.yml for all targets
