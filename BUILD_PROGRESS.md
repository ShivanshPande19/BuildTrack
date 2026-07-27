# BuildTrack — Build Progress

**Approach:** role-by-role (complete one role fully, then the next). Order chosen by data-flow priority.

**Definition of done (per role):** all designed screens · navigation wired · Supabase read + write actions · loading/empty/error states.

Legend: ✅ done · 🔨 in progress · ⬜ not started

---

## Foundation
- ✅ Supabase backend (schema, RLS, functions, seed) — live
- ✅ Flutter app skeleton (theme, auth/login, role routing, design-system widgets)
- ✅ Data layer (models + repositories) — extended per role as we go

## 1. Admin 🔨
- ✅ Dashboard (fleet, live)
- ✅ **Onboard project** (create → auto stages + order-by) — live via fn_onboard_project
- ✅ **Create custom template** (name + stages/durations → saved, selectable) + **add new client**
- ✅ **Team & roles** (members list, role pills) — live via profiles
- ✅ **Add member (assign role)** — via Edge Function `admin-create-member` (auth user + profile + client_account)
- ✅ **Projects list** (tab + status filters, tappable rows)
- ✅ **Project detail** (progress + delivery + build-stage timeline)
- ✅ **Analytics / Insights** (on-track %, counts, fleet distribution)
- ✅ **Stage detail** (photos + installed parts + checklist + delays, per stage)
- ✅ **Notifications** (grouped Today/Earlier, mark all read)
- ✅ **Profile / Settings** (identity + settings + log out)

**→ ADMIN ROLE COMPLETE (Phase-1)**

## 2. Procurement 🔨  *(Hero #1)*
- ✅ To-Order + Create PO (live)
- ⬜ Purchase Orders list
- ⬜ PO detail (status stepper)
- ⬜ Receive / GRN
- ⬜ Vendors + vendor detail
- ⬜ Notifications · Profile

## 3. Store ⬜  *(Hero #2 — intake)*
- ⬜ Inbox · Receive/GRN · Log component · Inventory · Components search · Component detail · Recall · Notifications · Profile

## 4. Workshop ⬜  *(Hero #2 — install)*
- ⬜ My Tasks · Task detail · Add photo · Scan to install · Components · Mark complete · My week · Notifications · Profile

## 5. Project Manager ⬜
- ⬜ Dashboard · Projects · Project detail · Assign task · Schedule/bays · Team workload · Approvals · Notifications · Profile

## 6. Client ⬜
- ⬜ My Trucks · Truck dashboard · Build journey · Photos · Approve design · Documents · Raise request · Support · Notifications · Profile

## 7. Design ⬜ *(Phase 2)*
## 8. Service ⬜ *(Phase 2)*

---
*Next up: complete the Admin role.*
