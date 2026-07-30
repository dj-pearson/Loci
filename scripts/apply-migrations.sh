#!/bin/bash
# apply-migrations.sh — idempotent migration runner with applied-version tracking.
#
# US-214: docker-compose.prod.yml stopped bind-mounting backend/migrations and told
# operators to apply them by hand, with no record of what had run. A partial or
# double apply was easy and undetectable. This records every applied file with its
# checksum, applies only what is pending, and refuses to continue if a file that
# was already applied has since changed.
#
# Usage:
#   scripts/apply-migrations.sh                 # apply pending migrations
#   scripts/apply-migrations.sh --dry-run       # list pending migrations, change nothing
#   scripts/apply-migrations.sh --baseline      # record all migrations as applied
#                                               # WITHOUT running them (for a database
#                                               # provisioned before this runner existed)
#   scripts/apply-migrations.sh --status        # show the applied ledger
#
# Connection comes from the standard PG* environment variables (PGHOST, PGPORT,
# PGUSER, PGPASSWORD, PGDATABASE) or a DATABASE_URL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/backend/migrations"

MODE="apply"
case "${1:-}" in
    --dry-run)  MODE="dry-run" ;;
    --baseline) MODE="baseline" ;;
    --status)   MODE="status" ;;
    "")         MODE="apply" ;;
    *)
        echo "Unknown flag: $1" >&2
        echo "Usage: $0 [--dry-run|--baseline|--status]" >&2
        exit 2
        ;;
esac

if [ -n "${DATABASE_URL:-}" ]; then
    PSQL=(psql "$DATABASE_URL" --no-psqlrc -v ON_ERROR_STOP=1)
else
    PSQL=(psql --no-psqlrc -v ON_ERROR_STOP=1)
fi

q() { "${PSQL[@]}" -tAc "$1"; }

checksum() {
    # sha256sum on Linux, shasum on macOS — operators run this from both.
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------
q "
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    filename    TEXT PRIMARY KEY,
    checksum    TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_by  TEXT NOT NULL DEFAULT current_user
);
COMMENT ON TABLE public.schema_migrations IS
    'Applied migration ledger, maintained by scripts/apply-migrations.sh (US-214).';
" >/dev/null

if [ "$MODE" = "status" ]; then
    echo "Applied migrations:"
    "${PSQL[@]}" -c "
        SELECT filename, applied_at, applied_by, left(checksum, 12) AS checksum
        FROM public.schema_migrations
        ORDER BY filename;
    "
    exit 0
fi

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------
shopt -s nullglob
migrations=("$MIGRATIONS_DIR"/[0-9]*.sql)
shopt -u nullglob

if [ ${#migrations[@]} -eq 0 ]; then
    echo "No migrations found in $MIGRATIONS_DIR" >&2
    exit 1
fi

pending=()
drifted=()

for migration in "${migrations[@]}"; do
    name="$(basename "$migration")"
    sum="$(checksum "$migration")"
    recorded="$(q "SELECT checksum FROM public.schema_migrations WHERE filename = '$name';")"

    if [ -z "$recorded" ]; then
        pending+=("$migration")
    elif [ "$recorded" != "$sum" ]; then
        drifted+=("$name")
    fi
done

# A changed file that was already applied means the database and the repository
# disagree about the schema. Continuing would apply later migrations on top of an
# unknown state, so stop and make a human decide.
if [ ${#drifted[@]} -ne 0 ]; then
    echo "ERROR: these migrations were already applied but their contents have changed:" >&2
    for name in "${drifted[@]}"; do
        echo "  - $name" >&2
    done
    echo "" >&2
    echo "Never edit an applied migration. Add a new numbered migration that makes" >&2
    echo "the change forward. If the edit was cosmetic and the schema is genuinely" >&2
    echo "unchanged, update the ledger deliberately:" >&2
    echo "  UPDATE public.schema_migrations SET checksum = '<new>' WHERE filename = '<name>';" >&2
    exit 1
fi

if [ ${#pending[@]} -eq 0 ]; then
    echo "Up to date — ${#migrations[@]} migrations already applied."
    exit 0
fi

echo "Pending migrations (${#pending[@]}):"
for migration in "${pending[@]}"; do
    echo "  $(basename "$migration")"
done

if [ "$MODE" = "dry-run" ]; then
    echo ""
    echo "(dry run — nothing applied)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
if [ "$MODE" = "baseline" ]; then
    echo ""
    echo "Baselining: recording as applied WITHOUT executing."
    for migration in "${pending[@]}"; do
        name="$(basename "$migration")"
        sum="$(checksum "$migration")"
        q "INSERT INTO public.schema_migrations (filename, checksum) VALUES ('$name', '$sum');" >/dev/null
        echo "  baselined $name"
    done
    echo "Done. ${#pending[@]} migrations recorded."
    exit 0
fi

echo ""
for migration in "${pending[@]}"; do
    name="$(basename "$migration")"
    sum="$(checksum "$migration")"
    printf 'applying %s ... ' "$name"

    # Each migration and its ledger row commit together: a failure rolls back both,
    # so the ledger can never claim a migration that did not fully apply.
    if "${PSQL[@]}" --quiet --single-transaction \
        -f "$migration" \
        -c "INSERT INTO public.schema_migrations (filename, checksum) VALUES ('$name', '$sum');" \
        >/dev/null 2>"$MIGRATIONS_DIR/.apply-error.log"; then
        echo "ok"
    else
        echo "FAILED"
        echo "" >&2
        cat "$MIGRATIONS_DIR/.apply-error.log" >&2
        rm -f "$MIGRATIONS_DIR/.apply-error.log"
        echo "" >&2
        echo "Rolled back. No ledger row was written for $name." >&2
        exit 1
    fi
    rm -f "$MIGRATIONS_DIR/.apply-error.log"
done

echo ""
echo "Applied ${#pending[@]} migration(s)."
