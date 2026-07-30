#!/bin/sh
# Verify the whole backend against a real Postgres 15, with RLS enforced.
#
#   sh supabase/tests/run.sh
#
# Needs only Docker. It spins up a throwaway postgres:15-alpine, applies the
# migration chain + seed, re-applies the newest migration to prove it is
# idempotent, runs the workflow tests as real (non-superuser) users, and finally
# checks that full_setup.sql alone produces the same working database.
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)

docker run --rm -v "$REPO":/w --user postgres postgres:15-alpine \
  sh /w/supabase/tests/_inside.sh
