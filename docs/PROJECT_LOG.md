# BuildTrack — Project Log

**The single source of truth for "where is this project right now".**
Read this first. Update it at the end of every change — see [How to maintain this log](#how-to-maintain-this-log).

Last updated: **30 Jul 2026**

---

## 1. Where the project stands

| | |
|---|---|
| **What it is** | One Flutter app, 8 role-based experiences, for managing premium food-truck builds end to end |
| **Backend** | Supabase (Postgres + Auth + Storage + RLS). Migrations `0001` → `0009` |
| **Roughly complete** | **~75%** of the intended product. 7 of 8 roles usable, the core chain works, the two "hero" features work |
| **Not usable yet** | Service role, real photo upload, real QR scanning, documents, delay/bay tracking |
| **Deployed state** | Migrations through `0009`. Both Edge Functions live. Accounts created. Platform folders exist locally (untracked) |

### The operating chain — works end to end ✅

```
Admin   creates the build + the client's login  ──►  assigns a Project Manager
PM      sees only their builds  ──►  assigns each stage to the right discipline (+ dates)
Staff   see only their assigned work  ──►  start it, upload, submit
PM      approves  ──►  stage done  ──►  next stage auto-starts  ──►  client sees progress
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
| 📋 **PM** | 2 + shared | ✅ usable | My builds (real at-risk/delayed counts) · **Assign work** screen (every unassigned/rework stage across their builds) · assign stage → discipline-aware picker + start/due dates + workload · approvals (approve → next stage auto-starts / reject **with a reason**) · editable materials + delivery date (re-schedules) · team workload · bay list *(read-only, see gaps)* |
| 🛒 **Procurement** | 4 | ✅ usable | To-Order (order-by alerts) · create PO from an alert or manually · PO list + detail · mark dispatched / received (closes requirements, writes GRN) · vendors + add vendor · add catalog items inline |
| 📦 **Store** | 3 | ✅ usable | Inbox/receive · log component (serial + warranty + vendor, optionally assign to a build) · inventory + low-stock · component list + digital record · **recall check + working "Notify all"** |
| 🔧 **Workshop** | 3 | ✅ usable | My tasks (with due dates, overdue flags, **rework reason from the PM**, "awaiting approval") · **Start work** · checklist toggle · scan-to-install a part *(manual pick, not camera)* · add photo *(placeholder image)* · submit for approval |
| 🎨 **Design** | 3 | ✅ usable | **Scoped to assigned builds only** · studio stats · design library + filters · new design (upload `.glb` + preview to Storage) · new version after a change request · design detail with interactive 3D · client approval loop + feedback |
| 🙋 **Client** | 6 | ✅ usable | My trucks + progress + **3D showcase of the approved design** · stage timeline + per-stage photos · **approve / request changes on designs (now actually works)** · raise a request (ticket) · my requests · documents tab *(always empty — nothing creates documents)* |
| 🛠️ **Service** | 0 | ❌ **not built** | Falls back to a generic "role shell" placeholder. Client tickets have no consumer |

**Shared:** login · set-password (invite flow) · notifications feed · profile · role-based routing.

---

## 3. What's pending

### Blocking a complete product
1. **Service role — no screens at all.** Clients can raise tickets but nobody can see or resolve them.
   Needs: ticket queue, assign technician, resolution (warranty replace / repair / remote guide),
   `service_visits`, warranty lookup by serial. Tables already exist.
2. **Real build-photo upload.** `addStagePhoto()` attaches a random `picsum.photos` URL. Needs an
   `image_picker` + a `builds` Storage bucket + policies (mirror `0008` for `designs`).
3. **Real QR/barcode scanning.** "Scan to install" is a manual dropdown pick. Needs `mobile_scanner`.

### Features that exist in the schema but nothing writes to them
4. **`checklist_items` are never created.** Every stage has an empty checklist — templates can't
   define checks. Needs a `template_stage_checks` table + UI in Create Template.
5. **`delay_logs`** — never written, so Insights' "top delay reasons" can't work and the PM's
   "tag reason & reschedule" card has no action behind it.
6. **`bays`** — never assigned, so the PM Schedule tab always reports every bay "Free".
7. **`documents`** (contract / invoice / warranty pack / handover) — never created, so the client's
   Documents tab is permanently empty.

### Smaller
8. Profile "My details" is a coming-soon snackbar.
9. Workflow templates can't set a stage's `discipline` in the UI (inferred from the stage name;
   a PM can override per stage).
10. Delivery isn't an action — nothing sets `actual_delivery_date`, so nothing reaches `delivered`
    except by hand.
11. Client tickets aren't visible to Admin/PM anywhere.

---

## 4. Deploy / environment facts

- **Supabase:** migrations `0001`–`0009` applied. Storage bucket `designs` (public) from `0008`.
- **Edge Functions:** `admin-create-member`, `admin-delete-member` — both deployed.
  Service-role key is injected by Supabase automatically.
- **App config:** `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`
  (defaults in `core/supabase_client.dart` are placeholders).
- **Platform folders** (`android/`, `ios/`, `web/`) exist locally but are **not tracked in git**.
  Regenerating them with `flutter create .` wipes the deep-link edits in
  `AndroidManifest.xml` / `Info.plist` — re-apply from `INVITE_FLOW.md` §3–4.
  (`flutter create .` does *not* touch `lib/` or `pubspec.yaml` — verified.)
- **Adding members:** the "set a password now" path needs no SMTP. Email invites need Resend SMTP
  + redirect URLs + the deep-link edits (`INVITE_FLOW.md`).
- **Recommended cron:** `select public.fn_refresh_all_statuses();` daily — otherwise at-risk/delayed
  only recompute when a stage is touched, not as the calendar moves.

### Verifying a change

```bash
sh supabase/tests/run.sh        # backend: needs only Docker. ~49 assertions as real users
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
- **DB and app must ship together.** After `0009`, direct table writes are blocked — an old app
  build against the new schema will fail on assignment/approval.

---

## 6. Change log

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
