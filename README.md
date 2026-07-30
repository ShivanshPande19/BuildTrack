# Azimuth BuildTrack

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
│   └── lib/{core, shared, features}
└── supabase/                 # backend
    ├── migrations/               # 0001 schema · 0002 RLS · 0003 functions · … · 0009 workflow
    ├── functions/                # Edge Functions (admin create/delete member)
    ├── tests/                    # run.sh — verifies the whole backend on real Postgres
    ├── full_setup.sql            # GENERATED one-shot setup (build_full_setup.sh)
    └── seed.sql                  # demo data
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
| Phase-1 role screens wired to Supabase | ✅ Admin · PM · Procurement · Store · Workshop · Design · Client |
| Assignment chain (Admin → PM → role staff) enforced in the DB | ✅ see `docs/WORKFLOW_AUDIT.md` |
| Service role screens · real photo upload · delay logging | ⏭️ next |

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

**Verify the backend** (needs only Docker — spins up a throwaway Postgres 15, applies everything and
runs ~40 assertions as real non-superuser users so RLS actually applies):

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

See `docs/` for the full blueprint.
