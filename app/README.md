# Azimuth BuildTrack — app

Food-truck build management for Azimuth Business on Wheels. One mobile app, 8 role-based experiences.

## Stack
- **Flutter** (iOS + Android) · Riverpod · go_router · google_fonts
- **Supabase** — Postgres + Auth + Storage + Realtime + RLS (role permissions in the DB)

## Structure
```
buildtrack/
├── app/                      # Flutter app
│   └── lib/
│       ├── core/             # theme (Equora tokens), router, supabase client
│       ├── shared/           # design-system widgets (cards, pills, nav)
│       └── features/         # auth, home (role shells) …
└── supabase/
    ├── migrations/           # 0001 schema · 0002 RLS · 0003 functions
    └── seed.sql              # demo data (AZ-118 etc.)
```

## Backend setup (Supabase)
1. Create a Supabase project.
2. Run the migrations in order (`0001_init.sql`, `0002_rls.sql`, `0003_functions.sql`) via the SQL editor or `supabase db push`.
3. (Optional) run `seed.sql` for demo data.
4. Create auth users; a `profiles` row (with `role`) maps each user to their role UI.

> Validated locally against PostgreSQL 15 — schema, RLS, scheduling/recall functions and seed all run clean. Backward scheduling + order-by dates + recall verified.

## Run the app
```bash
cd app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

## Status
- ✅ DB schema + RLS + core functions (scheduling, progress, recall)
- ✅ App foundation: theme (Equora), auth (login), role-based routing, design-system widgets, role shells
- ⏭️ Next: build each role's designed screens (Phase-1: Admin, Procurement, Store, Workshop, Client) onto the shells

See `../BuildTrack_*.md` for the full proposal, roles, data model, API and build plan.
