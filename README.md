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
├── docs/
│   ├── PROJECT_LOG.md            # ← start here: current state, known gaps, deploy facts, change log
│   ├── OVERVIEW.md               # what the app is + the end-to-end workflow
│   ├── Roles.md                  # every role's tabs, FAB, screens, limits
│   ├── DataModel.md              # 33 tables, views, triggers, RLS matrix, storage
│   ├── API.md                    # the real API: RPCs, views, Edge Functions, direct writes
│   ├── TESTING_GUIDE.md          # deploy checklist + 2-device test plan
│   ├── WORKFLOW_AUDIT.md         # audit findings + fix status
│   ├── UX_NAVIGATION_AUDIT.md    # navigation clean-up (Tier 3) status
│   ├── WORKLOG.md                # session-by-session trail
│   ├── NATIVE_SETUP.md · INVITE_FLOW.md · TechStack_and_BuildPlan.md
│   └── Proposal.pdf              # leadership proposal
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
│   ├── migrations/               # 0001 schema … 0020 PO approvals … 0025 atomic design versions
│   ├── functions/                # Edge Functions (admin create/delete member)
│   ├── tests/                    # run.sh: 149 assertions on real Postgres, as real users
│   ├── check_migrations.sql      # read-only: which migrations a database has
│   ├── full_setup.sql            # GENERATED one-shot setup (build_full_setup.sh)
│   └── seed.sql                  # demo data (+ seed_*_demo.sql extras)
├── DEPENDENCIES.md           # who produces which data for whom; repos; screen matrix
├── BUILD_PROGRESS.md         # per-role build history
└── .github/workflows/ci.yml  # analyze · test · Android build · backend suite
```

> `design/` holds the **original** 73-screen mock-ups. The shipped app has since changed in places
> (e.g. the client truck view is one scrolling screen, not tabs). `docs/Roles.md` describes what ships.

## Tech stack

- **Flutter 3.44.8** (iOS + Android; web works, but the camera needs HTTPS) with:
  - Riverpod 2 · go_router 14 · google_fonts;
  - `model_viewer_plus` (3D `.glb`) · `mobile_scanner` (barcodes) · `image_picker` · `file_picker`;
  - `pdf` + `printing` (GST purchase orders).
- **Supabase**: Postgres + Auth + Storage + Edge Functions + **Row-Level Security** (role permissions
  live in the DB). Realtime is not used yet, so pull to refresh.

## Status

*As of 7 Oct 2026 (`main` @ PR #46).*

| Area | State |
|---|---|
| All 8 roles wired to Supabase: Admin · PM · Procurement · Store · Workshop · Design · Service · Client | ✅ |
| Assignment chain (Admin → PM → role staff) enforced in the DB | ✅ `docs/WORKFLOW_AUDIT.md` |
| Hero #1 order-by engine · Hero #2 traceability + recall | ✅ |
| Template BOM + checklists · stock movement · bill capture · delay logging · documents | ✅ |
| PO approval chain (Procurement → PM → owner) + GST PO document | ✅ |
| Command Center · tabbed build screen (Overview / Pipeline / Materials / Record) · truck record | ✅ |
| Camera photos + barcode scanning · after-sales (tickets, SLA, visits, warranty) | ✅ |
| Multi-user hardening (double-tap guards, atomic design versions, live SLA) | ✅ PR #46 |
| Reproducible build + CI (analyze, test, Android build, Postgres suite) | ✅ |
| Known gaps: Design/Service can't submit a stage, several DB bypasses, Store "new item" RLS | ⬜ `docs/PROJECT_LOG.md` §3 |
| Offline · push notifications · realtime · pagination · localization | ⏭️ not started |

The gaps are real and listed deliberately. `docs/PROJECT_LOG.md` §3 has the full numbered set.

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
`docs/WORKFLOW_AUDIT.md` documents the ~40 issues this closed (§1–§6) and the ones still open (§7).

## Getting started

**Backend:** create a Supabase project, then paste `supabase/full_setup.sql` once (for a fresh project), or run
`supabase/migrations/*.sql` in order. Deploy the Edge Functions in `supabase/functions/`.
On an **existing** project, run `supabase/check_migrations.sql` (read-only) first. It tells you which
migrations are missing. Full checklist: `docs/TESTING_GUIDE.md` §1.

Optional but recommended: schedule `select public.fn_refresh_all_statuses();` daily so at-risk /
delayed statuses roll forward with the calendar.

**Verify the backend.** This needs only Docker. It:
- spins up a throwaway Postgres 15 and applies the migration chain;
- proves the newest migration is idempotent;
- runs **149 assertions** in 7 suites as real non-superuser users, so RLS and the guard triggers actually apply;
- checks that `full_setup.sql` alone produces the same database.

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
