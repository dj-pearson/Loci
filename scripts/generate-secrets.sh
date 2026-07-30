#!/bin/bash
# generate-secrets.sh — Generates platform secret files from environment variables.
# Used by GitHub Actions during CI/CD. For local dev, copy the .example files.
#
# Usage:
#   scripts/generate-secrets.sh              # generate iOS + Android (skip whichever
#                                              has no env vars set)
#   scripts/generate-secrets.sh --ios        # iOS only (fail if iOS vars missing)
#   scripts/generate-secrets.sh --android    # Android only (fail if Android vars missing)
#   scripts/generate-secrets.sh --all        # both, fail if either set is incomplete
#
# iOS required environment variables:
#   SUPABASE_URL             — Production Supabase URL
#   SUPABASE_ANON_KEY        — Production Supabase anonymous key
#   REVENUECAT_API_KEY       — RevenueCat Apple API key
#   TELEMETRYDECK_APP_ID     — TelemetryDeck app identifier
#
# iOS optional environment variables (emitted empty if unset):
#   CERT_PIN_HASH            — Primary certificate pin (SPKI SHA-256, base64). Empty
#                              disables pinning; the release workflows require it.
#   CERT_BACKUP_PIN_HASH     — Backup certificate pin (defaults to Let's Encrypt)
#   REQUEST_SIGNING_KEY      — HMAC-SHA256 secret for request signing (optional)
#   SENTRY_DSN               — Crash reporting DSN (optional; empty disables it)
#
# Android required environment variables:
#   SUPABASE_URL             — Production Supabase URL (shared with iOS)
#   SUPABASE_ANON_KEY        — Production Supabase anonymous key (shared with iOS)
#   MAPS_API_KEY             — Google Maps SDK for Android API key
#
# Android optional environment variables (emitted empty if unset):
#   CERT_PIN_HASH            — Primary certificate pin (SPKI SHA-256, base64)
#   CERT_BACKUP_PIN_HASH     — Backup certificate pin
#   REQUEST_SIGNING_KEY      — HMAC-SHA256 secret for request signing (shared with iOS)
#   SENTRY_DSN               — Crash reporting DSN (shared with iOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_OUTPUT="$REPO_ROOT/Lociate/Configuration/BuildSecrets.swift"
ANDROID_OUTPUT="$REPO_ROOT/android/local.properties"

# ---------------------------------------------------------------------------
# Parse mode
# ---------------------------------------------------------------------------
MODE="auto"
case "${1:-}" in
    --ios)     MODE="ios" ;;
    --android) MODE="android" ;;
    --all)     MODE="all" ;;
    "")        MODE="auto" ;;
    *)
        echo "Unknown flag: $1" >&2
        echo "Usage: $0 [--ios|--android|--all]" >&2
        exit 2
        ;;
esac

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# CERT_PIN_HASH is deliberately NOT here. An empty pin hash has a defined meaning —
# certificate pinning off — which is why `BuildSecretsValidator` classes it as
# non-critical and the Android list omits it. Requiring it made the CI iOS build
# unable to pass at all, because ci.yml exports it empty on purpose. Whether a
# *shipped* build may have pinning off is a release question, and release.yml and
# testflight.yml now assert it explicitly.
ios_required=(
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "REVENUECAT_API_KEY"
    "TELEMETRYDECK_APP_ID"
)

android_required=(
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "MAPS_API_KEY"
)

# US-210: refuse to write a secret file to a path git is tracking. The previous
# `Loci/Configuration/BuildSecrets.swift` was committed because .gitignore named
# one hardcoded path and the rename moved the real one — this guard makes that
# class of mistake fail loudly instead of leaking credentials into a commit.
assert_untracked() {
    local target=$1
    local rel
    rel="$(realpath --relative-to="$REPO_ROOT" "$target")"

    if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        return 0  # not a git checkout (e.g. a release tarball); nothing to guard
    fi

    if git -C "$REPO_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
        echo "ERROR: refusing to write secrets to '$rel' — that path is tracked by git." >&2
        echo "Remove it from the index (git rm --cached '$rel') and confirm it is" >&2
        echo "covered by .gitignore before running this script again." >&2
        exit 1
    fi

    if ! git -C "$REPO_ROOT" check-ignore -q "$rel"; then
        echo "ERROR: '$rel' is not matched by .gitignore." >&2
        echo "Writing real secrets there risks committing them. Add a matching rule first." >&2
        exit 1
    fi
}

# Takes the variable NAMES as positional arguments and echoes the ones that are
# empty or unset.
#
# This used to take the name of an array and dereference it with `local -n`, which
# is bash 4.3+. macOS ships bash 3.2 and that is what the `macos-14` runner's
# `/bin/bash` is, so the nameref failed there with "local: -n: invalid option" and
# `check_vars` then reported an empty list of missing variables — making the iOS
# build fail with a message that named nothing. Plain "$@" works on both.
check_vars() {
    local missing=""
    local var
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            missing="${missing:+$missing }$var"
        fi
    done
    if [ -n "$missing" ]; then
        echo "$missing"
        return 1
    fi
}

generate_ios() {
    assert_untracked "$IOS_OUTPUT"
    local cert_backup="${CERT_BACKUP_PIN_HASH:-C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=}"
    cat > "$IOS_OUTPUT" << SWIFT
// AUTO-GENERATED FILE — DO NOT EDIT MANUALLY
// Generated by scripts/generate-secrets.sh from environment variables.
// This file is .gitignored. See BuildSecrets.swift.example for the template.

import Foundation

enum BuildSecrets {
    // MARK: - Supabase

    static let supabaseURL = "${SUPABASE_URL}"
    static let supabaseAnonKey = "${SUPABASE_ANON_KEY}"

    // MARK: - RevenueCat

    static let revenueCatAPIKey = "${REVENUECAT_API_KEY}"

    // MARK: - TelemetryDeck

    static let telemetryDeckAppID = "${TELEMETRYDECK_APP_ID}"

    // MARK: - Certificate Pinning

    static let certificatePinHash = "${CERT_PIN_HASH}"
    static let certificateBackupPinHash = "${cert_backup}"

    // MARK: - Request Signing

    static let requestSigningKey = "${REQUEST_SIGNING_KEY:-}"

    // MARK: - Crash Reporting (US-199)

    static let sentryDSN = "${SENTRY_DSN:-}"
}
SWIFT
    echo "iOS BuildSecrets.swift generated at $IOS_OUTPUT"
}

generate_android() {
    assert_untracked "$ANDROID_OUTPUT"

    # Preserve an existing sdk.dir if the file already exists (Android Studio
    # writes it on first sync; CI doesn't need it because ANDROID_HOME is set).
    local sdk_line=""
    if [ -f "$ANDROID_OUTPUT" ]; then
        sdk_line="$(grep -E '^\s*sdk\.dir\s*=' "$ANDROID_OUTPUT" || true)"
    fi

    {
        echo "# AUTO-GENERATED FILE — DO NOT EDIT MANUALLY"
        echo "# Generated by scripts/generate-secrets.sh from environment variables."
        echo "# This file is .gitignored. See local.properties.example for the template."
        echo ""
        if [ -n "$sdk_line" ]; then
            echo "$sdk_line"
            echo ""
        fi
        echo "SUPABASE_URL=${SUPABASE_URL}"
        echo "SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
        echo "MAPS_API_KEY=${MAPS_API_KEY}"
        echo "CERT_PIN_HASH=${CERT_PIN_HASH:-}"
        echo "CERT_BACKUP_PIN_HASH=${CERT_BACKUP_PIN_HASH:-}"
        echo "REQUEST_SIGNING_KEY=${REQUEST_SIGNING_KEY:-}"
        echo "SENTRY_DSN=${SENTRY_DSN:-}"
    } > "$ANDROID_OUTPUT"
    echo "Android local.properties generated at $ANDROID_OUTPUT"
}

fail_missing() {
    local platform=$1
    shift
    echo "ERROR: The following required environment variables for $platform are empty or unset:" >&2
    for var in "$@"; do
        echo "  - $var" >&2
    done
    echo "" >&2
    echo "Set them in your environment or in CI secrets before running this script." >&2
    echo "For local development, copy the matching .example file instead." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------
did_generate=false

if [ "$MODE" = "ios" ] || [ "$MODE" = "all" ]; then
    missing=$(check_vars "${ios_required[@]}") || fail_missing "iOS" $missing
    generate_ios
    did_generate=true
fi

if [ "$MODE" = "android" ] || [ "$MODE" = "all" ]; then
    missing=$(check_vars "${android_required[@]}") || fail_missing "Android" $missing
    generate_android
    did_generate=true
fi

if [ "$MODE" = "auto" ]; then
    if ios_missing=$(check_vars "${ios_required[@]}"); then
        generate_ios
        did_generate=true
    else
        echo "Skipping iOS (missing: $ios_missing)" >&2
    fi
    if android_missing=$(check_vars "${android_required[@]}"); then
        generate_android
        did_generate=true
    else
        echo "Skipping Android (missing: $android_missing)" >&2
    fi
fi

if [ "$did_generate" = false ]; then
    echo "ERROR: No secrets generated — no platform had all required env vars set." >&2
    exit 1
fi
