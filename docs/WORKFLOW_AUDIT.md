# BuildTrack — Workflow Audit (Admin → PM → Role staff)

Full read-through of the repo (docs + schema + RLS + functions + every Flutter screen) against the
intended chain:

```
1. Admin creates a project  +  creates that project's client login
2. Admin assigns the project to a Project Manager
3. PM sees only the projects assigned to them
4. PM assigns each build stage to the right role (design → designer, workshop → fabricator …)
5. The assignee sees that project/stage, works on it, and uploads their output
```

Legend — **Sev:** 🔴 blocker (breaks the flow) · 🟠 wrong/weak logic · 🟡 gap/polish · 🔒 security.
**State:** ✅ fixed in this pass · ⬜ known remaining gap.

---

## 1. Step 1 — Admin creates project + client account

| # | Sev | Problem | Fix |
|---|---|---|---|
| A1 | 🔴 | Client could **not** be created while onboarding. Admin had to leave, go to Team → Add member (role=client), come back. The screen even admitted it ("Clients appear here once added as users"). | ✅ Onboard Project now has an inline **＋ New** client that creates the auth login + profile + `client_accounts` row in one step (via the existing `admin-create-member` Edge Function) and selects it. |
| A2 | 🔴🔒 | `AdminRepo.createClient()` inserted a `client_accounts` row with **no `contact_user_id`** → a client account nobody can log into. Any project attached to it is invisible to the client forever (`my_client_account()` returns null → RLS matches no rows). | ✅ Method deleted. Client accounts can now only be created together with their login. |
| A3 | 🟠 | The Client dropdown listed **every** `client_accounts` row, including login-less ones (e.g. the demo `Ramesh Traders` from `seed.sql`). | ✅ `AdminRepo.clients()` now only returns accounts that have a linked login; onboarding warns when login-less accounts exist. |
| A4 | 🟡 | Duplicate project `code` surfaced a raw `PostgrestException` to the admin. | ✅ Friendly, mapped error messages (duplicate code / missing field / permission). |
| A5 | 🟠 | `fn_onboard_project` silently did nothing if the template had zero stages, or if the project already had stages. | ✅ Raises a clear exception when the template has no stages; still idempotent otherwise. |

## 2. Step 2 — Admin assigns the project to a PM

| # | Sev | Problem | Fix |
|---|---|---|---|
| B1 | 🔴 | **PM could only ever be set at creation time, and it was optional.** There was no "assign PM" / "change PM" screen anywhere in the app. A project onboarded without a PM was permanently stranded: no PM sees it (`pm_id = me`), and Admin opens project detail with `canAssign: false`, so *nobody* could assign its stages. The bundled `seed.sql` project (`AZ-118`) is exactly this case. | ✅ PM is now **required** at onboarding, `fn_onboard_project` refuses a project with no PM, and Project detail has a **Project manager** card where an admin can assign / change the PM at any time. |
| B2 | 🟠 | No validation that the chosen PM actually has `role = 'pm'` or is still active. | ✅ `fn_assign_pm` verifies role + status server-side. |
| B3 | 🔴 | Admin had **no way to spot** PM-less projects in the fleet list. | ✅ Projects tab has a **No PM** filter chip and every row shows a "No PM" pill. |
| B4 | 🟠 | Nobody was notified about anything, ever — **no code in the app wrote a single `notifications` row.** The bells, the feed and `seed_notifications_demo.sql` were decoration. | ✅ Server-side `fn_notify` + notifications on: PM assigned/reassigned, stage assigned/unassigned, stage started, stage submitted, stage approved/rejected, design decided, recall. |
| B5 | 🔒 | `notifications` RLS was `using (user_id = auth.uid()) with check (user_id = auth.uid())` — you can only insert notifications **for yourself**, so cross-user notification was impossible by construction. | ✅ Writes now go through the `SECURITY DEFINER` `fn_notify`; the own-row policy stays for reads. |
| B6 | 🟡 | No record of *who* assigned a PM and when. | ✅ `projects.pm_assigned_by` / `pm_assigned_at` + `audit_log` entry. |

## 3. Step 3 — PM sees their projects

| # | Sev | Problem | Fix |
|---|---|---|---|
| C1 | 🔴🔒 | **PM's ＋ button opened "Onboard Project".** A PM could create projects *and* client accounts — Admin-only work per `Roles.md`. RLS allowed it too (`p_projects_write … for all … or pm_id = auth.uid()` covers INSERT, and the PM just sets themselves as PM). | ✅ PM's ＋ is now **Assign work**. `projects` INSERT/DELETE is admin-only in RLS, and a guard trigger stops a non-admin changing `pm_id`, `code`, `client_account_id` or `template_id`. |
| C2 | 🟠 | PM's "active builds" count included `delivered` projects. | ✅ Delivered builds are counted separately. |
| C3 | 🟡 | `myProjectsProvider` correctly filters `pm_id = me`. No change needed. | — |

## 4. Step 4 — PM assigns stages to the right role

| # | Sev | Problem | Fix |
|---|---|---|---|
| D1 | 🔴 | **A stage had no notion of which role should do it.** `assignableMembers()` returned every workshop + design + store + service member in one flat list, so a PM could hand "Design & Layout" to a welder and "Electrical work" to a designer. Nothing anywhere linked a stage to a discipline. | ✅ New `stages.discipline` / `template_stages.discipline` (`user_role`). Existing rows are backfilled by `fn_infer_discipline(name)`. The assign sheet now shows **Recommended · <discipline>** first and requires an explicit confirm to override with another role; `fn_assign_stage` enforces it server-side. |
| D2 | 🟠 | `Roles.md` promises "Assign task: pick member **+ set start/due dates**" — `assignStage()` only wrote `assignee_id`. | ✅ `stages.assigned_start` / `assigned_due`, set from the assign sheet, shown to the assignee. |
| D3 | 🔴 | The assignee was never told. | ✅ `fn_assign_stage` notifies the new assignee (and the previous one on reassign/unassign). |
| D4 | 🔒 | `p_stages_staff on stages for all using (is_staff())` — **any** staff member (workshop, store, procurement, design, service) could UPDATE or DELETE **any** stage of **any** project, including assigning tasks to themselves or wiping a build's timeline. | ✅ Stage INSERT/DELETE = admin or that project's PM. UPDATE = admin, that PM, or the assignee — and a guard trigger blocks an assignee from touching `assignee_id`, `discipline`, `ord`, `bay_id`, `project_id` or the planned dates. |
| D5 | 🟠 | Assigning to a **disabled** member was allowed. | ✅ Blocked in `fn_assign_stage`. |
| D6 | 🟠 | `workload()` counted only `in_progress` stages, so a member holding five queued stages showed as **"Free"** in the PM's Team tab. | ✅ Counts the real open load (`todo` + `in_progress` + `rework`). |
| D7 | 🟡 | No single place to see "what still needs assigning" across a PM's builds. | ✅ New **Assign work** screen: every unassigned / rework stage across the PM's projects, grouped by build. |

## 5. Step 5 — The assignee works and uploads

| # | Sev | Problem | Fix |
|---|---|---|---|
| E1 | 🔴 | **The Design role ignored assignment completely.** `myDesignsProvider` selected *all* `design_artifacts` of *all* projects, and New Design's project dropdown was `allProjectsProvider` — so every designer saw and could create designs on every truck, whether assigned or not. Step 5 was simply not implemented for design. | ✅ New `assignedProjectsProvider` (projects where I hold ≥1 stage). Designer Studio/Library/Approvals and the New-design picker are scoped to it (plus anything they authored). Empty state now explains that a PM must assign a design stage first. |
| E2 | 🔴 | A stage **never became `in_progress`** — nothing in the app set it. Knock-on effects: PM "Today's stages" was always empty, `workload()` always 0, workshop cards always said "Queued". | ✅ **Start work** action (`fn_start_stage`) sets `in_progress` + `actual_start`, and approving a stage auto-starts the next one. |
| E3 | 🟠 | `submitForApproval` set `approver_id = null`, so the approval had no owner; `pendingApprovals()` fetched **every** pending approval in the database and filtered by PM in Dart. | ✅ `fn_submit_stage` stamps `approver_id` with the project's PM; the query filters server-side with an inner join. |
| E4 | 🔴 | If a project had no PM, a submitted stage went into a **black hole** — no one could ever approve it. | ✅ `fn_submit_stage` refuses with "this build has no project manager yet"; and B1 makes PM-less projects impossible going forward. |
| E5 | 🟠 | Tapping *Submit* repeatedly created unlimited duplicate pending approvals. | ✅ Unique partial index + explicit check in `fn_submit_stage`. |
| E6 | 🟠 | Approving a stage set `status='done'` but never wrote `actual_end`, never advanced `projects.current_stage_id`, and never started the next stage. | ✅ Handled in `fn_decide_stage`. |
| E7 | 🟠 | Reject wrote `changes_requested` into `stage_approvals`, but the workshop screen had no idea it had been sent back. | ✅ Uses `rejected`, notifies the submitter, and the task card shows a **Rework** banner with the reason. |
| E8 | 🔴🔒 | **Client design approval silently did nothing.** `decideDesign()` UPDATEs `design_artifacts`, but the client only has a `SELECT` policy on that table — the update matched 0 rows, and Supabase returns success. The client saw "Design approved 🎉" and nothing changed. | ✅ New `fn_client_decide_design` (definer, verifies the caller owns the project, refuses if the design isn't awaiting approval), writes a real `design_approvals` audit row and notifies the designer + PM. |
| E9 | 🟠 | Workshop "scan to install" updated `component_instances` directly, with no check that the part was in stock or that the caller owns the stage. | ✅ `fn_install_component` validates in-stock + assignee, then links part → truck/stage. |
| E10 | 🟡 | Store's **"Notify all N"** recall button only showed a snackbar — nothing was sent. | ✅ Wired to `fn_recall_notify`, which notifies each affected build's PM and client. |
| E11 | 🟡 | Workshop "Add photo" attaches a random `picsum.photos` URL — there is no real image upload (no `builds` storage bucket). | ⬜ Needs a `builds` bucket + `image_picker`; the dialog says so honestly. |
| E12 | 🟡 | **No stage ever has a checklist.** `fn_onboard_project` creates stages but no `checklist_items`, and templates can't define them — only `seed_stage_demo.sql` has any. | ⬜ Needs `template_stage_checks` + Create-Template UI. |
| E13 | 🟠 | `checklist_items` were writable by any staff member. | ✅ Write = admin, that project's PM, or the stage's assignee. |

## 6. Cross-cutting logic holes

| # | Sev | Problem | Fix |
|---|---|---|---|
| F1 | 🔴 | **`projects.status` was never computed.** Every project stayed `on_track` forever, so Admin's fleet health, at-risk/delayed counts, Insights "on-time %", PM's "Needs you today" and the client's status pill were all permanently wrong. | ✅ `fn_recompute_status`: `delivered` → `delayed` (a stage overran its planned end) → `at_risk` (a stage should have started, or a pending requirement is past its order-by) → `on_track`. Runs on every stage change, plus `fn_refresh_all_statuses()` for a daily cron. |
| F2 | 🟠 | `projects.current_stage_id` was written by nothing and read by nothing — a dead column. | ✅ Maintained by `fn_recompute_current_stage`. |
| F3 | 🔒 | **`v_order_due` bypassed RLS.** Postgres views run with the *owner's* rights unless `security_invoker` is set, so any signed-in user — **including a client** — could read every project's procurement data through the view. | ✅ `alter view … set (security_invoker = on)`. |
| F4 | 🔒 | `p_profiles_read … using (auth.uid() is not null)` let **clients read the whole staff directory** (names, emails, roles). | ✅ Staff read all; a client reads only their own profile. |
| F5 | 🔴 | **Deleting a member threw a foreign-key error** whenever they were a PM or a stage assignee (`projects.pm_id` / `stages.assignee_id` → `profiles(id)` with no `ON DELETE`), so `admin-delete-member` failed on exactly the people you'd want to offboard. | ✅ Every people-reference FK is now `ON DELETE SET NULL` (and the audit trail keeps the `audit_log` row). |
| F6 | 🔒 | Blanket `for all using (is_staff())` on 15 operational tables meant, e.g., workshop could create vendors and POs, procurement could invent component serials, designers could edit the item catalog. `DataModel.md` §10 documents a far tighter matrix. | ✅ Reads stay staff-wide (roles genuinely need context); **writes** are now per-role: vendors/POs = procurement, stock/components = store, requirements/templates/bays = PM, tickets = service, etc. |
| F7 | 🟠 | `role_home.dart` fell back to the **client UI** when `profiles.role` was missing (`role0 ?? 'client'`) — an auth user with no profile row would land in a client experience. | ✅ Shows an explicit "no role assigned" screen with a sign-out. |
| F8 | 🟡 | `audit_log` was readable by all staff and written by nothing. | ✅ Read = admin; written by the assignment/approval functions. |
| F9 | 🟡 | Delay reasons (`delay_logs`) are never captured, so Analytics' "top delay reasons" can't work. PM's card even says "tag reason & reschedule" with no action behind it. | ⬜ Needs a "log delay" sheet on the PM stage view. |
| F10 | 🟡 | `bays.current_stage_id` is never set, so the PM Schedule tab always reports every bay "Free". | ✅ Bay board removed from the app. Schedule now shows the PM's open stages by due date (`assigned_due`, falling back to `planned_end`). Table + `stages.bay_id` kept in the schema for whenever bay allocation is genuinely built. |
| F11 | 🔴 | Procurement/Store/Service are fleet-wide by design (correct), but **Service had no screens at all**, so client tickets had no consumer — and `tickets.sla_due`, `service_visits` and `resolution_*` were never written. | ✅ Service role built in `0010_service.sql` (see `docs/PROJECT_LOG.md`). |
| F13 | 🔴 | **Nothing set `projects.actual_delivery_date`**, so no build could ever reach `delivered` — the whole after-sales stage of the product was unreachable. | ✅ `fn_mark_delivered`, surfaced as **Mark delivered** on the PM's project detail. |
| F12 | 🔴 | **`supabase/full_setup.sql` had drifted out of sync with `migrations/`.** It was missing migration 0005 (the `template_stage_items` BOM table *and* the BOM-aware `fn_onboard_project`) and 0006 (the client build-photo policy). Anyone who set up a project from that one file got an app where Create-Template and client photos fail. | ✅ It is now **generated** — `sh supabase/build_full_setup.sh` concatenates the migrations + seed, so it can never drift again. |

---

## Verification

`supabase/tests/run.sh` (Docker only) boots a throwaway Postgres 15 and checks all of this
for real, as non-superuser users so RLS and the guard triggers actually apply:

- the migration chain + seed apply cleanly, and the newest migration is idempotent;
- `full_setup.sql` on a fresh database produces the same working schema;
- ~40 assertions walking the whole chain — a welder cannot create a project, a PM cannot
  create one and hand it to themselves, onboarding is refused without a PM, a designer
  cannot be made PM, a design stage refuses a welder unless overridden, staff cannot
  assign work to themselves by writing the table, only the assignee can start/submit,
  only that build's PM can approve, approval advances the next stage, a client sees only
  their own build and can no longer read the staff directory or `v_order_due`, a direct
  client UPDATE on a design is still powerless while `fn_client_decide_design` works,
  an overrun stage flips the build to `delayed`, recall notifies every affected build,
  offboarding a PM no longer trips a foreign key, and work cannot be submitted into a
  PM-less build.

---

## Migration / deploy checklist after this pass

1. Run `supabase/migrations/0009_workflow.sql` (or `supabase/full_setup.sql` on a fresh project).
2. Re-deploy the Edge Function `admin-create-member` (it now returns `client_account_id`).
3. For any pre-existing project with no PM (e.g. the seeded `AZ-118`): open **Admin → Projects → No PM**
   and assign one. Nothing else in the flow will work for that build until you do.
4. Optional: schedule `select public.fn_refresh_all_statuses();` daily (Supabase → Database → Cron)
   so at-risk/delayed statuses roll forward without a stage edit.
