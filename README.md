# Azimuth BuildTrack

[![CI](https://github.com/ShivanshPande19/BuildTrack/actions/workflows/ci.yml/badge.svg)](https://github.com/ShivanshPande19/BuildTrack/actions/workflows/ci.yml)

Build-management app for **Azimuth Business on Wheels** (premium food trucks, carts & kiosks). One mobile app, **8 role-based experiences**, that runs the entire build phase — from a confirmed order to delivery and after-sales — so nothing slips through the cracks across 35+ parallel builds.

## Why

Two real problems this solves:
1. **Timeline derailment** — missed order-by dates push deliveries late. → **Backward-scheduling + alert engine.**
2. **No component traceability** — can't find a failed part's bill/warranty or which trucks share it. → **Per-truck digital twin + recall.**

## The 8 roles

👑 Admin · 📋 Project Manager · 🛒 Procurement · 🔧 Workshop · 📦 Store/Inventory · 🎨 Design · 🛠️ Service · 🙋 Client

## Repository structure

```
BuildTrack/
├── docs/                     # specs
│   ├── Proposal.pdf              # leadership proposal
│   ├── Roles.md                  # roles, features, permissions
│   ├── DataModel.md              # entities, relations, ER diagram
│   ├── API.md                    # REST endpoints by role
│   └── TechStack_and_BuildPlan.md
├── design/                   # the full UI (Equora style)
│   ├── html/                     # source of each role's screens (8 files)
│   ├── screens/                  # rendered PNGs per role (73 screens)
│   ├── showcases/                # per-role showcase decks (PNG + PDF)
│   └── tools/                    # render/compose scripts
├── app/                      # Flutter app
│   ├── lib/{core, shared, features}
│   ├── test/                     # pure-Dart domain tests (no network, no emulator)
│   ├── android/ ios/ web/        # tracked — a clone has to build
│   ├── analysis_options.yaml     # lint + strict-cast rules CI enforces
│   └── pubspec.lock              # committed: every machine resolves the same versions
├── supabase/                 # backend
│   ├── migrations/               # 0001 schema · 0002 RLS · 0003 functions · … · 0011 storage
│   ├── functions/                # Edge Functions (admin create/delete member)
│   ├── tests/                    # run.sh — verifies the whole backend on real Postgres
│   ├── full_setup.sql            # GENERATED one-shot setup (build_full_setup.sh)
│   └── seed.sql                  # demo data
└── .github/workflows/ci.yml  # analyze · test · Android build · backend suite
```

## Tech stack

- **Flutter** (iOS + Android) · Riverpod · go_router · google_fonts
- **Supabase** — Postgres + Auth + Storage + Realtime + **Row-Level Security** (role permissions in the DB)

## Status

| Area | State |
|---|---|
| Proposal, roles, data model, API, build plan | ✅ documented |
| UI — all 8 roles (73 screens) | ✅ designed |
| DB schema + RLS + scheduling/recall functions + seed | ✅ built & validated on Postgres 15 |
| Flutter foundation (theme, auth, role routing, design-system widgets) | ✅ scaffolded |
| Role screens wired to Supabase | ✅ all 8 — Admin · PM · Procurement · Store · Workshop · Design · Service · Client |
| Assignment chain (Admin → PM → role staff) enforced in the DB | ✅ see `docs/WORKFLOW_AUDIT.md` |
| Real camera photos + barcode scanning · after-sales / tickets | ✅ built |
| Reproducible build (platform folders, lockfiles, native config, CI) | ✅ this is new — see below |
| Stock movement · bill capture · template checklists · delay logging · handover documents | ⏭️ next |
| Offline support · push notifications · realtime · pagination · localization | ⏭️ not started |

Progress percentages in `docs/PROJECT_LOG.md` describe features wired up, not production readiness.
The gaps above are real and listed deliberately: `docs/PROJECT_LOG.md` §3 has the full set.

## The operating chain

```
Admin   creates the build + the client's login  ──►  assigns a Project Manager
PM      sees only their builds  ──►  assigns each stage to the right discipline (+ dates)
Staff   see only their assigned work  ──►  start it, upload, submit
PM      approves  ──►  stage done  ──►  next stage starts  ──►  client sees progress
```

Every step is enforced in Postgres (RLS + guard triggers + `SECURITY DEFINER` RPCs), not just in
the UI — so a welder cannot create a project, a PM cannot touch someone else's build, and a design
stage cannot be handed to a fabricator without an explicit override.
`docs/WORKFLOW_AUDIT.md` documents the ~40 issues this closed.

## Getting started

**Backend:** create a Supabase project → run `supabase/migrations/*.sql` in order (or paste
`supabase/full_setup.sql` for a fresh project) → deploy the Edge Functions in `supabase/functions/`.

Optional but recommended: schedule `select public.fn_refresh_all_statuses();` daily so at-risk /
delayed statuses roll forward with the calendar.

**Verify the backend** (needs only Docker — spins up a throwaway Postgres 15, applies the migration
chain, proves the newest migration is idempotent, runs 83 assertions as real non-superuser users so
RLS and the guard triggers actually apply, then checks `full_setup.sql` alone produces the same
database):

```bash
sh supabase/tests/run.sh
```

**App:**
```bash
cd app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Native setup (camera permissions, the invite deep link, iOS usage strings) is already committed —
`docs/NATIVE_SETUP.md` explains why each piece is there. On macOS, run `pod install` in `app/ios`
after any dependency change.

## CI

`.github/workflows/ci.yml` runs on every push and pull request:

| Job | What it proves |
|---|---|
| **Flutter · analyze + test** | The Dart compiles, the lints in `app/analysis_options.yaml` pass, the domain tests pass, and `pubspec.lock` matches `pubspec.yaml` |
| **Android · debug build** | The Gradle/manifest/`minSdk` config actually builds, and the CAMERA, INTERNET and `io.supabase.buildtrack` entries are still in the manifest |
| **Postgres · migrations, RLS, workflow rules** | `supabase/tests/run.sh` against a real Postgres 15 |

Run the same checks locally before pushing:

```bash
cd app && flutter analyze && flutter test
sh ../supabase/tests/run.sh
```

The manifest check exists because `flutter create .` silently overwrites `AndroidManifest.xml` with a
stock template. The app still builds and runs afterwards — only the camera, the barcode scanner and
invite deep links stop working. That is exactly how they went missing once already.

iOS is not built in CI (it needs a macOS runner). Build it locally before any release.

See `docs/` for the full blueprint.
