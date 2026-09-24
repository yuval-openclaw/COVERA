#!/usr/bin/env python3
"""Fill missing translations in Localizable.xcstrings using Gemini.

Keys come from the build's .stringsdata files (build with SWIFT_EMIT_LOC_STRINGS),
so the list is exactly what the app asks for, interpolations included
("%lld of %lld done"). Existing translations are never overwritten.

A translation is rejected — and that string stays in English — if it changes
the format specifiers, drops the "Covera" name, or translates the "DELETE"
confirmation word the app checks for literally.

Usage: python3 ios/scripts/translate_strings.py <DerivedData path>
Reads COVERA_GEMINI_API_KEY from api/.env. Sends UI strings only, never user data.
"""
import glob
import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "ios/Covera/Resources/Localizable.xcstrings"
LANGUAGES = {
    "fr": "French", "es": "Spanish", "pt": "Portuguese", "de": "German", "he": "Hebrew",
    "ar": "Arabic", "hi": "Hindi", "th": "Thai", "ja": "Japanese",
}
MODEL = "gemini-2.5-flash"
BATCH = 40
SPEC = re.compile(r"%(?:\d+\$)?(lld|ld|d|@|lf|f)")


def api_key() -> str:
    for line in (ROOT / "api/.env").read_text().splitlines():
        if line.startswith("COVERA_GEMINI_API_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("COVERA_GEMINI_API_KEY not found in api/.env")


def app_keys(derived_data: str) -> set[str]:
    keys = set()
    for path in glob.glob(f"{derived_data}/Build/Intermediates.noindex/**/*.stringsdata", recursive=True):
        for entry in json.load(open(path)).get("tables", {}).get("Localizable", []):
            keys.add(entry["key"])
    return keys


def acceptable(source: str, translated: str) -> bool:
    if not translated.strip():
        return False
    if sorted(SPEC.findall(source)) != sorted(SPEC.findall(translated)):
        return False
    # "DELETE" in capitals is a literal the user types to confirm an erasure, so
    # it has to survive translation. The check runs both ways: a model told to
    # preserve it will otherwise leave an ordinary "Delete" verb in English too,
    # which produced buttons reading "DELETE וצא/י" in Hebrew.
    if ("DELETE" in source) != ("DELETE" in translated):
        return False
    return "Covera" not in source or "Covera" in translated


def translate(key: str, code: str, strings: list[str]) -> dict[str, str]:
    numbered = "\n".join(f"{i}: {json.dumps(s, ensure_ascii=False)}" for i, s in enumerate(strings))
    prompt = f"""Translate these user-interface strings from English to {LANGUAGES[code]}.

Context: Covera, a calm, trustworthy iPhone app that helps people understand their own health insurance policies during a medical event. Use a polite, clear register suitable for a frightened reader. Keep translations about as short as the English, since they appear on buttons and labels.

Rules:
- Keep every format specifier exactly (%lld, %@). If word order requires it, use positional forms (%1$lld, %2$lld).
- Keep the brand name "Covera" untranslated.
- "DELETE" written in Latin capitals is a literal word the user has to type to confirm; keep it exactly as written. An ordinary "Delete" or "delete" is just the verb — translate it normally, and never leave it in English.
- Do not add or remove information.

Return JSON: {{"items": [{{"i": number, "t": translation}}]}} with one item per input.

{numbered}"""
    body = json.dumps({
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseJsonSchema": {
                "type": "object",
                "properties": {"items": {"type": "array", "items": {
                    "type": "object",
                    "properties": {"i": {"type": "integer"}, "t": {"type": "string"}},
                    "required": ["i", "t"],
                }}},
                "required": ["items"],
            },
            "temperature": 0.2,
            "maxOutputTokens": 16000,
        },
    }).encode()
    request = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
        data=body, headers={"Content-Type": "application/json", "x-goog-api-key": key},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        out = json.load(response)
    text = "".join(p.get("text", "") for p in out["candidates"][0]["content"]["parts"] if not p.get("thought"))
    result = {}
    for item in json.loads(text)["items"]:
        i = item.get("i")
        if isinstance(i, int) and 0 <= i < len(strings) and acceptable(strings[i], item.get("t", "")):
            result[strings[i]] = item["t"]
    return result


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    key = api_key()
    keys = app_keys(sys.argv[1])
    catalog = json.load(open(CATALOG))
    entries = catalog["strings"]

    jobs = []
    for code in LANGUAGES:
        missing = sorted(k for k in keys if code not in entries.get(k, {}).get("localizations", {}))
        jobs += [(code, missing[i:i + BATCH]) for i in range(0, len(missing), BATCH)]

    def run(job):
        code, batch = job
        try:
            return code, batch, translate(key, code, batch)
        except Exception as error:  # one failed batch should not lose the others
            print(f"  {code}: batch failed ({type(error).__name__}), left in English", file=sys.stderr)
            return code, batch, {}

    added = {code: 0 for code in LANGUAGES}
    rejected = {code: 0 for code in LANGUAGES}
    with ThreadPoolExecutor(max_workers=8) as pool:
        for code, batch, result in pool.map(run, jobs):
            for source in batch:
                if source in result:
                    loc = entries.setdefault(source, {}).setdefault("localizations", {})
                    loc[code] = {"stringUnit": {"state": "translated", "value": result[source]}}
                    added[code] += 1
                else:
                    rejected[code] += 1

    # Strings the code no longer uses are dropped from the catalog.
    for stale in set(entries) - keys:
        del entries[stale]

    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    for code in LANGUAGES:
        total = sum(1 for k in keys if code in entries.get(k, {}).get("localizations", {}))
        print(f"{code}: +{added[code]} added, {rejected[code]} left in English -> {total}/{len(keys)} translated")


if __name__ == "__main__":
    main()
