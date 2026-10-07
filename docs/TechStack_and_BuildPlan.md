# Azimuth BuildTrack — Tech Stack & Build Plan (Step C)

> **Status (7 Oct 2026): decided and built.** Path 2 (Flutter + Supabase) was chosen. The sections
> below are the original plan, kept for the reasoning. How it actually turned out:
>
> | Planned | Built |
> |---|---|
> | Flutter + Riverpod + Dio | Flutter 3.44.8 + Riverpod 2 + go_router 14. Supabase is accessed through `supabase_flutter` (no Dio). |
> | Supabase tables + RLS | 25 migrations: 33 tables, 5 views, RLS + guard triggers + ~40 `SECURITY DEFINER` RPCs ([`API.md`](API.md)) |
> | Edge Function + `pg_cron` daily order-by job | Order-by is recomputed in SQL on every schedule change. Statuses refresh when the dashboards load. A daily `fn_refresh_all_statuses()` cron is recommended but not set up. Edge Functions are used only for member create/delete. |
> | Realtime dashboards, FCM push | **Not built yet.** Pull to refresh; in-app notifications only. |
> | Offline sync for Workshop | **Not built yet.** |
> | Design + Service deferred to Phase 2 | Built in the first pass. All 8 roles have worked since 30 Jul 2026. |
> | ~10-week roadmap | Started 24 Jul 2026. Every role was wired by 30 Jul. Followed by hardening, Phase 1 loops, inventory, the PO approval chain, the ops backbone, UI polish and Tier 1–3 (see [`PROJECT_LOG.md`](PROJECT_LOG.md) §6). |
>
> Also added beyond the plan: 3D `.glb` showcase (`model_viewer_plus`), barcode scanning
> (`mobile_scanner`), camera photos (`image_picker`), GST PO PDFs (`pdf` + `printing`), and CI
> (analyze, test, Android build, Postgres suite).

We have the vision, all 8 role UIs, the data model, and the API. This locks **what we build with** and **in what order**. Tuned for a **solo developer** who wants to ship an MVP fast without cutting corners on the two hero features.

---

## 1. The stack decision (solo-friendly)

Two viable paths. Same Flutter app on top; the difference is the backend.

### Path 1 — Custom backend (max control)
- **Mobile:** Flutter (iOS + Android, one codebase) · Riverpod (state) · Dio (HTTP)
- **Backend:** NestJS (Node + TypeScript) · PostgreSQL · Redis (jobs/cache)
- **Auth:** JWT + role-based guards · **Storage:** S3 · **Jobs:** BullMQ (order-by recompute) · **Push:** FCM
- Best when you want full control and custom logic everywhere.
- Trade-off: **you write & host a lot of backend** — slower for one person.

### Path 2 — Flutter + Supabase ⭐ *(recommended for solo MVP)*
- **Mobile:** Flutter + Riverpod (same premium UI)
- **Backend:** **Supabase** = managed PostgreSQL + Auth + Storage + Realtime + Edge Functions, all in one
  - Our **data model → Postgres tables** directly
  - **Row-Level Security (RLS)** enforces the role permission matrix at the database (very powerful, less code)
  - **Storage** for bills / photos / design files
  - **Edge Function + `pg_cron`** for the daily **order-by recompute + alerts** (Hero #1)
  - **Realtime** for live dashboards
  - **FCM** for push
- Best when one person needs to ship fast. **~70% less backend code.** Can migrate to a custom backend later if ever needed.

> **Recommendation:** **Path 2 (Flutter + Supabase)** for the MVP. It gives auth, database, storage, realtime, and RLS-based permissions out of the box — perfect for a solo build — while keeping the exact same data model and UI.

---

## 2. Phase-1 MVP scope (what we build first)

Focus on the two problems that actually hurt. Build these first:

1. **Auth + Roles** — login, role-based home (all roles route correctly)
2. **Admin:** create user + assign role; onboard project (auto-generates stages + order-by dates)
3. **Hero #1 — Scheduling/Procurement:** stages timeline + `order_by_date` engine + Procurement "To-Order" alerts + Create PO
4. **Hero #2 — Traceability:** Store receive + log component (serial+bill+warranty) → Workshop scan-to-install → component search + **recall**
5. **PM:** assign task, approve stage completion
6. **Client:** My Trucks + truck progress + photos (read-only)

**Deferred to Phase 2+:** Design approvals, Service tickets/SLA, full analytics dashboards, WhatsApp/SMS, predictive AI.

---

## 3. Proposed repo structure

```
buildtrack/
├── app/                # Flutter mobile app (all roles, role-based routing)
│   ├── lib/
│   │   ├── core/       # theme (Equora tokens), router, api client
│   │   ├── features/   # auth, projects, procurement, store, workshop, client…
│   │   └── shared/     # widgets (cards, pills, nav, progress ring)
├── supabase/           # Path 2: migrations (tables), RLS policies, edge functions, seed
│   ├── migrations/
│   ├── functions/      # order-by recompute, notifications
│   └── seed.sql
└── docs/               # the specs we built (proposal, roles, data model, API)
```
*(Path 1 would replace `supabase/` with `api/` = NestJS.)*

---

## 4. Build roadmap (~10 weeks, solo, Path 2)

| Weeks | Milestone |
|---|---|
| 1 | Supabase project: tables from data model + RLS + seed · Flutter app skeleton + Equora design system + auth + role routing |
| 2–3 | Admin (users/roles, project onboarding) + stage engine + backward-scheduling function |
| 4–5 | Procurement to-order + POs + Store receive/log component (Hero #1 + start #2) |
| 6 | Workshop scan-to-install + component search + recall (Hero #2 complete) |
| 7 | PM assign/approve + notifications (push) |
| 8 | Client: My Trucks + progress + photos |
| 9 | Offline sync (workshop), polish, RLS hardening |
| 10 | Test + pilot on 2–3 real projects |

---

## 5. Decision (taken)

1. **Path 2 (Supabase)** was chosen.
2. The Phase-1 scope was delivered, and Design + Service were built in the same pass instead of being deferred.

What's next is tracked in [`PROJECT_LOG.md`](PROJECT_LOG.md) §3: known gaps first, then offline, push,
realtime, pagination and localization.

---

*Azimuth BuildTrack · Tech Stack & Build Plan · Step C*
