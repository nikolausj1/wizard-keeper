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
# Jessica ("cgSgspJ2msm6clMCkdW9") retired 2026-07-12 per Justin — single
# male voice pack. Keep the ID here if she ever gets a comeback tour.
VOICES = {"charlie": "IKne3meq5aSn9XLyUdCD"}
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
         11:"Eleven",12:"Twelve",13:"Thirteen",14:"Fourteen",15:"Fifteen",
         16:"Sixteen",17:"Seventeen",18:"Eighteen",19:"Nineteen",20:"Twenty"}
POINTS = {40:"Forty",50:"Fifty",60:"Sixty",70:"Seventy",80:"Eighty",90:"Ninety",100:"One hundred",
          110:"One hundred ten",120:"One hundred twenty",130:"One hundred thirty",140:"One hundred forty",
          150:"One hundred fifty",160:"One hundred sixty",170:"One hundred seventy",180:"One hundred eighty",
          190:"One hundred ninety",200:"Two hundred",210:"Two hundred ten",220:"Two hundred twenty"}

# --- Broadcast connectives: style -> {intro, trans, outro} -------------
# Glue for the one-button round broadcast: [intro] insight [trans] insight
# [trans] insight [outro]. Name-free, number-free, tone-matched per style.
CONNECTIVES = {
 1: {"intro": ["Let's check in on the table!", "Time for the round update!", "Here's how things stand!"],
     "trans": ["Meanwhile...", "There's more, folks...", "Also worth noting...", "In other news..."],
     "outro": ["Back to the cards!", "Good luck out there, everyone!", "Play on, everyone!"]},
 2: {"intro": ["Round update, and we have some notes!", "Gather 'round — the table has issues!", "The scorepad has OPINIONS tonight!"],
     "trans": ["It gets better...", "Meanwhile, in less flattering news...", "Speaking of questionable choices...", "Which brings us to..."],
     "outro": ["Deal 'em up — and try to do better!", "Back to the table. Some of you have work to do!", "Shuffle up \u2014 and do better!"]},
 3: {"intro": ["ROUND UPDATE! Somebody's getting called OUT!", "STOP the presses — you need to hear this!", "EMERGENCY meeting — look at this scorepad!"],
     "trans": ["Oh, we're NOT done...", "But WAIT, there's carnage...", "And it gets JUICIER...", "Hold on, there's MORE..."],
     "outro": ["Back to the cards!", "That's the damage \u2014 back to WAR!"]},
 4: {"intro": ["Round update — and my GOD, where do I start?!", "Gather round for the damage report!"],
     "trans": ["Oh, it gets worse...", "And as if that wasn't enough...", "Meanwhile, in the disaster zone...", "And because the universe is cruel...", "Oh, and one more disaster..."],
     "outro": ["Update over. Some of you should reflect on your damn choices!", "Back to it — and for the love of GOD, bid better!", "Back at it \u2014 and for God's sake, do better!"]},
 5: {"intro": ["ROUND UPDATE! Buckle the hell up!", "Holy shit, folks, what a round — let's break it down!", "Strap in for the damn update!"],
     "trans": ["Hold my beer, there's more...", "And it gets worse...", "Meanwhile, in dumpster-fire news...", "And in worse news...", "Hold my drink, there's more..."],
     "outro": ["That's the damn update! Play better, all of you!", "Back to the table — and NO more shit bids!", "Now get back in there and raise hell!"]},
}

# --- Flavor tails: style -> kind -> variants ---------------------------
# All name-free and number-free; never target age/looks/intelligence.
TAILS = {
 1: {  # Classic — warm sports-caster
  "leadChange": ["A NEW leader at the table!", "The top spot changes hands!"],
  "nosedive": ["That one left a mark!", "A tough, tough round!"],
  "everybodyHit": ["EVERYBODY hit! What a round!", "A clean sweep — everyone landed it!"],
  "carnage": ["What a round — almost nobody survived!", "The deck showed no mercy!"],
  "tightRace": ["It is NECK and NECK at the top!", "This one's coming down to the wire!"],
  "kickoff": ["Shuffle up and deal — let's play!", "Round one — here we go!"],
  "chasing": ["Right on the leader's heels!", "The chase is ON!", "Within striking distance!", "Keeping the pressure on!"],
  "trailing": ["Bringing up the rear — plenty of game left!", "Last place... for now!", "Room to grow, friend!", "The comeback starts now!"],
  "leading": ["Out in front and cruising!", "Top of the pile, folks!", "Setting the pace so far!", "The one to catch, folks!"],
  "reigningChamp": ["The reigning champion is at the table!", "Last game's winner is BACK!"],
  "freshGame": ["A fresh scorepad! Anything can happen!", "New game, clean slate — good luck, everyone!"],
  "perfect": ["Still PERFECT! Not a single miss all game!", "Flawless! The bids just keep landing!", "A spotless record so far!", "Not one wrong call yet!"],
  "hotStreak": ["On FIRE! Another bid, another hit!", "The streak continues — they simply do not miss!", "Locked in right NOW!", "Everything's landing!"],
  "coldStreak": ["The cold streak continues. Thoughts and prayers.", "Ice cold! Somebody grab a blanket!",
                 "Another miss! The wheels are wobbling, folks.", "The luck has GOT to turn soon.", "A rough patch, folks \u2014 hang tight."],
  "bigRound": ["BOOM! The round of the game!", "A MASSIVE round! The scorepad is smoking!"],
  "zeroSpecialist": ["Another perfect zero! An artist at work!", "Bid nothing, took nothing — poetry, folks!"],
  "boldestBidder": ["The boldest bidder at the table — no fear!", "Swinging BIG again!"],
  "winner": ["That's the GAME! We have a CHAMPION!", "It's all over — what a performance!"],
  "lastPlace": ["And hey — somebody had to come in last.", "Better luck next game, friend."],
 },
 2: {  # Spicy — the announcer has opinions
  "leadChange": ["NEW leader! Act surprised, everyone!", "There's been a coup at the top!"],
  "nosedive": ["That sound you hear is a score screaming!", "Ouch. OUCH."],
  "everybodyHit": ["Everybody hit?! BORING! Where's the drama?!", "All hits! Suspiciously competent!"],
  "carnage": ["CARNAGE! The deck took hostages!", "A massacre! Somebody call for help!"],
  "tightRace": ["Photo finish territory, people!", "The leader can hear footsteps!"],
  "kickoff": ["Deal 'em up. Let's see who disappoints first!", "Round one! Places, everyone!"],
  "chasing": ["Closing in — the leader should be nervous!", "Hot on the trail!", "Plotting a takeover as we speak!", "Smelling blood in the water!"],
  "trailing": ["Holding down last place like it's a job!", "The basement has a new tenant!", "Someone start a rescue fund!", "It's called building suspense, folks!"],
  "leading": ["Leading the pack — for now!", "First place! Enjoy it while it lasts!", "Enjoying the view from the top!", "Comfortably ahead \u2014 for now!"],
  "reigningChamp": ["The champ is back to defend the crown!", "Reigning champion — target on their back!"],
  "freshGame": ["Clean slate! Time for some questionable bids!", "New game! Zero points, zero excuses!"],
  "perfect": ["Still perfect! Save some glory for the rest of the table!", "Perfection! This is getting suspicious, folks!", "Flawless \u2014 and just a little smug about it!", "Perfect record! The audacity!"],
  "hotStreak": ["Red hot! The table is in TROUBLE!", "Untouchable right now \u2014 annoyingly so!"],
  "coldStreak": ["The confidence and the scorecard are no longer on speaking terms!",
                 "Another miss! Hide the scorecard from the children!", "The bids and the cards are not on speaking terms!", "Cold enough to see your breath over there!"],
  "bigRound": ["A monster round! Show-off.", "Massive points! Absolutely rude!"],
  "zeroSpecialist": ["Another zero! Doing nothing has never looked so good!", "Zero called, zero taken. Menace behavior!"],
  "boldestBidder": ["Huge bid AGAIN! Confidence level: unearned!", "The audacity is off the charts!"],
  "winner": ["It's OVER! Act like you've been here before!", "The winner! Everyone else — take notes!"],
  "lastPlace": ["Dead last! But hey — great snacks tonight.", "Last place! We've alerted the authorities."],
 },
 3: {  # Scorched — full roast-battle meltdown, still clean
  "leadChange": ["A HOSTILE TAKEOVER at the top!", "DETHRONED! There's a new ruler!"],
  "nosedive": ["A collapse of HISTORIC proportions!", "That wasn't a round, that was a DEMOLITION!"],
  "everybodyHit": ["A PERFECT round?! Who ARE you people?!", "Everybody hit! I'm genuinely SHOCKED!"],
  "carnage": ["ABSOLUTE CARNAGE! No survivors!", "The deck committed CRIMES that round!"],
  "tightRace": ["A KNIFE FIGHT at the top of the table!", "Nobody breathe — this is TOO close!"],
  "kickoff": ["Shuffle up — the CARNAGE begins NOW!", "Round ONE! Let the chaos COMMENCE!"],
  "chasing": ["The hunt is ON! Nowhere to hide!", "Breathing down the leader's NECK!", "The predator has the scent!", "Closing FAST \u2014 someone warn the leader!"],
  "trailing": ["ANCHORED to the bottom of this table!", "Last place and digging DEEPER!", "The basement is FULLY furnished now!", "Bolted to last place \u2014 BOLTED!"],
  "leading": ["DOMINATING! Somebody do something!", "On TOP and rubbing it in!", "RUNNING AWAY with it!", "KING of the mountain \u2014 for now!"],
  "reigningChamp": ["The CHAMPION walks among you! BOW!", "Back to defend the title — and talking TRASH!"],
  "freshGame": ["A NEW battle begins! May the odds ignore your history!", "Fresh scorepad — carnage incoming!"],
  "perfect": ["PERFECT AGAIN! Everyone else can GO HOME! It's OVER!", "Not playing cards — committing ROBBERY!", "Machine-like PRECISION!", "Still flawless \u2014 it's getting SCARY!"],
  "hotStreak": ["They simply CANNOT be stopped! This is a HOSTILE TAKEOVER!", "Another one! Have MERCY on this table!", "A RAMPAGE! No one is safe!", "Merciless! Absolutely MERCILESS!"],
  "coldStreak": ["I have seen CAR CRASHES with better outcomes!", "The deck is just BULLYING them at this point!",
                 "A collapse in REAL TIME, people!", "Someone take the scorecard away — this is a CRIME SCENE!", "An absolute FREEFALL, people!", "The wheels came OFF three exits ago!"],
  "bigRound": ["That wasn't a round — that was a STATEMENT!", "DETONATION! The whole table felt that one!"],
  "zeroSpecialist": ["Another zero! Cold. Blooded. ASSASSIN!", "Doing NOTHING and getting PAID! Criminal!"],
  "boldestBidder": ["The audacity! The HUBRIS! The inevitable DISASTER!", "Betting the farm AGAIN! Somebody stop them!"],
  "winner": ["TOTAL DOMINATION! The rest of you were DECORATION!", "A MASSACRE! Frame this scorecard!"],
  "lastPlace": ["Last place! We are still LOOKING for the strategy, folks!",
                "Dead last! The announcer's union says I don't have to talk about it!"],
 },
 4: {  # Vicious — mild expletives, personal edge. ADULTS ONLY.
  "leadChange": ["The throne has been STOLEN — deal with it!", "New leader! The old one should be embarrassed!"],
  "nosedive": ["Good LORD, what a collapse!", "Somebody check on that score — it's not moving!"],
  "everybodyHit": ["Everyone hit?! Fine. FINE. Show-offs, all of you!", "All hits! Who let the table get good?!"],
  "carnage": ["A damn BLOODBATH! Avert your eyes!", "The deck said NO to everyone tonight!"],
  "tightRace": ["Too close! Somebody's heart is getting broken!", "The margin is INSULTINGLY thin!"],
  "kickoff": ["Deal the damn cards — destiny is waiting!", "Round one! Try not to blow it immediately!"],
  "chasing": ["Coming for the throne — and the leader KNOWS it!", "The gap is shrinking, people! PANIC!", "Hunting the leader like rent is due!", "One good round from a damn coup!"],
  "trailing": ["Dead last — somebody stage a damn rescue!", "The basement called. They want rent!", "The basement has their mail forwarded now!", "Last place called \u2014 it's getting crowded down there!"],
  "leading": ["Leading, and frankly? Insufferable about it!", "First place! The rest of you should be embarrassed!", "On top and rubbing everyone's nose in it!", "Leading like it's a damn birthright!"],
  "reigningChamp": ["The champ is HERE — act like it matters, people!", "Defending champion! Somebody take them down a damn peg!"],
  "freshGame": ["New game! Try not to embarrass yourselves this time!", "Clean slate — and some of you need it, BADLY!"],
  "perfect": ["Perfect AGAIN! The rest of you should be ASHAMED!", "Good LORD! Just hand over the trophy already!", "Perfect \u2014 and completely insufferable about it!", "Not a single damn mistake yet!"],
  "hotStreak": ["ANOTHER hit! This is getting disrespectful as hell!", "Unstoppable! And frankly? Insufferable!", "Disgustingly good right now!", "Hot enough to fry an egg on that scorecard!"],
  "coldStreak": ["My GOD, have some self-respect!", "What the HELL was that bid?!",
                 "A five-year-old with a juice box saw that coming!", "Somebody call their emergency contact!", "A slow-motion car crash, and we CAN'T look away!", "Somebody revoke their bidding privileges!"],
  "bigRound": ["A damn MASTERPIECE of a round!", "Pack it up, everyone. Pack it ALL up."],
  "zeroSpecialist": ["Another zero — living their best damn life!", "Doing nothing and STILL beating half this table!"],
  "boldestBidder": ["That bid is an INSULT to everyone who has ever held cards!", "Bidding like rent is due TONIGHT!"],
  "winner": ["It's OVER! And it wasn't even CLOSE, was it?!", "The winner! The rest of you made damn good television!"],
  "lastPlace": ["Dead last. At this point it's not luck — it's a personality trait!", "Last place AGAIN! The family is WATCHING!"],
 },
 5: {  # Unhinged — real profanity, R-rated roast. ADULTS ONLY, never App Store.
  "leadChange": ["The throne just got JACKED!", "NEW leader — and the trash talk writes itself!"],
  "nosedive": ["HOLY SHIT, what a faceplant!", "That round beat their ass fair and square!"],
  "everybodyHit": ["Everybody hit! Un-freaking-believable!", "A perfect round?! Get the hell out of here!"],
  "carnage": ["An absolute SHIT-SHOW of a round!", "The deck just wrecked EVERYBODY!"],
  "tightRace": ["Ass-clenchingly close at the top!", "This race is TOO damn tight!"],
  "kickoff": ["Shuffle up — and let the shit-show BEGIN!", "Round ONE, baby! LET'S GO!"],
  "chasing": ["Coming for BLOOD!", "The leader's ass is officially on notice!", "Coming up fast with bad intentions!", "About to ruin somebody's whole damn night!"],
  "trailing": ["Stone. Cold. LAST. Get your shit together!", "Living in the basement rent-free — and it SHOWS!", "Dead last and somehow still confident!", "The basement's new favorite tenant!"],
  "leading": ["On TOP! Somebody knock their ass off the throne!", "Leading the whole damn table!", "Sitting on the throne like they own the place!", "Top of the pile and talking SO much shit!"],
  "reigningChamp": ["The CHAMP is back — and the trash talk is EARNED!", "Reigning champion! Someone knock their ass off!"],
  "freshGame": ["FRESH game! Zero points, zero shits given — let's GO!", "New scorepad, same suspects — let the beatdown begin!"],
  "perfect": ["STILL perfect! You have GOT to be shitting me!", "UNREAL! Somebody frisk this player — I am dead serious!", "Still perfect \u2014 this is bullshit-tier luck!", "Flawless! Check the sleeves, check the SHOES!"],
  "hotStreak": ["ANOTHER one! This is bullshit-level lucky, folks!", "On FIRE! The rest of this table is getting its ass KICKED!", "Hotter than the devil's kitchen!", "An absolute WRECKING BALL right now!"],
  "coldStreak": ["That was a shit bid and EVERYBODY at this table knew it!", "Holy hell — someone stage an intervention!",
                 "Get your shit together — the FAMILY is watching!", "How?! HOW does that keep happening?!", "A cold streak from HELL!", "The cards have personally declared war!"],
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

# --- Score-grammar clips (2026-07-11): the announcer says the numbers ---
# Grammar: NAME! + [lead-in ending mid-sentence] + [number burst].
# e.g. "KELLY!" + "Stretching the lead to..." + "One-eighty!"
# Numbers are sports-caster style ("one-eighty", never "one hundred eighty").
# Wizard scores/gaps/deltas are always multiples of 10.

def caster(n):
    """Sports-caster spelling of a (multiple-of-10) score: 90 -> 'Ninety',
    180 -> 'One-eighty', 200 -> 'Two hundred', -30 -> 'Minus thirty'."""
    if n < 0:
        return "Minus " + caster(-n).lower()
    if n == 0:
        return "Zero"
    tens = {10: "Ten", 20: "Twenty", 30: "Thirty", 40: "Forty", 50: "Fifty",
            60: "Sixty", 70: "Seventy", 80: "Eighty", 90: "Ninety"}
    if n < 100:
        return tens[n]
    hundreds = {100: "One", 200: "Two", 300: "Three"}
    if n % 100 == 0:
        return f"{hundreds[n]} hundred"
    return f"{hundreds[n - n % 100]}-{tens[n % 100].lower()}"

# num_<n> / num_m<n>: bare terminal numbers — totals, gaps, deltas.
NUM_RANGE = list(range(-100, 0, 10)) + list(range(0, 310, 10))
# back_<n>: "<N> back!" — margins behind the leader, complete phrase.
BACK_RANGE = list(range(10, 160, 10))
# ontop_<n>: consecutive rounds leading. basement_<n>: "since round N".
ONTOP_RANGE = list(range(2, 11))
BASEMENT_RANGE = list(range(2, 15))

# Lead-ins keyed by LISTENER TIER (1 Classic, 2 Fun, 3 Spicy) — unlike
# TAILS' five generation buckets, because these carry facts, not spice;
# the tail garnish supplies the extra heat. Kinds ending "..." hand off
# to a number burst; (chase pairs with back_<n>, all others with num).
# Complete-sentence kinds (leadStatic, bottomStatic, earlyGame, lateGame)
# take no number. Number semantics per kind:
#   leaderTotal/leadNew -> leader's total; leadGrew/leadShrank -> the gap;
#   chase -> margin behind; bottomDeeper/bottomClimb -> bottom's total;
#   bigRound/mover -> points gained; nosedive -> points lost (positive);
#   tiedAt -> the shared total; winnerBy -> final margin.
LEADINS = {
 1: {  # Classic — warm sports-caster
  "leaderTotal": ["Leads the table with...", "Out in front with..."],
  "leadGrew": ["Stretching the lead to...", "Pulling away — the gap is now..."],
  "leadShrank": ["Still on top, but the lead is down to...", "The lead is shrinking — just..."],
  "leadNew": ["Takes the lead with...", "Our new leader — now on top with..."],
  "chase": ["Second place —", "Right behind the leader —"],
  "bottomDeeper": ["Bottom of the table, now at...", "Last place, sliding to..."],
  "bottomClimb": ["Climbing out of the basement — up to...", "The comeback begins! Up to..."],
  "bigRound": ["Banks a massive...", "Goes off for..."],
  "nosedive": ["Drops...", "Gives back..."],
  "tiedAt": ["Tied at...", "Deadlocked at..."],
  "mover": ["Round's big mover, jumping...", "Biggest gain of the round — up..."],
  "winnerBy": ["Wins it by...", "Takes the game by..."],
  "leadStatic": ["Still on top — steady as she goes!", "No movement at the top!"],
  "bottomStatic": ["Holding steady at the bottom!", "Still finding their footing down there!"],
  "earlyGame": ["Early days — plenty of game left!", "It's early, folks — anything can happen!"],
  "lateGame": ["It's getting late — every trick counts now!", "The finish line is in sight!"],
 },
 2: {  # Fun — roasts the scoreboard
  "leaderTotal": ["Sitting pretty on top with...", "Running this table with..."],
  "leadGrew": ["Rubbing it in — the lead is up to...", "Making it look easy — the gap is now..."],
  "leadShrank": ["Feeling the heat! The lead is down to...", "Getting nervous up there — the cushion is just..."],
  "leadNew": ["There's been a coup! On top with...", "Snatches the lead at..."],
  "chase": ["Hunting the leader —", "Smelling blood —"],
  "bottomDeeper": ["The basement runs deep — down to...", "Redecorating the basement at..."],
  "bottomClimb": ["Signs of life at the bottom! Up to...", "The basement is stirring — up to..."],
  "bigRound": ["Shows off with...", "Piles on a rude..."],
  "nosedive": ["Face-plants — coughing up...", "Generously donates..."],
  "tiedAt": ["Locked together at...", "Sharing a trophy shelf at..."],
  "mover": ["Making a move — up...", "On the charge, jumping..."],
  "winnerBy": ["Wins going away — by...", "Laps the field by..."],
  "leadStatic": ["Getting comfortable up there — somebody do something!", "Still king of this hill!"],
  "bottomStatic": ["Still keeping the basement warm!", "The basement lease got renewed!"],
  "earlyGame": ["An early lead means NOTHING, folks!", "Save the celebration — it's still early!"],
  "lateGame": ["Crunch time, people — the math is getting REAL!", "Late game! Time to panic accordingly!"],
 },
 3: {  # Spicy — adults only
  "leaderTotal": ["Hogging first place with a damn...", "Lording over this table with..."],
  "leadGrew": ["Piling on! The gap is now a damn...", "Showing NO mercy — the lead is up to..."],
  "leadShrank": ["Sweating BULLETS — the lead is down to a lousy...", "One bad round from disaster — just..."],
  "leadNew": ["Steals the damn throne with...", "Kicks the door in and takes the lead with..."],
  "chase": ["Coming for the crown —", "About to ruin somebody's night —"],
  "bottomDeeper": ["Digging toward the earth's core at...", "Dead-ass last at..."],
  "bottomClimb": ["The dead have RISEN — up to...", "Clawing out of hell, up to..."],
  "bigRound": ["Goes NUCLEAR for...", "Smashes the table for..."],
  "nosedive": ["Absolutely EATS it — down...", "Flushes..."],
  "tiedAt": ["In a damn stalemate at...", "Neck and neck at..."],
  "mover": ["On a heater — up...", "Storming the standings, up..."],
  "winnerBy": ["WRECKS the field by...", "Wins by a disgusting..."],
  "leadStatic": ["STILL on top — living there rent-free!", "Parked on the damn throne like they own it!"],
  "bottomStatic": ["Still dead last — it's a lifestyle now!", "The basement has a damn nameplate now!"],
  "earlyGame": ["Nobody crown anybody — it's damn EARLY!", "Early lead? Big deal — PROVE it!"],
  "lateGame": ["It's late, and the knives are OUT!", "Panic o'clock, people — the runway is damn short!"],
 },
}

def num_slug(n):
    return f"m{-n}" if n < 0 else str(n)

def jobs_for_voice():
    jobs = []  # (filename, spoken text) — generation order = priority order
    for slug, spoken in FAMILY:
        jobs.append((f"name_{slug}.mp3", f"{spoken}!"))
    for n in range(2, 21):
        jobs.append((f"inarow_{n}.mp3", f"{WORDS[n]} in a row!"))
    for n in range(3, 21):
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
    # Numbers land after the lead-in's dramatic pause. Default delivery is
    # NATURAL ("One-eighty!"); the all-caps `numx_`/`backx_` variants are a
    # SHOUTED emphasis set the announcer reserves for big moments (lead
    # change, monster round, winning margin) — Justin wants a mix, not a
    # constant yell.
    for n in NUM_RANGE:
        jobs.append((f"num_{num_slug(n)}.mp3", f"{caster(n)}!"))
        jobs.append((f"numx_{num_slug(n)}.mp3", f"{caster(n).upper()}!"))
    for n in BACK_RANGE:
        jobs.append((f"back_{n}.mp3", f"{caster(n)} back!"))
        jobs.append((f"backx_{n}.mp3", f"{caster(n).upper()} BACK!"))
    for n in ONTOP_RANGE:
        jobs.append((f"ontop_{n}.mp3", f"{WORDS[n]} straight rounds on top!"))
    for n in BASEMENT_RANGE:
        jobs.append((f"basement_{n}.mp3", f"In the basement since round {WORDS[n].lower()}!"))
    for tier, kinds in LEADINS.items():
        for kind, variants in kinds.items():
            for i, line in enumerate(variants):
                jobs.append((f"leadin_{tier}_{kind}_{i}.mp3", line))
    for slug, spoken in COMMON:
        jobs.append((f"name_{slug}.mp3", f"{spoken}!"))
    return jobs

def main():
    manifest = {"voices": list(VOICES), "styles": {str(s): {k: len(v) for k, v in kinds.items()} for s, kinds in TAILS.items()},
                "names": [s for s, _ in FAMILY + COMMON],
                "aliases": {"nicky": "nikki", "may": "mae", "cammy": "cami", "cammie": "cami", "nanna": "nana", "jeffrey": "jeffery"},
                "inarow": [2, 20], "perfect": [3, 20], "points": [40, 220], "zeros": [3, 10],
                "num": [NUM_RANGE[0], NUM_RANGE[-1]], "back": [BACK_RANGE[0], BACK_RANGE[-1]],
                "ontop": [ONTOP_RANGE[0], ONTOP_RANGE[-1]], "basement": [BASEMENT_RANGE[0], BASEMENT_RANGE[-1]],
                "leadins": {str(t): {k: len(v) for k, v in kinds.items()} for t, kinds in LEADINS.items()}}
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
