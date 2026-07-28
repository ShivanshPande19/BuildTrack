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
- ✅ **Tab shell** (To Order · Orders · Receive · Vendors) with bell/avatar
- ✅ **To Order** (hero order-today card + upcoming list + Create PO inline)
- ✅ **Orders list** (status filters, tappable → detail)
- ✅ **PO detail** (Ordered→Dispatched→Received stepper + items + Mark received → GRN)
- ✅ **Receive** (incoming POs, Receive & verify)
- ✅ **Vendors** (reliability score + lead time)
- ✅ **Notifications · Profile** (shared `common/` screens, reused)
- ⬜ Vendor detail (pr7) · manual New PO (pr4) — round 2

## Shared / common
- ✅ `common/notifications.dart`, `common/profile.dart` — reused across roles
- ✅ `EmptyState` widget — friendly placeholders everywhere

## 3. Store 🔨  *(Hero #2 — traceability + recall)*
- ✅ **Tab shell** (Inbox · Stock · Parts) + bell/avatar + scan FAB
- ✅ **Inbox** (stats: tracked/low-stock/lines + low-stock list)
- ✅ **Stock** (inventory list, All/Low filter, OK/Fair/Low)
- ✅ **Parts** (component search by serial/model/truck)
- ✅ **Component detail** (record + warranty banner)
- ✅ **Recall check** (Hero #2 — every truck with a model installed → Notify all) via `fn_recall`
- ✅ **Log component** (item + serial + warranty + assign to build → feeds traceability)
- ✅ Notifications · Profile (shared common)
- ⬜ Receive/GRN link from Procurement (round 2)

## 4. Workshop 🔨  *(Hero #2 — install)*
- ✅ **Tab shell** (Tasks · Parts · Week) + bell/avatar + scan FAB
- ✅ **My Tasks** (stages assigned to me: in-progress + queued)
- ✅ **Task detail** (checklist toggle, progress, photo, install, submit)
- ✅ **Scan to install** (in-stock component → install into truck/stage — Hero #2)
- ✅ **Add photo** (attach work photo + note to stage)
- ✅ **Mark complete → Submit for approval** (creates stage_approval → PM Approvals)
- ✅ **Components** (parts installed on my trucks) · **My Week**
- ✅ Notifications · Profile (shared common)

**Chain live:** Store logs component (in-stock) → Workshop scan-to-install → assigned to truck/stage → traceable + recall-able. Workshop submits → PM approves → stage done → progress updates.

## 5. Project Manager 🔨  *(owns build planning)*
- ✅ **Tab shell** (My Builds · Projects · Schedule · Team) + bell/avatar
- ✅ **My Builds** dashboard (assigned counts, needs-you, today's stages) — pm-scoped
- ✅ **My Projects** (pm_id = me, filters) → project detail with **editable Materials**
- ✅ **Schedule** (workshop bays: busy/free)
- ✅ **Team** (workload — in-progress task count per member; only doer roles)
- ✅ **Assign / reassign / unassign** stages to team (from project detail)
- ✅ **Approvals** (approve/reject stage completions → stage done/rework)
- ✅ **Edit timeline** (change delivery date → re-schedules + order-by)
- ✅ **Create Template + BOM UI** (items per stage → onboarding auto-generates requirements, no SQL)
- ✅ Notifications · Profile (shared common)

**→ PROJECT MANAGER ROLE COMPLETE (Phase-1)**

> Note: PM sees projects where `pm_id = me`. Assign a PM in Onboard Project (PM dropdown).
> Assignment: Admin→PM (`pm_id`); PM→staff (`stages.assignee_id`). All data providers are auth-aware (correct data right after login).

## 6. Client ✅
- ✅ **My Trucks** (multi-project entry, progress + status)
- ✅ **Truck view** — tabbed (Progress · Photos · Docs · Support)
- ✅ **Progress** (build % ring + current stage + build-journey timeline)
- ✅ **Photos** (build photos — needs migration 0006 for client read)
- ✅ **Documents** (available client docs)
- ✅ **Approve design** (approve / request changes) — feeds Design role later
- ✅ **Raise request** (creates ticket) + **Support** (my requests)
- ✅ Notifications · Profile (shared common)

**→ CLIENT ROLE COMPLETE (Phase-1) · 6/6 core roles done**

## 7. Design ✅ *(Phase 2)*
- ✅ **Tab shell** (Studio · Designs · Approvals · Profile) + bell + New-design FAB
- ✅ **Studio** (stat tiles: drafts/awaiting/changes/approved + "needs your attention")
- ✅ **Designs** (full library, status filter chips)
- ✅ **Approvals** (submitted designs + client outcome + feedback surfaced)
- ✅ **New design** (pick project + type · attach .glb model + 2D preview + note · save draft / submit)
- ✅ **New version** (re-upload after a change request → resubmits, clears feedback)
- ✅ **Design detail** (interactive 3D/2D preview · client feedback · status banners · version history)
- ✅ Notifications · Profile (shared common)

**Client loop live:** Designer submits → Client **Approve / Request changes (with feedback)** →
approved design's `.glb` flows to the **3D showcase**.

## 🧊 3D showcase (Blender `.glb` → app)
- ✅ `Truck3DPreview` (model_viewer_plus: rotate/zoom/AR + full-screen) — `features/client/truck_3d.dart`
- ✅ **Client** My Trucks card · **Admin/PM** project detail — show approved model, demo fallback
- ✅ `truckModelUrlProvider(projectId)` → approved design's `model_url`
- Backend: `design_versions.model_url` + `design_artifacts.client_feedback` (migration **0007**)

## 8. Service ⬜ *(Phase 2 — next)*

---
*Phase 2: Design role ✅ done. Next: Service role (connects to Client raise-request / tickets).*
*Migrations to run: 0005_bom, 0006_client_attachments, 0007_design_model. Edge functions: admin-create-member, admin-delete-member.*
