# BuildTrack — Project Log

**The single source of truth for "where is this project right now".**
Read this first. Update it at the end of every change — see [How to maintain this log](#how-to-maintain-this-log).

Last updated: **22 Aug 2026** (ops command center)

---

## 1. Where the project stands

| | |
|---|---|
| **What it is** | One Flutter app, 8 role-based experiences, for managing premium food-truck builds end to end |
| **Backend** | Supabase (Postgres + Auth + Storage + RLS). Migrations `0001` → `0021` |
| **Roughly complete** | **~90%** of the intended product. **All 8 roles usable**, the core chain works, the two "hero" features work, after-sales closed |
| **Phase 1 shipped** | Documents, delay logging, template checklists, stock movement, bill capture, PM approval evidence, client ticket visibility — all closed (PRs #7–#13, migrations 0012–0014). See `WORKLOG.md`. |
| **Not started (Phase 2)** | Offline support, push notifications, realtime, pagination, localization, dependency upgrades |
| **Deployed state** | Migrations through `0010`. Both Edge Functions live. Accounts created. Platform folders (`app/android`, `app/ios`, `app/web`) tracked in the repo |

### The operating chain — works end to end ✅

```
Admin   creates the build + the client's login  ──►  assigns a Project Manager
PM      sees only their builds  ──►  assigns each stage to the right discipline (+ dates)
Staff   see only their assigned work  ──►  start it, upload, submit
PM      approves  ──►  stage done  ──►  next stage auto-starts  ──►  client sees progress
```

Then, after handover:

```
PM      marks the build delivered  ──►  it enters after-sales
Client  raises a request           ──►  every service member is notified
Service triages → assigns a technician → books a visit
Service resolves (warranty replace / repair / remote guide)  ──►  client told
Client  can reopen if it is still broken  ──►  jumps the queue at high priority
```

Enforced in Postgres (RLS + guard triggers + `SECURITY DEFINER` RPCs), not just the UI.
A welder can't create a project; a PM can't touch someone else's build; a design stage can't go to
a fabricator without an explicit override. Full detail: [`WORKFLOW_AUDIT.md`](WORKFLOW_AUDIT.md).

### The two hero features — both work ✅

1. **Order-by alert engine** — template BOM → onboarding auto-generates requirements →
   backward-scheduled `order_by = needed_by − lead_time − buffer` → `v_order_due` surfaces
   "order this in N days" to Admin + Procurement.
2. **Component traceability / recall** — Store logs a serial + warranty + bill → Workshop links it
   to a truck + stage → given a faulty model, `fn_recall` lists every affected truck and
   `fn_recall_notify` notifies each build's PM and client.

---

## 2. What each role can do today

| Role | Screens | Status | What works |
|---|---|---|---|
| 👑 **Admin** | 7 | ✅ usable | Fleet dashboard (health, order-by alerts) · onboard project **+ create the client's login inline** · **assign / change the PM** · **No PM** filter for stranded builds · project detail + stage detail (read-only oversight) · materials/order-by view · team management (add/delete members, all 8 roles) · create workflow template + BOM · insights |
| 📋 **PM** | 2 + shared | ✅ usable | My builds (real at-risk/delayed counts) · **Assign work** screen (every unassigned/rework stage across their builds) · assign stage → discipline-aware picker + start/due dates + workload · approvals (approve → next stage auto-starts / reject **with a reason**) · editable materials + delivery date (re-schedules) · **mark delivered** (hands the truck to after-sales) · team workload · **Schedule** (open stages by due date — overdue / today / next 7 days / later / no date) |
| 🛒 **Procurement** | 4 | ✅ usable | To-Order (order-by alerts) · create PO from an alert or manually · PO list + detail · mark dispatched / received (closes requirements, writes GRN) · vendors + add vendor · add catalog items inline |
| 📦 **Store** | 3 | ✅ usable | Inbox/receive · log component (serial + warranty + vendor, optionally assign to a build) · inventory + low-stock · component list + digital record · **recall check + working "Notify all"** |
| 🔧 **Workshop** | 3 | ✅ usable | My tasks (with due dates, overdue flags, **rework reason from the PM**, "awaiting approval") · **Start work** · checklist toggle · **scan a part's QR/barcode to install it** (with manual-serial fallback) · **take a real site photo** (camera or gallery, uploaded to the `builds` bucket) · submit for approval |
| 🎨 **Design** | 3 | ✅ usable | **Scoped to assigned builds only** · studio stats · design library + filters · new design (upload `.glb` + preview to Storage) · new version after a change request · design detail with interactive 3D · client approval loop + feedback |
| 🙋 **Client** | 6 | ✅ usable | My trucks + progress + **3D showcase of the approved design** · stage timeline + per-stage photos · **approve / request changes on designs (now actually works)** · raise a request (ticket) **with a photo of the problem** · my requests **with the resolution and a "still not fixed" reopen** · documents tab *(always empty — nothing creates documents)* |
| 🛠️ **Service** | 5 | ✅ usable | Ticket queue sorted by **SLA countdown** (open / overdue / fixed-today) · ticket detail with the linked part's **warranty state** · triage to a technician · **schedule a visit** (tech + date + time + note) · **resolve** (warranty replace / repair / remote guide) with a note the client reads · close · **delivered trucks** list with open-ticket / warranty health · **truck history** (parts tracked, warranty position, every past request) · **warranty lookup** by serial / model / truck · **sees the client's photos** on a ticket · log a phoned-in ticket |

**Shared:** login · set-password (invite flow) · notifications feed · profile · role-based routing.

---

## 3. What's pending

### Features that exist in the schema but nothing writes to them
1. **`checklist_items` are never created.** Every stage has an empty checklist — templates can't
   define checks. Needs a `template_stage_checks` table + UI in Create Template.
2. **`delay_logs`** — never written, so Insights' "top delay reasons" can't work and the PM's
   "tag reason & reschedule" card has no action behind it.
3. ~~**`bays`**~~ — **removed from the app.** Nothing in the app or the database ever set
   `stages.bay_id` or `bays.current_stage_id`, so the PM Schedule tab could only ever report
   every bay "Free". The bay board is gone; Schedule now shows the PM's open stages grouped as
   overdue / due today / next 7 days / later / no date, off `assigned_due` (what the PM
   committed to) falling back to `planned_end` (backward scheduling). The `bays` table and
   `stages.bay_id` are still in the schema, untouched, for whenever bay allocation is actually
   built.
4. **`documents`** (contract / invoice / warranty pack / handover) — never created, so the client's
   Documents tab is permanently empty.

### Smaller
5. Profile "My details" is a coming-soon snackbar.
6. Workflow templates can't set a stage's `discipline` in the UI (inferred from the stage name;
   a PM can override per stage).
7. Client tickets aren't visible to Admin/PM anywhere (Service and the client see them).
8. SLA thresholds (4h / 24h / 72h) are fixed in `fn_sla_hours` — the designed "SLA settings" screen
   would make them configurable.

---

## 4. Deploy / environment facts

- **Supabase:** migrations `0001`–`0011` applied. Storage buckets `designs` (from `0008`) and
  `builds` (from `0011`), both public read.
- **Edge Functions:** `admin-create-member`, `admin-delete-member` — both deployed.
  Service-role key is injected by Supabase automatically.
- **App config:** `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`
  (defaults in `core/supabase_client.dart` are placeholders).
- **Platform folders** (`android/`, `ios/`, `web/`) exist locally but are **not tracked in git**.
  Regenerating them with `flutter create .` wipes the native edits — re-apply the camera/photo
  permissions from [`NATIVE_SETUP.md`](NATIVE_SETUP.md) and the deep links from
  `INVITE_FLOW.md` §3–4. (`flutter create .` does *not* touch `lib/` or `pubspec.yaml` — verified.)
- **Native requirements:** Android `minSdk` 23 + `CAMERA` + `INTERNET`; iOS 13 + camera/photo usage
  strings. Camera on web needs HTTPS.
- **Adding members:** the "set a password now" path needs no SMTP. Email invites need Resend SMTP
  + redirect URLs + the deep-link edits (`INVITE_FLOW.md`).
- **Recommended cron:** `select public.fn_refresh_all_statuses();` daily — otherwise at-risk/delayed
  only recompute when a stage is touched, not as the calendar moves.

### Verifying a change

```bash
sh supabase/tests/run.sh        # backend: needs only Docker. ~83 assertions as real users
cd app && flutter analyze       # app: must report 0 errors
```

`supabase/full_setup.sql` is **generated** — never hand-edit it:
```bash
cd supabase && sh build_full_setup.sh
```

---

## 5. Decisions worth remembering

- **Admin = oversight + people.** Creates builds, client logins, members, templates. Assigns the PM.
  Does *not* assign stages or edit materials (opens project detail read-only).
- **PM = build planning.** Owns stage assignment, materials/requirements, delivery date, approvals.
  Cannot create projects or change who owns a build (RLS + `trg_guard_projects`).
- **Stage assignees = workshop / design / store / service only.** Never admin/pm/procurement/client.
- **Every stage has a `discipline`**, so the right role is recommended and mismatches need an
  explicit override.
- **A build must always have a PM.** `fn_onboard_project` refuses without one; a PM-less build is
  stranded (invisible to PMs, unassignable, unapprovable).
- **A client's account and login are always created together.** An account without
  `contact_user_id` can never see its truck.
- **Business rules live in the database**, exposed as RPCs, so they hold no matter what calls them.
  The app surfaces their messages via `friendlyError()`.
- **DB and app must ship together.** From `0009` on, direct table writes are blocked — an old app
  build against the new schema fails on assignment/approval, and on `0010` it would miss ticket
  SLAs and the delivery handover.

---

## 6. Change log

### 22 Aug 2026 — Ops command center: sub-teams, PO priority, factory board (migration `0021`)

The owner wanted to stop walking the floor asking "which build is where, who's on
it, what needs signing first". Phase 1 of the operations backbone:

- **Sub-teams.** A department (role) like Workshop splits into teams — Welding,
  Paint, Electrical, Fitter — while small departments (Design) have none. New
  `sub_teams` table (department → team) + `profiles.sub_team_id`. Add Member gains
  a department-aware team picker with inline "new team"; admin manages the list.
- **PO approval priority.** Many POs land at once; the owner should sign the one
  that unblocks the soonest delivery first. Priority is derived deterministically
  from the item's order-by date — overdue = **critical**, ≤3 days = **high**,
  ≤7 days = **medium**, later = **low**, a general PO with no date = medium — with
  an **admin override** (`fn_set_po_priority`). The approvals inbox sorts by it and
  shows a priority stripe + badge; admin taps the badge to bump/clear it.
- **Command center** (`v_ops_board` → Admin → Home → *Command Center*). One live
  screen: active builds count + on-track/at-risk/delayed, a **by-department** strip
  (how many builds each department is on right now), a **needs-attention** list
  (delayed / at-risk / stuck > 7 days in a stage / order-by passed), and the full
  board — each build's current stage + department + assignee **+ sub-team** + how
  long it's sat there + progress + next order-by. Delivered builds drop off.

**Watch out when deploying:** run `0021_ops_command_center.sql`. Sub-teams seed
Workshop's four; other departments start empty (add via Add Member). Views are
`grant`ed to `authenticated` in the migration.

### 22 Aug 2026 — Multi-level PO approval chain + delay trail (migration `0020`)

Purchase orders used to go live the instant Procurement created them — a bare
`INSERT` with status `ordered`, nobody signing anything. That is not how the
business actually buys: Procurement raises a PO (with clarity from the PM), the
**PM signs** it, and then it reaches an **owner/admin (Puneet / Shelly mam) for
final approval** before the order is placed. When a signature is late the order
slips, and there was no record of where it was held up.

**Backend (`0020_po_approvals.sql`)** — a separate approval lifecycle
(`pending_pm → pending_final → approved / rejected`) that gates the existing
fulfilment lifecycle (`ordered → dispatched → received`):
- `fn_create_po` — the only way a PO is raised now (direct inserts are blocked
  by RLS). Computes header totals from per-line rate + GST, routes project POs
  to the PM and general/stock POs straight to final approval, and parks the
  requirement / stock request it fulfils.
- `fn_pm_sign_po` · `fn_final_approve_po` · `fn_reject_po` · `fn_resubmit_po`.
  Rejection is a **rework loop, not a dead end**: the PO goes back to
  procurement with the remark (the requirement stays parked), they fix it and
  resubmit, and it re-enters the chain from the top. When the *owner* rejects a
  PO the PM had signed, the PM is kept in the loop too.
- `po_approval_events` — an immutable, timestamped trail of every signature and
  rejection (who, when): **the delay log for approvals**.
- A guard trigger refuses to dispatch/receive a PO until it is approved.
- `v_po_pending_approvals` — the approvals queue with waiting time + an overdue
  flag against the order-by date.
- Money + tax + HSN on the lines, buyer identity (`company_settings`) and vendor
  GSTIN/address were added too, for the office-level PO document (rendered in a
  follow-up).
- RLS: PO costs are now kept off the shop floor (workshop/design/service/client
  can't read POs). 111 backend assertions pass; migration is idempotent.

**Office-level PO document (app-only follow-up)** — a proper GST purchase order is generated on
device with `pdf` + `printing`: buyer + supplier (GSTIN), line items with HSN/SAC + rate, the
CGST/SGST (same state) or IGST (inter-state) split, the grand total in words, terms, and an
authorised-signatory block filled from the approval trail. View / print / share from the PO detail.
Buyer identity lives in Admin → Team → Company details; vendor GSTIN + state are captured on the
vendor form. New deps: `pdf`, `printing`.

**App** — the New PO form captures per-line rate + GST + delivery/payment terms
and shows a live total; it is the single path a PO is raised through (To-Order
alerts and Store reorders open it pre-filled). PO detail shows the approval
stepper, the signature trail, the amount + GST breakdown, and the right action
for the viewer (PM signs, admin approves, either rejects with a reason). A
role-aware **PO Approvals** inbox is surfaced on the PM home and the admin
dashboard, flagging how long each PO has waited and which are overdue.

**Watch out when deploying:** run `0020_po_approvals.sql`. Existing POs are
grandfathered to `approved`. From this migration on, a PO must be raised through
`fn_create_po` — an old app build doing a direct insert will be refused by RLS.

### 30 Jul 2026 — Real photos and real barcode scanning (migration `0011`)

Two placeholders that shipped in every role became real.

- **Build photos were stock photography.** `addStagePhoto()` inserted a random `picsum.photos` URL,
  so the gallery the *client* watches their truck through was showing pictures of strangers' things.
  Now: `image_picker` (camera or gallery) → downscaled to 1600px / q82 on the device → uploaded to a
  new public **`builds`** bucket → the attachment points at the real file.
- **"Scan to install" never used the camera** — it was a dropdown of in-stock parts. Now a real
  `mobile_scanner` viewfinder with a torch toggle; the scanned serial is looked up
  (case-insensitive), checked to be genuinely in stock, then installed through the same confirmation.
  **Manual serial entry** is kept for damaged labels, and a denied camera permission shows a clear
  state instead of a black screen.
- **The client can attach a photo to a support request** (it was a coming-soon snackbar), and
  Service sees it under *Photos from the client* on the ticket — usually faster than reading the
  description. A failed photo upload no longer loses the request itself.

New deps: `image_picker`, `mobile_scanner`. Storage policy (`0011`) lets staff write anywhere in
`builds` but a client only under `tickets/`.

**Watch out when deploying:** run `0011`, then apply the native permission edits in
[`NATIVE_SETUP.md`](NATIVE_SETUP.md) — Android needs `CAMERA` (and `INTERNET` for release builds),
iOS needs `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription`, `minSdk` 23, iOS 13.
Without them the camera silently fails to open.

### 30 Jul 2026 — Service role built, after-sales loop closed (migration `0010`)

The last unbuilt role. Clients could raise requests but nothing consumed them, and no truck could
even reach `delivered`, so after-sales had no data to work with.

**Backend (`0010_service.sql`)**
- `fn_mark_delivered` — the missing handover step. Nothing set `actual_delivery_date`, so no build
  could ever become `delivered`. Refuses while stages are unapproved unless forced; notifies the
  client and the service team.
- SLA is real: `trg_ticket_defaults` stamps `sla_due` (high 4h · medium 24h · low 72h) and a
  sequential `T-001` number on **every** insert path, so the client's own screen gets it too.
  Ticket numbers used to be `R-<millis>` generated in Dart.
- `trg_ticket_created` notifies every service member — a client request used to go nowhere.
- `fn_notify_role` — notify a whole role (the piece that was missing for this).
- `fn_create_ticket` (phoned-in requests) · `fn_assign_ticket` · `fn_schedule_visit`
  (one live booking per ticket; re-scheduling cancels the old one) · `fn_resolve_ticket` (a note is
  mandatory — the client reads it) · `fn_close_ticket` (only after resolve) · `fn_reopen_ticket`
  (client-facing; re-prioritises to high).
- `fn_warranty_search` / `fn_warranty_expiring` — lookup by serial / model / truck, staff-only.
- A client can now see the visit booked on their own ticket (`p_visits_client`).

**App** — 5 new screens under `features/service/`: ticket queue (SLA-sorted), ticket detail with the
linked part's warranty state, resolve, schedule visit, new ticket, truck history; plus delivered
trucks and warranty lookup tabs. `role_home` routes `service` → `ServiceHome`. PM project detail gains
**Mark delivered**. The client's requests now show the resolution and a "still not fixed" reopen.

**Watch out when deploying:** run `0010`; ticket numbering switches from `R-…` to `T-…` (existing
tickets are backfilled with both a number and an SLA); a build must be marked delivered by its PM
before it appears to Service.

**Found and fixed while testing:** resolving a ticket sent the client **two** identical
notifications (once as the project's client, once as the raiser).

Verified: 83 backend assertions pass (`supabase/tests/run.sh`, now including `20_service_tests.sql`),
`flutter analyze` reports 0 errors.

### 30 Jul 2026 — Assignment chain made real and enforced ([PR #1](https://github.com/ShivanshPande19/BuildTrack/pull/1), merged)
Audited the whole repo against the intended flow; ~40 findings in [`WORKFLOW_AUDIT.md`](WORKFLOW_AUDIT.md).

Added `0009_workflow.sql`, rewired the Flutter data layer onto RPCs, added the PM **Assign work**
screen, Admin **PM assign/change**, and `supabase/tests/`.

Biggest things that were broken and are now fixed:
- PM could only be set at creation, was optional, and had no change screen → PM-less builds were
  permanently stranded
- PM's ＋ button created projects and client logins (Admin-only work)
- Any staff member could update or delete any stage of any project, including self-assigning
- Design ignored assignment entirely — every designer saw every truck
- Stages never became `in_progress` (nothing made the transition)
- Client design approval silently did nothing (client has no UPDATE policy — 0 rows, "success")
- `projects.status` was never computed → every dashboard number was wrong
- Notifications were dead — no code wrote a single row
- `v_order_due` leaked all procurement data to any signed-in user, clients included
- Deleting a PM or assignee failed on a foreign key
- `full_setup.sql` had drifted (missing `0005`'s BOM table + `0006`'s policy)

**Migration notes:** existing projects change status (correctly) as real dates apply · PM-less
builds surface under Admin → Projects → **No PM** · stage `discipline` is backfilled from names
(check `Paint & Branding` → design, `Testing & Delivery` → service) · login-less client accounts
disappear from the onboarding picker.

### Before that
See [`BUILD_PROGRESS.md`](../BUILD_PROGRESS.md) for the per-role build history
(Admin → Procurement → Store → Workshop → PM → Client → Design), the 3D showcase, and the
Hero #1 order-by chain.

---

## How to maintain this log

At the end of **every** change, update:
1. **§1** if the overall state moved (roles usable, deployed migration level).
2. **§2** if a role gained or lost a capability.
3. **§3** — tick off what you finished, add what you discovered.
4. **§4** if setup/deploy steps changed (new migration, new bucket, new env var, new dependency).
5. **§5** if a rule or ownership decision changed.
6. **§6** — add a dated entry: what changed, why, what to watch out for when deploying.

Keep it factual and short. If something is half-built, say so — an honest gap is more useful than an
optimistic tick. Verify claims (`flutter analyze`, `supabase/tests/run.sh`) before writing ✅.

Two things that go stale quietly:
- **The migration number appears in §1, §4 and §5.** After adding a migration, grep the file for the
  previous number and update every hit.
- **The assertion count in §4** — read it off the actual test run, don't carry the old number over.
- **§3 is one continuous numbered list** across all three sub-headings. Renumber after removing an item.
