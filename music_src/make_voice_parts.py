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
    "incoming_nuke": "Alarm: an enemy nuke is about to land.",
    "level_3_intro": "Start of level 3, introducing the nuclear silo.",
    "level_2_intro": "Start of level 2, introducing the stronghold.",
    "enemy_stronghold": "Level 2, when our missile first reveals the enemy's stronghold.",
    "attack_unaimed": "First time the player presses Attack with weapons not aimed.",
    "first_base_lost": "Level 1, when the player loses their first base.",
    "boat_spotted": "Start of a round when an enemy boat is crossing the channel.",
    "battle_report": "Start of each round after an attack, opening the battle summary. The summary lines below follow it, then the income.",
    "income_after_report": "After the battle summary, the round's income.",
}
TIP_WHEN = "Tutorial tip (shown once; the player can turn tips off)."
REPORT_WHEN = "Battle summary, after the opening line. Only the lines for what happened are said, in this order."
NUMBERED = {"{n}": "n", "{money}": "money", "{fuel}": "fuel", "{research}": "research"}   # gap labels


# Who says numbers that change during play, and which number clips they need.
NUMBER_CLIPS = {
    "ginger": {"from": 1, "to": 100,
               "note": "Her warning counts incoming missiles. Past 100 it shows in the text only."},
    "pilot": {"from": 0, "to": 99, "hundreds": True,
              "note": "The battle summary and income report (the summary counts missiles, buildings and soldiers; "
                      "soldiers go up in eights). A number over 99 is said as its hundreds clip then the rest: "
                      "345 is `pilot_n300` + `pilot_n045` (\"three hundred\" + \"forty-five\"); 300 is just `pilot_n300`."},
}

ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


def words_for(v):
    if v < 20:
        return ONES[v]
    if v < 100:
        return TENS[v // 10] + ("" if v % 10 == 0 else "-" + ONES[v % 10])
    if v % 100 == 0 and v < 1000:
        return ONES[v // 100] + " hundred"
    return str(v)


def number_list(rng):
    nums = list(range(rng["from"], rng["to"] + 1))
    if rng.get("hundreds"):
        nums += [h * 100 for h in range(1, 10)]
    return nums


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


ENDINGS = {}   # line key -> the endings one of which is said after it, at random


def lines():
    """[(key, character, text, when)] in game order."""
    d = load("data/dialogue.json")
    out = []
    for t in d["tips"]:
        out.append(("tip:" + t["id"], t["character"], t["text"], TIP_WHEN))
    ann = d["announcements"]
    for k, v in ann.items():
        if k.startswith("_"):
            continue
        out.append(("say:" + k, v["character"], v["text"], ANNOUNCE_WHEN.get(k, "")))
        ENDINGS["say:" + k] = v.get("endings", [])
        if k == "battle_report":
            for part, forms in v.get("parts", {}).items():
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
        if key in ids and not ids[key].startswith(who + "_"):
            del ids[key]   # the line moved to another speaker: it gets that speaker's next number
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
           "- **[n]** marks a number that changes during play. The game plays that speaker's number clip there "
           "(see *Numbers* in each speaker's section). Where a number falls in the middle of a line, the line is "
           "split into pieces recorded separately: `pilot_006a`, `pilot_006b`, and so on.",
           "- Made by `music_src/make_voice_parts.py` from `data/dialogue.json`. Clip numbers are kept in "
           "`voice_ids.json`, so a line keeps its name when lines are added.", ""]
    sections = []
    counts = []
    for who in ORDER + sorted(set(by_who) - set(ORDER)):
        if who not in by_who:
            continue
        body = []
        n_clips = 0
        last_when = None
        for clip, key, text, when in by_who[who]:
            said = re.sub(r"\{(\w+)\}", lambda m: values.get(m.group(1), "{%s}" % m.group(1)), text)
            if when != last_when:
                body.append("*%s*" % when)
                body.append("")
                last_when = when
            pieces = re.split(r"(\{\w+\})", said)
            gaps = [p for p in pieces if p in NUMBERED]
            words = [p.strip() for p in pieces if p not in NUMBERED]
            inner = [w for w in words[1:-1]] if len(words) > 2 else []
            if not gaps:
                body.append("**%s**  %s" % (clip, said))
                n_clips += 1
            elif len(gaps) == 1 and (words[0] == "" or words[-1] == ""):
                # The number at the start or end: one clip for the rest.
                shown = said.replace(gaps[0], "**[%s]**" % NUMBERED[gaps[0]])
                body.append("**%s**  %s" % (clip, shown))
                body.append("")
                body.append("> Record without the number: \"%s\"" % " ".join(w for w in words if w))
                n_clips += 1
            else:
                # Numbers in the middle: a piece for each run of words.
                shown = said
                for g in gaps:
                    shown = shown.replace(g, "**[%s]**" % NUMBERED[g], 1)
                body.append("%s  (in pieces)" % shown)
                body.append("")
                letter = 0
                for k, p in enumerate(pieces):
                    if p in NUMBERED:
                        body.append("> *(%s number)*" % NUMBERED[p])
                    elif p.strip() != "":
                        body.append("> **%s%s**  %s" % (clip, "abcdefghij"[letter], p.strip()))
                        letter += 1
                        n_clips += 1
                    body.append(">")
                body.pop()
            if ENDINGS.get(key):
                body.append("")
                body.append("> Then one of these, picked at random each time (recorded separately):")
                for k, e in enumerate(ENDINGS[key]):
                    body.append("> **%s_e%d**  %s" % (clip, k + 1, e))
                    n_clips += 1
            body.append("")
        rng = NUMBER_CLIPS.get(who)
        if rng is not None:
            nums = number_list(rng)
            body += ["### Numbers", "",
                     "One clip per number, said on its own in the voice of the lines above, "
                     "named for its value: `%s_n024` says \"twenty-four\". %s" % (who, rng["note"]), ""]
            for v in nums:
                body.append("**%s_n%03d**  %s" % (who, v, words_for(v)))
                body.append("")
            n_clips += len(nums)
        counts.append("%s %d" % (who.capitalize(), n_clips))
        sections += ["---", "", "## %s" % who.upper(), ""] + body
    out.append("Clips: " + ", ".join(counts) + ".")
    out.append("")
    out += sections
    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("wrote", OUT_PATH, "-", ", ".join(counts))


if __name__ == "__main__":
    main()
