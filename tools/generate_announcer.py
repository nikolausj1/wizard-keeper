#!/usr/bin/env python3
"""Design-time announcer clip generation (ElevenLabs) — see PRD and
Announcer Overhaul Plan.md.

Generates the Charlie voice pack for the in-game announcer: name call-outs,
number bursts, round stamps, and the three purpose-written tiers
(1 Classic, 2 Fun, 3 Spicy). Tier 3 contains profanity and is written to
Sources/App/Resources/AnnouncerSpicy/, which ONLY the TrashTalkKeeper
(18+) target bundles; the clean WizardKeeper/OhHellKeeper targets never
see those files. The old five-bucket corpus and the seg_* connective clips
were retired in the 2026-07-25 rewrite (score-rundown broadcast).

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
# Spicy (tier 3) clips live in a sibling folder bundled only by the 18+
# TrashTalkKeeper target — see project.yml and Announcer.swift's
# resolvedURL fallbacks.
OUT_SPICY = os.path.join(os.path.dirname(__file__), "..", "Sources", "App", "Resources", "AnnouncerSpicy")
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

# App Store name expansion (2026-07-25): ~300 common US first names with
# pronunciation fixes, generated AFTER everything else (lowest priority
# in a resumable run). EXPANSION_ALIASES fold alternate spellings into
# these clips, merged into the manifest aliases below.
EXPANSION = [
    ("william", "William"),
    ("james", "James"),
    ("michael", "Michael"),
    ("richard", "Richard"),
    ("joseph", "Joseph"),
    ("christopher", "Christopher"),
    ("donald", "Donald"),
    ("edward", "Edward"),
    ("ronald", "Ronald"),
    ("jason", "Jason"),
    ("larry", "Larry"),
    ("roger", "Roger"),
    ("gerald", "Gerald"),
    ("arnold", "Arnold"),
    ("willie", "Willie"),
    ("dennis", "Dennis"),
    ("roy", "Roy"),
    ("ralph", "Ralph"),
    ("eugene", "Eugene"),
    ("harry", "Harry"),
    ("douglas", "Douglas"),
    ("frank", "Frank"),
    ("stanley", "Stanley"),
    ("norman", "Norman"),
    ("victor", "Victor"),
    ("martin", "Martin"),
    ("herbert", "Herbert"),
    ("francis", "Francis"),
    ("alan", "Alan"),
    ("curtis", "Curtis"),
    ("clarence", "Clarence"),
    ("milton", "Milton"),
    ("chester", "Chester"),
    ("vernon", "Vernon"),
    ("herman", "Herman"),
    ("lloyd", "Lloyd"),
    ("cecil", "Cecil"),
    ("otis", "Otis"),
    ("walter", "Walter"),
    ("patricia", "Patricia"),
    ("jennifer", "Jennifer"),
    ("barbara", "Barbara"),
    ("dorothy", "Dorothy"),
    ("helen", "Helen"),
    ("donna", "Donna"),
    ("ruth", "Ruth"),
    ("laura", "Laura"),
    ("kimberly", "Kimberly"),
    ("shirley", "Shirley"),
    ("angela", "Angela"),
    ("brenda", "Brenda"),
    ("stephanie", "Stephanie"),
    ("catherine", "Catherine"),
    ("marie", "Marie"),
    ("janet", "Janet"),
    ("ann", "Ann"),
    ("diane", "Diane"),
    ("victoria", "Victoria"),
    ("pamela", "Pamela"),
    ("debra", "Debra"),
    ("judy", "Judy"),
    ("teresa", "Teresa"),
    ("cheryl", "Cheryl"),
    ("andrea", "Andrea"),
    ("doris", "Doris"),
    ("jacqueline", "Jacqueline"),
    ("edna", "Edna"),
    ("lois", "Lois"),
    ("myrtle", "Myrtle"),
    ("opal", "Opal"),
    ("hazel", "Hazel"),
    ("ida", "Ida"),
    ("agnes", "Agnes"),
    ("gladys", "Gladys"),
    ("viola", "Viola"),
    ("liam", "Liam"),
    ("noah", "Noah"),
    ("mason", "Mason"),
    ("lucas", "Lucas"),
    ("jackson", "Jackson"),
    ("oliver", "Oliver"),
    ("gavin", "Gavin"),
    ("dylan", "Dylan"),
    ("austin", "Austin"),
    ("colton", "Colton"),
    ("carter", "Carter"),
    ("owen", "Owen"),
    ("jaxon", "Jaxon"),
    ("brody", "Brody"),
    ("landon", "Landon"),
    ("bryce", "Bryce"),
    ("hudson", "Hudson"),
    ("isaiah", "Isaiah"),
    ("levi", "Levi"),
    ("jace", "Jace"),
    ("bentley", "Bentley"),
    ("olivia", "Olivia"),
    ("ava", "Ava"),
    ("isabella", "Isabella"),
    ("charlotte", "Charlotte"),
    ("harper", "Harper"),
    ("ella", "Ella"),
    ("grace", "Grace"),
    ("riley", "Riley"),
    ("lily", "Lily"),
    ("hannah", "Hannah"),
    ("avery", "Avery"),
    ("kayla", "Kayla"),
    ("madison", "Madison"),
    ("savannah", "Savannah"),
    ("taylor", "Taylor"),
    ("peyton", "Peyton"),
    ("bailey", "Bailey"),
    ("kaitlyn", "Kaitlyn"),
    ("alexis", "Alexis"),
    ("natalie", "Natalie"),
    ("jasmine", "Jasmine"),
    ("willow", "Willow"),
    ("violet", "Violet"),
    ("jose", "Ho-zay"),
    ("luis", "Loo-ees"),
    ("juan", "Wahn"),
    ("javier", "Ha-vee-air"),
    ("ricardo", "Ricardo"),
    ("alejandro", "Ah-leh-han-dro"),
    ("francisco", "Francisco"),
    ("pedro", "Pedro"),
    ("rafael", "Rah-fah-el"),
    ("diego", "Dee-ay-go"),
    ("mario", "Mario"),
    ("ramon", "Rah-moan"),
    ("alberto", "Alberto"),
    ("gustavo", "Goo-stah-vo"),
    ("cesar", "Say-zar"),
    ("rodrigo", "Rodrigo"),
    ("salvador", "Salvador"),
    ("esteban", "Es-teh-bahn"),
    ("mateo", "Mah-tay-oh"),
    ("gabriel", "Gabriel"),
    ("marcos", "Marcos"),
    ("enrique", "En-ree-kay"),
    ("jesus", "Hey-zoos"),
    ("maria", "Mah-ree-ah"),
    ("guadalupe", "Gwa-dah-loo-pay"),
    ("carmen", "Carmen"),
    ("isabel", "Isabel"),
    ("adriana", "Ah-dree-ah-nah"),
    ("alejandra", "Ah-leh-han-drah"),
    ("monica", "Monica"),
    ("sofia", "So-fee-ah"),
    ("ximena", "Hee-may-nah"),
    ("camila", "Kah-mee-lah"),
    ("lucia", "Loo-see-ah"),
    ("dolores", "Doh-lo-res"),
    ("marisol", "Mah-ree-sol"),
    ("alicia", "Ah-lee-see-ah"),
    ("consuelo", "Con-sway-lo"),
    ("luz", "Looz"),
    ("nayeli", "Nah-yeh-lee"),
    ("xiomara", "See-oh-mah-rah"),
    ("lupe", "Loo-pay"),
    ("pepe", "Peh-peh"),
    ("memo", "Meh-moh"),
    ("paco", "Pah-koh"),
    ("darnell", "Darnell"),
    ("deshawn", "Deh-shawn"),
    ("marcus", "Marcus"),
    ("andre", "Ahn-dray"),
    ("tyrone", "Ty-rone"),
    ("jerome", "Juh-rome"),
    ("reginald", "Reginald"),
    ("tyree", "Ty-ree"),
    ("kareem", "Kah-reem"),
    ("darius", "Dare-ee-us"),
    ("lamar", "Luh-mar"),
    ("rashad", "Rah-shod"),
    ("antoine", "An-twahn"),
    ("deion", "Dee-on"),
    ("keyshawn", "Kee-shawn"),
    ("marquis", "Mar-keese"),
    ("rasheed", "Rah-sheed"),
    ("terrance", "Terrance"),
    ("dashawn", "Duh-shawn"),
    ("aaliyah", "Ah-lee-ah"),
    ("imani", "Ee-mah-nee"),
    ("latoya", "Luh-toy-ah"),
    ("shanice", "Shuh-neese"),
    ("tanisha", "Tuh-nee-shah"),
    ("jada", "Jay-dah"),
    ("latasha", "Luh-tah-shah"),
    ("precious", "Precious"),
    ("tia", "Tee-ah"),
    ("zuri", "Zoor-ee"),
    ("aisha", "Ah-ee-shah"),
    ("danielle", "Dan-yell"),
    ("jazmine", "Jazz-meen"),
    ("laquita", "Luh-kee-tah"),
    ("raven", "Raven"),
    ("tiffany", "Tiffany"),
    ("wei", "Way"),
    ("jun", "Joon"),
    ("hiro", "Hee-ro"),
    ("daiki", "Dye-kee"),
    ("jin", "Jin"),
    ("wang", "Wong"),
    ("feng", "Fung"),
    ("hao", "How"),
    ("kai", "Kye"),
    ("takashi", "Tah-kah-shee"),
    ("akira", "Ah-kee-rah"),
    ("masato", "Mah-sah-toh"),
    ("haruto", "Hah-roo-toh"),
    ("tran", "Trahn"),
    ("huy", "Hwee"),
    ("anh", "Ahn"),
    ("khang", "Kahng"),
    ("cuong", "Kwong"),
    ("mei", "May"),
    ("ling", "Ling"),
    ("yan", "Yahn"),
    ("yuki", "You-kee"),
    ("hana", "Hah-nah"),
    ("emi", "Eh-mee"),
    ("yui", "You-ee"),
    ("seoyeon", "Suh-yun"),
    ("eun", "Uhn"),
    ("mina", "Mee-nah"),
    ("linh", "Lin"),
    ("lan", "Lahn"),
    ("kim", "Kim"),
    ("raj", "Rahj"),
    ("amit", "Uh-meet"),
    ("rohan", "Ro-hahn"),
    ("sanjay", "Sun-jye"),
    ("ajay", "Uh-jay"),
    ("rahul", "Rah-hool"),
    ("anil", "Uh-neel"),
    ("ashok", "Uh-shoke"),
    ("pradeep", "Pruh-deep"),
    ("mohan", "Mo-hun"),
    ("kiran", "Keer-un"),
    ("rajesh", "Ruh-jesh"),
    ("manoj", "Muh-nohj"),
    ("vivek", "Vih-vake"),
    ("karan", "Kuh-run"),
    ("aryan", "Ar-yun"),
    ("kabir", "Kuh-beer"),
    ("siddharth", "Sid-arth"),
    ("uday", "Oo-dye"),
    ("akash", "Uh-kahsh"),
    ("gaurav", "Gow-ruv"),
    ("ahmed", "Ah-med"),
    ("hassan", "Huh-sahn"),
    ("omar", "Oh-mar"),
    ("imran", "Im-rahn"),
    ("zain", "Zayn"),
    ("usman", "Oos-mahn"),
    ("kamal", "Kuh-mahl"),
    ("priya", "Pree-yah"),
    ("anjali", "Un-jah-lee"),
    ("kavita", "Kuh-vih-tah"),
    ("pooja", "Poo-jah"),
    ("meera", "Mee-rah"),
    ("divya", "Div-yah"),
    ("sushma", "Soosh-mah"),
    ("geeta", "Gee-tah"),
    ("radha", "Rah-dah"),
    ("uma", "Oo-mah"),
    ("indira", "In-deer-ah"),
    ("ritu", "Ree-too"),
    ("shanti", "Shan-tee"),
    ("vandana", "Vun-dah-nah"),
    ("zainab", "Zay-nub"),
    ("amina", "Uh-mee-nah"),
    ("noor", "Noor"),
    ("sara", "Sah-rah"),
    ("siobhan", "Shiv-awn"),
    ("liz", "Liz"),
    ("beth", "Beth"),
    ("cathy", "Cathy"),
    ("peggy", "Peggy"),
    ("pat", "Pat"),
    ("jenny", "Jenny"),
    ("vicky", "Vicky"),
    ("gabby", "Gabby"),
    ("stevie", "Stevie"),
    ("bobby", "Bobby"),
    ("tommy", "Tommy"),
    ("ronnie", "Ronnie"),
    ("timmy", "Timmy"),
    ("chuck", "Chuck"),
    ("gus", "Gus"),
    ("toni", "Toni"),
    ("tammy", "Tammy"),
    ("robbie", "Robbie"),
    ("zach", "Zach"),
    ("jon", "Jon"),
    ("stan", "Stan"),
    ("marty", "Marty"),
    ("uncle", "Uncle"),
    ("auntie", "Auntie"),
    ("coach", "Coach"),
    ("champ", "Champ"),
    ("rookie", "Rookie"),
    ("jonathan", "Jonathan"),
    ("zachary", "Zackary"),
]
EXPANSION_ALIASES = {
 "kaitlin": "kaitlyn",
 "caitlyn": "kaitlyn",
 "jonathon": "jonathan",
 "stephan": "stevie",
 "zack": "zach",
 "robby": "robbie",
 "timothy": "timmy",
 "ahmad": "ahmed",
 "shivon": "siobhan",
 "chevonne": "siobhan",
 "javy": "javier",
 "dashaun": "dashawn",
 "deshaun": "deshawn",
 "keshawn": "keyshawn",
 "keshaun": "keyshawn",
 "marquise": "marquis",
 "madisyn": "madison",
 "peyten": "peyton",
 "payton": "peyton",
 "jaxson": "jaxon",
 "kolton": "colton",
 "izabella": "isabella",
 "bella": "isabella",
 "ellah": "ella",
 "charlette": "charlotte",
 "lillie": "lily",
 "alexus": "alexis",
 "alexi": "alexis",
 "natalee": "natalie",
 "nathalie": "natalie",
 "jazmin": "jazmine",
 "ximenna": "ximena",
 "jimena": "ximena",
 "xiomera": "xiomara",
 "siomara": "xiomara",
 "marysol": "marisol",
 "cesare": "cesar",
 "tyreek": "tyree",
 "tyriq": "tyree",
 "aliyah": "aaliyah",
 "aleeyah": "aaliyah",
 "imane": "imani",
 "iman": "imani",
 "latonya": "latoya",
 "shanise": "shanice",
 "danyelle": "danielle",
 "rayvin": "raven",
 "ravyn": "raven",
 "tiffanie": "tiffany",
 "tiffani": "tiffany",
 "jaeda": "jada",
 "jayda": "jada",
 "ayesha": "aisha",
 "zaynab": "zainab",
 "sanjai": "sanjay",
 "sunjay": "sanjay",
 "preeya": "priya",
 "pria": "priya",
 "anjalee": "anjali",
 "divia": "divya",
 "mira": "meera",
 "kavitha": "kavita",
 "hasan": "hassan",
 "sidharth": "siddharth",
 "sidarth": "siddharth",
 "akaash": "akash",
 "kieran": "kiran"
}


WORDS = {1:"One",2:"Two",3:"Three",4:"Four",5:"Five",6:"Six",7:"Seven",8:"Eight",9:"Nine",10:"Ten",
         11:"Eleven",12:"Twelve",13:"Thirteen",14:"Fourteen",15:"Fifteen",
         16:"Sixteen",17:"Seventeen",18:"Eighteen",19:"Nineteen",20:"Twenty"}
POINTS = {40:"Forty",50:"Fifty",60:"Sixty",70:"Seventy",80:"Eighty",90:"Ninety",100:"One hundred",
          110:"One hundred ten",120:"One hundred twenty",130:"One hundred thirty",140:"One hundred forty",
          150:"One hundred fifty",160:"One hundred sixty",170:"One hundred seventy",180:"One hundred eighty",
          190:"One hundred ninety",200:"Two hundred",210:"Two hundred ten",220:"Two hundred twenty"}

# --- Flavor tails (punchlines): tier -> kind -> variants -------------
# Three purpose-written characters (2026-07-25 rewrite): 1 Classic "The
# Pro", 2 Fun "The Wise Guy" (strictly clean, 9+), 3 Spicy "The Roast
# Comic" (R-rated, one expletive max per line, ships ONLY in the Trash
# Talk target via the AnnouncerSpicy folder). All name-free and
# number-free; never target age/looks/intelligence. Punchlines are ten
# words or fewer; at most one ALL-CAPS word per line.
TAILS = {
 1: {
  "leadChange": ["A NEW leader at the table.", "The top spot changes hands.", "First place has a new owner.", "The lead just moved.", "That's a new name up top."],
  "nosedive": ["That one left a mark.", "A tough, tough round.", "That round is going to sting.", "Nobody saw that coming.", "The scoreboard felt that one."],
  "everybodyHit": ["EVERYBODY hit! What a round.", "A clean sweep. Everyone landed it.", "Not a single miss among them.", "A round for the record books.", "Every bid, right on the money."],
  "carnage": ["What a round. Almost nobody survived.", "The deck showed no mercy.", "A rough one for the whole table.", "Tough round, across the board.", "That round humbled everybody."],
  "tightRace": ["Neck and neck at the top.", "This one's coming down to the wire.", "Barely any daylight between them.", "Too close to call right now.", "A real battle at the top."],
  "kickoff": ["Shuffle up and deal. Let's play.", "Round one. Here we go.", "Fresh deck, fresh chances. Good luck.", "Let's get started, everybody.", "Cards are in the air."],
  "chasing": ["Right on the leader's heels.", "The chase is on.", "Within striking distance now.", "Keeping the pressure on.", "Closing the gap, round by round."],
  "trailing": ["Bringing up the rear, folks.", "Last place, for now.", "Room to grow, friend.", "The comeback starts now.", "Plenty of game left to find it."],
  "leading": ["Out in front and cruising.", "Top of the pile, folks.", "Setting the pace so far.", "The one to beat right now.", "Comfortably ahead of the field."],
  "reigningChamp": ["The reigning champion is at the table.", "Last game's winner is back.", "The defending champion has arrived.", "Back again, fresh off a win.", "The champion returns to the table."],
  "freshGame": ["A fresh scorepad. Anything can happen.", "New game, clean slate. Good luck, everyone.", "Everybody starts even tonight.", "A brand new scoreboard, zero to zero.", "Here we go again, folks."],
  "perfect": ["Still PERFECT. Not a single miss yet.", "Flawless. The bids just keep landing.", "A spotless record so far.", "Not one wrong call yet.", "Still hasn't put a foot wrong."],
  "hotStreak": ["On fire. Another bid, another hit.", "The streak continues. They don't miss.", "Locked in right now.", "Everything is landing for them.", "Bid after bid, right on target."],
  "coldStreak": ["The cold streak continues. Hang in there.", "Ice cold. Somebody grab a blanket.", "Another miss. The wheels are wobbling.", "The luck has got to turn soon.", "A rough patch. It happens to everyone."],
  "bigRound": ["BOOM. The round of the game.", "A massive round. Well earned.", "That's the biggest round yet.", "A monster round right there.", "That round will be hard to top."],
  "zeroSpecialist": ["Another perfect zero. An artist at work.", "Bid nothing, took nothing. Poetry, folks.", "Zero and zero, exactly as planned.", "A quiet kind of mastery, that.", "Doing absolutely nothing, beautifully."],
  "boldestBidder": ["The boldest bid at the table. No fear.", "Swinging big again.", "Betting on themselves, every single time.", "That's a confident bid right there.", "Not afraid to go big tonight."],
  "winner": ["That's the game. Take a bow.", "It's all over. What a performance.", "A win, clean and deserved.", "Game over. Well played.", "Ballgame. And a good one."],
  "lastPlace": ["Somebody had to come in last.", "Better luck next game, friend.", "Last place, but great company tonight.", "The comeback story starts here.", "Everybody's got an off night sometimes."],
 },
 2: {
  "leadChange": ["New leader. Try to act surprised.", "There's been a coup at the top.", "First place just got repossessed.", "The crown changed hands. No ceremony.", "Somebody's renting the top spot now."],
  "nosedive": ["That's the sound of a scorecard crying.", "Ouch. Just, ouch.", "That round filed for divorce from the scoreboard.", "Somebody find that score a doctor.", "The scorecard needs a moment alone."],
  "everybodyHit": ["Everybody hit. Suspiciously competent, all of you.", "All hits. Where did that come from.", "A clean round. Somebody's been practicing.", "Everyone nailed it. Deeply unsettling.", "Not one miss. Who are you people."],
  "carnage": ["Carnage. The deck took hostages.", "A massacre. Somebody call for help.", "The whole table just got humbled.", "That round had no survivors.", "Rough round. Bring snacks and sympathy."],
  "tightRace": ["Photo finish territory, people.", "The leader can hear footsteps.", "That gap is basically theoretical.", "Nobody's breathing easy up there.", "This is entirely too close for comfort."],
  "kickoff": ["Deal 'em up. Who disappoints first.", "Round one. Places, everyone.", "Let's see who folds under pressure.", "Cards are out. Let the excuses begin.", "Here we go. Try to keep up."],
  "chasing": ["Closing in. The leader should be nervous.", "Breathing down the leader's neck.", "Plotting a takeover as we speak.", "Smelling blood in the water.", "Sniffing out a real opportunity."],
  "trailing": ["Holding down last place, full time.", "The basement has a new tenant.", "Someone start a rescue fund.", "It's called building suspense, folks.", "Last place. Character developing nicely."],
  "leading": ["Leading the pack. For now.", "First place. Enjoy it while it lasts.", "Enjoying the view from the top.", "Ahead, and not sweating it yet.", "Cruising up there, a little smug."],
  "reigningChamp": ["The champ is back to defend the crown.", "Reigning champion. Target on their back.", "Title in hand. No pressure at all.", "The defending champ walked in like they own the place.", "Last game's winner is here to do it again."],
  "freshGame": ["Clean slate. Time for some questionable bids.", "New game. Zero points, zero excuses.", "Everybody's undefeated again, for about five minutes.", "Fresh scorepad. Try not to ruin it immediately.", "New game. Old grudges apply."],
  "perfect": ["Still perfect. Save some glory for the rest of us.", "Perfection. Getting suspicious over here.", "Flawless, and enjoying it way too much.", "Perfect record. The audacity.", "Still hasn't missed. Somebody check their math."],
  "hotStreak": ["Red hot. The table is in trouble.", "Untouchable right now. Annoyingly so.", "Another hit. This is getting disrespectful.", "Hot enough to fry an egg on that scorecard.", "They simply refuse to miss."],
  "coldStreak": ["Confidence and the scorecard aren't speaking anymore.", "Another miss. Hide the scorecard from the kids.", "Cold enough to see your breath over there.", "Somebody's cards are on strike.", "The cards have simply stopped cooperating."],
  "bigRound": ["A monster round. Show off.", "Massive points. Absolutely rude.", "That round should come with a warning label.", "Somebody's feeling themselves right now.", "That's a whole lot of round for one hand."],
  "zeroSpecialist": ["Another zero. Doing nothing looks great on them.", "Zero called, zero taken. Menace behavior.", "Bid zero, meant it. Respect.", "The zero game is undefeated tonight.", "Doing nothing and still stealing the show."],
  "boldestBidder": ["Huge bid again. Confidence level: unearned.", "The audacity is off the charts.", "Betting big with a straight face.", "That bid is all nerve, zero backup.", "Going for the fences, every round."],
  "winner": ["It's over. Act like you've been here before.", "The winner. Everyone else, take notes.", "Game over. Somebody go tell the others.", "That's a win with style points.", "Well, that settles that."],
  "lastPlace": ["Dead last. But hey, great snacks tonight.", "Last place. We've alerted the authorities.", "Last place. But you brought real energy.", "Somebody had to hold down the bottom.", "Last place. It's a character-building night."],
 },
 3: {
  "leadChange": ["The throne just got jacked.", "New leader. The old one should be pissed.", "First place changed hands, no permission asked.", "Somebody stole the lead in broad daylight.", "First place has new, undeserving management."],
  "nosedive": ["Holy hell, what a faceplant.", "That round kicked their ass, clean.", "That was a collapse for the history books.", "Somebody call it, that score just died.", "That round did some real damage."],
  "everybodyHit": ["A perfect round. Somebody check the deck for a wire.", "Everybody hit. I'm genuinely shook.", "Not a single damn miss. Unreal.", "All hits. Somebody frisk this table.", "A clean sweep. Well, shit, look at that."],
  "carnage": ["Absolute carnage. Somebody get the mop.", "The deck committed straight up crimes that round.", "That round wrecked the entire table.", "Damn near everybody ate it that round.", "A bloodbath. Somebody light a candle."],
  "tightRace": ["Ass-clenchingly close at the top.", "This race is way too damn tight.", "Somebody's about to lose it up there.", "That gap is one bad bid wide.", "Too close for anybody's blood pressure."],
  "kickoff": ["Shuffle up. Let the chaos begin.", "Round one, baby. Let's go.", "Cards are out. Somebody's about to embarrass themselves.", "Let's see who chokes first.", "Deal it out and pray."],
  "chasing": ["Coming for blood.", "The leader is officially on notice.", "Closing fast with bad intentions.", "One good round from a hostile takeover.", "About to ruin somebody's whole night."],
  "trailing": ["Stone cold last. Get it together.", "Living underground, and somehow thriving.", "Dead last, and completely unbothered.", "That's not luck, that's a lifestyle.", "Last place. The floor is generously padded."],
  "leading": ["On top and rubbing it in.", "Running away with this thing.", "King of the mountain, for now.", "Sitting up there like they own the place.", "Leading like it's their birthright."],
  "reigningChamp": ["The champ's back, and the trash talk is earned.", "Reigning champion. Somebody knock them off already.", "Back to defend the throne, no fear.", "Last game's winner, here to run it back.", "Last year's champ, still looking hungry."],
  "freshGame": ["Fresh scorepad. Zero points, zero shits given.", "New game, same suspects, same bad decisions.", "Clean slate. Somebody's going to blow it fast.", "Everybody's tied. Enjoy it while it lasts.", "New battle. Forget whatever happened last time."],
  "perfect": ["Still perfect. You've got to be shitting me.", "Unreal. That can't be legal, honestly.", "Flawless. Check the sleeves, check the shoes.", "Still perfect. This is bullshit tier luck.", "Not one miss. Somebody's cheating, probably."],
  "hotStreak": ["On fire, and the table is officially screwed.", "Another one. Have mercy on this table.", "Hotter than the devil's kitchen right now.", "An absolute wrecking ball at the moment.", "They cannot be stopped, and it's getting rude."],
  "coldStreak": ["I've seen car crashes with better outcomes.", "The deck is just bullying them at this point.", "Someone tape off this crime scene.", "A cold streak straight from hell.", "How does that keep happening. How."],
  "bigRound": ["Holy shit, what a round.", "That's a whole-ass beatdown in one hand.", "That wasn't a round, that was a statement.", "Somebody just detonated the scoreboard.", "That round should be illegal, honestly."],
  "zeroSpecialist": ["Zero called, zero taken, zero shits given.", "Doing nothing and getting paid for it. Criminal.", "That's not luck, that's a damn art form.", "Bid zero, delivered zero, no notes.", "Zero effort. Somehow still winning at it."],
  "boldestBidder": ["That bid took balls of solid brass.", "Betting like a maniac with nothing to lose.", "That bid was an insult to everyone else's math.", "Bidding like rent is due tonight.", "The guts, the swagger, the inevitable crash."],
  "winner": ["It's over. And it wasn't even close.", "Champion. The rest of you got wrecked.", "Game over. That was a straight up beatdown.", "That's a win for the damn history books.", "It's over, and nobody's surprised."],
  "lastPlace": ["Dead. Ass. Last. Somebody drive them home.", "This is an intervention. We love you. But damn.", "Last place. My union won't let me elaborate.", "Dead last, and weirdly still smiling.", "Last place. It happens to the best of us."],
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
# round_<n>: the rundown's opening stamp ("Round seven."), period not bang
# — it's orientation, not hype. 25 covers Oh Hell's longest up-and-down
# schedule; Wizard tops out at 20.
ROUND_RANGE = list(range(1, 26))

# --- Integer clip family (2026-07-19): Oh Hell scores move in 1s, not --
# 10s, so the tens-only `caster()` family above can't cover them. Same
# grammar (NAME! + lead-in + number burst / "<N> back!"), just a
# ones-granularity number library alongside the existing tens one, in the
# SAME shared clip folder (both apps bundle it; `GameVariant.
# announcerUsesTensClips` picks which family Announcer.swift reads from).
INT_TENS = {20: "Twenty", 30: "Thirty", 40: "Forty", 50: "Fifty", 60: "Sixty",
            70: "Seventy", 80: "Eighty", 90: "Ninety"}

def caster_int(n):
    """Natural word spelling of an integer score (0...160), NOT tens-only:
    0 'Zero'; 1-20 word names ('Seven', 'Thirteen'); 21-99 hyphenated
    ('Twenty-three', 'Ninety-nine'); 100 'One hundred'; 101-109
    'One-oh-<d>' ('One-oh-five'); 110-160 caster reads built by recursing
    on the last two digits ('One-ten', 'One-eleven', 'One-twenty-three')."""
    if n == 0:
        return "Zero"
    if n <= 20:
        return WORDS[n]
    if n < 100:
        tens_digit = (n // 10) * 10
        remainder = n % 10
        if remainder == 0:
            return INT_TENS[tens_digit]
        return f"{INT_TENS[tens_digit]}-{WORDS[remainder].lower()}"
    if n == 100:
        return "One hundred"
    if n <= 109:
        return f"One-oh-{WORDS[n - 100].lower()}"
    if n <= 160:
        return f"One-{caster_int(n - 100).lower()}"
    raise ValueError(f"caster_int out of range: {n}")

# num1_<n>: bare terminal integer numbers, natural delivery (no shouted
# emphasis set — Justin wants natural as the default for these).
INT_RANGE = list(range(0, 161))
# back1_<n>: "<N> back!" — integer margins behind the leader.
BACK1_RANGE = list(range(1, 41))

# Lead-ins keyed by LISTENER TIER (1 Classic, 2 Fun, 3 Spicy). Tier 3
# ships only in the Trash Talk target (AnnouncerSpicy folder). Kinds
# ending "..." or "," hand off to a number burst (chase pairs with
# back_<n>, all others with num); complete-sentence kinds (leadStatic,
# bottomStatic, earlyGame, lateGame) take no number. Number semantics
# per kind are unchanged:
#   leaderTotal/leadNew -> leader's total; leadGrew/leadShrank -> the gap;
#   chase -> margin behind; bottomDeeper/bottomClimb -> bottom's total;
#   bigRound/mover -> points gained; nosedive -> points lost (positive);
#   tiedAt -> the shared total; winnerBy -> final margin.
LEADINS = {
 1: {
  "leaderTotal": ["Leads with...", "On top with...", "Out in front with..."],
  "leadGrew": ["Stretching the lead to...", "Pulling further ahead at...", "Widens the gap to..."],
  "leadShrank": ["Down to just...", "The lead shrinks to...", "Cushion now down to..."],
  "leadNew": ["Takes the lead with...", "Now on top with...", "New leader, at..."],
  "chase": ["Second place,", "Right behind the leader,", "Close on their heels,"],
  "bottomDeeper": ["Slides to the bottom at...", "Falls further, now at...", "Last place, down to..."],
  "bottomClimb": ["Climbing out, now at...", "The comeback begins, up to...", "Finding their footing at..."],
  "bigRound": ["Banks a massive...", "Goes off for...", "Cashes in for..."],
  "nosedive": ["Drops...", "Gives back...", "Loses a painful..."],
  "tiedAt": ["Tied at...", "Deadlocked at...", "Dead even at..."],
  "mover": ["Round's big mover, up...", "Biggest gain this round, up...", "Jumping the most, up..."],
  "winnerBy": ["Wins it by...", "Takes the game by...", "Closes it out by..."],
  "leadStatic": ["Still on top. Steady as ever.", "No movement at the top this round.", "No challengers in sight."],
  "bottomStatic": ["Holding steady at the bottom.", "Still finding their footing down there.", "Last place hasn't budged this round."],
  "earlyGame": ["Early days. Plenty of game left.", "It's early, folks. Anything can happen.", "So much game still to play."],
  "lateGame": ["It's getting late. Every trick counts now.", "The finish line is in sight.", "Down to the final few rounds."],
 },
 2: {
  "leaderTotal": ["Sitting pretty with...", "Running the table with...", "Hogging first place with..."],
  "leadGrew": ["Padding the lead to...", "Gap's up to a rude...", "Lead ballooning to..."],
  "leadShrank": ["Feeling the heat at...", "Nervous now, down to...", "Lead getting thin, just..."],
  "leadNew": ["Snatches the lead at...", "There's a coup, now at...", "Steals the top spot with..."],
  "chase": ["Hunting the leader,", "On the hunt,", "Breathing down their neck,"],
  "bottomDeeper": ["Redecorating the basement at...", "Slipping further, now at...", "Digging deeper, down to..."],
  "bottomClimb": ["Signs of life, up to...", "The basement's stirring, now at...", "Crawling back, up to..."],
  "bigRound": ["Shows off with...", "Piles on a rude...", "Casually drops a..."],
  "nosedive": ["Face-plants, coughing up...", "Generously donates...", "Hands right back..."],
  "tiedAt": ["Locked together at...", "Sharing a trophy shelf at...", "Splitting the spotlight at..."],
  "mover": ["Making a move, up...", "On the charge, up...", "Storming up the standings, up..."],
  "winnerBy": ["Laps the field by...", "Cruises to victory by...", "Wins comfortably by..."],
  "leadStatic": ["Getting comfortable up there. Somebody do something.", "Still king of this hill.", "Nobody's touched that lead all night."],
  "bottomStatic": ["Still holding down the floor.", "No signs of an eviction yet.", "Last place remains fully occupied."],
  "earlyGame": ["An early lead means nothing, folks.", "Save the celebration. It's still early.", "Way too early to start bragging."],
  "lateGame": ["Crunch time, people. The math is getting real.", "Late game. Time to panic accordingly.", "Every trick's worth its weight in gold now."],
 },
 3: {
  "leaderTotal": ["Lording over the table with...", "Perched on a damn...", "Owning this table with..."],
  "leadGrew": ["Piling on, gap now...", "Showing no mercy, up by...", "Twisting the knife at..."],
  "leadShrank": ["Sweating bullets, down to...", "One bad round from just...", "Margin's looking shaky at..."],
  "leadNew": ["Grabs the damn throne at...", "Kicks the door in at...", "Jacks the lead at..."],
  "chase": ["Coming for the crown,", "Closing in fast,", "Stalking the leader,"],
  "bottomDeeper": ["Digging toward the core at...", "Dead ass last at...", "Sinking, now down to..."],
  "bottomClimb": ["The dead have risen at...", "Clawing out of hell at...", "Back from the grave at..."],
  "bigRound": ["Goes nuclear for...", "Smashes the table for...", "Blows the roof off for..."],
  "nosedive": ["Absolutely eats it, down...", "Flushes...", "Bleeds out a nasty..."],
  "tiedAt": ["In a damn stalemate at...", "Neck and neck at...", "Tied up, and tense, at..."],
  "mover": ["On a heater, up...", "Rocketing up the standings, up...", "Making a run, up..."],
  "winnerBy": ["Wrecks the field by...", "Takes it by a disgusting...", "Runs away with it by..."],
  "leadStatic": ["Still on top, living there rent free.", "Parked on that lead like they own it.", "Nobody's come close to that lead yet."],
  "bottomStatic": ["Still dead last. It's a lifestyle now.", "That last-place throne isn't going anywhere.", "Still down there, weirdly at peace with it."],
  "earlyGame": ["Nobody crown anybody. It's still damn early.", "Early lead. Big deal. Prove it.", "Way too soon for that attitude."],
  "lateGame": ["It's late, and the knives are out.", "Panic o'clock, people. The runway is short.", "Down to the wire, and it's ugly."],
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
    # Integer family (Oh Hell, ones granularity) — natural delivery only,
    # no shouted variant.
    for n in INT_RANGE:
        jobs.append((f"num1_{n}.mp3", f"{caster_int(n)}!"))
    for n in BACK1_RANGE:
        jobs.append((f"back1_{n}.mp3", f"{caster_int(n)} back!"))
    for n in ONTOP_RANGE:
        jobs.append((f"ontop_{n}.mp3", f"{WORDS[n]} straight rounds on top!"))
    for n in BASEMENT_RANGE:
        jobs.append((f"basement_{n}.mp3", f"In the basement since round {WORDS[n].lower()}!"))
    for n in ROUND_RANGE:
        jobs.append((f"round_{n}.mp3", f"Round {caster_int(n).lower()}."))
    for tier, kinds in LEADINS.items():
        for kind, variants in kinds.items():
            for i, line in enumerate(variants):
                jobs.append((f"leadin_{tier}_{kind}_{i}.mp3", line))
    for slug, spoken in COMMON:
        jobs.append((f"name_{slug}.mp3", f"{spoken}!"))
    # App Store expansion names last: lowest priority in a resumable run.
    for slug, spoken in EXPANSION:
        jobs.append((f"name_{slug}.mp3", f"{spoken}!"))
    return jobs

def main():
    manifest = {"voices": list(VOICES), "styles": {str(s): {k: len(v) for k, v in kinds.items()} for s, kinds in TAILS.items()},
                "names": [s for s, _ in FAMILY + COMMON + EXPANSION],
                "aliases": {"nicky": "nikki", "may": "mae", "cammy": "cami", "cammie": "cami", "nanna": "nana", "jeffrey": "jeffery",
                            **EXPANSION_ALIASES},
                "inarow": [2, 20], "perfect": [3, 20], "points": [40, 220], "zeros": [3, 10],
                "num": [NUM_RANGE[0], NUM_RANGE[-1]], "back": [BACK_RANGE[0], BACK_RANGE[-1]],
                "num1": [INT_RANGE[0], INT_RANGE[-1]], "back1": [BACK1_RANGE[0], BACK1_RANGE[-1]],
                "ontop": [ONTOP_RANGE[0], ONTOP_RANGE[-1]], "basement": [BASEMENT_RANGE[0], BASEMENT_RANGE[-1]],
                "round": [ROUND_RANGE[0], ROUND_RANGE[-1]],
                "leadins": {str(t): {k: len(v) for k, v in kinds.items()} for t, kinds in LEADINS.items()}}
    os.makedirs(OUT_ROOT, exist_ok=True)
    with open(os.path.join(OUT_ROOT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)

    done = skipped = failed = 0
    for vname, vid in VOICES.items():
        vdir = os.path.join(OUT_ROOT, vname)
        os.makedirs(vdir, exist_ok=True)
        # Tier-3 clips route to the spicy folder by filename: only the
        # TrashTalkKeeper target bundles AnnouncerSpicy.
        sdir = os.path.join(OUT_SPICY, vname)
        os.makedirs(sdir, exist_ok=True)
        for fname, text in jobs_for_voice():
            outdir = sdir if fname.startswith(("tail_3_", "leadin_3_")) else vdir
            path = os.path.join(outdir, fname)
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
