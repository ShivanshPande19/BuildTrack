#!/bin/sh
# Regenerates full_setup.sql = every migration, in order, + the demo seed.
#
# full_setup.sql is the "paste this into a fresh Supabase SQL editor" file. It had
# drifted out of sync with migrations/ (0005's BOM table and 0006's client photo
# policy were missing), which silently broke Create-Template and client photos on
# any project set up from it. Generating it removes the drift for good.
#
#   cd supabase && sh build_full_setup.sh
set -e
cd "$(dirname "$0")"
OUT=full_setup.sql

{
  echo "-- Azimuth BuildTrack — complete backend setup (schema · RLS · functions · seed)"
  echo "--"
  echo "-- GENERATED FILE — do not edit by hand."
  echo "-- Regenerate with:  cd supabase && sh build_full_setup.sh"
  echo "-- Source of truth:  migrations/*.sql applied in order, then seed.sql."
  echo "--"
  echo "-- Run this once on a fresh Supabase project (SQL editor), or apply the"
  echo "-- migrations individually if the project already has some of them."
  echo

  for f in migrations/*.sql; do
    echo
    echo "-- ═══════════════════════════════════════════════════════════════════════"
    echo "-- $f"
    echo "-- ═══════════════════════════════════════════════════════════════════════"
    cat "$f"
  done

  echo
  echo "-- ═══════════════════════════════════════════════════════════════════════"
  echo "-- seed.sql — demo data (safe to delete this section for a clean install)"
  echo "-- ═══════════════════════════════════════════════════════════════════════"
  cat seed.sql
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT") lines) from $(ls migrations/*.sql | wc -l) migrations + seed"
