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
| ✅ | `fn_onboard_project(p_project)` | admin | Requires a template with stages **and a PM**. Creates stages (with discipline) and checklists from the template, backward-schedules them, generates BOM requirements, and notifies the PM. |
| ✅ | `fn_assign_pm(p_project, p_pm)` | admin | Target must be an active `pm`. Records who and when, notifies the new and old PM. |
| ✅ | `fn_assign_stage(p_stage, p_assignee, p_start?, p_due?, p_override=false)` | admin · build's PM | Assignee must be an active workshop / design / store / service member. A discipline mismatch needs `p_override`. Sets `assigned_*` and notifies the new and old assignee. `p_assignee = null` unassigns. |
| ✅ | `fn_start_stage(p_stage)` | admin · assignee · build's PM | todo / rework → in_progress, sets `actual_start`, notifies the PM. |
| ✅ | `fn_submit_stage(p_stage) → uuid` | admin · assignee | One pending `stage_approvals` row addressed to the build's PM. Refuses duplicates and PM-less builds. |
| ✅ | `fn_decide_stage(p_approval, p_approve, p_note?)` | admin · build's PM | **Approve:** stage done, **next todo stage auto-starts**, and the submitter, next assignee and client are notified. **Reject:** stage goes to `rework` and the note reaches the assignee. |
| ✅ | `fn_install_component(p_component, p_stage)` | admin · stage assignee · store | Part must be `in_stock`. Links it to the truck and stage (`installed`). |
| ✅ | `fn_mark_delivered(p_project, p_date?, p_force=false)` | admin · build's PM | Refuses while stages are open unless `p_force`. Sets the delivery date and status `delivered`, and notifies the client and every service member. |
| ✅ | `fn_recompute_schedule(p_project, p_rebaseline_assigned=false)` | *no check* ⚠️ | Backward schedule + order-by dates. `true` also re-baselines the assigned dates. |
| ✅ | `fn_refresh_all_statuses() → int` | *no check* ⚠️ | Recomputes every build's status. Called when the fleet, PM and Command Center screens load. |
| | `fn_recompute_progress` · `fn_recompute_status` · `fn_recompute_current_stage` | internal | Called by triggers and the RPCs above. |

### Design
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_add_design_version(p_artifact, p_model_url?, p_image_url?, p_change_note?, p_submit=false) → uuid` | admin · design | Next `version_no` under a row lock (`0025`). Repoints the current version, sets status draft / pending_approval, clears client feedback. |
| ✅ | `fn_client_decide_design(p_artifact, p_approve, p_feedback?)` | the build's client | Design must be `pending_approval`; feedback is required to reject. Writes `design_approvals`, notifies the designer and PM. |

### Procurement (PO chain, `0020`)
| ✅ | Function | Who | Effect |
|---|---|---|---|
| ✅ | `fn_create_po(p_vendor?, p_project?, p_order_date?, p_delivery_date?, p_lines jsonb, p_notes?, p_payment_terms?, p_ship_to?, p_requirement?, p_stock_request?) → uuid` | admin · procurement | **The only way to create a PO.** `p_lines = [{item_catalog_id, qty, unit_price, tax_rate, hsn_code, description}]`. Computes totals and the `PO-00001` number. A project PO goes to `pending_pm`; a general one to `pending_final`. Parks the linked requirement or stock request as `ordered`. |
| ✅ | `fn_pm_sign_po(p_po, p_note?)` | admin · the PO's `pm_id` | pending_pm → pending_final, notifies admins. |
| ✅ | `fn_final_approve_po(p_po, p_note?)` | admin | pending_final → approved, notifies the submitter and PM. |
| ✅ | `fn_reject_po(p_po, p_reason)` | admin (either step) · PM (own, at pending_pm) | A reason is required. → rejected, notifies the submitter (and the PM if the owner rejected). |
| ✅ | `fn_resubmit_po(p_po, p_vendor?, p_delivery_date?, p_lines?, p_notes?, p_payment_terms?, p_ship_to?)` | admin · procurement | rejected → back into the chain from the top. Header fields only apply when `p_lines` is passed. |
| ✅ | `fn_set_po_priority(p_po, p_priority)` | admin | Override `critical / high / medium / low`; `null` = automatic. |
| ✅ | `fn_receive_po(p_po)` | admin · procurement · store | Must be dispatched / partial. Marks the PO received and writes a GRN. Adds stock for **bulk** lines only. Closes the requirements and stock requests. ⚠️ No row lock. |
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
`fn_notify(…)`, `fn_notify_client(…)`, `fn_notify_role(…)`, `fn_audit(…)`.
⚠️ The definer helpers are executable by every role over RPC (no `REVOKE`); see `WORKFLOW_AUDIT.md` H2.

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
| `delay_logs` insert | PM → build → Log a delay |
| `documents` insert (after upload to `builds/docs/`) | Build → Overview → Add document |
| `workflow_templates`, `template_stages`, `template_stage_items`, `template_stage_checks` inserts | Onboard → Template "New" |
| `item_catalog` insert | inline "New item" (New PO, Materials, Create template; also attempted by Store, which RLS refuses) |
| `vendors` insert | Procurement → Vendors → Add vendor |
| `company_settings` update | Admin → Team → Company details |
| `purchase_orders` update to dispatched + `expected_date` | Procurement → Mark dispatched |
| `component_instances` insert | Store → Log component |
| `checklist_items.done` update | Workshop → Task detail |
| `attachments` insert | Workshop stage photo; client ticket photo |
| `tickets` insert | Client → Raise request |
| `design_artifacts` insert / update, `design_versions` insert (v1) | Design → New design; Submit for approval |
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
