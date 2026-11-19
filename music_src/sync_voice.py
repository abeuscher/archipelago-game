"""Copies the recorded voice clips into the game and writes data/voice.json.

    python music_src/sync_voice.py

Recordings go in music_src/voice/ named by clip ([character]_[3 digits].ogg,
see voice_parts.md). Each one found is copied to assets/voice/, and
data/voice.json maps the line it belongs to (from voice_ids.json) to that
copy. A line with no recording yet is simply silent. Re-run after adding
recordings.
"""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "voice")
DEST = os.path.join(ROOT, "assets", "voice")

ids = json.load(open(os.path.join(HERE, "voice_ids.json"), encoding="utf-8"))
os.makedirs(DEST, exist_ok=True)
lines = {}
for key, clip in sorted(ids.items(), key=lambda kv: kv[1]):
    src = os.path.join(SRC, clip + ".ogg")
    if not os.path.exists(src):
        continue
    shutil.copy2(src, os.path.join(DEST, clip + ".ogg"))
    lines[key] = "assets/voice/%s.ogg" % clip

out_path = os.path.join(ROOT, "data", "voice.json")
volume = 0
if os.path.exists(out_path):   # keep a volume set by hand
    volume = json.load(open(out_path, encoding="utf-8")).get("volume_db", 0)
out = {
    "_note": "Written by music_src/sync_voice.py: each spoken line (tip:<id>, say:<id>) and its recording. "
             "A line not listed has no recording yet and is shown silently.",
    "volume_db": volume,
    "lines": lines,
}
json.dump(out, open(out_path, "w", encoding="utf-8", newline="\n"),
          indent=2, ensure_ascii=False)
print("%d recorded line(s)" % len(lines))
