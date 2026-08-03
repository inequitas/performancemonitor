#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# check-glossary.sh — verifies the process glossary files agree with each other.
#
# Every language file must describe the same processes in the same order as the
# English one. Only `title` and `description` may differ. Translating a
# `match.name` would silently stop the lookup working for that language, since
# it is compared against the literal name the kernel reports, and nothing at
# runtime would complain: the entry would simply never match and the process
# would show no explanation.
#
# Run by CI, and worth running after editing any glossary file.

GLOSSARY_DIR="Sources/PerformanceApp/Resources/Glossary"
LANGUAGES=(nl de fr es zh-Hans ja)

python3 - "$GLOSSARY_DIR" "${LANGUAGES[@]}" <<'PY'
import json, sys, pathlib

directory = pathlib.Path(sys.argv[1])
languages = sys.argv[2:]
english = json.loads((directory / "glossary.en.json").read_text())
problems = []

print(f"english: {len(english['entries'])} entries")

for code in languages:
    path = directory / f"glossary.{code}.json"
    if not path.exists():
        problems.append(f"{code}: file missing")
        continue
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        problems.append(f"{code}: invalid JSON ({exc})")
        continue

    if data.get("language") != code:
        problems.append(f"{code}: language field is {data.get('language')!r}")

    if len(data["entries"]) != len(english["entries"]):
        problems.append(f"{code}: {len(data['entries'])} entries, expected {len(english['entries'])}")
        continue

    for source, translated in zip(english["entries"], data["entries"]):
        where = source["match"]
        if source["match"] != translated["match"]:
            problems.append(f"{code}: match changed for {where} -> {translated['match']}")
        for field in ("category", "vendor", "expectedHigh"):
            if source.get(field) != translated.get(field):
                problems.append(f"{code}: {field} changed for {where}")
        for field in ("title", "description"):
            if not translated.get(field, "").strip():
                problems.append(f"{code}: empty {field} for {where}")
    if "—" in path.read_text():
        problems.append(f"{code}: contains an em dash")

    print(f"{code}: {len(data['entries'])} entries, consistent with english")

if problems:
    print("\nFAILED:")
    for p in problems:
        print(f"  {p}")
    sys.exit(1)
print("\nall glossary files agree")
PY
