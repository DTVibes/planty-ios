#!/usr/bin/env bash
# Applies all migrations to a throwaway PostgreSQL database and runs the security tests.
# Usage: DATABASE_URL=postgres://user@host:5432/postgres scripts/test-db.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADMIN_URL="${DATABASE_URL:-postgres://postgres@localhost:5432/postgres}"
DB="planty_test_$$"

psql "$ADMIN_URL" -qc "create database $DB"
trap 'psql "$ADMIN_URL" -qc "drop database if exists $DB with (force)"' EXIT
TEST_URL="${ADMIN_URL%/*}/$DB"

psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/supabase_stubs.sql"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f "$migration"
done
psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/rls_test.sql"
