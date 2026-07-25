#!/usr/bin/env python3
"""Build Sources/App/Resources/Announcer/captions.json — the spoken text of
every announcer clip, keyed by basename (filename minus ".mp3").

The clip TEXT is otherwise design-time-only knowledge living in
generate_announcer.py's corpus; the app needs it at runtime to caption the
"Share the Call" export video. This reads the corpus straight out of
generate_announcer.py (single source of truth, same trick as
tools/build_audit_page.py) without ever calling ElevenLabs — the API key is
stubbed and only jobs_for_voice() is walked, never main().

Silence clips (silence_200, silence_400) and anything else not produced by
jobs_for_voice() get no entry; ShareCall holds the previous caption across
those, so that's fine.

Usage: python3 tools/build_captions.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "tools", "generate_announcer.py")
OUT = os.path.join(ROOT, "Sources", "App", "Resources", "Announcer", "captions.json")

# --- Load the corpus from the generator without running it (or the API) ---
os.environ.setdefault("ELEVENLABS_API_KEY", "captions-build-stub")
ns = {"__name__": "captions", "__file__": GEN}
with open(GEN) as f:
    exec(compile(f.read(), GEN, "exec"), ns)

jobs_for_voice = ns["jobs_for_voice"]

# basename (no ".mp3") -> spoken text. Duplicate basenames across the name
# lists collapse to one entry (the text is identical either way).
captions = {}
for fname, text in jobs_for_voice():
    basename = fname[:-4] if fname.endswith(".mp3") else fname
    captions[basename] = text

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(captions, f, indent=1, sort_keys=True, ensure_ascii=False)

print(f"wrote {OUT} — {len(captions)} caption entries")
