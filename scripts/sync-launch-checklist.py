#!/usr/bin/env python3
"""Regenerate LAUNCH_CHECKLIST.md §4 from prd.json.

US-217: §4 previously listed two open gaps while the audit found build-blocking
defects on both platforms, so the go/no-go gate green-lit an unshippable build.
Deriving the section from prd.json means it cannot drift again.

    python3 scripts/sync-launch-checklist.py
    python3 scripts/sync-launch-checklist.py --check   # fails if out of date
"""

from __future__ import annotations

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRD = os.path.join(REPO, "prd.json")
CHECKLIST = os.path.join(REPO, "LAUNCH_CHECKLIST.md")

# The audit stories. Everything before US-185 predates it.
FIRST_AUDIT_STORY = 185

START = "## 4. Known gaps / hardening items"
END = "## 5. Backend — Supabase"

PREAMBLE = """Open items from the 2026-07 production-readiness audit. Each maps to a
story in `prd.json` (US-185 onward) with the full finding in its `notes`.

This section is generated — run `python3 scripts/sync-launch-checklist.py` after
changing a story's status.
"""

EPILOGUE = """> **What this audit found.** The previous version of this section listed two open
> gaps and implied everything else was shippable. In fact neither app could build
> and the backend's core read path did not work:
>
> - **iOS could not compile.** 72 of 104 Swift files had no target membership, and
>   the project declared zero SPM packages while sources imported `Supabase` and
>   `RevenueCat`. There was no widget target, no test target, and no shared scheme —
>   so every `xcodebuild -scheme Lociate` call in CI and Fastlane had nothing to
>   resolve. (US-185–188)
> - **Android could not configure.** `settings.gradle.kts` used `dependencyResolution`
>   instead of `dependencyResolutionManagement`, so Gradle could not evaluate the
>   settings file at all. There was no Gradle wrapper, no launcher icons, and the
>   `MAPS_API_KEY` manifest placeholder was undefined. (US-189–192)
> - **Every authenticated read of `loci` failed.** The `household_members` SELECT
>   policy filtered that table by a subquery over itself, and `loci_select_shared`
>   depends on it — PostgreSQL aborted with "infinite recursion detected in policy".
>   (US-218)
> - **CI had never run.** Every workflow triggered on `develop`/`main`; this
>   repository's default branch is `master`. (US-193)
> - **Android sync discarded data.** `SyncWorker` marked every pending locus SYNCED
>   without uploading anything. (US-194)
> - **Push was unwired end to end.** Nothing on iOS ever called
>   `registerForRemoteNotifications()`, and the server-side sender was a
>   `console.log`. (US-195, US-196)
>
> Treat "the checklist says done" as a claim to verify, not evidence.
"""


def build_section() -> str:
    stories = json.load(open(PRD))["userStories"]
    audit = [
        s for s in stories
        if s["id"].startswith("US-") and int(s["id"][3:]) >= FIRST_AUDIT_STORY
    ]
    audit.sort(key=lambda s: int(s["id"][3:]))

    done = [s for s in audit if s["passes"]]
    todo = [s for s in audit if not s["passes"]]

    lines = [START, "", PREAMBLE]

    lines.append(f"### Resolved ({len(done)})")
    lines.append("")
    for s in done:
        lines.append(f"- [x] **{s['id']}** — {s['title']}")
    lines.append("")

    if todo:
        lines.append(
            f"### Still open ({len(todo)}) — resolve or explicitly defer before launch"
        )
        lines.append("")
        for s in todo:
            lines.append(f"- [ ] **{s['id']}** — {s['title']}")
    else:
        lines.append("### Still open (0)")
        lines.append("")
        lines.append("All audit items resolved.")
    lines.append("")
    lines.append(EPILOGUE)

    return "\n".join(lines) + "\n---\n\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    current = open(CHECKLIST).read()
    start = current.index(START)
    end = current.index(END)
    updated = current[:start] + build_section() + current[end:]

    if args.check:
        if updated != current:
            print(
                "LAUNCH_CHECKLIST.md §4 is out of date with prd.json.\n"
                "Run: python3 scripts/sync-launch-checklist.py",
                file=sys.stderr,
            )
            return 1
        print("LAUNCH_CHECKLIST.md §4 is in sync with prd.json")
        return 0

    open(CHECKLIST, "w").write(updated)
    print("LAUNCH_CHECKLIST.md §4 regenerated from prd.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
