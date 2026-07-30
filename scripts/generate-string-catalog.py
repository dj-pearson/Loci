#!/usr/bin/env python3
"""Generate Localizable.xcstrings and InfoPlist.xcstrings from the source tree.

US-211: CLAUDE.md mandates `String(localized:)` for every user-facing string, and
610 call sites already did it — but no string catalog existed. Without one, every
key silently resolves to itself: the app appears to work in English and cannot be
translated at all, and a typo'd key is invisible.

Keys are extracted from the sources rather than hand-maintained, so the catalog
cannot drift from what the code asks for:

    python3 scripts/generate-string-catalog.py
    python3 scripts/generate-string-catalog.py --check    # what CI runs

For the source language (en) the key *is* the value, so no `en` translation unit is
emitted for simple keys — Xcode resolves those from the key itself. Pluralized keys
are the exception: their variations are declared explicitly below, because a plural
rule cannot be derived from a key name.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(REPO, "Lociate")
CATALOG = os.path.join(APP_DIR, "Localizable.xcstrings")
INFO_CATALOG = os.path.join(APP_DIR, "InfoPlist.xcstrings")

SOURCE_LANGUAGE = "en"

# `String(localized: "…")` with a plain literal. Interpolated literals are skipped
# deliberately: Foundation resolves those against the interpolated *format*, and
# emitting the raw Swift expression as a key would never match at runtime.
LOCALIZED_PATTERN = re.compile(r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"')

# Keys that need plural variations. A plural rule cannot be inferred from a key
# name, and `%lld` binds to the count argument passed by
# `String(localized:count:)` in Utilities/LocalizedPlural.swift.
PLURALS: dict[str, dict[str, str]] = {
    "failed_attempt_count": {
        "one": "%lld failed attempt",
        "other": "%lld failed attempts",
    },
    "household_member_count": {
        "one": "%lld member",
        "other": "%lld members",
    },
}

# Permission prompts and display name live in InfoPlist.xcstrings, not the main
# catalog — iOS reads them from a separate table.
INFO_PLIST_KEYS = [
    "CFBundleDisplayName",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
]


def swift_sources() -> list[str]:
    paths = []
    for root, dirs, names in os.walk(APP_DIR):
        if ".xcodeproj" in root:
            continue
        dirs.sort()
        for name in sorted(names):
            if name.endswith(".swift"):
                paths.append(os.path.join(root, name))
    return paths


def extract_keys() -> set[str]:
    keys: set[str] = set()
    for path in swift_sources():
        for match in LOCALIZED_PATTERN.finditer(open(path).read()):
            # Unescape the Swift literal so the key matches what the runtime sees.
            keys.add(match.group(1).replace('\\"', '"').replace("\\\\", "\\"))
    return keys


def build_catalog(keys: set[str]) -> dict:
    strings: dict[str, dict] = {}

    for key in sorted(keys):
        if key in PLURALS:
            continue  # emitted below with its variations
        # No `localizations` entry: for the source language Xcode uses the key as
        # the value, and inventing an `en` unit here would just duplicate it.
        strings[key] = {"extractionState": "manual"}

    for key, forms in PLURALS.items():
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                SOURCE_LANGUAGE: {
                    "variations": {
                        "plural": {
                            category: {
                                "stringUnit": {"state": "translated", "value": value}
                            }
                            for category, value in forms.items()
                        }
                    }
                }
            },
        }

    return {
        "sourceLanguage": SOURCE_LANGUAGE,
        "strings": strings,
        "version": "1.0",
    }


def build_info_catalog() -> dict:
    plist_path = os.path.join(APP_DIR, "Info.plist")
    import plistlib

    plist = plistlib.load(open(plist_path, "rb"))

    strings: dict[str, dict] = {}
    for key in INFO_PLIST_KEYS:
        value = plist.get(key)
        if key == "CFBundleDisplayName":
            value = "Lociate"
        if not value:
            continue
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                SOURCE_LANGUAGE: {
                    "stringUnit": {"state": "translated", "value": value}
                }
            },
        }

    return {
        "sourceLanguage": SOURCE_LANGUAGE,
        "strings": strings,
        "version": "1.0",
    }


def serialize(catalog: dict) -> str:
    # Xcode writes these sorted with 2-space indent; matching that keeps the diff
    # readable and avoids churn when Xcode rewrites the file.
    return json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    keys = extract_keys()
    missing_plurals = [k for k in PLURALS if k not in keys]
    if missing_plurals:
        print(
            "PLURALS declares keys no source file uses: "
            + ", ".join(sorted(missing_plurals))
            + "\nRemove them, or the catalog carries dead entries.",
            file=sys.stderr,
        )
        return 1

    targets = [
        (CATALOG, serialize(build_catalog(keys))),
        (INFO_CATALOG, serialize(build_info_catalog())),
    ]

    if args.check:
        stale = [
            os.path.relpath(path, REPO)
            for path, content in targets
            if not os.path.exists(path) or open(path).read() != content
        ]
        if stale:
            print("String catalogs are out of date with the sources:", file=sys.stderr)
            for path in stale:
                print(f"  {path}", file=sys.stderr)
            print("\nRun: python3 scripts/generate-string-catalog.py", file=sys.stderr)
            return 1
        print(f"String catalogs up to date ({len(keys)} keys, {len(PLURALS)} pluralized)")
        return 0

    for path, content in targets:
        open(path, "w").write(content)
        print(f"wrote {os.path.relpath(path, REPO)}")
    print(f"{len(keys)} keys, {len(PLURALS)} pluralized")
    return 0


if __name__ == "__main__":
    sys.exit(main())
