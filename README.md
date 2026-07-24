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
    ├── migrations/               # 0001 schema · 0002 RLS · 0003 functions
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
| Phase-1 role screens wired to Supabase | ⏭️ next |

## Getting started

**Backend:** create a Supabase project → run `supabase/migrations/*.sql` in order → optionally `seed.sql`.

**App:**
```bash
cd app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

See `docs/` for the full blueprint.
