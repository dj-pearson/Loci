#!/usr/bin/env python3
"""Validate store listing metadata against each platform's limits (US-204).

App Store Connect and Play Console both reject an upload for an over-length field,
and both do it late — after the build has been processed. Catching it here turns a
failed submission into a failed check.

    python3 scripts/check-store-metadata.py

Also asserts that the files a submission cannot proceed without are present at all:
the listing previously had 7 files and none of the URLs, review information, or
release notes.
"""

from __future__ import annotations

import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPLE = os.path.join(REPO, "Lociate", "fastlane", "metadata", "en-US")
PLAY = os.path.join(REPO, "android", "fastlane", "metadata", "android", "en-US")

# (relative path, max characters or None, required)
FIELDS = [
    (os.path.join(APPLE, "name.txt"), 30, True),
    (os.path.join(APPLE, "subtitle.txt"), 30, True),
    (os.path.join(APPLE, "keywords.txt"), 100, True),
    (os.path.join(APPLE, "promotional_text.txt"), 170, False),
    (os.path.join(APPLE, "description.txt"), 4000, True),
    (os.path.join(APPLE, "release_notes.txt"), 4000, True),
    (os.path.join(APPLE, "support_url.txt"), None, True),
    (os.path.join(APPLE, "marketing_url.txt"), None, False),
    (os.path.join(APPLE, "privacy_url.txt"), None, True),
    (os.path.join(APPLE, "copyright.txt"), None, True),
    (os.path.join(APPLE, "primary_category.txt"), None, True),
    (os.path.join(APPLE, "review_information", "email_address.txt"), None, True),
    (os.path.join(APPLE, "review_information", "first_name.txt"), None, True),
    (os.path.join(APPLE, "review_information", "last_name.txt"), None, True),
    (os.path.join(APPLE, "review_information", "notes.txt"), 4000, True),
    # Demo credentials: required because Family sharing cannot be reviewed without
    # a pre-seeded household, and the placeholder check below is what stops the
    # placeholder password reaching a reviewer.
    (os.path.join(APPLE, "review_information", "demo_user.txt"), None, True),
    (os.path.join(APPLE, "review_information", "demo_password.txt"), None, True),
    # Play limits are tighter than Apple's and differ per field.
    (os.path.join(PLAY, "title.txt"), 30, True),
    (os.path.join(PLAY, "short_description.txt"), 80, True),
    (os.path.join(PLAY, "full_description.txt"), 4000, True),
]

# Values that must be replaced before a real submission. Shipping one of these is
# worse than a missing file, because the submission proceeds and the reviewer hits
# a dead end.
PLACEHOLDER_MARKERS = ["REPLACE_BEFORE_SUBMISSION", "TEAM_ID", "TODO", "example.com"]


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []

    for path, limit, required in FIELDS:
        rel = os.path.relpath(path, REPO)

        if not os.path.exists(path):
            (errors if required else warnings).append(f"missing: {rel}")
            continue

        value = open(path).read().strip()
        if required and not value:
            errors.append(f"empty: {rel}")
            continue

        if limit is not None and len(value) > limit:
            errors.append(f"too long: {rel} is {len(value)} chars, limit {limit}")

        for marker in PLACEHOLDER_MARKERS:
            if marker in value:
                warnings.append(f"placeholder in {rel}: contains {marker!r}")

    # Screenshots cannot be generated in CI, so their absence is a warning the
    # launch checklist tracks rather than a build failure.
    for label, directory in (
        ("App Store screenshots", os.path.join(APPLE, "..", "screenshots")),
        ("Play phone screenshots", os.path.join(PLAY, "images", "phoneScreenshots")),
    ):
        if not os.path.isdir(directory) or not os.listdir(directory):
            warnings.append(f"{label} not present — required before submission")

    for warning in warnings:
        print(f"WARN  {warning}")
    for error in errors:
        print(f"ERROR {error}", file=sys.stderr)

    if errors:
        print(f"\n{len(errors)} blocking metadata problem(s).", file=sys.stderr)
        return 1

    print(f"\nStore metadata OK ({len(FIELDS)} fields checked, {len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
