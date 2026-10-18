#!/usr/bin/env python3
"""Catch UUID literals in supabase/*.sql that are not valid hex.

    python3 supabase/check_uuid_literals.py

Postgres accepts only 0-9 and a-f in a uuid, so a fixture id like
`a1000000-0000-0000-0000-0000000000t1` fails at run time with "invalid input
syntax for type uuid" — and a grep for uuids written the usual way,
`[0-9a-f]{12}`, cannot see it, because the typo is precisely what stops it
matching. That is how thirty of them reached CI in one suite.

So this matches the *shape* first (any word characters in 8-4-4-4-12) and then
asks whether what it found is actually hex. Exits non-zero if anything is off,
so it can go in front of a push.
"""
import re, sys, pathlib
# Anything that *looks* like a uuid literal (8-4-4-4-12 of word chars), then
# check whether it is actually valid hex. The usual regex only matches valid
# ones, so a typo like "…t1" is invisible to it — which is how this got through.
shape = re.compile(r"'([0-9A-Za-z]{8}-[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]{12})'")
valid = re.compile(r'^[0-9a-fA-F-]+$')
bad = 0
for f in sorted(pathlib.Path('supabase').rglob('*.sql')):
    for i, line in enumerate(f.read_text().splitlines(), 1):
        for m in shape.finditer(line):
            if not valid.match(m.group(1)):
                print(f'{f}:{i}: INVALID UUID {m.group(1)}')
                bad += 1
print(f'--- {bad} invalid uuid literal(s) ---')
sys.exit(1 if bad else 0)
