#!/usr/bin/env python3
"""Design-time announcer clip generation (ElevenLabs) — see PRD.

Generates the two voice packs (Charlie, Jessica) for the in-game announcer:
name call-outs, number stat bursts, and per-style flavor tails (styles 1-5:
Classic, Spicy, Scorched, Vicious, Unhinged). Styles 4-5 are adults-only,
never ship to the kids' iPads, and must be stripped before any App Store
submission.

Resumable: existing non-empty files are skipped. Writes manifest.json with
tail-variant counts so the app can pick clips without directory scans.

Usage: source ~/.secrets/api-keys.env && python3 tools/generate_announcer.py
"""
import json
import os
import sys
import time
import urllib.request

API_KEY = os.environ.get("ELEVENLABS_API_KEY")
if not API_KEY:
    sys.exit("ELEVENLABS_API_KEY not set — source ~/.secrets/api-keys.env")

OUT_ROOT = os.path.join(os.path.dirname(__file__), "..", "Sources", "App", "Resources", "Announcer")
VOICES = {"charlie": "IKne3meq5aSn9XLyUdCD", "jessica": "cgSgspJ2msm6clMCkdW9"}
MODEL = "eleven_multilingual_v2"

# --- Names ------------------------------------------------------------
# (slug, spoken text) — spoken text carries pronunciation fixes.
FAMILY = [
    ("darren", "Darren"), ("nikki", "Nikki"), ("matt", "Matt"), ("mark", "Mark"),
    ("marco", "Marco"), ("justin", "Justin"), ("sheena", "Sheena"), ("cami", "Cammy"),
    ("trygve", "Trigvee"), ("chase", "Chase"), ("vinny", "Vinny"), ("tucker", "Tucker"),
    ("hank", "Hank"), ("cashton", "Cashton"), ("julie", "Julie"), ("ruthie", "Ruthie"),
    ("mae", "May"), ("jeff", "Jeff"), ("sherry", "Sherry"), ("pop", "Pop"),
    ("nana", "Nanna"), ("jessica", "Jessica"), ("alex", "Alex"), ("chris", "Chris"),
    ("alice", "Alice"), ("jess", "Jess"), ("sharon", "Sharon"), ("jeffery", "Jeffery"),
    ("ben", "Ben"), ("leslie", "Leslie"), ("jake", "Jake"), ("annie", "Annie"),
]
COMMON = [(n, n.capitalize()) for n in [
    "john", "mike", "dave", "bob", "bill", "tom", "jim", "joe", "steve", "dan",
    "paul", "kevin", "brian", "scott", "eric", "ryan", "josh", "andy", "sam", "nick",
    "tony", "adam", "kyle", "tyler", "jack", "mary", "linda", "susan", "karen", "lisa",
    "amy", "sarah", "emily", "emma", "katie", "rachel", "megan", "ashley",
    "kelly", "grandma", "grandpa", "mom", "dad",
]]

WORDS = {2:"Two",3:"Three",4:"Four",5:"Five",6:"Six",7:"Seven",8:"Eight",9:"Nine",10:"Ten",
         11:"Eleven",12:"Twelve",13:"Thirteen",14:"Fourteen",15:"Fifteen"}
POINTS = {40:"Forty",50:"Fifty",60:"Sixty",70:"Seventy",80:"Eighty",90:"Ninety",100:"One hundred",
          110:"One hundred ten",120:"One hundred twenty",130:"One hundred thirty",140:"One hundred forty",
          150:"One hundred fifty",160:"One hundred sixty",170:"One hundred seventy",180:"One hundred eighty",
          190:"One hundred ninety",200:"Two hundred",210:"Two hundred ten",220:"Two hundred twenty"}

# --- Broadcast connectives: style -> {intro, trans, outro} -------------
# Glue for the one-button round broadcast: [intro] insight [trans] insight
# [trans] insight [outro]. Name-free, number-free, tone-matched per style.
CONNECTIVES = {
 1: {"intro": ["Let's check in on the table!", "Time for the round update!"],
     "trans": ["Meanwhile...", "And elsewhere...", "There's more, folks..."],
     "outro": ["Back to the cards!", "Good luck out there, everyone!"]},
 2: {"intro": ["Round update, and OH do we have notes!", "Gather 'round — the table has issues!"],
     "trans": ["It gets better...", "Meanwhile, in less flattering news...", "And ANOTHER thing..."],
     "outro": ["Deal 'em up — and try to do better!", "Back to the table. Some of you have work to do!"]},
 3: {"intro": ["ROUND UPDATE! Somebody's getting called OUT!", "STOP the presses — you need to hear this!"],
     "trans": ["Oh, we're NOT done...", "But WAIT, there's carnage...", "And meanwhile, folks..."],
     "outro": ["That's the update! Pray for the bottom of this table!", "Back to the cards — SHOW me something!"]},
 4: {"intro": ["Round update — and my GOD, where do I start?!", "Listen up! The table demands accountability!"],
     "trans": ["Oh, it gets worse...", "And as if that wasn't enough...", "Meanwhile, in the disaster zone..."],
     "outro": ["Update over. Some of you should reflect on your damn choices!", "Back to it — and for the love of GOD, bid better!"]},
 5: {"intro": ["ROUND UPDATE! Buckle the hell up!", "Holy shit, folks, what a round — let's break it down!"],
     "trans": ["Oh, we are NOT done...", "And it gets messier...", "Meanwhile, in dumpster-fire news..."],
     "outro": ["That's the damn update! Play better, all of you!", "Back to the table — and NO more shit bids!"]},
}

# --- Flavor tails: style -> kind -> variants ---------------------------
# All name-free and number-free; never target age/looks/intelligence.
TAILS = {
 1: {  # Classic — warm sports-caster
  "perfect": ["Still PERFECT! Not a single miss all game!", "Flawless! The bids just keep landing!"],
  "hotStreak": ["On FIRE! Another bid, another hit!", "The streak continues — they simply do not miss!"],
  "coldStreak": ["The cold streak continues. Thoughts and prayers.", "Ice cold! Somebody grab a blanket!",
                 "Another miss! The wheels are wobbling, folks."],
  "bigRound": ["BOOM! The round of the game!", "A MASSIVE round! The scorepad is smoking!"],
  "zeroSpecialist": ["Another perfect zero! An artist at work!", "Bid nothing, took nothing — poetry, folks!"],
  "boldestBidder": ["The boldest bidder at the table — no fear!", "Swinging BIG again!"],
  "winner": ["That's the GAME! We have a CHAMPION!", "It's all over — what a performance!"],
  "lastPlace": ["And hey — somebody had to come in last.", "Better luck next game, friend."],
 },
 2: {  # Spicy — the announcer has opinions
  "perfect": ["Still perfect! Save some glory for the rest of the table!", "Perfection! This is getting suspicious, folks!"],
  "hotStreak": ["Another hit! Leave some for everybody else!", "Red hot! The table is in TROUBLE!"],
  "coldStreak": ["Speedrunning last place, folks!", "The confidence and the scorecard are no longer on speaking terms!",
                 "Another miss! Hide the scorecard from the children!"],
  "bigRound": ["A monster round! Show-off.", "Massive points! Absolutely rude!"],
  "zeroSpecialist": ["Another zero! Doing nothing has never looked so good!", "Zero called, zero taken. Menace behavior!"],
  "boldestBidder": ["Huge bid AGAIN! Confidence level: unearned!", "The audacity is off the charts!"],
  "winner": ["It's OVER! Act like you've been here before!", "The winner! Everyone else — take notes!"],
  "lastPlace": ["Dead last! But hey — great snacks tonight.", "Last place! We've alerted the authorities."],
 },
 3: {  # Scorched — full roast-battle meltdown, still clean
  "perfect": ["PERFECT AGAIN! Everyone else can GO HOME! It's OVER!", "Not playing cards — committing ROBBERY!"],
  "hotStreak": ["They simply CANNOT be stopped! This is a HOSTILE TAKEOVER!", "Another one! Have MERCY on this table!"],
  "coldStreak": ["I have seen CAR CRASHES with better outcomes!", "The deck is just BULLYING them at this point!",
                 "A collapse in REAL TIME, people!", "Someone take the scorecard away — this is a CRIME SCENE!"],
  "bigRound": ["That wasn't a round — that was a STATEMENT!", "DETONATION! The whole table felt that one!"],
  "zeroSpecialist": ["Another zero! Cold. Blooded. ASSASSIN!", "Doing NOTHING and getting PAID! Criminal!"],
  "boldestBidder": ["The audacity! The HUBRIS! The inevitable DISASTER!", "Betting the farm AGAIN! Somebody stop them!"],
  "winner": ["TOTAL DOMINATION! The rest of you were DECORATION!", "A MASSACRE! Frame this scorecard!"],
  "lastPlace": ["Last place! We are still LOOKING for the strategy, folks!",
                "Dead last! The announcer's union says I don't have to talk about it!"],
 },
 4: {  # Vicious — mild expletives, personal edge. ADULTS ONLY.
  "perfect": ["Perfect AGAIN! The rest of you should be ASHAMED!", "Good LORD! Just hand over the trophy already!"],
  "hotStreak": ["ANOTHER hit! This is getting disrespectful as hell!", "Unstoppable! And frankly? Insufferable!"],
  "coldStreak": ["My GOD, have some self-respect!", "What the HELL was that bid?!",
                 "A five-year-old with a juice box saw that coming!", "Somebody call their emergency contact!"],
  "bigRound": ["A damn MASTERPIECE of a round!", "Pack it up, everyone. Pack it ALL up."],
  "zeroSpecialist": ["Another zero — living their best damn life!", "Doing nothing and STILL beating half this table!"],
  "boldestBidder": ["That bid is an INSULT to everyone who has ever held cards!", "Bidding like rent is due TONIGHT!"],
  "winner": ["It's OVER! And it wasn't even CLOSE, was it?!", "The winner! The rest of you made damn good television!"],
  "lastPlace": ["Dead last. At this point it's not luck — it's a personality trait!", "Last place AGAIN! The family is WATCHING!"],
 },
 5: {  # Unhinged — real profanity, R-rated roast. ADULTS ONLY, never App Store.
  "perfect": ["STILL perfect! You have GOT to be shitting me!", "UNREAL! Somebody frisk this player — I am dead serious!"],
  "hotStreak": ["ANOTHER one! This is bullshit-level lucky, folks!", "On FIRE! The rest of this table is getting its ass KICKED!"],
  "coldStreak": ["That was a shit bid and EVERYBODY at this table knew it!", "Holy hell — someone stage an intervention!",
                 "Get your shit together — the FAMILY is watching!", "How?! HOW does that keep happening?!"],
  "bigRound": ["HOLY SHIT, what a round!", "That is a whole-ass BEATDOWN in one hand!"],
  "zeroSpecialist": ["Zero called, zero taken, zero shits given! LEGEND!"],
  "boldestBidder": ["That bid?! BALLS of solid brass, folks!", "Betting like a maniac with NOTHING to lose!"],
  "winner": ["IT'S OVER! An ass-kicking for the AGES!", "CHAMPION! The rest of you got absolutely WRECKED!"],
  "lastPlace": ["Dead. Ass. LAST. Someone drive them home!", "This is an intervention. We love you. But DAMN!"],
 },
}

def tts(voice_id, text, path):
    body = json.dumps({
        "text": text, "model_id": MODEL,
        "voice_settings": {"stability": 0.35, "similarity_boost": 0.75, "style": 0.65},
    }).encode()
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128",
        data=body, headers={"xi-api-key": API_KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    if not data.startswith(b"ID3") and data[:1] != b"\xff":
        raise RuntimeError(f"non-audio response: {data[:120]!r}")
    with open(path, "wb") as f:
        f.write(data)

def jobs_for_voice():
    jobs = []  # (filename, spoken text) — generation order = priority order
    for slug, spoken in FAMILY:
        jobs.append((f"name_{slug}.mp3", f"{spoken}!"))
    for n in range(2, 16):
        jobs.append((f"inarow_{n}.mp3", f"{WORDS[n]} in a row!"))
    for n in range(3, 16):
        jobs.append((f"perfect_{n}.mp3", f"{WORDS[n]} for {WORDS[n].lower()} — PERFECT!"))
    for pts, word in POINTS.items():
        jobs.append((f"points_{pts}.mp3", f"{word} points!"))
    for n in range(3, 11):
        jobs.append((f"zeros_{n}.mp3", f"{WORDS[n]} perfect zeros!"))
    for style, kinds in TAILS.items():
        for kind, variants in kinds.items():
            for i, line in enumerate(variants):
                jobs.append((f"tail_{style}_{kind}_{i}.mp3", line))
    for style, groups in CONNECTIVES.items():
        for group, variants in groups.items():
            for i, line in enumerate(variants):
                jobs.append((f"seg_{style}_{group}_{i}.mp3", line))
    for slug, spoken in COMMON:
        jobs.append((f"name_{slug}.mp3", f"{spoken}!"))
    return jobs

def main():
    manifest = {"voices": list(VOICES), "styles": {str(s): {k: len(v) for k, v in kinds.items()} for s, kinds in TAILS.items()},
                "names": [s for s, _ in FAMILY + COMMON],
                "aliases": {"nicky": "nikki"},
                "inarow": [2, 15], "perfect": [3, 15], "points": [40, 220], "zeros": [3, 10]}
    os.makedirs(OUT_ROOT, exist_ok=True)
    with open(os.path.join(OUT_ROOT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)

    done = skipped = failed = 0
    for vname, vid in VOICES.items():
        vdir = os.path.join(OUT_ROOT, vname)
        os.makedirs(vdir, exist_ok=True)
        for fname, text in jobs_for_voice():
            path = os.path.join(vdir, fname)
            if os.path.exists(path) and os.path.getsize(path) > 1000:
                skipped += 1
                continue
            for attempt in (1, 2):
                try:
                    tts(vid, text, path)
                    done += 1
                    break
                except Exception as e:
                    if attempt == 2:
                        failed += 1
                        print(f"FAIL {vname}/{fname}: {e}", flush=True)
                    else:
                        time.sleep(3)
            if done and done % 25 == 0:
                print(f"progress: {done} generated ({vname})", flush=True)
            time.sleep(0.35)  # gentle on rate limits
    print(f"DONE: {done} generated, {skipped} skipped, {failed} failed", flush=True)

if __name__ == "__main__":
    main()
