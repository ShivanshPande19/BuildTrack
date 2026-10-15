# Azimuth BuildTrack: API

There is **no custom REST server**. The app talks to Supabase directly:

- **PostgREST** for table and view reads, plus a few direct writes, all filtered by RLS.
- **RPCs** (`sb.rpc('fn_…')`): Postgres functions that hold the business rules. Most are
  `SECURITY DEFINER` and check the caller's role themselves.
- **Edge Functions** for creating and removing logins (they need the service-role key).
- **Storage** for files.

The REST design in earlier versions of this file (`/api/v1/...`) was never built.
Supabase replaced it ([`TechStack_and_BuildPlan.md`](TechStack_and_BuildPlan.md), Path 2).
Tables are in [`DataModel.md`](DataModel.md). All app calls live in `app/lib/data/repositories.dart`.

---

## 1. Auth

| What | How |
|---|---|
| Sign in | `auth.signInWithPassword(email, password)`. There is no sign-up and no forgot-password screen. |
| Session | PKCE flow. The router sends you to `/login` without a session, to `/set-password` while `user_metadata.needs_password`, and to `/home` otherwise. |
| Role → home | `profiles.role` (`fetchMyRole`). No role shows a "No role assigned yet" screen with a sign-out. |
| Invite link | Deep link `io.supabase.buildtrack://login-callback/` → **Set your password** → `auth.updateUser(password, data:{needs_password:false})`. See [`INVITE_FLOW.md`](INVITE_FLOW.md). |

---

## 2. Edge Functions (admin only; the caller must have `profiles.role = 'admin'`)

| Function | Body | Does | Returns |
|---|---|---|---|
| `admin-create-member` | `full_name, email, role, phone?, password?, business_name?, redirect_to?` | **With `password`:** creates a confirmed auth user, profile `active`. **Without:** `inviteUserByEmail` (needs SMTP), profile `invited`. For `role = client` it also creates `client_accounts` (`contact_user_id` = the new user). It rolls back the auth user if a later insert fails. | `{ok, user_id, client_account_id}` |
| `admin-delete-member` | `target_user_id` | Unlinks `client_accounts.contact_user_id`, then deletes the auth user (the profile cascades). Refuses to delete yourself. | `{ok}` |

Errors: 401 unauthorized, 403 `forbidden: admin only`, 400 validation / auth errors, 405 for non-POST.

---

## 3. RPCs

✅ = called by the app. "Who" is the server-side check; anyone else gets SQLSTATE `42501` with a readable message.

### Builds & stages
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_onboard_project(p_project)` | admin | Requires a template with stages **and a PM**. Creates stages (with discipline) and checklists from the template — carrying each check's `photo_required` since `0029` — backward-schedules them, generates BOM requirements, and notifies the PM. Every step is guarded, so re-onboarding cannot duplicate. |
| ✅ | `fn_assign_pm(p_project, p_pm)` | admin | Target must be an active `pm`. Records who and when, notifies the new and old PM. **`0026`:** also moves pending stage approvals and unsigned POs on that build to the new PM, and tells them what is waiting. |
| ✅ | `fn_assign_stage(p_stage, p_assignee, p_start?, p_due?, p_override=false)` | admin · build's PM | Assignee must be an active workshop / design / store / service member. A discipline mismatch needs `p_override`. Sets `assigned_*` and notifies the new and old assignee. `p_assignee = null` unassigns. |
| ✅ | `fn_start_stage(p_stage)` | admin · assignee · build's PM | todo / rework → in_progress, sets `actual_start`, notifies the PM. Reachable by **every** discipline since `0026` — Design and Service have a stage screen too. |
| ✅ | `fn_submit_stage(p_stage) → uuid` | admin · assignee | One pending `stage_approvals` row addressed to the build's PM. Refuses duplicates and PM-less builds. **`0028`:** a **design**-discipline stage is also refused until an approved design exists on that build — a stage whose checklist says *"layout approved by client"* cannot be closed without the client having approved one. Other disciplines are untouched. |
| ✅ | `fn_decide_stage(p_approval, p_approve, p_note?)` | admin · build's PM | **Approve:** stage done, **next todo stage auto-starts**, and the submitter, next assignee and client are notified. **Reject:** stage goes to `rework` and the note reaches the assignee. |
| ✅ | `fn_install_component(p_component, p_stage)` | admin · stage assignee · store | Part must be `in_stock`. Links it to the truck and stage (`installed`). This is the **only** path that marks a part installed: Store's intake screen only *reserves* one for a build (`0026`). **`0029`:** refuses a stage already **approved** (the evidence of a signed-off stage must not change afterwards — `fn_start_stage` and `fn_submit_stage` have refused one since `0026`), and refuses a part **earmarked for a different build** rather than overwriting `installed_in_project_id` silently. |
| ✅ | `fn_mark_delivered(p_project, p_date?, p_force=false)` | admin · build's PM | Refuses while stages are open unless `p_force`. Sets the delivery date and status `delivered`, and notifies the client and every service member. |
| ✅ | `fn_recompute_schedule(p_project, p_rebaseline_assigned=false)` | *no check* ⚠️ | Backward schedule + order-by dates, then refreshes the build's status (`0026`). `true` is a full re-plan: it re-baselines the assigned stage dates **and** moves each still-pending requirement's `needed_by_date` onto the new plan, so the order-by engine never alerts against a schedule that is no longer live. |
| ✅ | `fn_refresh_all_statuses() → int` | *no check* ⚠️ | Recomputes every build's status. Called when the fleet, PM and Command Center screens load. |
| ✅ | `fn_tick_check(p_item, p_done, p_proof?)` | admin · stage assignee · build's PM | **`0029`. The only way `done` moves on a checklist item** — a direct UPDATE is refused by `trg_guard_checklist`, which is what leaves the record no hole. Writes `done_by` / `done_at` (cleared again on un-tick: a check that is not done was not done by anybody) and audits as `tick_check` / `untick_check`. Refuses a stage already **approved**, for everyone but an admin. A check marked `photo_required` needs `p_proof` — an attachment **on that stage**, checked, since otherwise any attachment id would satisfy it — and the row keeps which photo discharged it. |
| | `fn_check_rpc_begin()` | internal · revoked | Marks the transaction a sanctioned checklist write, transaction-local. Same pattern as `fn_stage_rpc_begin` (`0026`). |
| | `fn_recompute_progress` · `fn_recompute_status` · `fn_recompute_current_stage` | internal | Called by triggers and the RPCs above. |

### Design
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_create_design(p_project, p_type, p_model_url?, p_image_url?, p_change_note?, p_submit=false, p_stage?) → uuid` | admin · design | **`0026`.** Artifact + first version + `current_version_id` in one transaction (it was three client writes, and a failure halfway left an un-openable design). On submit, notifies the client and the PM. **`0028`:** `p_stage` attaches the design to the design stage it is the work for, refusing a stage on a different build. The old 6-argument signature is **dropped** in `0028` — `create or replace` with an added parameter makes an overload, not a replacement, and every call then fails as ambiguous. |
| ✅ | `fn_add_design_version(p_artifact, p_model_url?, p_image_url?, p_change_note?, p_submit=false) → uuid` | admin · design | Next `version_no` under a row lock (`0025`). Repoints the current version, sets status draft / pending_approval, clears client feedback. **`0026`:** on submit, notifies the client and the PM — the "they've been notified" banner is now true. |
| ✅ | `fn_client_decide_design(p_artifact, p_approve, p_feedback?)` | the build's client | Design must be `pending_approval`; feedback is required to reject. Writes `design_approvals`, notifies the designer and PM. **`0028`:** also tells whoever holds the linked stage what the decision means for *their* work — *"your stage can be submitted"* or *"still waiting on the client"* — as a separate row with its own type (`stage_ready` / `stage_waiting`) pointing at the stage, so the feed does not say the same thing twice and each row opens the right screen. |

### Procurement (PO chain, `0020`)
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_create_po(p_vendor?, p_project?, p_order_date?, p_delivery_date?, p_lines jsonb, p_notes?, p_payment_terms?, p_ship_to?, p_requirement?, p_stock_request?) → uuid` | admin · procurement | **The only way to create a PO.** `p_lines = [{item_catalog_id, qty, unit_price, tax_rate, hsn_code, description}]`. Computes totals and the `PO-00001` number. A project PO goes to `pending_pm`; a general one to `pending_final`. **`0027`:** a project PO on a build with **no PM** is refused rather than routed straight to the owner — that dropped a signature silently, and offboarding a PM is the real path into it. Parks the linked requirement or stock request as `ordered` — and since `0026`, **every** still-pending requirement on that build whose item is on the PO, so a PO raised from the blank FAB stops the alert too. |
| ✅ | `fn_pm_sign_po(p_po, p_note?)` | admin · the PO's `pm_id` | pending_pm → pending_final, notifies admins. |
| ✅ | `fn_final_approve_po(p_po, p_note?)` | admin | pending_final → approved, notifies the submitter and PM. |
| ✅ | `fn_reject_po(p_po, p_reason)` | admin (either step) · PM (own, at pending_pm) | A reason is required. → rejected, notifies the submitter (and the PM if the owner rejected). |
| ✅ | `fn_resubmit_po(p_po, p_vendor?, p_delivery_date?, p_lines?, p_notes?, p_payment_terms?, p_ship_to?)` | admin · procurement | rejected → back into the chain from the top. **`0026`:** the header update no longer sits inside `if p_lines is not null`, so a vendor or date change lands on its own, and every field the caller leaves `null` keeps its current value instead of being wiped. **`0027`:** refused on a PM-less build, for the same reason as `fn_create_po`. |
| ✅ | `fn_set_po_priority(p_po, p_priority)` | admin | Override `critical / high / medium / low`; `null` = automatic. |
| ✅ | `fn_receive_po(p_po)` | admin · procurement · store | Must be dispatched / partial. Marks the PO received and writes a GRN. Adds stock for **bulk** lines only. Closes the requirements and stock requests. **`0026`:** takes a row lock, so two people receiving the same delivery cannot double the stock. |
| ✅ | `fn_request_stock(p_item, p_qty, p_note?) → uuid` | admin · store | Creates a `stock_requests` row and notifies procurement and admin. |

Dispatch is **not** an RPC: the app UPDATEs `purchase_orders.status = 'dispatched'`, and `trg_po_require_approval` refuses it until the PO is approved.

### Store / recall
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_recall(p_item) → (project_id, project_code, serial, status)` | staff (via RLS) | Every truck with that catalog item installed. |
| ✅ | `fn_recall_notify(p_item, p_note?) → int` | admin · store · service | Notifies each affected build's PM and client. |

### Service
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_create_ticket(p_project, p_category, p_description, p_priority='medium', p_component?) → uuid` | admin · service | A ticket raised on the client's behalf. Triggers set the number and SLA and notify. |
| ✅ | `fn_assign_ticket(p_ticket, p_technician)` | admin · service | Technician must be service / workshop. open → in_progress. Notifies the technician. |
| ✅ | `fn_schedule_visit(p_ticket, p_technician, p_when, p_note?) → uuid` | admin · service | Cancels any live booking, books a new one, notifies the technician and client. |
| ✅ | `fn_resolve_ticket(p_ticket, p_resolution, p_note)` | admin · service | The note is required (the client reads it). Marks the ticket resolved and its visits done, and notifies the client. |
| ✅ | `fn_close_ticket(p_ticket)` | admin · service | Only after it is resolved. |
| ✅ | `fn_reopen_ticket(p_ticket, p_reason?)` | *no check* ⚠️ | resolved / closed → in_progress, **high** priority, new 4h SLA. Notifies service, admin and the assignee. |
| ✅ | `fn_warranty_search(p_q?)` | staff | Searches serial, item, model and project. Limit 100. |
| ✅ | `fn_warranty_expiring(p_days=60)` | staff | Per build: parts whose warranty ends within N days. |

### Helpers (used inside RLS and RPCs)
`my_role()`, `is_admin()`, `is_staff()`, `has_role(text[])`, `my_client_account()`, `is_pm_of(project)`,
`is_pm_of_stage(stage)`, `is_stage_assignee(stage)`, `fn_infer_discipline(name)`, `fn_sla_hours(priority)`,
`fn_notify(…)`, `fn_notify_client(…)`, `fn_notify_role(…)`, `fn_audit(…)`, `fn_stage_rpc_begin()`.

`my_role()` returns **NULL for a disabled account** (`0026`), so every role test built on it denies —
and `is_admin()` coalesces, because `if not public.is_admin()` is *false* when `is_admin()` is NULL.

`fn_notify*`, `fn_audit` and `fn_stage_rpc_begin` are **revoked from `authenticated`** (`0026`), so
notifications can no longer be spoofed over RPC. `fn_recompute_schedule` and `fn_refresh_all_statuses`
stay granted — the app calls both directly. See `PROJECT_LOG.md` §3 #13.

---

## 4. Views read by the app

`v_order_due` · `v_po_pending_approvals` · `v_ops_board` · `v_project_delays` · `v_truck_components`
(columns in [`DataModel.md`](DataModel.md) §4).

---

## 5. Direct table writes the app makes (allowed by RLS; no RPC)

| Write | Where in the app |
|---|---|
| `projects` insert (then `fn_onboard_project`) | Admin → Onboard project |
| `projects.target_delivery_date` update (then `fn_recompute_schedule(…, true)`) | PM → build → Delivery date; Log delay with push |
| `procurement_requirements` insert / update / delete | PM → build → Materials |
| `documents` insert (after upload to `builds/docs/`) | Build → Overview → Add document |
| `workflow_templates`, `template_stages`, `template_stage_items`, `template_stage_checks` inserts | Onboard → Template "New" |
| `item_catalog` insert | inline "New item" (New PO, Materials, Create template, and Store — `0026` added `store` to the policy) |
| `vendors` insert | Procurement → Vendors → Add vendor |
| `company_settings` update | Admin → Team → Company details |
| `purchase_orders` update to dispatched + `expected_date` | Procurement → Mark dispatched |
| `component_instances` insert | Store → Log component |
| `checklist_items` insert / `label` + `photo_required` update / delete | PM · admin → stage detail → **Edit checks** (`trg_guard_checklist`, `0028`/`0029`). Locked once the stage is approved. |
| `delay_logs` insert | PM · admin → build → Log a delay · **the stage's own assignee → Report a hold-up** (`0029`) |
| `attachments` insert | Workshop stage photo; client ticket photo |
| `tickets` insert | Client → Raise request |
| `design_artifacts` update (status) | Design → Submit for approval (the insert goes through `fn_create_design`) |
| `sub_teams` insert, `profiles.sub_team_id` update | Admin → Add member |
| `notifications.read` update | Notifications → Mark all read |

---

## 6. Storage

`uploadToBuilds()` writes `builds/<folder>/<ms>_<name>` with `upsert`. Folders: `stages/<id>`,
`tickets/<id>`, `bills`, `docs/<projectId>`. Design files go to `designs/<uid>/<ms>_<name>`. Both buckets are
public-read and the app stores public URLs.

---

## 7. Errors

RPCs raise readable messages ("Only this build's project manager can assign its stages.", …).
`friendlyError(e)` shows them as-is and maps the generic codes:

| Code | Message |
|---|---|
| `23505` duplicate | "That project code is already used by another build." / "That record already exists." |
| `42501` / RLS | "You do not have permission to do that." |
| `23503` | "Something this depends on is missing — refresh and try again." |
| `23502` | "A required field is missing." |
| Edge Function error | the function's `error` text |

---

## 8. Key flows as calls

- **Onboard:** insert `projects` → `fn_onboard_project` (`createClientLogin` → `admin-create-member` first, if the client is new).
- **Assign → do → approve:** `fn_assign_stage` → `fn_start_stage` → `fn_install_component` + attachments
  insert → `fn_submit_stage` → `fn_decide_stage`.
- **Order-by → PO → stock:** `v_order_due` → `fn_create_po(p_requirement)` → `fn_pm_sign_po` →
  `fn_final_approve_po` → update to dispatched → `fn_receive_po`.
- **Store reorder:** `fn_request_stock` → Procurement `fn_create_po(p_stock_request)` → …
- **Design loop:** design_artifacts + v1 insert → status update to pending_approval → client
  `fn_client_decide_design` → `fn_add_design_version` for revisions.
- **Recall:** `fn_recall` → `fn_recall_notify`.
- **After-sales:** `fn_mark_delivered` → client tickets insert, or `fn_create_ticket` → `fn_assign_ticket` →
  `fn_schedule_visit` → `fn_resolve_ticket` → `fn_close_ticket`, or a client `fn_reopen_ticket`.
