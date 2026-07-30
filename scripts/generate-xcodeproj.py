#!/usr/bin/env python3
"""Generate Lociate.xcodeproj/project.pbxproj from the on-disk source tree.

The project file was previously hand-maintained and drifted badly: 72 of 104
Swift sources had no target membership, there were no SPM package references
despite `import Supabase` / `import RevenueCat`, and neither the widget
extension nor the unit-test bundle existed as targets (US-185..US-188).

Running this script is idempotent — object IDs are derived from a hash of a
stable key, so regenerating without source changes produces a byte-identical
file. Add a Swift file to the tree, re-run, commit.

    python3 scripts/generate-xcodeproj.py            # write the project
    python3 scripts/generate-xcodeproj.py --check     # verify it is up to date

`--check` is what CI runs: it fails if the committed project does not match the
source tree, which is exactly the drift that broke the build before.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(REPO, "Lociate")
TESTS_DIR = os.path.join(REPO, "LociateTests")
PROJ_DIR = os.path.join(APP_DIR, "Lociate.xcodeproj")
PBXPROJ = os.path.join(PROJ_DIR, "project.pbxproj")
SCHEME = os.path.join(PROJ_DIR, "xcshareddata", "xcschemes", "Lociate.xcscheme")

APP = "Lociate"
WIDGET = "LociateWidget"
TESTS = "LociateTests"

BUNDLE_ID = "app.lociate.ios"
WIDGET_BUNDLE_ID = "app.lociate.ios.widget"
TESTS_BUNDLE_ID = "app.lociate.ios.tests"
DEPLOYMENT_TARGET = "17.0"
SWIFT_VERSION = "5.0"

# Sources shared between the app and the widget extension. The widget builds its
# own SwiftData container against the same schema, so it needs every @Model plus
# the distance helpers and the category presentation layer. Keep this list
# minimal — anything added here is compiled into the extension too, and widget
# extensions have a hard memory budget.
WIDGET_SHARED_SOURCES = [
    "Models/AuditLogEntry.swift",
    "Models/Household.swift",
    "Models/HouseholdMember.swift",
    "Models/Locus.swift",
    "Models/LocusCategory.swift",
    "Models/UserProfile.swift",
    "Utilities/AppConstants.swift",
    "Utilities/DesignSystem.swift",
    "Utilities/HaversineDistance.swift",
    "Utilities/ModelContainerConfiguration.swift",
    "Utilities/Theme.swift",
]

# Remote SPM dependencies. `products` are attached to the app target's Frameworks
# build phase; the widget and test bundles link nothing (the widget closure above
# deliberately avoids them, and tests link against the host app).
PACKAGES = [
    {
        "name": "supabase-swift",
        "url": "https://github.com/supabase-community/supabase-swift.git",
        "minimum": "2.5.1",
        "products": ["Supabase"],
    },
    {
        "name": "purchases-ios",
        "url": "https://github.com/RevenueCat/purchases-ios.git",
        "minimum": "4.43.0",
        "products": ["RevenueCat"],
    },
    {
        "name": "SwiftSDK",
        "url": "https://github.com/TelemetryDeck/SwiftSDK.git",
        "minimum": "2.2.0",
        "products": ["TelemetryDeck"],
    },
]

# Directories under Lociate/ whose Swift sources belong to the app target, in
# the order the groups should appear in Xcode's navigator.
APP_GROUP_ORDER = [
    "Models",
    "ViewModels",
    "Views",
    "Services",
    "Utilities",
    "Configuration",
]


def uid(kind: str, key: str) -> str:
    """Deterministic 24-hex-character Xcode object identifier."""
    return hashlib.sha256(f"{kind}\x00{key}".encode()).hexdigest()[:24].upper()


def file_type(name: str) -> str:
    return {
        ".swift": "sourcecode.swift",
        ".xcassets": "folder.assetcatalog",
        ".plist": "text.plist.xml",
        ".entitlements": "text.plist.entitlements",
        ".xcprivacy": "text.plist.xml",
        ".xcstrings": "text.json.xcstrings",
        ".md": "net.daringfireball.markdown",
    }.get(os.path.splitext(name)[1], "text")


def collect() -> dict:
    """Walk the source tree and bucket every file by target membership."""
    app_sources: dict[str, list[str]] = {}
    widget_sources: list[str] = []
    resources: list[str] = []

    for group in APP_GROUP_ORDER:
        base = os.path.join(APP_DIR, group)
        if not os.path.isdir(base):
            continue
        for root, dirs, names in os.walk(base):
            dirs.sort()
            rel_dir = os.path.relpath(root, APP_DIR)
            swift = sorted(n for n in names if n.endswith(".swift"))
            if swift:
                app_sources.setdefault(rel_dir, []).extend(
                    os.path.join(rel_dir, n).replace(os.sep, "/") for n in swift
                )

    widget_dir = os.path.join(APP_DIR, "Widget")
    widget_resources: list[str] = []
    if os.path.isdir(widget_dir):
        widget_sources = [
            f"Widget/{n}" for n in sorted(os.listdir(widget_dir)) if n.endswith(".swift")
        ]
        # An app extension is a separate bundle, so the containing app's privacy
        # manifest does not cover it (US-200).
        if os.path.exists(os.path.join(widget_dir, "PrivacyInfo.xcprivacy")):
            widget_resources.append("Widget/PrivacyInfo.xcprivacy")

    root_sources = [
        n for n in sorted(os.listdir(APP_DIR)) if n.endswith(".swift")
    ]

    for name in ("Assets.xcassets", "PrivacyInfo.xcprivacy", "Localizable.xcstrings"):
        if os.path.exists(os.path.join(APP_DIR, name)):
            resources.append(name)

    test_sources = []
    if os.path.isdir(TESTS_DIR):
        for root, dirs, names in os.walk(TESTS_DIR):
            dirs.sort()
            rel_dir = os.path.relpath(root, TESTS_DIR)
            for n in sorted(names):
                if n.endswith(".swift"):
                    rel = n if rel_dir == "." else os.path.join(rel_dir, n)
                    test_sources.append(rel.replace(os.sep, "/"))

    missing = [s for s in WIDGET_SHARED_SOURCES if not os.path.exists(os.path.join(APP_DIR, s))]
    if missing:
        raise SystemExit(
            "WIDGET_SHARED_SOURCES references files that do not exist:\n  "
            + "\n  ".join(missing)
        )

    return {
        "app_sources": app_sources,
        "root_sources": root_sources,
        "widget_sources": widget_sources,
        "widget_resources": widget_resources,
        "resources": resources,
        "test_sources": test_sources,
    }


class Writer:
    def __init__(self) -> None:
        self.parts: list[str] = []

    def w(self, text: str = "") -> None:
        self.parts.append(text)

    def __str__(self) -> str:
        return "\n".join(self.parts) + "\n"


COMMON_SETTINGS = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS", "YES"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "YES_AGGRESSIVE"),
    ("CLANG_CXX_LANGUAGE_STANDARD", '"gnu++20"'),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("CLANG_ENABLE_OBJC_WEAK", "YES"),
    ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
    ("CLANG_WARN_BOOL_CONVERSION", "YES"),
    ("CLANG_WARN_COMMA", "YES"),
    ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
    ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
    ("CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "YES_ERROR"),
    ("CLANG_WARN_DOCUMENTATION_COMMENTS", "YES"),
    ("CLANG_WARN_EMPTY_BODY", "YES"),
    ("CLANG_WARN_ENUM_CONVERSION", "YES"),
    ("CLANG_WARN_INFINITE_RECURSION", "YES"),
    ("CLANG_WARN_INT_CONVERSION", "YES"),
    ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
    ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_ROOT_CLASS", "YES_ERROR"),
    ("CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "YES"),
    ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
    ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
    ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
    ("CLANG_WARN_UNGUARDED_AVAILABILITY", "YES_AGGRESSIVE"),
    ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
    ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("ENABLE_USER_SCRIPT_SANDBOXING", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("GCC_WARN_64_TO_32_BIT_CONVERSION", "YES"),
    ("GCC_WARN_ABOUT_RETURN_TYPE", "YES_ERROR"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("GCC_WARN_UNINITIALIZED_AUTOS", "YES_AGGRESSIVE"),
    ("GCC_WARN_UNUSED_FUNCTION", "YES"),
    ("GCC_WARN_UNUSED_VARIABLE", "YES"),
    ("IPHONEOS_DEPLOYMENT_TARGET", DEPLOYMENT_TARGET),
    ("LOCALIZATION_PREFERS_STRING_CATALOGS", "YES"),
    ("MTL_FAST_MATH", "YES"),
    ("SDKROOT", "iphoneos"),
    ("SWIFT_VERSION", SWIFT_VERSION),
]

PROJECT_DEBUG_EXTRA = [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_DYNAMIC_NO_PIC", "NO"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("GCC_PREPROCESSOR_DEFINITIONS", '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)'),
    ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"'),
    ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"'),
]

PROJECT_RELEASE_EXTRA = [
    ("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("VALIDATE_PRODUCT", "YES"),
]

APP_TARGET_SETTINGS = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("DEVELOPMENT_TEAM", '""'),
    ("ENABLE_PREVIEWS", "YES"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("INFOPLIST_FILE", "Info.plist"),
    ("INFOPLIST_KEY_CFBundleDisplayName", "Lociate"),
    ("INFOPLIST_KEY_LSApplicationCategoryType", '"public.app-category.lifestyle"'),
    ("INFOPLIST_KEY_UIApplicationSceneManifest_Generation", "YES"),
    ("INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents", "YES"),
    ("INFOPLIST_KEY_UILaunchScreen_Generation", "YES"),
    (
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad",
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
        'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    ),
    (
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone",
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft '
        'UIInterfaceOrientationLandscapeRight"',
    ),
    (
        "LD_RUNPATH_SEARCH_PATHS",
        '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
    ),
    ("MARKETING_VERSION", "1.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
    ("SUPPORTS_MACCATALYST", "NO"),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("TARGETED_DEVICE_FAMILY", '"1,2"'),
]

WIDGET_TARGET_SETTINGS = [
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME", "WidgetBackground"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("DEVELOPMENT_TEAM", '""'),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("INFOPLIST_FILE", "Widget/Info.plist"),
    ("INFOPLIST_KEY_CFBundleDisplayName", '"Nearby Loci"'),
    ("INFOPLIST_KEY_NSHumanReadableCopyright", '""'),
    (
        "LD_RUNPATH_SEARCH_PATHS",
        '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n'
        '\t\t\t\t\t"@executable_path/../../Frameworks",\n\t\t\t\t)',
    ),
    ("MARKETING_VERSION", "1.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", WIDGET_BUNDLE_ID),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SKIP_INSTALL", "YES"),
    ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("TARGETED_DEVICE_FAMILY", '"1,2"'),
]

TESTS_TARGET_SETTINGS = [
    ("BUNDLE_LOADER", '"$(TEST_HOST)"'),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("DEVELOPMENT_TEAM", '""'),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    (
        "LD_RUNPATH_SEARCH_PATHS",
        '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n'
        '\t\t\t\t\t"@loader_path/Frameworks",\n\t\t\t\t)',
    ),
    ("MARKETING_VERSION", "1.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", TESTS_BUNDLE_ID),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
    (
        "TEST_HOST",
        '"$(BUILT_PRODUCTS_DIR)/Lociate.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Lociate"',
    ),
    ("TARGETED_DEVICE_FAMILY", '"1,2"'),
]


def entitlements_settings(config: str) -> list[tuple[str, str]]:
    """US-202: production aps-environment for Release, development for Debug."""
    suffix = "Debug" if config == "Debug" else "Release"
    return [("CODE_SIGN_ENTITLEMENTS", f"Lociate.{suffix}.entitlements")]


def widget_entitlements_settings(config: str) -> list[tuple[str, str]]:
    suffix = "Debug" if config == "Debug" else "Release"
    return [("CODE_SIGN_ENTITLEMENTS", f"Widget/LociateWidget.{suffix}.entitlements")]


def emit_settings(out: Writer, settings: list[tuple[str, str]]) -> None:
    for key, value in sorted(settings):
        out.w(f"\t\t\t\t{key} = {value};")


def generate(tree: dict) -> str:
    app_sources = tree["app_sources"]
    root_sources = tree["root_sources"]
    widget_sources = tree["widget_sources"]
    resources = tree["resources"]
    widget_resources = tree["widget_resources"]
    test_sources = tree["test_sources"]

    # Every path is relative to Lociate/ (the project's SOURCE_ROOT).
    all_app_swift = list(root_sources)
    for group in APP_GROUP_ORDER:
        for rel_dir in sorted(app_sources):
            if rel_dir == group or rel_dir.startswith(group + os.sep):
                all_app_swift.extend(app_sources[rel_dir])

    widget_member_paths = widget_sources + WIDGET_SHARED_SOURCES

    out = Writer()
    out.w("// !$*UTF8*$!")
    out.w("{")
    out.w("\tarchiveVersion = 1;")
    out.w("\tclasses = {")
    out.w("\t};")
    out.w("\tobjectVersion = 56;")
    out.w("\tobjects = {")
    out.w()

    # ── PBXBuildFile ───────────────────────────────────────────────────────
    out.w("/* Begin PBXBuildFile section */")
    build_files: list[tuple[str, str, str, str]] = []  # (id, name, phase, fileRefId)
    for path in all_app_swift:
        name = os.path.basename(path)
        build_files.append(
            (uid("bf-app", path), name, "Sources", uid("fr", path))
        )
    for path in resources:
        build_files.append(
            (uid("bf-res", path), os.path.basename(path), "Resources", uid("fr", path))
        )
    for path in widget_member_paths:
        name = os.path.basename(path)
        build_files.append(
            (uid("bf-widget", path), name, "Sources", uid("fr", path))
        )
    for path in widget_resources:
        build_files.append(
            (uid("bf-widget-res", path), os.path.basename(path), "Resources", uid("fr", path))
        )
    for path in test_sources:
        build_files.append(
            (uid("bf-test", path), os.path.basename(path), "Sources", uid("fr-test", path))
        )
    for bf_id, name, phase, fr_id in build_files:
        out.w(
            f"\t\t{bf_id} /* {name} in {phase} */ = {{isa = PBXBuildFile; "
            f"fileRef = {fr_id} /* {name} */; }};"
        )
    # Embedded widget product.
    out.w(
        f"\t\t{uid('bf', 'embed-widget')} /* {WIDGET}.appex in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {uid('product', WIDGET)} /* {WIDGET}.appex */; "
        'settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };'
    )
    # SPM products linked into the app.
    for pkg in PACKAGES:
        for product in pkg["products"]:
            out.w(
                f"\t\t{uid('bf-pkg', product)} /* {product} in Frameworks */ = "
                f"{{isa = PBXBuildFile; productRef = {uid('pkg-product', product)} "
                f"/* {product} */; }};"
            )
    out.w("/* End PBXBuildFile section */")
    out.w()

    # ── PBXContainerItemProxy ─────────────────────────────────────────────
    out.w("/* Begin PBXContainerItemProxy section */")
    for dep_target in (WIDGET, APP):
        out.w(f"\t\t{uid('proxy', dep_target)} /* PBXContainerItemProxy */ = {{")
        out.w("\t\t\tisa = PBXContainerItemProxy;")
        out.w(f"\t\t\tcontainerPortal = {uid('project', 'Lociate')} /* Project object */;")
        out.w("\t\t\tproxyType = 1;")
        out.w(f"\t\t\tremoteGlobalIDString = {uid('target', dep_target)};")
        out.w(f"\t\t\tremoteInfo = {dep_target};")
        out.w("\t\t};")
    out.w("/* End PBXContainerItemProxy section */")
    out.w()

    # ── PBXCopyFilesBuildPhase ────────────────────────────────────────────
    out.w("/* Begin PBXCopyFilesBuildPhase section */")
    out.w(f"\t\t{uid('phase', 'embed')} /* Embed Foundation Extensions */ = {{")
    out.w("\t\t\tisa = PBXCopyFilesBuildPhase;")
    out.w("\t\t\tbuildActionMask = 2147483647;")
    out.w("\t\t\tdstPath = \"\";")
    out.w("\t\t\tdstSubfolderSpec = 13;")
    out.w("\t\t\tfiles = (")
    out.w(
        f"\t\t\t\t{uid('bf', 'embed-widget')} /* {WIDGET}.appex in "
        "Embed Foundation Extensions */,"
    )
    out.w("\t\t\t);")
    out.w('\t\t\tname = "Embed Foundation Extensions";')
    out.w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.w("\t\t};")
    out.w("/* End PBXCopyFilesBuildPhase section */")
    out.w()

    # ── PBXFileReference ──────────────────────────────────────────────────
    out.w("/* Begin PBXFileReference section */")
    out.w(
        f"\t\t{uid('product', APP)} /* {APP}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; "
        "sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    out.w(
        f"\t\t{uid('product', WIDGET)} /* {WIDGET}.appex */ = {{isa = PBXFileReference; "
        'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
        f"path = {WIDGET}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    out.w(
        f"\t\t{uid('product', TESTS)} /* {TESTS}.xctest */ = {{isa = PBXFileReference; "
        'explicitFileType = wrapper.cfbundle; includeInIndex = 0; '
        f"path = {TESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )

    loose_files = [
        "Info.plist",
        "Lociate.Debug.entitlements",
        "Lociate.Release.entitlements",
        ".swiftlint.yml",
    ]
    widget_loose = list(widget_resources) + [
        "Widget/Info.plist",
        "Widget/LociateWidget.Debug.entitlements",
        "Widget/LociateWidget.Release.entitlements",
    ]
    for path in sorted(
        set(all_app_swift + resources + widget_member_paths + loose_files + widget_loose)
    ):
        name = os.path.basename(path)
        out.w(
            f"\t\t{uid('fr', path)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(name)}; path = {name}; "
            'sourceTree = "<group>"; };'
        )
    for path in test_sources:
        name = os.path.basename(path)
        out.w(
            f"\t\t{uid('fr-test', path)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(name)}; path = {name}; "
            'sourceTree = "<group>"; };'
        )
    out.w("/* End PBXFileReference section */")
    out.w()

    # ── PBXFrameworksBuildPhase ───────────────────────────────────────────
    out.w("/* Begin PBXFrameworksBuildPhase section */")
    for target, products in (
        (APP, [p for pkg in PACKAGES for p in pkg["products"]]),
        (WIDGET, []),
        (TESTS, []),
    ):
        out.w(f"\t\t{uid('phase', f'frameworks-{target}')} /* Frameworks */ = {{")
        out.w("\t\t\tisa = PBXFrameworksBuildPhase;")
        out.w("\t\t\tbuildActionMask = 2147483647;")
        out.w("\t\t\tfiles = (")
        for product in products:
            out.w(f"\t\t\t\t{uid('bf-pkg', product)} /* {product} in Frameworks */,")
        out.w("\t\t\t);")
        out.w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.w("\t\t};")
    out.w("/* End PBXFrameworksBuildPhase section */")
    out.w()

    # ── PBXGroup ──────────────────────────────────────────────────────────
    out.w("/* Begin PBXGroup section */")

    def group(gid: str, name: str, children: list[str], path: str | None) -> None:
        out.w(f"\t\t{gid} /* {name} */ = {{")
        out.w("\t\t\tisa = PBXGroup;")
        out.w("\t\t\tchildren = (")
        for child in children:
            out.w(f"\t\t\t\t{child}")
        out.w("\t\t\t);")
        if path is None:
            out.w(f"\t\t\tname = {name};")
        else:
            out.w(f"\t\t\tpath = {path};")
        out.w('\t\t\tsourceTree = "<group>";')
        out.w("\t\t};")

    # Nested source groups mirroring the directory layout.
    dirs_by_parent: dict[str, set[str]] = {}
    for rel_dir in app_sources:
        parts = rel_dir.split(os.sep)
        for i in range(len(parts)):
            parent = os.sep.join(parts[:i]) if i else ""
            dirs_by_parent.setdefault(parent, set()).add(os.sep.join(parts[: i + 1]))

    def emit_dir_group(rel_dir: str) -> None:
        children: list[str] = []
        for sub in sorted(dirs_by_parent.get(rel_dir, ())):
            children.append(f"{uid('group', sub)} /* {os.path.basename(sub)} */,")
        for path in app_sources.get(rel_dir, []):
            name = os.path.basename(path)
            children.append(f"{uid('fr', path)} /* {name} */,")
        group(
            uid("group", rel_dir),
            os.path.basename(rel_dir),
            children,
            os.path.basename(rel_dir),
        )
        for sub in sorted(dirs_by_parent.get(rel_dir, ())):
            emit_dir_group(sub)

    for top in sorted(dirs_by_parent.get("", ())):
        emit_dir_group(top)

    widget_children = [
        f"{uid('fr', p)} /* {os.path.basename(p)} */,"
        for p in widget_sources + widget_resources
    ] + [
        f"{uid('fr', 'Widget/Info.plist')} /* Info.plist */,",
        f"{uid('fr', 'Widget/LociateWidget.Debug.entitlements')} "
        "/* LociateWidget.Debug.entitlements */,",
        f"{uid('fr', 'Widget/LociateWidget.Release.entitlements')} "
        "/* LociateWidget.Release.entitlements */,",
    ]
    group(uid("group", "Widget"), "Widget", widget_children, "Widget")

    test_children = [
        f"{uid('fr-test', p)} /* {os.path.basename(p)} */," for p in test_sources
    ]
    group(uid("group", "tests"), TESTS, test_children, f"../{TESTS}")

    root_children = [
        f"{uid('fr', p)} /* {p} */," for p in root_sources
    ]
    root_children += [f"{uid('group', g)} /* {g} */," for g in APP_GROUP_ORDER if g in app_sources or any(d.split(os.sep)[0] == g for d in app_sources)]
    root_children.append(f"{uid('group', 'Widget')} /* Widget */,")
    root_children += [f"{uid('fr', p)} /* {p} */," for p in resources]
    root_children += [
        f"{uid('fr', 'Info.plist')} /* Info.plist */,",
        f"{uid('fr', 'Lociate.Debug.entitlements')} /* Lociate.Debug.entitlements */,",
        f"{uid('fr', 'Lociate.Release.entitlements')} /* Lociate.Release.entitlements */,",
        f"{uid('fr', '.swiftlint.yml')} /* .swiftlint.yml */,",
    ]
    group(uid("group", "app-root"), APP, root_children, None)

    products_children = [
        f"{uid('product', APP)} /* {APP}.app */,",
        f"{uid('product', WIDGET)} /* {WIDGET}.appex */,",
        f"{uid('product', TESTS)} /* {TESTS}.xctest */,",
    ]
    group(uid("group", "products"), "Products", products_children, None)

    main_children = [
        f"{uid('group', 'app-root')} /* {APP} */,",
        f"{uid('group', 'tests')} /* {TESTS} */,",
        f"{uid('group', 'products')} /* Products */,",
    ]
    out.w(f"\t\t{uid('group', 'main')} = {{")
    out.w("\t\t\tisa = PBXGroup;")
    out.w("\t\t\tchildren = (")
    for child in main_children:
        out.w(f"\t\t\t\t{child}")
    out.w("\t\t\t);")
    out.w('\t\t\tsourceTree = "<group>";')
    out.w("\t\t};")
    out.w("/* End PBXGroup section */")
    out.w()

    # ── PBXNativeTarget ───────────────────────────────────────────────────
    out.w("/* Begin PBXNativeTarget section */")

    def native_target(
        name: str,
        phases: list[str],
        deps: list[str],
        product_ref: str,
        product_type: str,
        packages: list[str],
    ) -> None:
        out.w(f"\t\t{uid('target', name)} /* {name} */ = {{")
        out.w("\t\t\tisa = PBXNativeTarget;")
        out.w(
            f"\t\t\tbuildConfigurationList = {uid('cfglist', name)} "
            f'/* Build configuration list for PBXNativeTarget "{name}" */;'
        )
        out.w("\t\t\tbuildPhases = (")
        for phase in phases:
            out.w(f"\t\t\t\t{phase}")
        out.w("\t\t\t);")
        out.w("\t\t\tbuildRules = (")
        out.w("\t\t\t);")
        out.w("\t\t\tdependencies = (")
        for dep in deps:
            out.w(f"\t\t\t\t{dep}")
        out.w("\t\t\t);")
        out.w(f"\t\t\tname = {name};")
        if packages:
            out.w("\t\t\tpackageProductDependencies = (")
            for product in packages:
                out.w(f"\t\t\t\t{uid('pkg-product', product)} /* {product} */,")
            out.w("\t\t\t);")
        out.w(f"\t\t\tproductName = {name};")
        out.w(f"\t\t\tproductReference = {product_ref};")
        out.w(f'\t\t\tproductType = "{product_type}";')
        out.w("\t\t};")

    native_target(
        APP,
        [
            f"{uid('phase', f'sources-{APP}')} /* Sources */,",
            f"{uid('phase', f'frameworks-{APP}')} /* Frameworks */,",
            f"{uid('phase', 'resources')} /* Resources */,",
            f"{uid('phase', 'embed')} /* Embed Foundation Extensions */,",
        ],
        [f"{uid('dep', WIDGET)} /* PBXTargetDependency */,"],
        f"{uid('product', APP)} /* {APP}.app */",
        "com.apple.product-type.application",
        [p for pkg in PACKAGES for p in pkg["products"]],
    )
    native_target(
        WIDGET,
        [
            f"{uid('phase', f'sources-{WIDGET}')} /* Sources */,",
            f"{uid('phase', f'frameworks-{WIDGET}')} /* Frameworks */,",
            f"{uid('phase', 'resources-widget')} /* Resources */,",
        ],
        [],
        f"{uid('product', WIDGET)} /* {WIDGET}.appex */",
        "com.apple.product-type.app-extension",
        [],
    )
    native_target(
        TESTS,
        [
            f"{uid('phase', f'sources-{TESTS}')} /* Sources */,",
            f"{uid('phase', f'frameworks-{TESTS}')} /* Frameworks */,",
        ],
        [f"{uid('dep', APP)} /* PBXTargetDependency */,"],
        f"{uid('product', TESTS)} /* {TESTS}.xctest */",
        "com.apple.product-type.bundle.unit-test",
        [],
    )
    out.w("/* End PBXNativeTarget section */")
    out.w()

    # ── PBXProject ────────────────────────────────────────────────────────
    out.w("/* Begin PBXProject section */")
    out.w(f"\t\t{uid('project', 'Lociate')} /* Project object */ = {{")
    out.w("\t\t\tisa = PBXProject;")
    out.w("\t\t\tattributes = {")
    out.w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    out.w("\t\t\t\tLastSwiftUpdateCheck = 1540;")
    out.w("\t\t\t\tLastUpgradeCheck = 1540;")
    out.w("\t\t\t\tTargetAttributes = {")
    for name in (APP, WIDGET, TESTS):
        out.w(f"\t\t\t\t\t{uid('target', name)} = {{")
        out.w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;")
        if name == TESTS:
            out.w(f"\t\t\t\t\t\tTestTargetID = {uid('target', APP)};")
        out.w("\t\t\t\t\t};")
    out.w("\t\t\t\t};")
    out.w("\t\t\t};")
    out.w(
        f"\t\t\tbuildConfigurationList = {uid('cfglist', 'project')} "
        '/* Build configuration list for PBXProject "Lociate" */;'
    )
    out.w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    out.w("\t\t\tdevelopmentRegion = en;")
    out.w("\t\t\thasScannedForEncodings = 0;")
    out.w("\t\t\tknownRegions = (")
    out.w("\t\t\t\ten,")
    out.w("\t\t\t\tBase,")
    out.w("\t\t\t);")
    out.w(f"\t\t\tmainGroup = {uid('group', 'main')};")
    out.w("\t\t\tpackageReferences = (")
    for pkg in PACKAGES:
        out.w(
            f"\t\t\t\t{uid('pkg', pkg['name'])} /* XCRemoteSwiftPackageReference "
            f"\"{pkg['name']}\" */,"
        )
    out.w("\t\t\t);")
    out.w(f"\t\t\tproductRefGroup = {uid('group', 'products')} /* Products */;")
    out.w('\t\t\tprojectDirPath = "";')
    out.w('\t\t\tprojectRoot = "";')
    out.w("\t\t\ttargets = (")
    for name in (APP, WIDGET, TESTS):
        out.w(f"\t\t\t\t{uid('target', name)} /* {name} */,")
    out.w("\t\t\t);")
    out.w("\t\t};")
    out.w("/* End PBXProject section */")
    out.w()

    # ── PBXResourcesBuildPhase ────────────────────────────────────────────
    out.w("/* Begin PBXResourcesBuildPhase section */")
    for phase_key, paths, prefix in (
        ("resources", resources, "bf-res"),
        ("resources-widget", widget_resources, "bf-widget-res"),
    ):
        out.w(f"\t\t{uid('phase', phase_key)} /* Resources */ = {{")
        out.w("\t\t\tisa = PBXResourcesBuildPhase;")
        out.w("\t\t\tbuildActionMask = 2147483647;")
        out.w("\t\t\tfiles = (")
        for path in paths:
            out.w(
                f"\t\t\t\t{uid(prefix, path)} /* {os.path.basename(path)} in Resources */,"
            )
        out.w("\t\t\t);")
        out.w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.w("\t\t};")
    out.w("/* End PBXResourcesBuildPhase section */")
    out.w()

    # ── PBXSourcesBuildPhase ──────────────────────────────────────────────
    out.w("/* Begin PBXSourcesBuildPhase section */")
    for target, paths, prefix in (
        (APP, all_app_swift, "bf-app"),
        (WIDGET, widget_member_paths, "bf-widget"),
        (TESTS, test_sources, "bf-test"),
    ):
        out.w(f"\t\t{uid('phase', f'sources-{target}')} /* Sources */ = {{")
        out.w("\t\t\tisa = PBXSourcesBuildPhase;")
        out.w("\t\t\tbuildActionMask = 2147483647;")
        out.w("\t\t\tfiles = (")
        for path in paths:
            out.w(
                f"\t\t\t\t{uid(prefix, path)} /* {os.path.basename(path)} in Sources */,"
            )
        out.w("\t\t\t);")
        out.w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.w("\t\t};")
    out.w("/* End PBXSourcesBuildPhase section */")
    out.w()

    # ── PBXTargetDependency ───────────────────────────────────────────────
    out.w("/* Begin PBXTargetDependency section */")
    for dep_target in (WIDGET, APP):
        out.w(f"\t\t{uid('dep', dep_target)} /* PBXTargetDependency */ = {{")
        out.w("\t\t\tisa = PBXTargetDependency;")
        out.w(f"\t\t\ttarget = {uid('target', dep_target)} /* {dep_target} */;")
        out.w(
            f"\t\t\ttargetProxy = {uid('proxy', dep_target)} /* PBXContainerItemProxy */;"
        )
        out.w("\t\t};")
    out.w("/* End PBXTargetDependency section */")
    out.w()

    # ── XCBuildConfiguration ──────────────────────────────────────────────
    out.w("/* Begin XCBuildConfiguration section */")

    def build_config(scope: str, config: str, settings: list[tuple[str, str]]) -> None:
        out.w(f"\t\t{uid('cfg', f'{scope}-{config}')} /* {config} */ = {{")
        out.w("\t\t\tisa = XCBuildConfiguration;")
        out.w("\t\t\tbuildSettings = {")
        emit_settings(out, settings)
        out.w("\t\t\t};")
        out.w(f"\t\t\tname = {config};")
        out.w("\t\t};")

    build_config("project", "Debug", COMMON_SETTINGS + PROJECT_DEBUG_EXTRA)
    build_config("project", "Release", COMMON_SETTINGS + PROJECT_RELEASE_EXTRA)
    for config in ("Debug", "Release"):
        build_config(APP, config, APP_TARGET_SETTINGS + entitlements_settings(config))
        build_config(
            WIDGET, config, WIDGET_TARGET_SETTINGS + widget_entitlements_settings(config)
        )
        build_config(TESTS, config, TESTS_TARGET_SETTINGS)
    out.w("/* End XCBuildConfiguration section */")
    out.w()

    # ── XCConfigurationList ───────────────────────────────────────────────
    out.w("/* Begin XCConfigurationList section */")
    for scope, label in (
        ("project", 'PBXProject "Lociate"'),
        (APP, f'PBXNativeTarget "{APP}"'),
        (WIDGET, f'PBXNativeTarget "{WIDGET}"'),
        (TESTS, f'PBXNativeTarget "{TESTS}"'),
    ):
        key = "project" if scope == "project" else scope
        out.w(
            f"\t\t{uid('cfglist', key)} /* Build configuration list for {label} */ = {{"
        )
        out.w("\t\t\tisa = XCConfigurationList;")
        out.w("\t\t\tbuildConfigurations = (")
        for config in ("Debug", "Release"):
            out.w(f"\t\t\t\t{uid('cfg', f'{scope}-{config}')} /* {config} */,")
        out.w("\t\t\t);")
        out.w("\t\t\tdefaultConfigurationIsVisible = 0;")
        out.w("\t\t\tdefaultConfigurationName = Release;")
        out.w("\t\t};")
    out.w("/* End XCConfigurationList section */")
    out.w()

    # ── XCRemoteSwiftPackageReference ─────────────────────────────────────
    out.w("/* Begin XCRemoteSwiftPackageReference section */")
    for pkg in PACKAGES:
        out.w(
            f"\t\t{uid('pkg', pkg['name'])} /* XCRemoteSwiftPackageReference "
            f"\"{pkg['name']}\" */ = {{"
        )
        out.w("\t\t\tisa = XCRemoteSwiftPackageReference;")
        out.w(f'\t\t\trepositoryURL = "{pkg["url"]}";')
        out.w("\t\t\trequirement = {")
        out.w("\t\t\t\tkind = upToNextMajorVersion;")
        out.w(f'\t\t\t\tminimumVersion = "{pkg["minimum"]}";')
        out.w("\t\t\t};")
        out.w("\t\t};")
    out.w("/* End XCRemoteSwiftPackageReference section */")
    out.w()

    # ── XCSwiftPackageProductDependency ───────────────────────────────────
    out.w("/* Begin XCSwiftPackageProductDependency section */")
    for pkg in PACKAGES:
        for product in pkg["products"]:
            out.w(f"\t\t{uid('pkg-product', product)} /* {product} */ = {{")
            out.w("\t\t\tisa = XCSwiftPackageProductDependency;")
            out.w(
                f"\t\t\tpackage = {uid('pkg', pkg['name'])} "
                f"/* XCRemoteSwiftPackageReference \"{pkg['name']}\" */;"
            )
            out.w(f"\t\t\tproductName = {product};")
            out.w("\t\t};")
    out.w("/* End XCSwiftPackageProductDependency section */")
    out.w()

    out.w("\t};")
    out.w(f"\trootObject = {uid('project', 'Lociate')} /* Project object */;")
    out.w("}")
    return str(out)


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "Lociate.app"
               BlueprintName = "Lociate"
               ReferencedContainer = "container:Lociate.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{widget_target}"
               BuildableName = "LociateWidget.appex"
               BlueprintName = "LociateWidget"
               ReferencedContainer = "container:Lociate.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{tests_target}"
               BuildableName = "LociateTests.xctest"
               BlueprintName = "LociateTests"
               ReferencedContainer = "container:Lociate.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "Lociate.app"
            BlueprintName = "Lociate"
            ReferencedContainer = "container:Lociate.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "Lociate.app"
            BlueprintName = "Lociate"
            ReferencedContainer = "container:Lociate.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def generate_scheme() -> str:
    return SCHEME_TEMPLATE.format(
        app_target=uid("target", APP),
        widget_target=uid("target", WIDGET),
        tests_target=uid("target", TESTS),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if the committed project is out of date",
    )
    args = parser.parse_args()

    tree = collect()
    pbxproj = generate(tree)
    scheme = generate_scheme()

    targets = [(PBXPROJ, pbxproj), (SCHEME, scheme)]

    if args.check:
        stale = []
        for path, content in targets:
            current = open(path).read() if os.path.exists(path) else None
            if current != content:
                stale.append(os.path.relpath(path, REPO))
        if stale:
            print("Xcode project is out of date with the source tree:", file=sys.stderr)
            for path in stale:
                print(f"  {path}", file=sys.stderr)
            print(
                "\nRun: python3 scripts/generate-xcodeproj.py && git add -A Lociate/Lociate.xcodeproj",
                file=sys.stderr,
            )
            return 1
        n = sum(len(v) for v in tree["app_sources"].values()) + len(tree["root_sources"])
        print(f"Xcode project up to date ({n} app sources, "
              f"{len(tree['widget_sources'])} widget sources, "
              f"{len(tree['test_sources'])} test sources)")
        return 0

    for path, content in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(content)
        print(f"wrote {os.path.relpath(path, REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
