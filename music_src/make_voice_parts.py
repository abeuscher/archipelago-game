"""Writes voice_parts.md: every line the characters speak, grouped by speaker
like a script, each with its clip name ([character]_[3 digits]).

    python music_src/make_voice_parts.py

Reads data/dialogue.json (and data/rules.json, data/settings.json for the
numbers some tips quote). Clip numbers are kept in voice_ids.json, so a line
keeps its number when lines are added; new lines get the next free number.
Re-run after editing dialogue.json.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
IDS_PATH = os.path.join(HERE, "voice_ids.json")
OUT_PATH = os.path.join(HERE, "voice_parts.md")

ORDER = ["admiral", "ginger", "pilot", "mechanic", "scientist"]

# When each announcement plays, for the voice direction.
ANNOUNCE_WHEN = {
    "income": "Start of each round from round 2, reporting what came in.",
    "incoming_one": "Alarm: one enemy missile is about to land.",
    "incoming_many": "Alarm: several enemy missiles are about to land.",
    "incoming_troops": "Alarm: an enemy transport is about to drop troops.",
    "incoming_boat": "Alarm: an enemy boat is coming ashore.",
    "level_2_intro": "Start of level 2, introducing the stronghold.",
    "enemy_stronghold": "Level 2, when our missile first reveals the enemy's stronghold.",
    "attack_unaimed": "First time the player presses Attack with weapons not aimed.",
    "first_base_lost": "Level 1, when the player loses their first base.",
    "boat_spotted": "Start of a round when an enemy boat is crossing the channel.",
    "battle_report": "End of each round, opening the battle summary. The summary lines below follow it.",
}
TIP_WHEN = "Tutorial tip (shown once; the player can turn tips off)."
REPORT_WHEN = "Battle summary, after the opening line. Only the lines for what happened are said, in this order."
NUMBERED = {"{n}": "n", "{money}": "money", "{fuel}": "fuel", "{research}": "research"}   # gap labels


def load(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return json.load(f)


def rule_values():
    """The fixed numbers tips quote, as the game fills them in today."""
    r = load("data/rules.json")
    s = load("data/settings.json")
    aa = r["anti_air"]
    return {
        "build_clock": str(int(s["build_clock_seconds"])),
        "repair_pct": str(round(r["damage"]["repair_cost_fraction"] * 100)),
        "aa_radius": str(int(aa["radius"])),
        "aa_engagements": str(int(aa["engagements"])),
        "acc": str(round(aa["accuracy"] * 100)),
        "acc_radar": str(round(aa["accuracy_with_radar"] * 100)),
        "base_hits": str(int(r["buildings"]["base"]["hits_to_destroy"])),
        "decoy_hits": str(int(r["buildings"]["decoy"]["hits_to_destroy"])),
        "refinery_fuel": str(int(r["buildings"]["refinery"]["produces"]["fuel"])),
    }


def lines():
    """[(key, character, text, when)] in game order."""
    d = load("data/dialogue.json")
    out = []
    for t in d["tips"]:
        out.append(("tip:" + t["id"], t["character"], t["text"], TIP_WHEN))
    ann = d["announcements"]
    for k, v in ann.items():
        out.append(("say:" + k, v["character"], v["text"], ANNOUNCE_WHEN.get(k, "")))
        if k == "battle_report":
            for part, forms in v["parts"].items():
                out.append(("report:%s:one" % part, v["character"], forms[0], REPORT_WHEN))
                out.append(("report:%s:many" % part, v["character"], forms[1], REPORT_WHEN))
    return out


def main():
    ids = {}
    if os.path.exists(IDS_PATH):
        with open(IDS_PATH, encoding="utf-8") as f:
            ids = json.load(f)
    values = rule_values()
    all_lines = lines()
    # Number new lines after the highest number each character already has.
    for key, who, _, _ in all_lines:
        if key not in ids:
            used = [int(v.split("_")[-1]) for k, v in ids.items() if v.startswith(who + "_")]
            ids[key] = "%s_%03d" % (who, max(used, default=0) + 1)
    with open(IDS_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(ids, f, indent=2)

    by_who = {}
    for key, who, text, when in all_lines:
        by_who.setdefault(who, []).append((ids[key], key, text, when))
    for who in by_who:
        by_who[who].sort(key=lambda e: e[0])

    out = ["# Voice parts", "",
           "Every line the characters say, grouped by speaker. Each clip is named on the left: "
           "`[character]_[3 digits]`, e.g. `admiral_001.ogg`.", "",
           "- Numbers that come from the rules (seconds, percentages) are filled in as the game says them today. "
           "If a rule changes, that line needs re-recording.",
           "- **[n]** marks a number that changes during play. See *Numbers* at the end.",
           "- Made by `music_src/make_voice_parts.py` from `data/dialogue.json`. Clip numbers are kept in "
           "`voice_ids.json`, so a line keeps its name when lines are added.", ""]
    counts = []
    for who in ORDER + sorted(set(by_who) - set(ORDER)):
        if who not in by_who:
            continue
        counts.append("%s %d" % (who.capitalize(), len(by_who[who])))
    out.append("Clips: " + ", ".join(counts) + ".")
    out.append("")
    for who in ORDER + sorted(set(by_who) - set(ORDER)):
        if who not in by_who:
            continue
        out.append("---")
        out.append("")
        out.append("## %s" % who.upper())
        out.append("")
        last_when = None
        for clip, key, text, when in by_who[who]:
            said = re.sub(r"\{(\w+)\}", lambda m: values.get(m.group(1), "{%s}" % m.group(1)), text)
            for ph in NUMBERED:
                said = said.replace(ph, "**[%s]**" % NUMBERED[ph])
            if when != last_when:
                out.append("*%s*" % when)
                out.append("")
                last_when = when
            out.append("**%s**  %s" % (clip, said))
            out.append("")
    out += ["---", "", "## Numbers", "",
            "Some lines say a number that changes during play. Three ways to handle them, line by line:", "",
            "1. **Record each number as its own clip** for that speaker and play them in the gap: "
            "e.g. `admiral_n02` ... `admiral_n20` for *two* to *twenty* (the battle summary says up to twenty "
            "in words). Ginger's missile count needs the same, roughly two to ten.",
            "2. **Record a version without the number**: e.g. \"General, several enemy missiles incoming!\" "
            "and keep the number on screen only.",
            "3. **Leave that line as text only** and voice the rest.", "",
            "The Pilot's income report (money, fuel, research) has numbers into the hundreds, so option 2 or 3 "
            "suits it best; we can reword it when you get there.", ""]
    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("wrote", OUT_PATH, "with", sum(len(v) for v in by_who.values()), "clips")


if __name__ == "__main__":
    main()
