#!/bin/bash
# run-backend-tests.sh — applies the migrations to a scratch database and runs the
# SQL test suite in backend/tests/ (US-207).
#
# Usage:
#   scripts/run-backend-tests.sh                 # uses PG* env vars / local socket
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres scripts/run-backend-tests.sh
#
# Requires a PostgreSQL 15+ server with PostGIS available to the connecting role.
# In CI this is a postgis/postgis service container. The scratch database is
# dropped and recreated on every run so results never depend on prior state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$REPO_ROOT/backend/migrations"
TESTS_DIR="$REPO_ROOT/backend/tests"

TEST_DB="${TEST_DB:-lociate_test}"
export PGHOST="${PGHOST:-/var/run/postgresql}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"

psql_admin() { psql --dbname=postgres --no-psqlrc --quiet -v ON_ERROR_STOP=1 "$@"; }
psql_test() { psql --dbname="$TEST_DB" --no-psqlrc -v ON_ERROR_STOP=1 "$@"; }

echo "==> Recreating scratch database '$TEST_DB'"
psql_admin -c "DROP DATABASE IF EXISTS $TEST_DB WITH (FORCE);" >/dev/null
psql_admin -c "CREATE DATABASE $TEST_DB;" >/dev/null

echo "==> Bootstrapping the Supabase-provided schema surface"
psql_test --quiet -f "$TESTS_DIR/00_bootstrap.sql" >/dev/null

echo "==> Applying migrations"
for migration in "$MIGRATIONS_DIR"/[0-9]*.sql; do
    name="$(basename "$migration")"
    printf '    %s\n' "$name"
    if ! psql_test --quiet -f "$migration" >/dev/null; then
        echo "FAILED applying $name" >&2
        exit 1
    fi
done

# Anything added to public/ after the migrations still needs the role grants.
psql_test --quiet -c "
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
        TO authenticated;
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public
        TO anon, authenticated, service_role;
" >/dev/null

echo "==> Running tests"
status=0
for test_file in "$TESTS_DIR"/[1-9]*.sql; do
    name="$(basename "$test_file")"
    echo "--- $name"
    # Assertions raise, and ON_ERROR_STOP turns that into a non-zero exit.
    if psql_test -f "$test_file" 2>&1 | sed 's/^/    /'; then
        echo "    PASS $name"
    else
        echo "    FAIL $name" >&2
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "==> All backend tests passed"
else
    echo "==> Backend tests FAILED" >&2
fi
exit "$status"
