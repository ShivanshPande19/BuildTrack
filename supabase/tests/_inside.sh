#!/bin/sh
# Runs INSIDE the postgres:15-alpine container (as user postgres). Invoked by run.sh.
set -e
export PGDATA=/tmp/pgdata
export PGUSER=postgres
SQL=/w/supabase
T=/w/supabase/tests

rm -rf "$PGDATA"
initdb -D "$PGDATA" -U postgres --auth=trust >/dev/null 2>&1
pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start >/dev/null 2>&1

run() {  # run <db> <file>
  printf '%-36s' "$(basename "$2")"
  if psql -v ON_ERROR_STOP=1 -d "$1" -q -f "$2" >/tmp/out.log 2>&1; then
    echo ok
  else
    echo FAILED; cat /tmp/out.log; exit 1
  fi
}

grants() {
  psql -d "$1" -q -c "
    grant all on all tables    in schema public to authenticated;
    grant all on all sequences in schema public to authenticated;
    grant all on all functions in schema public to authenticated;" >/dev/null
}

# ── path A: the migration chain, the way a maintained project evolves ────────
createdb buildtrack
run buildtrack "$T/00_shim.sql"
for f in "$SQL"/migrations/*.sql; do run buildtrack "$f"; done
run buildtrack "$SQL/seed.sql"
grants buildtrack
echo '--- migrations + seed applied cleanly ---'

# re-running the newest migration must be a no-op, not an error
run buildtrack "$(ls "$SQL"/migrations/*.sql | tail -1)"
echo '--- newest migration is idempotent ---'

echo
# workflow first — it builds the AZ-200 fixture the later suites reuse
psql -v ON_ERROR_STOP=1 -d buildtrack -f "$T/10_workflow_tests.sql"
for t in "$T"/[2-9][0-9]_*.sql; do
  [ -f "$t" ] || continue
  psql -v ON_ERROR_STOP=1 -d buildtrack -f "$t"
done

# ── path B: one-shot full_setup.sql, the way a fresh project is set up ───────
echo
createdb oneshot
run oneshot "$T/00_shim.sql"
run oneshot "$SQL/full_setup.sql"
grants oneshot
printf '%-36s' "same test suites on that database"
if psql -v ON_ERROR_STOP=1 -d oneshot -f "$T/10_workflow_tests.sql" >/tmp/o2.log 2>&1 \
   && { for t in "$T"/[2-9][0-9]_*.sql; do
          [ -f "$t" ] || continue
          psql -v ON_ERROR_STOP=1 -d oneshot -f "$t" >>/tmp/o2.log 2>&1 || exit 1
        done; }; then
  echo ok
else
  echo FAILED; tail -30 /tmp/o2.log; exit 1
fi
echo '--- full_setup.sql matches the migration chain ---'
