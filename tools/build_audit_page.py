#!/usr/bin/env python3
"""Build _review/announcer-audit.html — line-by-line audit of every announcer clip.

Reads the corpus straight out of generate_announcer.py (single source of truth)
and merges tools/announcer_suggestions.json (per-line improvement suggestions).
Each line gets: the spoken text, play buttons for both voices, the suggestion,
and a comment box (persisted to localStorage; export via Copy/Download buttons).

Audio is referenced by relative path into Sources/App/Resources/Announcer/, so
the page must stay in _review/. If the browser blocks file:// audio, run
_review/serve-audit.command and use the localhost URL it prints.

Usage: python3 tools/build_audit_page.py
"""
import html
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "tools", "generate_announcer.py")
SUGGESTIONS = os.path.join(ROOT, "tools", "announcer_suggestions.json")
OUT = os.path.join(ROOT, "_review", "announcer-audit.html")

# --- Load the corpus from the generator without running it --------------
os.environ.setdefault("ELEVENLABS_API_KEY", "audit-page-stub")
ns = {"__name__": "audit", "__file__": GEN}
with open(GEN) as f:
    exec(compile(f.read(), GEN, "exec"), ns)
FAMILY, COMMON = ns["FAMILY"], ns["COMMON"]
WORDS, POINTS = ns["WORDS"], ns["POINTS"]
CONNECTIVES, TAILS = ns["CONNECTIVES"], ns["TAILS"]

suggestions = {}
if os.path.exists(SUGGESTIONS):
    with open(SUGGESTIONS) as f:
        suggestions = json.load(f)
else:
    print("warning: no announcer_suggestions.json yet — building without suggestions")

missing_audio = []


def audio_exists(clip_id):
    ok = True
    for voice in ("charlie", "jessica"):
        p = os.path.join(ROOT, "Sources", "App", "Resources", "Announcer", voice, clip_id + ".mp3")
        if not os.path.exists(p):
            missing_audio.append(f"{voice}/{clip_id}")
            ok = False
    return ok


TIERS = [  # (anchor, tier label, buckets, blurb)
    ("classic", "Classic", [1], "Warm sports-caster. Family-safe, zero edge."),
    ("fun", "Fun", [2, 3], "The announcer has opinions — roasts the scoreboard, never the person."),
    ("spicy", "Spicy", [4, 5], "Adults-only. Expletives allowed. Never ships to the kids' iPads."),
]

KIND_LABELS = {
    "kickoff": "Kickoff (round 1 opener)",
    "freshGame": "Fresh game",
    "leadChange": "Lead change",
    "perfect": "Perfect record",
    "hotStreak": "Hot streak",
    "coldStreak": "Cold streak",
    "bigRound": "Big round",
    "nosedive": "Nosedive",
    "everybodyHit": "Everybody hit",
    "carnage": "Carnage",
    "tightRace": "Tight race",
    "chasing": "Chasing the leader",
    "trailing": "Trailing (last place, mid-game)",
    "leading": "Leading",
    "zeroSpecialist": "Zero specialist",
    "boldestBidder": "Boldest bidder",
    "reigningChamp": "Reigning champ",
    "winner": "Winner (game over)",
    "lastPlace": "Last place (game over)",
}
GROUP_LABELS = {"intro": "Intros", "trans": "Transitions", "outro": "Outros"}


def esc(s):
    return html.escape(s, quote=True)


def row(clip_id, text, with_suggestion=True, note=""):
    audio_exists(clip_id)
    sug = ""
    if with_suggestion:
        s = suggestions.get(clip_id, {}).get("suggestion", "")
        cls = "sug keep" if s.strip() == "Tight — keep." else "sug"
        sug = f'<div class="{cls}">{esc(s) if s else "<em>no suggestion drafted</em>"}</div>'
    note_html = f'<span class="note">{esc(note)}</span>' if note else ""
    return f'''<div class="line" id="{clip_id}">
  <div class="line-head">
    <button class="play" data-clip="{clip_id}" data-voice="charlie" title="Play — Charlie">&#9654; C</button>
    <button class="play" data-clip="{clip_id}" data-voice="jessica" title="Play — Jessica">&#9654; J</button>
    <span class="text">&ldquo;{esc(text)}&rdquo;</span>{note_html}
    <span class="clipid">{clip_id}</span>
  </div>
  {sug}
  <textarea class="fb" data-clip="{clip_id}" placeholder="Your revision notes for this line&hellip;" rows="1"></textarea>
</div>'''


parts = []

# --- 1. Connectives -----------------------------------------------------
parts.append('<section><h2 id="connectives">1 &middot; Broadcast glue (intros / transitions / outros)</h2>'
             '<p class="blurb">These stitch the whole broadcast together: <b>intro &rarr; insight &rarr; transition &rarr; insight &rarr; outro</b>. '
             'They pay the biggest wordiness tax because they wrap around already-long calls.</p>')
for anchor, tier, buckets, blurb in TIERS:
    parts.append(f'<div class="tier"><h3>{tier} <span class="tierblurb">{esc(blurb)}</span></h3>')
    for group in ("intro", "trans", "outro"):
        parts.append(f'<h4>{GROUP_LABELS[group]}</h4>')
        for b in buckets:
            bucket_note = f"bucket {b}" if len(buckets) > 1 else ""
            for i, line in enumerate(CONNECTIVES[b][group]):
                parts.append(row(f"seg_{b}_{group}_{i}", line, note=bucket_note))
    parts.append('</div>')
parts.append('</section>')

# --- 2. Flavor tails ----------------------------------------------------
parts.append('<section><h2 id="tails">2 &middot; Flavor tails</h2>'
             '<p class="blurb">The punchline after a name + stat burst, e.g. <i>&ldquo;KELLY! Five in a row! '
             '&rarr; [tail]&rdquo;</i>. Since the name and stat already spent words, tails should be one short breath.</p>')
kind_order = [k for k in KIND_LABELS if k in TAILS[1]] + [k for k in TAILS[1] if k not in KIND_LABELS]
for anchor, tier, buckets, blurb in TIERS:
    parts.append(f'<div class="tier" id="tails-{anchor}"><h3>{tier} <span class="tierblurb">{esc(blurb)}</span></h3>')
    for kind in kind_order:
        parts.append(f'<h4>{KIND_LABELS.get(kind, kind)}</h4>')
        for b in buckets:
            bucket_note = f"bucket {b}" if len(buckets) > 1 else ""
            for i, line in enumerate(TAILS[b].get(kind, [])):
                parts.append(row(f"tail_{b}_{kind}_{i}", line, note=bucket_note))
    parts.append('</div>')
parts.append('</section>')

# --- 3. Stat bursts (formulaic — folded, comment boxes only) ------------
parts.append('<section><h2 id="stats">3 &middot; Stat bursts</h2>'
             '<p class="blurb">Formulaic number clips (no per-line suggestions &mdash; the template is the thing to critique). '
             'Spot-check a few in each family and leave one comment per template if the pattern needs work.</p>')
stat_groups = [
    ("Streaks — “N in a row!”", [(f"inarow_{n}", f"{WORDS[n]} in a row!") for n in range(2, 21)]),
    ("Perfect rounds — “N for N — PERFECT!”", [(f"perfect_{n}", f"{WORDS[n]} for {WORDS[n].lower()} — PERFECT!") for n in range(3, 21)]),
    ("Point totals — “N points!”", [(f"points_{p}", f"{w} points!") for p, w in POINTS.items()]),
    ("Zero streaks — “N perfect zeros!”", [(f"zeros_{n}", f"{WORDS[n]} perfect zeros!") for n in range(3, 11)]),
]
for label, items in stat_groups:
    parts.append(f'<details><summary>{esc(label)} <span class="count">{len(items)} clips</span></summary>')
    for clip_id, text in items:
        parts.append(row(clip_id, text, with_suggestion=False))
    parts.append('</details>')
parts.append('</section>')

# --- 4. Names (pronunciation check) --------------------------------------
parts.append('<section><h2 id="names">4 &middot; Name call-outs</h2>'
             '<p class="blurb">Pronunciation audit. The <i>spoken</i> spelling is what was fed to the voice '
             '(e.g. Trygve &rarr; &ldquo;Trigvee&rdquo;). Flag any name that sounds off in either voice.</p>')
name_groups = [("Family", FAMILY), ("Common guest names", COMMON)]
for label, names in name_groups:
    parts.append(f'<details {"open" if label == "Family" else ""}><summary>{esc(label)} <span class="count">{len(names)} clips</span></summary>')
    for slug, spoken in names:
        note = f'spoken as “{spoken}”' if spoken.lower() != slug else ""
        parts.append(row(f"name_{slug}", f"{spoken}!", with_suggestion=False, note=note))
    parts.append('</details>')
parts.append('</section>')

body = "\n".join(parts)

total_lines = body.count('class="line"')

page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wizard Keeper — Announcer Line Audit</title>
<style>
  :root {{ --paper:#EFE6D3; --ink:#2B2118; --felt:#2F5D46; --terra:#AE4A2C; --brass:#A0721E; --card:#FBF6EA; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; font:16px/1.45 -apple-system, "SF Pro Text", Georgia, serif; background:var(--paper); color:var(--ink); }}
  header {{ position:sticky; top:0; z-index:10; background:var(--felt); color:#F2EAD8; padding:10px 18px;
           display:flex; align-items:center; gap:12px; flex-wrap:wrap; box-shadow:0 2px 8px rgba(43,33,24,.35); }}
  header h1 {{ font-size:17px; margin:0; flex:1; min-width:220px; }}
  header .btn {{ background:var(--brass); color:#fff; border:0; border-radius:8px; padding:8px 14px; font-size:14px; font-weight:600; cursor:pointer; }}
  header .btn.secondary {{ background:rgba(255,255,255,.16); }}
  #fbcount {{ font-size:13px; opacity:.85; }}
  main {{ max-width:880px; margin:0 auto; padding:18px 18px 120px; }}
  .howto {{ background:var(--card); border:1px solid #DDD3C0; border-radius:12px; padding:14px 16px; font-size:14px; }}
  .howto code {{ background:#EFE6D3; padding:1px 5px; border-radius:4px; }}
  h2 {{ margin:34px 0 6px; font-size:22px; border-bottom:2px solid var(--brass); padding-bottom:4px; }}
  h3 {{ margin:22px 0 4px; font-size:18px; color:var(--felt); }}
  h4 {{ margin:16px 0 4px; font-size:13px; text-transform:uppercase; letter-spacing:.06em; color:var(--terra); }}
  .tierblurb {{ font-size:13px; font-weight:400; color:#6B5D4A; margin-left:6px; }}
  .blurb {{ font-size:14px; color:#5A4C3A; margin:4px 0 10px; }}
  .line {{ background:var(--card); border:1px solid #E2D8C4; border-radius:10px; padding:10px 12px; margin:8px 0; }}
  .line-head {{ display:flex; align-items:center; gap:8px; flex-wrap:wrap; }}
  .play {{ background:var(--felt); color:#F2EAD8; border:0; border-radius:7px; padding:5px 10px; font-size:13px; font-weight:700; cursor:pointer; min-width:44px; }}
  .play.playing {{ background:var(--terra); }}
  .text {{ flex:1; min-width:200px; font-weight:600; }}
  .note {{ font-size:12px; color:#8A7A62; }}
  .clipid {{ font:11px ui-monospace, monospace; color:#A79878; }}
  .sug {{ margin:7px 0 0; font-size:13.5px; color:var(--brass); }}
  .sug::before {{ content:"Claude: "; font-weight:700; }}
  .sug.keep {{ color:#4F7D5E; }}
  .fb {{ width:100%; margin-top:8px; border:1px dashed #C9BBA0; border-radius:8px; background:#FFFDF7; padding:7px 9px;
        font:14px -apple-system, sans-serif; color:var(--ink); resize:vertical; }}
  .fb.has {{ border-style:solid; border-color:var(--terra); background:#FFF6F0; }}
  details {{ background:var(--card); border:1px solid #E2D8C4; border-radius:10px; padding:8px 12px; margin:10px 0; }}
  summary {{ cursor:pointer; font-weight:700; padding:4px 0; }}
  .count {{ font-size:12px; font-weight:400; color:#8A7A62; }}
  details .line {{ border:0; border-top:1px solid #EEE4D0; border-radius:0; margin:0; }}
  nav.toc {{ font-size:14px; margin:12px 0 0; }}
  nav.toc a {{ color:var(--felt); margin-right:14px; }}
</style></head><body>
<header>
  <h1>&#127908; Announcer Line Audit <span style="font-weight:400;opacity:.8">&middot; {total_lines} clips</span></h1>
  <span id="fbcount"></span>
  <button class="btn secondary" id="dl">Download feedback</button>
  <button class="btn" id="copy">Copy feedback for Claude</button>
</header>
<main>
<div class="howto">
  <b>How to use:</b> tap <b>&#9654; C</b> / <b>&#9654; J</b> to hear each line in Charlie / Jessica.
  Leave notes in any box &mdash; they auto-save in this browser. When done, hit
  <b>Copy feedback for Claude</b> and paste the result into chat; I&rsquo;ll revise the lines and re-record.
  Shorthand welcome: <code>cut</code>, <code>keep</code>, <code>too wordy</code>, or a full rewrite.
  <br><br>&#9888;&#65039; If play buttons are silent, your browser is blocking local audio &mdash; double-click
  <code>_review/serve-audit.command</code> and open <a href="http://localhost:8765/_review/announcer-audit.html">localhost:8765/_review/announcer-audit.html</a>.
  <nav class="toc"><a href="#connectives">1 Glue</a><a href="#tails">2 Tails</a><a href="#stats">3 Stat bursts</a><a href="#names">4 Names</a></nav>
</div>
{body}
</main>
<script>
const AUDIO_BASE = "../Sources/App/Resources/Announcer/";
let current = null, currentBtn = null;
document.querySelectorAll(".play").forEach(btn => {{
  btn.addEventListener("click", () => {{
    if (currentBtn === btn && current && !current.paused) {{ current.pause(); reset(); return; }}
    if (current) {{ current.pause(); reset(); }}
    current = new Audio(AUDIO_BASE + btn.dataset.voice + "/" + btn.dataset.clip + ".mp3");
    currentBtn = btn;
    btn.classList.add("playing"); btn.innerHTML = "&#9632;" + btn.textContent.slice(1);
    current.onended = reset;
    current.onerror = () => {{ reset(); alert("Couldn't load audio — run _review/serve-audit.command and use the localhost link at the top."); }};
    current.play().catch(() => {{ reset(); }});
  }});
}});
function reset() {{
  if (currentBtn) {{ currentBtn.classList.remove("playing"); currentBtn.innerHTML = "&#9654;" + currentBtn.textContent.slice(1); }}
  currentBtn = null;
}}
// --- feedback persistence ---
const KEY = id => "wkaudit." + id;
const boxes = document.querySelectorAll(".fb");
boxes.forEach(t => {{
  const saved = localStorage.getItem(KEY(t.dataset.clip));
  if (saved) {{ t.value = saved; t.classList.add("has"); autosize(t); }}
  t.addEventListener("input", () => {{
    if (t.value.trim()) localStorage.setItem(KEY(t.dataset.clip), t.value);
    else localStorage.removeItem(KEY(t.dataset.clip));
    t.classList.toggle("has", !!t.value.trim());
    autosize(t); updateCount();
  }});
}});
function autosize(t) {{ t.style.height = "auto"; t.style.height = Math.max(30, t.scrollHeight) + "px"; }}
function collect() {{
  const out = [];
  boxes.forEach(t => {{
    const v = (localStorage.getItem(KEY(t.dataset.clip)) || "").trim();
    if (!v) return;
    const text = t.closest(".line").querySelector(".text").textContent;
    out.push("- **" + t.dataset.clip + "** " + text + "\\n  feedback: " + v.replace(/\\n/g, " / "));
  }});
  return out.length ? "# Announcer audit feedback (" + out.length + " lines)\\n\\n" + out.join("\\n") : "";
}}
function updateCount() {{
  const n = Array.from(boxes).filter(t => (localStorage.getItem(KEY(t.dataset.clip)) || "").trim()).length;
  document.getElementById("fbcount").textContent = n ? n + " comment" + (n > 1 ? "s" : "") : "";
}}
updateCount();
document.getElementById("copy").addEventListener("click", async () => {{
  const md = collect();
  if (!md) {{ alert("No comments yet — type notes into any box first."); return; }}
  try {{ await navigator.clipboard.writeText(md); alert("Copied! Paste it to Claude in chat."); }}
  catch {{ prompt("Copy manually:", md); }}
}});
document.getElementById("dl").addEventListener("click", () => {{
  const md = collect();
  if (!md) {{ alert("No comments yet."); return; }}
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([md], {{type: "text/markdown"}}));
  a.download = "announcer-feedback.md"; a.click();
}});
</script>
</body></html>
"""

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write(page)

# Companion server script for browsers that block file:// audio.
serve = os.path.join(ROOT, "_review", "serve-audit.command")
with open(serve, "w") as f:
    f.write('#!/bin/zsh\ncd "$(dirname "$0")/.."\n'
            'echo "Open: http://localhost:8765/_review/announcer-audit.html"\n'
            '(sleep 1 && open "http://localhost:8765/_review/announcer-audit.html") &\n'
            'python3 -m http.server 8765\n')
os.chmod(serve, 0o755)

print(f"wrote {OUT} — {total_lines} lines, {len(suggestions)} suggestions merged")
if missing_audio:
    print(f"MISSING AUDIO ({len(missing_audio)}):")
    for m in missing_audio[:20]:
        print("  " + m)
    if len(missing_audio) > 20:
        print(f"  ... and {len(missing_audio) - 20} more")
