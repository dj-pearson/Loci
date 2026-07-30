#!/usr/bin/env python3
"""Fail if a user-facing string literal bypasses the localization catalog (US-211).

CLAUDE.md requires `String(localized:)` for every user-facing string. Without an
enforced check the rule erodes one `Text("Save")` at a time, and each one is
invisible until a translator asks why a screen is half-English.

    python3 scripts/check-localization.py

Deliberately narrow. It flags literals passed to the SwiftUI initializers that
render text, and allows the cases where localizing would be wrong or pointless:
punctuation and separators, bare interpolations (the plural rule belongs on the
phrase, not the number), the brand name, and SF Symbol identifiers.
"""

from __future__ import annotations

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(REPO, "Lociate")

# Initializers whose first argument renders as visible text.
FLAGGED = re.compile(
    r'\b(Text|Label|Button|TextField|SecureField|Toggle|Picker|Section|'
    r'navigationTitle|ContentUnavailableView)\(\s*"((?:[^"\\]|\\.)*)"'
)

BRAND_TERMS = {"Lociate", "Loci"}


def is_allowed(literal: str) -> bool:
    stripped = literal.strip()

    # Empty, whitespace, or pure punctuation/separators.
    if not stripped or not any(ch.isalnum() for ch in stripped):
        return True

    # Bare interpolation such as "\(count)" — the surrounding phrase is what needs
    # a plural rule, and there is nothing here to translate.
    if re.fullmatch(r'(\\\([^)]*\)|[\s\d/·,.:%-]|\\\(|\))+', stripped):
        return True

    # A literal that is *only* the brand name is a proper noun.
    if stripped in BRAND_TERMS:
        return True

    # SF Symbol names: lowercase, dot-separated, no spaces.
    if re.fullmatch(r'[a-z0-9]+(\.[a-z0-9]+)+', stripped):
        return True

    return False


def main() -> int:
    violations: list[tuple[str, int, str, str]] = []

    for root, dirs, names in os.walk(APP_DIR):
        if ".xcodeproj" in root:
            continue
        dirs.sort()
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(root, name)
            for lineno, line in enumerate(open(path).read().split("\n"), 1):
                # A line already routing through the catalog is fine even if it also
                # contains a literal (e.g. an accessibility label alongside a symbol).
                if "String(localized:" in line:
                    continue
                # Comments and doc comments frequently quote code — including the
                # very literals a story removed — and rewriting prose in a comment
                # would be nonsense.
                if re.match(r'\s*(//|\*|/\*)', line):
                    continue
                for match in FLAGGED.finditer(line):
                    initializer, literal = match.group(1), match.group(2)
                    if not is_allowed(literal):
                        violations.append(
                            (os.path.relpath(path, REPO), lineno, initializer, literal)
                        )

    if violations:
        print(
            f"{len(violations)} user-facing literal(s) bypass the localization "
            f"catalog:\n",
            file=sys.stderr,
        )
        for path, lineno, initializer, literal in violations:
            print(f"  {path}:{lineno}  {initializer}(\"{literal}\")", file=sys.stderr)
        print(
            '\nWrap with String(localized:), then regenerate the catalog:\n'
            "  python3 scripts/generate-string-catalog.py",
            file=sys.stderr,
        )
        return 1

    print("No un-localized user-facing literals found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
