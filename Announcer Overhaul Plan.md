---
title: "Announcer Overhaul Plan - Score-First Commentary and the Two-SKU App Store Strategy"
created: 2026-07-24
modified: 2026-07-25
version: 1.2
author: Claude Fable 5 (claude-fable-5)
tags:
---

# Announcer Overhaul Plan

The announcer is the hero feature and the reason this app can stand out in the App Store (competitive research found zero Wizard or Oh Hell scorekeepers with any voice feature). But the current commentary buries its two jobs, names and scores, under filler. This plan is in three parts: (1) a critical review of what is wrong today, (2) the redesign, (3) the App Store two-SKU and launch strategy.

North star, in one sentence: **Name. Score. One great joke. Under 15 seconds.**

## Part 1: What is wrong today

### 1.1 The connectives are the garbage

`announceRoundUpdate` assembles: intro + insight + transition + insight + transition + insight + transition + insight + outro. That is up to five clips per broadcast that carry zero information, and they are word-for-word the complained-about filler:

- Transitions: "Meanwhile...", "There's more, folks...", "Also worth noting...", "Oh, we're NOT done...", "But WAIT, there's carnage...", "Hold on, there's MORE...", "Hold my beer, there's more..."
- Intros delay the first name by 2-4 seconds: "ROUND UPDATE! Somebody's getting called OUT!", "STOP the presses - you need to hear this!"
- Outros are dead air after the payoff: "Update over. Some of you should reflect on your damn choices!"

**Verdict: delete the entire connective layer.** Not trim. Delete. A great announcer never says "in other news"; he just says the next name.

### 1.2 Most players never hear their own score

The broadcast covers up to 4 editorial "stories" (lead story, juice, rotating third story, garnish). In a 5-6 player game, half the table hears nothing about themselves, ever. The product promise is "hear YOUR name and YOUR score." That is a structural gap, not a line-quality gap, and no amount of line rewriting fixes it.

### 1.3 Redundancy: the tail restates the lead-in

"KELLY! Stretching the lead to... ONE-EIGHTY!" followed by tail "DOMINATING! Somebody do something!" is two clips saying the same thing. Tails are name-free, number-free, and picked by category, so they can only ever restate the category.

### 1.4 The joke comes before the score, or instead of it

Long wind-up lead-ins ("Sweating BULLETS - the lead is down to a lousy...") delay the number, which is the payload. Comedy rule and broadcast rule agree here: fact first, joke second. The punchline should land after the number, as a button, not before it as throat-clearing.

### 1.5 Volume is not a joke

The corpus's default comedic move is capitalization: "ABSOLUTE CARNAGE! No survivors!", "DETHRONED!", "The audacity! The HUBRIS!". A few lines are genuinely funny ("Zero called, zero taken. Menace behavior!", "Doing NOTHING and getting PAID!") and they share a shape: short, concrete, specific, dry. Spicy (buckets 4-5) mostly decorates the same cliches with damn/ass/shit instead of writing better jokes. Profanity should be seasoning on a real joke, not the joke.

The existing audit pass agrees: 192 of 400 entries in `tools/announcer_suggestions.json` carry edit suggestions, most of them pure wordiness trims, plus flagged duplicate gags across variants.

### 1.6 Merged buckets cause tonal whiplash

Fun draws from buckets 2+3: a dry one-liner followed by a SCREAMING MELTDOWN line in the same broadcast. Spicy merges "mild expletive" bucket 4 with R-rated bucket 5. Neither tier sounds like one person. Variety was the goal, but variety of jokes beats variety of personalities.

### 1.7 Every broadcast has the same shape

Intro, stories, outro, every round. Predictability kills comedy by round 5. The fix is not more variants of the same slots; it is a score-readout backbone (always fresh because the numbers change) plus exactly one rotating joke.

### What already works (keep it)

- The clip-stitching grammar (NAME + lead-in + 400ms beat + number) with natural numbers and reserved shouted emphasis. The dramatic pause is genuinely good.
- The insight engine: slot ranking, name dedupe, tenure override, mod-based story rotation. The selection brain is fine; the mouth is the problem.
- Per-name recorded call-outs. This is the magic. "It says MY name" is the whole hook.
- Graceful-skip resolution, variant no-repeat bookkeeping, audio session handling.

## Part 2: The redesign

### 2.1 New broadcast grammar: the Score Rundown

Every round update follows one backbone:

1. **Round stamp** (optional, 1 clip, under 1s): "Round seven." No hype intro.
2. **The rundown**: every player, standings order, NAME + number, rapid-fire, natural delivery. A 2-3 word lead-in on the leader only ("Leads with..."). Everyone else is bare NAME + number. Ties get "tied at".
3. **The button**: exactly ONE punchline, attached to the round's best story (the existing juice slot picks it), spoken as NAME + punchline clip. Shouted number emphasis stays reserved for genuine fist-pump moments (lead change, monster round).

Example target (Fun tier, 4 players):

> "Round seven. KELLY! Leads with one-eighty. MATT! One-forty. JUSTIN! Ninety. NIKKI! Forty. Nikki... that scorecard needs a lawyer."

Roughly 11 seconds. Every player hears their name and score every round. One joke, and it lands last.

Engineering notes:

- The clip library already supports this: name clips, `num_`/`num1_` families, short lead-ins. New work is assembly logic in `announceRoundUpdate` plus a handful of new micro lead-ins ("Leads with...", "Tied at...").
- Pacing: insert a short beat (150-200ms silence clip) between players so the rundown reads as a list, not a run-on.
- Keep the story slots (lead change, streaks, chase) as the punchline selector and as occasional replacements for the leader's plain lead-in ("KELLY! Takes the lead... one-eighty!"), not as extra segments.
- Player-count adaptation: 6 players, trim to leader + everyone rapid-fire + button; 2-3 players, room for one extra story beat. Cap total length at ~15s always.
- Pregame call and game wrap keep their current short shapes but lose their intro/outro connectives and get the same one-punchline discipline. The game wrap may keep two story beats; it is the trailer moment.

### 2.2 Corpus rewrite: three characters, written on purpose

Replace the five merged buckets with three tiers written as coherent characters, each with a one-page character bible before any lines are written:

- **Classic** (clean, 4+): the warm pro. Calls it straight, dry wit, never mocks. Think golf announcer who secretly loves everyone at the table.
- **Fun** (clean, target 9+): the roast is the scoreboard's fault. Dry, specific, modern; no shouting-as-joke. "Bid three, took zero. Bold strategy." "The basement lease got renewed."
- **Spicy** (18+ SKU only): actually funny R-rated roast. The profanity lands because the joke underneath is real. One expletive per line maximum; placement is the punch.

Writing rules (enforced in review):

1. Punchline of 10 words or fewer, one gag per line, concrete image over abstraction.
2. No meta-announcing ever: no "worth noting", "in other news", "update over", "where do I start".
3. Joke after fact. Lines that precede a number stay under 5 words.
4. No two variants of the same kind may share a gag (the audit already caught "not on speaking terms" twice).
5. Caps only where the TTS should genuinely spike, at most one word per line.
6. Never target age, looks, or intelligence (existing rule, keep).
7. Every line must survive being heard 20 times in one game night. When in doubt, shorter.

Inputs to the rewrite: the 192 trim suggestions in `announcer_suggestions.json` (mine them, do not start from zero), and the keep-list of the 208 lines already marked tight.

### 2.3 Production pipeline

1. Character bibles + full line corpus drafted (delegable writing work; lead reviews every line against the rules above; Justin has final ear).
2. Update `generate_announcer.py`: new corpus, three buckets replacing five, connectives removed, new micro lead-ins added. Regenerate through ElevenLabs (paid plan required: free-tier audio is not licensed for a shipped app; the commercial license on paid tiers covers embedding clips in the app).
3. Rebuild the audit page for the new corpus; one listening pass by Justin flags clunkers; regenerate flagged lines.
4. Update `Announcer.swift`: rundown assembly, connective removal, tier-to-bucket mapping simplification (the merged-pool logic in `tailURL` collapses to a direct mapping).
5. Real game night test with the family, both games. Success criteria: round update under 15s, every name heard, at least one genuine laugh per game, nobody reaches to skip it.

### 2.4 Name coverage (the App Store gap)

The current pack covers ~75 hardcoded family and common names. For strangers downloading from the App Store, an unknown name currently just goes silent, which kills the hook for exactly the people we want to wow.

- v1 (locked at ~300): expand the generated pack to the top ~300 US first names plus common nicknames (cheap: one-time generation, a few hundred small MP3s; measure bundle impact, likely acceptable at 128kbps mono).
- v1 fallback: when a name has no clip, the announcer still delivers the score line minus the name rather than skipping the player. Never silence.
- v2 (also the monetization/viral hook): "Custom Name Pack" IAP. User types any name or nickname, a small backend generates the call-out clips via the ElevenLabs API and the app downloads them. "It says MY name" becomes the paid delight and the thing people demo to friends.

## Part 3: App Store strategy, two SKUs

### 3.1 Ratings landscape (verified July 2026)

Apple's tiers are now 4+, 9+, 13+, 16+, 18+ (2025 overhaul). "Infrequent/Mild Profanity or Crude Humor" lands at 9+; "Frequent/Intense" lands at 16+ or 18+ depending on the combination. Censored profanity ("f***") still counts toward the rating. Precedents: Cards Against Humanity's Party Mouth sits at 16+ with frequent profanity descriptors; harder adult party apps sit at 18+. The rating must cover the worst content reachable in the binary, so a toggle-gated profanity mode does not lower the rating; one binary containing Spicy is a 16+/18+ app no matter the default.

Sources:
- https://developer.apple.com/news/?id=ks775ehf
- https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/
- https://developer.apple.com/app-store/review/guidelines/

### 3.2 The two SKUs

- **Clean SKU** ("Wizard Keeper" / "Oh Hell Keeper", target 4+ or 9+): ships Classic + Fun only. The Fun tier's crude-humor level decides 4+ vs 9+; write Fun to sit comfortably at 9+ and answer the questionnaire honestly.
- **Spicy SKU** (18+, distinct brand): ships Classic + Fun + Spicy (a superset; adults still get the clean tiers for mixed company). Marketed openly as the uncensored one.

Two risks to design around, both confirmed in the guidelines research:

1. **Guideline 4.3 (spam/duplicate apps)**: two near-identical listings from one developer invite rejection. Mitigation: the spicy SKU is a genuinely distinct product, not "Wizard Keeper (Spicy)": its own name, icon, screenshots, description, and the different rating. Working-title direction: a name that sells the announcer, not the scorepad (e.g. "Trash Talk Scorekeeper: Wizard"; final name is Justin's call).
2. **Marketing self-censorship**: even 18+ listings must keep name, subtitle, screenshots, and preview video clean of actual profanity (precedent: "Evil Apples: Funny as ____"). The listing teases, the app delivers.

Sequencing (locked): do not launch four apps at once. Wave 1 is clean Wizard Keeper + clean Oh Hell Keeper, both free. Wave 2 is one 18+ Wizard app under a new announcer-led brand; Oh Hell spicy only if wave 2 earns it. This halves the 4.3 surface at review time and the build/deploy burden per change (already flagged in STATUS as the biggest risk).

Build mechanics: tier availability becomes a compile-time flag alongside the existing `AppGame` config; the clean target's bundle simply never contains bucket-3 clips (strip at the resource-copy step, verified by a build-time test that fails if any spicy clip is present in a clean archive).

### 3.3 The viral loop: Share the Call

Research found the closest viral analog is the AI-roast trend (short, personalized, escalating audio roasts built to be screen-recorded). We can make sharing native instead of hoping for screen recordings:

- After any broadcast, a **Share the Call** button renders the audio over an animated scorecard with word-by-word captions (we know the exact script text of every clip, so captions are free) and exports a vertical video sized for Messages/TikTok/Reels.
- The end-of-game wrap is the flagship shareable: winner call, story beats, last-place roast, final chart.
- The group-chat drop after game night is the organic distribution channel; every shared call is an ad with the app's voice literally in it.

This is the single highest-leverage feature for "maybe even viral" and it is pure client-side work on top of assets we already have.

### 3.4 Remaining store readiness (unchanged from STATUS, sequenced last)

Icons at all required sizes, privacy policy (trivial: no accounts, no tracking, on-device data), listing copy and screenshots per SKU, `ITSAppUsesNonExemptEncryption`, TestFlight for both apps.

## Work packages

| # | Package | What | Size | Depends on |
|---|---------|------|------|------------|
| WP1 | Rundown grammar | `Announcer.swift` + slot logic: score rundown, connective removal, one-punchline rule, length caps | M | none |
| WP2 | Character bibles + corpus rewrite | 3 tier bibles, full line rewrite mining the audit suggestions, review against writing rules | L | none (parallel with WP1) |
| WP3 | Regeneration + audit | Update generator, regenerate clips (paid ElevenLabs), rebuild audit page, Justin ear pass, fix flagged lines | M | WP2 |
| WP4 | Name expansion | Top 300-500 names + nickname aliases + never-silent fallback | S | WP3 (batch together) |
| WP5 | Game night QA | Real family test against success criteria, iterate | S | WP1+WP3 |
| WP6 | Clean/Spicy build split | Tier compile flag, clip-strip step, build-time guard test | S | WP1 |
| WP7 | Share the Call | Caption-synced vertical video export of any broadcast | M | WP1 |
| WP8 | Store readiness | Ratings questionnaires, icons, privacy policy, listings, TestFlight, submission (wave 1 clean, wave 2 spicy) | M | all |

Suggested order: WP1+WP2 in parallel, then WP3+WP4, WP5 gate, then WP6+WP7, then WP8.

## Decisions locked (Justin, 2026-07-24)

1. **Business model: free + IAP.** Both clean apps free; monetize Custom Name Packs (and potentially tier unlocks) via in-app purchase. Viral spread is the priority.
2. **Rundown covers everyone, always.** Every player hears their name and score every round, even at 6 players. The core promise beats brevity.
3. **Round stamp stays.** Each broadcast opens with a bare "Round seven." then goes straight to the first name.
4. **Fun tier is 9+ family-safe.** Dry roasts of the scoreboard, zero profanity. Consequence: the clean SKU is safe for the kids' iPads, so no separate stripped family build is ever needed.
5. **Spicy persona: roast-comic.** Comedy-roast energy aimed at the scoreboard: personal, specific, profanity as punctuation on a real joke.
6. **Charlie only at launch.** One voice, one character. The two-man booth (play-by-play + color commentator trading lines) is explicitly backlogged as a future headline update, not launch scope.
7. **Name pack: ~300 names bundled**, top US first names + nicknames, never-silent fallback. Custom Name Pack IAP backend is fast-follow, not launch.
8. **ElevenLabs budget: already covered.** An adequate paid plan (commercial license) is active; regenerate freely.
9. **Spicy SKU: Wizard first, new brand.** One 18+ app for Wizard under an announcer-led name; Oh Hell spicy later only if it earns it. Open item: pitch brand-name candidates (working direction: sell the announcer, not the scorepad).
10. **Share the Call ships in the launch build.** No hard date; the quality gate is the family game night test.

Sole remaining open item at the time: the Spicy SKU's brand name. RESOLVED 2026-07-25 (overnight execution session, Justin pre-authorized all decisions): the 18+ SKU is **"Trash Talk"** (bundle `com.levelup.trashtalk`, target `TrashTalkKeeper`). Rationale: announcer-led (sells the hook, not the scorepad), clearly distinct from "Wizard Keeper" for Guideline 4.3, self-censorable in marketing, and searchable. Candidate names considered: Trash Talk, Smack Talk Scorekeeper, The Heckler, Roasted. Icon: grawlix speech bubble (candidate A of 4; all four in `_review/trashtalk-icon-*.png` for Justin's review; A is wired in as `AppIconTrashTalk` and deployed).

## Execution log (overnight 2026-07-25)

- WP1 done: score-rundown grammar shipped in `Announcer.swift` (round stamp + full standings readout + one punchline; connective machinery deleted). Call sites reuse `StandingsCalculator`.
- WP2 done: full three-character corpus rewrite (285 punchlines, 144 lead-ins), worker-drafted, lead-reviewed with 8 editorial fixes (gag collisions, gap-vs-total lead-in ambiguity).
- WP3 done: generator rebuilt for 3 tiers + round stamps (`round_1..25`) + `silence_200`; 760 new clips generated via ElevenLabs, 0 failures; audit page rebuilt (847 lines).
- WP4 done: 306-name expansion + 67 aliases; never-silent fallback confirmed (rundown skips a missing name clip but still reads the score).
- WP6 done: `TrashTalkKeeper` target (18+, all tiers); spicy clips isolated to `Sources/App/Resources/AnnouncerSpicy/` bundled ONLY by that target; clean targets hide Spicy via `GameVariant.allowsSpicyTier`; release guard `tools/check_clean_bundle.sh` passes for both clean apps.
- WP5 partial: engine suite green (109 checks), all three schemes build, bundle-level clip resolution verified; REAL game night test still pending (the true quality gate).
- WP7 (Share the Call): in flight at time of writing; see STATUS.
- Deployed: Trash Talk to Justin's iPhone (dev build, Recipe A).
