#!/usr/bin/env python3
"""Rasterize the Lociate brand mark into the PNGs the stores require.

US-201: AppIcon.appiconset contained only AppIcon.svg. Xcode rejects SVG for the
marketing icon, so archiving and App Store upload both fail. The Play Store
listing also needs a 512x512 PNG that no vector resource can satisfy.

The SVG stays the single source of truth — run this after editing it so the brand
never drifts between platforms:

    python3 scripts/generate-app-icons.py
    python3 scripts/generate-app-icons.py --check   # verify committed PNGs match

Requires cairosvg and pillow (`pip install cairosvg pillow`).
"""

from __future__ import annotations

import argparse
import io
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Source artwork lives outside the asset catalog: an unreferenced file inside an
# .appiconset makes Xcode emit an "unassigned child" warning on every build.
APP_ICON_SVG = os.path.join(REPO, "design", "AppIcon.svg")
LAUNCH_ICON_SVG = os.path.join(REPO, "design", "LaunchIcon.svg")
APPICON_DIR = os.path.join(REPO, "Lociate", "Assets.xcassets", "AppIcon.appiconset")
LAUNCH_DIR = os.path.join(REPO, "Lociate", "Assets.xcassets", "LaunchIcon.imageset")
STORE_DIR = os.path.join(REPO, "Lociate", "fastlane", "metadata", "store-assets")

# The iOS 17 asset catalog takes a single 1024pt universal icon; the system
# derives every other size. The launch icon is used at up to 3x of 180pt.
OUTPUTS = [
    (APPICON_DIR, "AppIcon-1024.png", 1024, False, APP_ICON_SVG),
    # The launch mark is a separate white-on-transparent variant, so it must be
    # rendered from its own source rather than cropped out of the app icon.
    (LAUNCH_DIR, "LaunchIcon.png", 180, True, LAUNCH_ICON_SVG),
    (LAUNCH_DIR, "LaunchIcon@2x.png", 360, True, LAUNCH_ICON_SVG),
    (LAUNCH_DIR, "LaunchIcon@3x.png", 540, True, LAUNCH_ICON_SVG),
    # Play Store listing icon (referenced by US-204).
    (STORE_DIR, "play-store-icon-512.png", 512, False, APP_ICON_SVG),
]


def render(source: str, size: int, keep_alpha: bool) -> bytes:
    import cairosvg
    from PIL import Image

    raw = cairosvg.svg2png(url=source, output_width=size, output_height=size)
    image = Image.open(io.BytesIO(raw)).convert("RGBA")

    if not keep_alpha:
        # Apple rejects a marketing icon with an alpha channel, and Play requires
        # 32-bit PNG with no transparency for the listing icon. Flatten onto the
        # brand blue so the rounded SVG corners do not turn black.
        background = Image.new("RGBA", image.size, (37, 99, 235, 255))
        image = Image.alpha_composite(background, image).convert("RGB")

    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


APPICON_CONTENTS = """{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

LAUNCHICON_CONTENTS = """{
  "images" : [
    {
      "filename" : "LaunchIcon.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "LaunchIcon@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "LaunchIcon@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify without writing")
    args = parser.parse_args()

    for source in (APP_ICON_SVG, LAUNCH_ICON_SVG):
        if not os.path.exists(source):
            print(f"missing source artwork: {source}", file=sys.stderr)
            return 1

    targets: list[tuple[str, bytes]] = []
    for directory, name, size, keep_alpha, source in OUTPUTS:
        targets.append((os.path.join(directory, name), render(source, size, keep_alpha)))
    targets.append((os.path.join(APPICON_DIR, "Contents.json"), APPICON_CONTENTS.encode()))
    targets.append((os.path.join(LAUNCH_DIR, "Contents.json"), LAUNCHICON_CONTENTS.encode()))

    if args.check:
        stale = [
            os.path.relpath(path, REPO)
            for path, content in targets
            if not os.path.exists(path) or open(path, "rb").read() != content
        ]
        if stale:
            print("Generated icons are out of date with design/*.svg:", file=sys.stderr)
            for path in stale:
                print(f"  {path}", file=sys.stderr)
            print("\nRun: python3 scripts/generate-app-icons.py", file=sys.stderr)
            return 1
        print(f"Icons up to date ({len(OUTPUTS)} PNGs)")
        return 0

    for path, content in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(content)
        print(f"wrote {os.path.relpath(path, REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
