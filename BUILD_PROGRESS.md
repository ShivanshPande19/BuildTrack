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
- ✅ **New design** (pick project + type · **upload .glb + preview image from device → Supabase Storage** · note · save draft / submit)
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

## 8. Service ✅ *(Phase 2 — migration 0010)*
- ✅ **Tab shell** (Tickets · Trucks · Warranty · Profile) + bell + New-ticket FAB
- ✅ **Ticket queue** (sv1) — open / overdue / fixed-today, filter chips, sorted by **SLA deadline**
- ✅ **Ticket detail** (sv2) — the client's words, the **linked part + its warranty state**, triage
  to a technician, visits booked against it, the resolution
- ✅ **Resolve** (sv3) — warranty replace / repair / remote guide + a note the **client reads**
- ✅ **Schedule visit** (sv4) — technician + date + time + note; one live booking per ticket
- ✅ **Delivered trucks** (sv5) — open-ticket / warranty-soon / healthy per truck
- ✅ **Truck history** (sv6) — client, parts tracked, warranty position, every past request
- ✅ **Warranty lookup** (sv7) — search by serial / model / truck, expiry state per part
- ✅ **New ticket** — log a request that came in by phone or on site
- ✅ Notifications · Profile

**After-sales loop live:** PM **marks delivered** → truck enters service → client raises a request →
**every service member is notified** → triage → visit → resolve → client told → client can
**reopen** if it's still broken (jumps the queue at high priority).

Backend (`0010_service.sql`): `fn_mark_delivered` (nothing set `actual_delivery_date` before, so no
build could ever reach `delivered`) · real SLA via `trg_ticket_defaults` (high 4h / medium 24h /
low 72h) + sequential `T-001` numbers on every insert path · `trg_ticket_created` + `fn_notify_role`
so client requests are actually heard · `fn_create_ticket` · `fn_assign_ticket` · `fn_schedule_visit`
· `fn_resolve_ticket` · `fn_close_ticket` · `fn_reopen_ticket` · `fn_warranty_search` /
`fn_warranty_expiring`.

**→ ALL 8 ROLES COMPLETE**

## 9. Assignment chain hardening ✅ *(migration 0009)*

The roles were all built, but the **chain between them** was not. Full audit in
`docs/WORKFLOW_AUDIT.md` (~40 findings). Headlines:

**Step 1-2 — Admin creates the build, then assigns a PM**
- ✅ Client **account + login created together**, inline from Onboard Project (`＋ New`)
- ✅ Onboarding hides login-less client accounts (they can never see their truck)
- ✅ **PM is required**, and now changeable any time (Project detail → Project manager → Assign/Change)
- ✅ `fn_onboard_project` refuses a PM-less build · **Admin → Projects → No PM** finds legacy ones
- ✅ `fn_assign_pm` validates the target is an active PM · records who assigned · notifies both PMs

**Step 3-4 — PM sees their builds and hands out the work**
- ✅ PM's ＋ is now **Assign work** (was "Onboard project" — Admin-only work a PM could do)
- ✅ Stages carry a **`discipline`**; the assign sheet recommends that role and requires an explicit
  override to hand a design stage to a welder — enforced by `fn_assign_stage`, not just the UI
- ✅ Assignment carries **start + due dates** and notifies the assignee (and the previous one)
- ✅ New **Assign work** screen: every unassigned / rework stage across the PM's builds
- ✅ Workload counts all open stages, so someone holding 5 queued stages no longer reads "Free"

**Step 5 — the assignee actually sees and does the work**
- ✅ **Design is scoped to assigned builds** (`assignedProjectsProvider`) — it previously showed
  every truck in the company to every designer
- ✅ **Start work** action (`fn_start_stage`) — the transition nothing used to make
- ✅ Submit → addressed to the build's PM · duplicates blocked · refused if there is no PM
- ✅ Approve → stage done + `actual_end` + **next stage auto-starts** + client notified
- ✅ Reject → rework **with a reason** shown on the assignee's task card
- ✅ Client design approval **actually works** (`fn_client_decide_design`) — the old direct UPDATE
  silently changed nothing while showing "Design approved"

**Cross-cutting**
- ✅ `projects.status` is finally computed (`delivered → delayed → at_risk → on_track`), so every
  dashboard, at-risk count and on-time % stops lying · `current_stage_id` maintained
- ✅ Notifications are real: nothing in the app wrote a single row before (`fn_notify`)
- ✅ RLS tightened from blanket `is_staff()` writes to the documented per-role matrix
- ✅ `v_order_due` no longer leaks procurement data to clients (`security_invoker`)
- ✅ Clients can no longer read the staff directory
- ✅ Offboarding a PM / assignee no longer fails on a foreign key
- ✅ Recall "Notify all" actually notifies · scan-to-install validated server-side
- ✅ `full_setup.sql` is **generated** (`build_full_setup.sh`) — it had drifted and was missing 0005/0006
- ✅ `supabase/tests/run.sh` — Docker-only backend verification, ~40 assertions as real users

## 9. Real photos + barcode scanning ✅ *(migration 0011)*
- ✅ **Workshop site photos** — camera / gallery via `image_picker`, downscaled on device, uploaded
  to the new public **`builds`** bucket. Previously a random `picsum.photos` URL, so the client's
  build gallery showed stock photography.
- ✅ **Scan to install** — real `mobile_scanner` viewfinder + torch; the scanned serial is resolved
  (case-insensitive), checked to be in stock, then installed. **Manual serial entry** for damaged
  labels; a denied camera permission shows a clear state, not a black screen.
- ✅ **Client ticket photos** — attach a photo of the problem when raising a request; Service sees it
  on the ticket. A failed upload no longer loses the request.
- ✅ `0011_builds_storage.sql` — `builds` bucket + policies (staff anywhere, client only under
  `tickets/`) + ticket-attachment RLS for the client.
- 📄 Native permissions documented in `docs/NATIVE_SETUP.md`.

---
*Next: delay logging + bay allocation, template checklists, handover documents,
Admin/PM visibility of client tickets.*
*Migrations to run: 0005_bom, 0006_client_attachments, 0007_design_model, 0008_design_storage
(public 'designs' bucket), **0009_workflow**. Edge functions: admin-create-member (re-deploy — it now
returns `client_account_id`), admin-delete-member.*
*After 0009: assign a PM to any pre-existing build under Admin → Projects → No PM.*
