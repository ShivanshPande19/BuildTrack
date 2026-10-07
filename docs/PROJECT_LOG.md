# BuildTrack — Project Log

**The single source of truth for "where is this project right now".**
Read this first. Update it at the end of every change — see [How to maintain this log](#how-to-maintain-this-log).

Last updated: **7 Oct 2026** (premium motion + UI polish pass on `feat/premium-motion-ui-polish`, after the full code audit.)

---

## 1. Where the project stands

| | |
|---|---|
| **What it is** | One Flutter app, 8 role-based experiences, for managing premium food-truck builds end to end |
| **Backend** | Supabase (Postgres + Auth + Storage + RLS). Migrations `0001` → `0025`: 33 tables, 5 views, 53 functions (about 30 called by the app), 2 Edge Functions |
| **Where it stands** | **All 8 roles are usable** and the core chain works end to end, including both hero features and after-sales. PR #46 (Tier 1–3 hardening and one canonical build screen) merged **7 Oct 2026**. The latest work is an app-wide motion and UI polish pass with logic fixes (§6), with no schema change. The known gaps are real and listed in §3. The biggest ones: Design and Service can't submit their own stages, and several DB rules can be bypassed. |
| **Verified** | 7 Oct 2026, on `main`: `supabase/tests/run.sh` gives **149/149** assertions on both the migration chain and `full_setup.sql`. CI is green (Flutter analyze + test, Android debug build, Postgres suite). The polish branch: `flutter analyze` 0 errors / 0 warnings, `flutter test` **44/44** (26 model + 18 widget), run locally on Flutter 3.44.8. |
| **Shipped phases** | Phase 0 (buildable repo + CI) → Phase 1 (seven broken loops closed, `0012`–`0014`) → inventory truthfulness (`0015`–`0019`) → PO approvals + ops backbone (`0020`–`0024`) → UI polish (PRs #32–#45) → Tier 1–3 hardening (PR #46, `0025`) → motion + UI polish (no migration). See §6 and `WORKLOG.md`. |
| **Not started** | Offline support, push notifications, realtime, pagination, localization, dependency upgrades |
| **Deployed state** | The last *recorded* level is `0001`–`0014` (Aug 2026). No doc records whether `0015`–`0025` were applied, so check with `supabase/check_migrations.sql` (§4). Both Edge Functions are deployed; they last changed on 30 Jul 2026. |

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

Tabs and FAB are exactly what the bottom `PillNav` shows. The FAB does **one** thing per role, whatever tab is open.
Full per-screen detail: [`Roles.md`](Roles.md).

| Role | Tabs · FAB | What works | Known gap (see §3) |
|---|---|---|---|
| 👑 **Admin** | Home · Projects · Team · Insights · **＋ Onboard project** | **Home:** fleet status, **Command Center** (factory board: who's on what, stuck > 7 days, order-by passed), **PO approvals** (final sign-off, priority override), order-by "needs attention", unread bell badge. **Projects:** status chips + **Delivered** and **No PM** chips, opening the build screen in *Oversight · read-only* mode, where the PM can be assigned or changed and documents added. **Team:** members grouped by department, **Add member** pill beside the title (admin sets the password), sub-teams, swipe to remove, **Workspace → Company details** (GST buyer block). **Insights:** on-track % of active builds, distribution. **Onboard:** create a client login inline, **create a template inline** (stages, days, BOM, checklist). | Templates can't be listed or edited. |
| 📋 **PM** | Home · Projects · Schedule · Team · **＋ Assign work** | **Home:** counts, Assign work, **Approvals** (photos, checklist and parts as evidence; approve auto-starts the next stage, reject sends rework with a reason), **PO approvals** (sign or reject own builds' POs). **Projects:** build screen in *You manage this build* mode, with discipline-aware stage assignment (override, start/due), editable materials, delivery date (re-baselines), **Log delay** (+ push the date), **Mark delivered** (force if stages are open), documents. **Schedule:** open stages as overdue / today / next 7 days / later / no date. **Team:** read-only workload. Home's at-risk and today rows open the build. | Approvals stranded on PM hand-over (§3 #5). |
| 🛒 **Procurement** | To Order · Orders · Receive · Vendors · **＋ New PO** | **To Order:** hero alert pre-fills a PO; Store's essentials requests become a *general PO*. **New PO:** lines with rate + GST % + HSN, terms, live total, sent through `fn_create_po` into the approval chain. **PO detail:** approval stepper + signature trail, **Fix & resubmit** after rejection, mark dispatched (ETA), receive, **GST PO PDF** (CGST/SGST vs IGST, amount in words with paise, signatories). **Receive tab:** awaiting dispatch / ready to receive. **Vendors:** list, add vendor (GSTIN, state). | Only the hero To-Order item pre-fills a PO. No vendor detail. No partial receipt. |
| 📦 **Store** | Inbox · Stock · Parts · **＋ Log component** | **Inbox:** tracked / low-stock / lines + low-stock list. **Stock:** bulk items from `stock_items`, serialized items = in-stock component count; OK/Fair/Low; reorder or **Request from procurement** (essentials only, `fn_request_stock`). **Parts:** search by serial / model / truck, opening the component record (warranty banner, **bill viewer**, **Recall check → Notify all**). **Log component:** scan or type the serial, vendor, warranty, **bill photo**, optional build. | Inline "New item" is blocked by RLS for Store. No incoming-PO / GRN list. |
| 🔧 **Workshop** | Tasks · Parts · Week · **＋ Scan to install** | **My Tasks:** in progress / up next, due + overdue flags, rework reason, awaiting approval. **Task detail:** **Start work**, optimistic checklist, **camera photo**, install part, submit for approval (both guarded against a double tap). **Scan to install:** camera barcode + manual serial, in-stock check (`fn_install_component`). **Parts:** parts on my builds. **Week:** all my stages. | Workshop is the **only** role with a stage Start/Submit UI. |
| 🎨 **Design** | Studio · Designs · Approvals (profile via avatar) · **＋ New design** | **Scoped to assigned builds.** **Studio:** "Assigned to me" carousel, draft / awaiting / changes / approved stats. **Designs:** library + filters. **New design:** upload `.glb` (≤ 25 MB) + preview to the `designs` bucket, save draft or submit. **Design detail:** 3D/2D preview, client feedback, version history, **Upload revised / new version** (atomic numbering, `fn_add_design_version`). | Can't start or submit its **stage**. Submitting a design doesn't notify the client. |
| 🛠️ **Service** | Tickets · Trucks · Warranty · Profile · **＋ New ticket** | **Tickets:** SLA-sorted queue, **live 1-min countdown**, open / overdue / fixed-today (local calendar day). **Ticket detail:** client photos, assign technician, linked part warranty, visits, resolution. **Schedule visit** (one live booking per ticket). **Resolve** (warranty replace / repair / remote guide + note the client reads). **Close.** **Trucks:** delivered list (open tickets / warranty soon / healthy), opening truck history. **Warranty:** search by serial / model / truck. **New ticket** for phoned-in requests. | Can't start or submit its **stage**. "Linked component" never shows (nothing sets it). |
| 🙋 **Client** | My Trucks · Support · Profile · **＋ Raise request** | **My Trucks:** cards with a live **3D model** (approved design, else demo), opening the truck. **Truck** (one scroll): progress ring, current stage, delivery date, **Approve design** cards, build journey (opening stage photos), documents, raise request. **Approve design:** approve / request changes with feedback. **Raise request:** category, description, photo. **Support:** every ticket on my trucks (incl. Service-raised), resolution note, **Still not fixed** reopen. | Document "download" only shows a snackbar. No priority picker on requests. |

**Shared:** login · set-password (email-invite path) · notifications feed (Today / Yesterday / Earlier by local day, mark all read; every role's bell shows the unread count) · profile (Admin, PM, Procurement, Store, Workshop and Design use the shared `ProfileScreen`; Service and Client have their own Profile tab) · role-based routing.

**The build screen** (`BuildScreen`): every entry point opens it, from Admin Projects, the Command Center, PM Projects and PM Schedule. Its tabs are **Overview · Pipeline · Materials · Record**. The Overview banner states the mode: *Oversight · read-only* for Admin, *You manage this build* for the PM.

---

## 3. What's pending

Known gaps, found by reading the code line by line on 7 Oct 2026 and verified where marked ✔︎.
This is one continuous numbered list. Items 1–11 hurt a real build, 12–21 are DB rules that can be
bypassed, and 22–34 are smaller. Fixed items are ticked ✅ in place, so the numbers other docs cite stay stable. The full write-up is in [`WORKFLOW_AUDIT.md`](WORKFLOW_AUDIT.md) §7.

### Workflow gaps
1. ✔︎ **Design- and Service-discipline stages can't be started or submitted from the app.** Only Workshop has
   a Task detail. A stage like *Design & Layout* or *Testing & Delivery* stays `todo`, progress never
   reaches 100%, and delivery needs *Deliver anyway*. Workaround: the PM reassigns the stage to a
   workshop member with an override.
2. ✔︎ **Templates can only be created from Admin → Onboard project → Template "New".** There is no
   template list, edit or delete, and no per-stage `discipline` picker (it's inferred from the stage name). RLS lets a PM
   write templates, but the PM has no UI for it.
3. ✔︎ **Store's inline "New item"** (Stock → Request sheet, Log component) is refused by RLS:
   `item_catalog` writes are `admin, procurement, pm` only.
4. ✔︎ **Invited members stay `invited` forever.** Set-password's `profiles.update(status:'active')`
   is silently blocked by RLS (only admin can update `profiles`).
5. **A PM hand-over strands in-flight approvals.** `stage_approvals.approver_id` and
   `purchase_orders.pm_id` are snapshots. The new PM can't see pending stage approvals, and PO signing
   stays with the old PM until a resubmit.
6. **Log component → "Assign to build"** marks a part `installed` with no stage, bypassing
   `fn_install_component`. It shows under "Other / at intake" in the truck record.
7. ✔︎ **Removing a member who raised or signed a PO, or requested stock, fails.** Seven FKs to `profiles`
   have no `ON DELETE`: `purchase_orders.{pm_id, submitted_by, pm_signed_by, final_signed_by,
   rejected_by}`, `po_approval_events.actor_id`, `stock_requests.requested_by`.
8. **Submitting a design doesn't notify the client.** The "They've been notified" banner is untrue.
9. **Client document download** only shows "Opening document…". It never opens `file_url`.
10. **Notifications aren't tappable.** There's no deep link to the build, PO or ticket.
11. **Only the To-Order *hero* item pre-fills a PO.** A PO raised from the blank FAB isn't linked to its
    requirement, so the requirement stays `pending` and keeps alerting.

### DB rules that can be bypassed (fix in Postgres, not the UI)
12. ✔︎ **`fn_reopen_ticket` has no caller check.** Any signed-in user can reopen any ticket and force it to
    high priority.
13. **`SECURITY DEFINER` helpers are callable by anyone over RPC:** `fn_notify*` (spoofed notifications),
    `fn_audit`, `fn_recompute_schedule` (including the rebaseline) and `fn_refresh_all_statuses`. There is no `REVOKE EXECUTE`.
14. ✔︎ **`trg_guard_stages` doesn't guard `status` / `actual_*`.** An assignee can mark their own stage
    `done` with a direct UPDATE, skipping submit and approve.
15. **`trg_guard_projects` doesn't guard `actual_delivery_date`, `target_delivery_date` or `status`.** A PM can
    "deliver" by direct UPDATE, skipping `fn_mark_delivered`.
16. **`purchase_orders_update` lets Procurement set `approval_status = 'approved'` itself.** `po_lines` also stay
    editable after approval.
17. **`p_tickets_client_new`:** any signed-in user can insert a ticket on any project and pre-set
    status, assignee or SLA.
18. **`p_dappr_client`** allows ALL on `design_approvals` by `client_user_id`, with no project check.
19. **Disabled accounts can still sign in** and use their role's screens. RLS and `is_staff()` ignore
    `profiles.status`.
20. ✔︎ **`fn_receive_po` reads the PO status without a row lock.** Two simultaneous receives double the
    stock and write two GRNs. `stock_items` has no `unique(item_catalog_id)`.
21. **Both buckets are public-read.** Contracts and invoices under `builds/docs/` are readable by anyone
    with the URL.

### Smaller
22. Add member (Team) always sets a password. The email-invite path is only reachable from Onboard →
    New client with "Set a password now" unticked.
23. Profile "My details", "Account details", "Company profile" and "Roles & permissions" are coming-soon.
24. ✅ ~~Only Admin's bell shows an unread badge~~. Fixed by the polish pass: every role's bell (shared `RoleHeader`) shows the unread count, Procurement's included. `unreadCountProvider` is still unused (#31).
25. ✅ Workshop Start / Submit now use `AsyncPrimaryButton` (no double submit). Still open: "Mark stage complete" submits with checks open.
26. ✅ ~~Admin Projects has no Delivered chip~~. Fixed: a Delivered chip (Admin and PM) and a mint *Delivered* pill.
27. Log delay doesn't refresh the Pipeline delay ledger. Assign-PM, onboarding and approvals don't
    refresh the Command Center (`opsBoardProvider`) or Schedule.
28. Some providers aren't auth-aware: `purchaseOrders`, `vendors`, `items`, `essentialItems`,
    `templates`, `clients`, `pms`, `allProjects` and every `.family`. After switching accounts **on one device**
    they can show the previous user's data until refreshed.
29. ✔︎ **Fresh / demo databases have no essentials.** `seed.sql` runs after `0019`'s backfill, so *Steel sheet* is
    not `is_essential`, and Store's "Request from procurement" picker is empty.
30. Test gaps. The backend has no tests for `fn_receive_po` / stock, `fn_request_stock`, the rebaseline flag,
    `0012` checklist copying, `0014` or `0025`. App tests cover models plus the shared widgets / motion layer
    (`test/widgets_test.dart`), but not `slaLabel`, warranty state or `rupeesInWords`.
31. Dead code: the non-embedded navigation in `ProjectDetailScreen` / `ProjectDossierScreen`,
    `poDocProvider`, `unreadCountProvider`, and `RoleHome._titles` / `_navs`.
32. Client tickets aren't visible to Admin or PM anywhere.
33. SLA thresholds (4h / 24h / 72h) are fixed in `fn_sla_hours`.
34. Bay allocation is deliberately not built. `bays` / `stages.bay_id` stay in the schema, unused.

---

## 4. Deploy / environment facts

- **Supabase migrations:** `0001`–`0025` are in the repo. Applied as last recorded: `0001`–`0014`.
  To find out what the live database has, run **`supabase/check_migrations.sql`** in the SQL editor.
  It is read-only and prints `applied` / `RUN THIS` for `0004`–`0025`. Run the missing ones **in order**.
  - `0025` adds a UNIQUE index on `design_versions(artifact_id, version_no)`, so first check this returns
    0 rows: `select artifact_id, version_no, count(*) from design_versions group by 1,2 having count(*) > 1;`
  - Don't re-run `0019` (it resets every bulk item to essential). Don't re-run `0020` after `0021`
    (it re-creates the old `v_po_pending_approvals` with no priority columns and no grant). Everything else is
    safe to re-run.
  - From `0020` on, a PO must be raised through `fn_create_po`. From `0025` on, the app adds design
    versions through `fn_add_design_version`, so **the DB must be at `0025` before running the
    current app**.
- **Storage:** buckets `designs` (`0008`) and `builds` (`0011`), both public read.
  - `designs/<uid>/…` holds `.glb` files and previews.
  - `builds/stages/<stageId>/` holds site photos.
  - `builds/tickets/<ticketId>/` holds client ticket photos; it's the only path a client can write.
  - `builds/bills/` holds component bills.
  - `builds/docs/<projectId>/` holds build documents.
- **Edge Functions:** `admin-create-member` (password or email-invite mode; returns `client_account_id`)
  and `admin-delete-member`. Both are deployed. They last changed on 30 Jul 2026, so PR #46 needs no redeploy.
- **App config:** `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`
  (defaults in `core/supabase_client.dart` are placeholders).
- **Platform folders** (`android/`, `ios/`, `web/`) **are tracked** (since PR #5), with native config
  committed. CI fails if the manifest loses `CAMERA`, `INTERNET` or the `io.supabase.buildtrack` deep link.
  `flutter create .` overwrites them silently, so `git diff` after it. See [`NATIVE_SETUP.md`](NATIVE_SETUP.md).
- **Native requirements:** Android `minSdk` 23 + `CAMERA` + `INTERNET`; iOS 13 + camera/photo usage
  strings. Camera on web needs HTTPS. The iOS Simulator has no camera: the scanner shows its
  manual-entry state, and gallery picking works.
- **Adding members:** Team → Add member always sets a password, which needs no SMTP. The email-invite path
  (Onboard → New client with "Set a password now" unticked) needs Resend SMTP, redirect URLs and the
  deep link ([`INVITE_FLOW.md`](INVITE_FLOW.md)).
- **Recommended cron:** `select public.fn_refresh_all_statuses();` daily. The fleet, PM and Command Center
  screens also call it on load.
- **Testing on devices:** [`TESTING_GUIDE.md`](TESTING_GUIDE.md) has the deploy checklist and a phased
  2-device plan.

### Verifying a change

```bash
sh supabase/tests/run.sh        # backend, needs only Docker: 149 assertions in 7 suites, run twice
                                #   (migration chain + full_setup.sql), as real non-superuser users
cd app && flutter analyze && flutter test   # app: 0 errors (CI pins Flutter 3.44.8)
```

`supabase/full_setup.sql` is **generated** — never hand-edit it:
```bash
cd supabase && sh build_full_setup.sh
```

---

## 5. Decisions worth remembering

- **Admin = oversight + people.** Creates builds, client logins, members and templates (template creation
  lives inside Onboard project). Assigns the PM and gives final approval on POs. Does *not* assign
  stages or edit materials: the build screen opens in *Oversight · read-only* mode.
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
- **PO approval chain (`0020`).** A project PO goes Procurement → the build's PM signs → an admin gives final
  approval. A general / stock PO goes straight to final approval. Rejection is a **rework loop** (fix and
  resubmit), not a dead end. Dispatch and receive are refused until the PO is approved.
- **One build, one screen.** Every "open a build" entry point lands on `BuildScreen` (Overview ·
  Pipeline · Materials · Record). Capability comes from flags, and the mode banner makes it visible.
- **Motion is part of the design system** (`shared/animations.dart`). It uses Material 3 tokens (`Motion.fast/base/slow`,
  emphasized easing), no animation packages, and it respects *Reduce motion*. Pushed screens use the native **Cupertino** transition on
  iOS so edge-swipe-back keeps working (a custom fade broke it) and predictive back on Android. Tabs and async slots
  **fade through** (the old one leaves before the new one arrives) instead of cross-fading, which ghosts.
- **A role is a team, not a person.** Several PMs, designers, technicians and so on work at once. Scope "my work"
  by user id, guard every mutating action against double-taps, put numbering and claims in the DB (row
  lock / unique index), and invalidate every affected provider. See `.kiro/steering/product.md`.

---

## 6. Change log

### 7 Oct 2026: Premium motion + UI polish, with logic fixes (app only, no migration)

Branch `feat/premium-motion-ui-polish`. Every screen of all 8 roles was touched. No new dependencies.

- **Motion layer** (`shared/animations.dart`) rebuilt on Material 3 tokens:
  - `Motion.fast/base/slow` durations with emphasized easing, and `Haptic` (tap / confirm).
  - Building blocks: `staggered()` page cascades, `PressableScale` springs on every tappable card and button,
    `CountUp` glides from the old value, `BadgePop`, `AnimatedSwap`.
  - Loading: shimmer `SkeletonList` replaces bare spinners. `ContentReveal` makes skeleton → content
    **fade through** while the slot's height glides.
  - Navigation: `TabSwitcher` fades through, and the leaving tab keeps its state, so it no longer rebuilds and
    replays mid-fade (regression test added). Route transitions are native Cupertino on iOS, which keeps
    edge-swipe-back, and predictive back on Android. Every bottom sheet uses `sheetMotion`.
  - *Reduce motion* is respected throughout.
- **Design system** (`shared/widgets.dart`, new `shared/role_header.dart`):
  - Headers: `RoleHeader` (bell + avatar on every role), `BackChip` on every pushed screen.
  - Buttons: `PrimaryButton(busy:)` morphs label ↔ spinner in place, so forms no longer jump. New
    `SecondaryButton`, and `PillAction` for in-section actions.
  - Lists and states: `AppChip` / `ChipBar`, `SegmentTabs` with a sliding indicator, `ErrorCard` with **Retry**.
  - `PillNav` gets a gliding ink bubble.
- **Glitches fixed:**
  - Admin Team's *Add member* is a pill beside the Members title. Company details moved to a *Workspace*
    section, and Procurement's *Add vendor* got the same treatment.
  - The Design carousel is sized from a real card, so it no longer overflows or leaves an empty band. The date chips wrap.
  - Two-button rows (approve design, new design, log component, onboard client, materials sheet) keep both
    buttons. The tapped one spins and the other locks.
  - Ticket detail no longer prints a short description twice. The workshop checklist lost its stray last divider,
    and its hint is centred.
- **Logic fixes:**
  - Home *Active builds* and Insights *on-track %* exclude delivered builds, so the shares sum to 100% and the % no
    longer drops when a truck ships.
  - Admin and PM have a *Delivered* chip and label. A removed member no longer flashes back after the swipe.
  - PM Home: the at-risk and today rows open the build. Schedule opens the right build header. Team hides disabled members.
  - Service's *overdue* filter falls back when it empties. The client's *Raise a request* card is tappable.
  - Notifications group by **local** day (a UTC bug misfiled evening items). They have icons for the real backend
    types, and *Mark all read* is optimistic and guarded.
  - Every role's bell shows the **unread** count. Procurement's used to show "order today" (§3 #24).
  - Workshop Start / Submit can't double-fire (§3 #25). Approval cards are keyed by id, so the next card can't
    inherit a decided card's state, and a decided card folds away before the list refreshes.
  - Deleting a material requirement is guarded and shows failures. Before, the error was unhandled.
  - Loading and error states on pushed screens keep the back button. Company details, Ticket detail and the
    account-load error used to be dead ends. The role-load error now has Retry + Sign out.
- **Tests:** `test/widgets_test.dart` has 18 widget tests (nav, buttons, sheets, chips, tabs, motion,
  fade-through, `ContentReveal`, busy buttons). Each screen was also checked as rendered frames, mid-animation
  included, with a local harness that isn't committed.

**Watch out when deploying:** nothing server-side. On device, check the haptics, iOS edge-swipe-back on pushed
screens, and the 3D truck card, which can't render in tests.

### 7 Oct 2026: Full code audit + docs refresh (no code change)

Read every line: app (`lib/` ~18k lines), all 25 migrations, both Edge Functions, the test suites and the seeds.
Then brought every doc in line with the code. Several had drifted badly:

- `API.md` described a REST API that was never built.
- `DataModel.md` predated `0009`.
- `BUILD_PROGRESS.md` / `Roles.md` listed tabs and screens that don't exist (a tabbed client truck view,
  a Design "Profile" tab, PM template creation).
- Test counts were quoted as "~40", "~49", "83" and "111". The real number is 149.

New findings are §3 items 1–34 and `WORKFLOW_AUDIT.md` §7. Added `supabase/check_migrations.sql`, a
read-only "which migrations are applied" checker verified on Postgres 15. `TESTING_GUIDE.md` was rewritten
around it, with a phased 2-device plan. Re-verified: 149/149 backend assertions; CI green on `main`.

### 7 Oct 2026: Tier 1–3 hardening + one canonical build screen ([PR #46](https://github.com/ShivanshPande19/BuildTrack/pull/46), migration `0025`)

Built 28–30 Sep, merged 7 Oct.

- **Multi-user per role.**
  - New shared `AsyncPrimaryButton` and in-flight guards on PO sign / approve / reject / dispatch / receive,
    recall Notify all, Close ticket, PM approvals and client reopen. Mark all read got error handling.
  - A new member appears in the PM / assignee / technician pickers immediately.
  - **Atomic design version numbering:** `fn_add_design_version` takes a row lock, backed by
    `ux_design_versions_artifact_no`.
- **Correctness.**
  - Optimistic workshop checklist.
  - Broader invalidation after logging a part or approving a design.
  - The PO amount in words now spells out paise.
  - `.when` on the new-ticket truck picker.
  - `mounted` guards.
  - `friendlyError` everywhere instead of raw `$e`.
- **Polish.** Live SLA countdown (1-min tick), "fixed today" by local calendar day, Admin bell = unread
  count, the design carousel scales with text size, and controllers are disposed.
- **Navigation (Tier 3).**
  - `BuildScreen` (Overview · Pipeline · Materials · Record) is the single place every build opens.
  - The Overview **mode banner** shows "Oversight · read-only" or "You manage this build".
  - The FAB is stable per role: Admin is always *Onboard*, and Add member moved into the Team tab. Procurement
    is always *New PO*, and Add vendor moved into the Vendors tab.
  - `errorBuilder` on the client's full-screen photo.
- **Docs.** `TESTING_GUIDE.md`, `UX_NAVIGATION_AUDIT.md`, `.kiro/steering/product.md`.

**Watch out when deploying:** run `0025` (idempotent) **before** shipping this app build. "Upload new
version" calls `fn_add_design_version`. `full_setup.sql` is regenerated.

### 27–31 Aug 2026: UI polish (PRs #32–#45, no migrations)

- Fixed Design Studio and Workshop "my work" failing to load (ambiguous `stages`↔`projects` embed, PR #32).
- Design home: profile in the header and an *Assigned to me* carousel with dates (#33).
- `AppSelectField` bottom-sheet selector replaces Material dropdowns (#34).
- Admin Team grouped by department, with filter pills (#35–#36).
- Nav bar iterations ending in a **floating pill over the content** (`extendBody`) (#37–#40, #45).
- Edge-to-edge transparent system bars, keeping the top safe area while the bottom runs edge-to-edge (#39, #43–#44).
- A **motion layer**, `shared/animations.dart`: `FadeSlideIn`, `PressableScale`, `CountUp`,
  `AnimatedBar`, `TabSwitcher`, plus fade-through page transitions (#41–#42).

### 26 Aug 2026 — Build status now honours the delivery date (migration `0024`)

Bug: a build whose promised delivery date had passed still showed **on-track**.
`fn_recompute_status` only looked at per-stage `planned_end` dates — it never
checked the project's own `target_delivery_date`. So a build with no/late stage
dates but a blown delivery date stayed on_track. Two fixes:

- **Logic** — not delivered + `target_delivery_date` in the past → **delayed**;
  not delivered + delivery within 7 days with work still open → **at-risk**. (The
  old stage-overrun / order-by / unstarted-stage rules still apply.) The migration
  re-runs `fn_refresh_all_statuses()` so existing builds correct themselves on
  deploy.
- **Freshness** — statuses only recomputed when a stage was touched, so they went
  stale as the calendar moved (there was no daily cron scheduled). The fleet
  dashboard, command center and PM dashboard now call `fn_refresh_all_statuses()`
  on load, so the owner always sees the truth. (A daily
  `select fn_refresh_all_statuses();` cron is still recommended for good measure.)

**Watch out when deploying:** run `0024_status_delivery_date.sql` — it recomputes
every build's status immediately.

### 22 Aug 2026 — Per-truck complete record (migration `0023`)

Phase 3 of the ops backbone. Every part fitted to a build already lived in
`component_instances` (serial, bill, warranty, the stage it went into, who
installed it — Hero #2); this surfaces it as one screen — the truck's digital
twin — so a warranty claim, an audit or a handover pack never means hunting
stage by stage.

- **`v_truck_components`** (migration `0023`) — every installed component for a
  build joined to its item, vendor, stage and installer. Read model, no new
  tables; stays off the client via RLS.
- **Truck Record** screen (Admin → dossier → *Truck record*): a dark summary
  (parts tracked + warranties **in-warranty / expiring / expired**), the
  components **grouped by the stage they were fitted in** — each with serial,
  vendor, install date + installer, a warranty badge and its **bill** (tap to
  view) — and the build's documents.

**Watch out when deploying:** run `0023_truck_record.sql` (view granted to
`authenticated`).

### 22 Aug 2026 — Project dossier: full pipeline + delay attribution (migration `0022`)

Phase 2 of the ops backbone. The command center says *which* builds need a look;
the dossier tells the whole story of one build in a single read-only screen, so
the owner never has to drill stage by stage or ask who held what.

- **`v_project_delays`** (migration `0022`) — joins each `delay_log` to its stage,
  the person who logged it, and the stage's assignee. Read model only; no new
  tables. RLS still keeps delays off the client.
- **Project Dossier** screen (Admin → Command Center → tap a build · or Project
  detail → *Pipeline & delays*):
  - **Where it is / who has it** — the current stage, the assignee **+ sub-team**,
    progress, total delay days, delivery date, in one dark summary card.
  - **Delay ledger** — every slip with the stage, reason, days, the note, and who
    logged it, plus a running total.
  - **The pipeline** — every stage read-only: assignee (+ sub-team), discipline,
    **planned vs actual** dates (late finishes flagged), status, and an inline
    "slipped N days · reason" badge on the stages that lost time.
- Command-center rows now open the dossier (the natural drill-down); the dossier
  has an *Open build controls* link back to the action screen.

**Watch out when deploying:** run `0022_project_delays.sql` (the view is granted
to `authenticated`).

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

### 10–11 Aug 2026: Inventory truthfulness (migrations `0015`–`0019`, PRs #17–#23)

- **`0015`:** changing the delivery date re-baselines each open stage's *assigned* dates too.
  `fn_recompute_schedule` gets `p_rebaseline_assigned`, which only the delivery-date action passes.
- **`0016`:** a PO must be **dispatched (with an ETA) before it can be received**.
- **`0017`:** `stock_requests` + `fn_request_stock`. Store raises reorders and Procurement fills them with
  general POs.
- **`0018`:** receiving tops up `stock_items` for **bulk** items only. Serialized parts enter stock when
  Store logs their serials. The Stock tab counts serialized on-hand from the component ledger.
- **`0019`:** `item_catalog.is_essential`. Store's request picker offers essentials only. The backfill
  marks existing bulk items as essential (see §3 #29 for the seed caveat).

### 5 Aug 2026: Phase 1, seven broken loops closed (migrations `0012`–`0014`, PRs #7–#13)

Template checklists, stock movement on receipt, client ticket visibility, bill capture, delay logging,
documents, and PM approval evidence. Details in [`WORKLOG.md`](WORKLOG.md).

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
