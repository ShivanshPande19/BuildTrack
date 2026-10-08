# BuildTrack — Role & Data Dependencies (authoritative)

> **Read this before building any role.** It maps which role produces which data and which roles consume it, so nothing is built in the wrong order and no screen is left without its data source. Keep this updated as the source of truth.

---

## 1. The golden data-flow chain (create → consume)

```
MASTER DATA  templates (+BOM +checklist), item_catalog, vendors, company_settings   ← Admin / Procurement / PM
        │
        ▼
Admin ── onboard project ──► project, stages (+discipline, +checklist), procurement_requirements (from BOM),
        │                    client_account + client login (inline), PM assigned (required)
        │
        ├──► PM          assigns stages (fn_assign_stage) · edits materials · delivery date · logs delays
        │
        ├──► Procurement reads v_order_due ─► fn_create_po ─► PM signs ─► Admin approves (0020)
        │            │                                     ─► mark dispatched ─► fn_receive_po
        │            │       fn_receive_po: GRN + bulk stock_items + requirement/stock_request "received"
        │            ▼
        ├──► Store       logs component_instances (serial + bill + warranty) ─► in_stock
        │                low essentials ─► fn_request_stock ─► back to Procurement as a general PO
        │            │
        │            ▼
        ├──► Workshop    assigned stage ─► fn_start_stage ─► fn_install_component (in-stock part → truck/stage)
        │                ─► photos (attachments) + checklist ─► fn_submit_stage
        │            │
        │            ▼
        ├──► PM          fn_decide_stage ─► done + next stage auto-starts (or rework + reason) ─► progress/status
        │
        ├──► Design      design_artifacts/versions for assigned builds ─► client approves (fn_client_decide_design)
        │                approved .glb ─► 3D showcase everywhere
        │
        ├──► Client      own trucks: progress, stage photos, documents, designs ─► raises tickets
        │
        └──► Service     PM fn_mark_delivered ─► tickets (client / fn_create_ticket) ─► assign ─► visit ─► resolve ─► close
                         client can fn_reopen_ticket
```

---

## 2. Per-role — NEEDS (prerequisites) vs PRODUCES (for others)

| Role | NEEDS (must exist first) | PRODUCES (consumed by) |
|---|---|---|
| **Admin** | workflow templates (+BOM/checklist), item_catalog, vendors, PMs | projects, stages, requirements, client_accounts + logins, members, PM assignment, PO final approval → **everyone** |
| **PM** | projects where `pm_id = me` (Admin), stages, stage_approvals (assignees), POs on my builds (Procurement) | stage assignments (→ doers), materials edits, delivery date, delay_logs, documents, approvals, PO signatures, delivery → **all** |
| **Procurement** | requirements (onboarding/PM), stock_requests (Store), vendors, item_catalog, company_settings | purchase_orders (+lines, approval trail), dispatch, goods_receipts, bulk stock → **PM/Admin (to sign), Store** |
| **Store** | item_catalog, vendors, bulk stock (from receipts) | component_instances (in_stock, bill, warranty), stock_requests, recall notices → **Workshop, Service, Procurement** |
| **Workshop** | stages assigned (PM), component_instances in_stock (Store) | started/submitted stages, installed parts, photos, checklist ticks → **PM, Client** |
| **Design** | builds where I hold a stage (PM) | design_artifacts/versions, approved `.glb` → **Client, Admin, PM** |
| **Client** | own projects (Admin), stage photos, documents, designs awaiting approval | design decisions (→ Design/PM), tickets + reopen (→ Service) |
| **Service** | delivered projects (PM `fn_mark_delivered`), tickets (Client), component warranty (Store) | assignments, visits, resolutions → **Client** |

---

## 3. Shared repositories (touched by multiple roles)

All in `app/lib/data/repositories.dart` (one Riverpod `Provider` per repo, e.g. `projectsRepoProvider`).
Extend the repo that owns the data. Don't re-query it from a screen.

| Repository | Owns | Used by |
|---|---|---|
| `ProjectsRepo` | projects, stages, `v_order_due`, `v_ops_board`, `v_project_delays`, `v_truck_components`, requirements, assignment (`fn_assign_stage`), delay_logs, documents, delivery date, `fn_mark_delivered`, stage approvals (`fn_decide_stage`), stage bundle (photos/checklist/parts/delays) | Admin, PM, Design (assigned builds), Client (detail) |
| `AdminRepo` | templates (+items/checks), client accounts, PMs, members + sub-teams (Edge Functions), onboarding, `fn_assign_pm` | Admin |
| `PmRepo` | my projects, active stages, schedule, workload | PM |
| `ProcurementRepo` | POs + approval chain RPCs, `v_po_pending_approvals`, priority, dispatch, `fn_receive_po`, vendors, item_catalog (+essentials, `createItem`), stock_requests, company_settings, PO document data | Procurement, PM, Admin, Store (`createItem`) |
| `StoreRepo` | components, stock (bulk + serialized on-hand), `fn_request_stock`, recall, log component, bills | Store |
| `WorkshopRepo` | my tasks, `fn_start_stage` / `fn_submit_stage`, checklist toggle, `fn_install_component`, stage photos, serial lookup | Workshop |
| `DesignRepo` | design artifacts/versions, `fn_add_design_version`, uploads to `designs`, approved model URL | Design, Client/Admin/PM (3D showcase) |
| `ClientRepo` | my trucks, photos, documents, designs, `fn_client_decide_design`, tickets + ticket photos, `fn_reopen_ticket` | Client |
| `ServiceRepo` | tickets + service RPCs, visits, technicians, delivered trucks, truck history, warranty search | Service |
| `NotificationsRepo` | notifications, mark all read | everyone |

---

## 4. Build-order rule & stubbing

- Build in the golden-chain order: **Admin → Procurement → Store → Workshop → PM → Client**.
- When a role's screen needs data a not-yet-built role would produce, **seed it** (demo rows) so the screen is testable now — never leave a screen without a data source.
- Whenever a new role is built, add/extend the **shared repo** it needs (see §3) rather than duplicating queries.

---

## 5. Screen-level dependency matrix (detailed)

Writes in **bold** are direct table writes; everything else goes through the named RPC.

### Admin
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Home (fleet) | projects (after `fn_refresh_all_statuses`), v_order_due, v_po_pending_approvals, notifications | — | projects onboarded |
| Command Center | v_ops_board | — | stages started (`days_in_stage`), assignees |
| PO approvals | v_po_pending_approvals | `fn_final_approve_po`, `fn_reject_po`, `fn_set_po_priority` | Procurement raised / PM signed |
| Onboard project | templates, client_accounts (with login), PMs | **projects** → `fn_onboard_project`; client login via `admin-create-member` | template with stages; a PM exists |
| Create template | item_catalog | **workflow_templates, template_stages, template_stage_items, template_stage_checks** | catalog items |
| Projects → build screen | projects, stages, profiles (PMs) | `fn_assign_pm`; **documents** | — |
| Team / Add member | profiles, sub_teams | `admin-create-member` (+ client_account if role = client), `admin-delete-member`; **sub_teams, profiles.sub_team_id** | — |
| Company details | company_settings | **company_settings** | — |
| Insights | projects | — | statuses computed |

> **Client sourcing rule:** a `client_account` and its **login are always created together** —
> either from Team → Add member (`role='client'`) or inline from **Onboard Project → Client → ＋ New**
> (`createClientLogin()`, which calls the same `admin-create-member` Edge Function and returns the new
> `client_account_id` so it can be selected immediately).
> The onboarding dropdown lists **only accounts that have `contact_user_id` set**: an account with no
> login is unreachable (`my_client_account()` returns null, so RLS matches no rows) and the client
> could never see their truck. Legacy login-less rows are hidden and counted in a hint on the screen.

### PM
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Home / Projects | projects (`pm_id = me`), stages (in progress) | — | Admin set `pm_id` |
| Assign work / assign sheet | stages (unassigned or rework), profiles (doers), workload | `fn_assign_stage` | stage has a discipline |
| Approvals | stage_approvals (`approver_id = me`) + stage bundle | `fn_decide_stage` | **assignee submitted** |
| PO approvals | v_po_pending_approvals (`pm_id = me`) | `fn_pm_sign_po`, `fn_reject_po` | Procurement raised a project PO |
| Build → Materials | procurement_requirements | **requirements** → `fn_recompute_schedule` | onboarding (BOM) |
| Build → Overview | projects, stages, documents | **target_delivery_date**, **delay_logs**, **documents**; `fn_mark_delivered` | — |
| Schedule | stages (`assigned_due` → `planned_end`), profiles | — | assigned dates / backward schedule |
| Team | stages (open, per assignee) | — | — |

### Procurement
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| To Order | v_order_due, stock_requests | → New PO | requirements exist (onboarding/PM); Store requests |
| New PO / Fix & resubmit | projects, vendors, item_catalog | `fn_create_po` / `fn_resubmit_po`; **item_catalog** (inline) | vendor exists |
| Orders / PO detail | purchase_orders, po_lines, po_approval_events | **status → dispatched**; `fn_receive_po` | PO approved (trigger) |
| PO document | PO detail + company_settings + vendor | — (PDF on device) | Company details filled |
| Receive | purchase_orders (approved) | **dispatch**; `fn_receive_po` (GRN + bulk stock) | approved PO |
| Vendors | vendors | **vendors** | — |

### Store
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Inbox | component_instances, stock | — | — |
| Stock | stock_items (bulk) + component_instances (serialized in_stock), item_catalog (essentials) | `fn_request_stock` | receipts (bulk) / logged parts (serialized) |
| Log component | item_catalog, vendors, projects | **component_instances** (+ bill upload to `builds/bills/`) | catalog item exists |
| Parts / component record | component_instances | — | logged components |
| Recall check | `fn_recall` | `fn_recall_notify` | components installed |

### Workshop
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| My Tasks / Week | stages (`assignee_id = me`) + stage_approvals | — | **PM assigned** |
| Task detail | stage bundle | `fn_start_stage`, **checklist_items.done**, **attachments** (photo), `fn_submit_stage` | — |
| Scan to install | component_instances (in_stock, by serial) | `fn_install_component` | **Store logged the part** |
| Parts | component_instances on my builds | — | parts installed |

### Design
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Studio / Designs / Approvals | stages (`assignee_id = me`) → projects, design_artifacts, design_versions | — | **PM assigned a stage on the build** |
| New design | assigned projects | **design_artifacts + design_versions (v1)**, uploads to `designs/` | assigned build |
| Design detail | artifact + versions | **status → pending_approval**; `fn_add_design_version` | — |

### Client
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| My Trucks | projects (own account), approved model URL | — | Admin onboarded with this client's login |
| Truck | project detail, stages, documents (available), pending designs | — | — |
| Stage photos | attachments (stage) | — | Workshop photos |
| Approve design | design_artifacts/versions | `fn_client_decide_design` | Design submitted |
| Raise request | — | **tickets**, **attachments** (+ `builds/tickets/`) | — |
| Support | tickets on own trucks | `fn_reopen_ticket` | — |

### Service
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Tickets | tickets (SLA order) | — | client / service raised |
| Ticket detail | ticket, attachments, visits, linked component | `fn_assign_ticket`, `fn_close_ticket` | — |
| Schedule visit / Resolve | profiles (service + workshop) | `fn_schedule_visit`, `fn_resolve_ticket` | — |
| Trucks / history | projects (delivered), tickets, `fn_warranty_expiring` | — | **PM marked delivered** |
| Warranty | `fn_warranty_search` | — | Store logged warranty |
| New ticket | delivered projects | `fn_create_ticket` | delivered truck |

---
*Keep this file updated whenever a role's screens or data flows change.*


---

## Stage Detail ("View details" per build stage) — data sources

The Admin/PM Stage detail screen aggregates existing tables (no new tables added).
When the owning role ships, its real data flows in automatically:

| Section on screen | Table / column | Produced by (role) |
|---|---|---|
| Photos / images | `attachments` where `owner_type='stage'`, `owner_id=stage.id` | Workshop (uploads on-site photos) |
| Parts installed (serial, warranty, vendor) | `component_instances` where `installed_stage_id=stage.id` (+ `item_catalog`, `vendors`) | Store logs at intake → Workshop "scan to install" sets `installed_stage_id` |
| Checklist | `checklist_items` where `stage_id=stage.id` | Workshop ticks items |
| Delays | `delay_logs` where `stage_id=stage.id` | PM / Workshop |
| Assignee | `stages.assignee_id → profiles.full_name` | PM assigns |

Project-level (NOT per-stage, shown on project overview instead):
- `documents` (contract / invoice / warranty_pack / handover_cert) — Store/PM, client-visible when `available`.
- `design_artifacts` + `design_versions` (layout/interior/exterior/branding) — Design role; surfaced on the design stage.

Demo seed for testing before those roles exist: `supabase/seed_stage_demo.sql`.


---

## Hero #1 — Order-by chain (now end-to-end)

Define once → auto-generate → customize per project → alerts:

1. **Template BOM** (`template_stage_items`): which catalog items each template stage needs (+ qty).
   Edited in **Create template** (Admin → Onboard → Template "New" → "+ item" per stage). The seed
   template has **no BOM**; run `supabase/seed_bom_demo.sql` or create a template with items.
2. **Onboarding** (`fn_onboard_project`): creates stages → backward-schedules them → **auto-generates `procurement_requirements`** from the BOM with `needed_by = stage.planned_start` → computes `order_by`.
3. **View / customize per project** (build screen → **Materials** tab, `ProjectRequirementsScreen`):
   - **Admin = read-only (monitor).** Sees materials and order-by risk, but cannot edit.
   - **PM = editing owner** (`materialsEditable: true`). Can add, change qty, change needed-by or remove. Add and
     edit call `fn_recompute_schedule` to refresh `order_by`. Remove doesn't.
4. **Alerts**: `order_by = needed_by − item.lead_time − item.buffer`. Surfaced via `v_order_due` (`days_left`) in Admin "Needs attention" + Procurement "To Order".
5. **Act**: Procurement → To Order hero → **Create Purchase Order** passes `p_requirement` to `fn_create_po`,
   so the requirement goes `pending → ordered` and drops off the list. The PO then needs the PM's signature and
   admin approval before it can be dispatched and received. A blank PO from the FAB is **not** linked to a
   requirement (gap).

Editing requirements invalidates `requirementsProvider`, `toOrderProvider`, `fleetProvider`.


---

## ⭐ Role ownership — build planning belongs to PM (decided)

**Admin = oversight + people.** Admin monitors the dashboards, manages the team, onboards builds (and today creates
templates inside onboarding), assigns the PM and gives POs final approval. Admin does NOT assign stages or edit
materials, the delivery date or delays.

**PM (Project Manager) owns build planning**, i.e. all of:
- **Per-project materials / requirements.** Add, edit qty, edit needed-by, remove (Materials tab, editable for the PM). ✅
- **Stage assignment, delivery date, delays, approvals, PO signatures, delivery.** ✅
- **Workflow templates + their BOM.** Decided as PM-owned, and RLS lets the PM write them, **but there is no
  PM screen**. Today a template can only be created from **Admin → Onboard project → Template "New"**,
  and nothing can list, edit or delete templates. ⬜ (`PROJECT_LOG.md` §3 #2)

**Procurement** consumes what PM plans: it sees order-by alerts (To Order) and raises POs for the PM and
admin to sign. **Store / Workshop** execute intake and install. **Client** views progress.


---

## Assignment architecture (two levels) — enforced in the database

See `docs/WORKFLOW_AUDIT.md` for the problems this replaced and
`supabase/migrations/0009_workflow.sql` for the implementation.

**Level 1 — Admin assigns the PM** (`projects.pm_id`)

- Set at **Onboard Project** (PM dropdown, **required**) and changeable any time from
  **build screen → Overview → Project manager → Assign / Change** (`canAssignPm: true`, Admin only).
- Goes through `fn_assign_pm(project, pm)`, which checks the target is an *active* member with
  `role='pm'`, records `pm_assigned_by` / `pm_assigned_at`, notifies the new PM and (on a
  hand-over) the previous one.
- `fn_onboard_project` **refuses** a build with no PM. A PM-less build is stranded: no PM sees it,
  its stages cannot be assigned, and submitted work cannot be approved. Legacy PM-less builds
  (e.g. the demo `AZ-118`) surface under **Admin → Projects → No PM**.
- A PM cannot create a project or take one over: `projects` INSERT/DELETE is admin-only in RLS,
  and `trg_guard_projects` blocks any non-admin from changing `pm_id`, `code`, `client_account_id`
  or `template_id`.

**Level 2 — PM assigns each stage to the right discipline** (`stages.assignee_id`)

- Every stage carries a **`discipline`** (`workshop | design | store | service`), copied from
  `template_stages.discipline` at onboarding, or inferred from the stage name by
  `fn_infer_discipline()` so existing templates work unchanged.
- Assignable staff = roles **workshop / design / store / service**, active only
  (`assignableForDisciplineProvider(discipline)` sorts the stage's own discipline first).
  Never admin / pm / procurement / client.
- Entry points: **PM → ＋ Assign work** (every unassigned or rework stage across their builds,
  `stagesToAssignProvider`) and **build screen → Overview → Build stages → Assign / Reassign / Unassign**.
- `assignStage(stageId, uid, start:, due:, override:)` → `fn_assign_stage`, which enforces:
  caller is that build's PM (or admin) · target role matches the stage discipline unless the PM
  explicitly confirms an `override` · account not disabled · `due >= start`. It stores
  `assigned_by/at/start/due` and notifies the new *and* previous assignee.
- `trg_guard_stages` stops an assignee from touching `assignee_id`, `discipline`, `ord`,
  `bay_id`, `project_id` or the planned/assigned dates — they may only move their own work forward.
- Workload (`workloadProvider`) counts **all open** stages (`todo + in_progress + rework`) per
  assignee, not just in-progress ones.

**Level 3 — the assignee executes** (this is what "assigned work shows up" means)

- `assignedProjectsProvider` = builds where I hold at least one stage. **Execution roles must scope
  to it** — Design's Studio / Library / Approvals and the New-design project picker all do.
- `fn_start_stage` → `in_progress` + `actual_start` (+ notifies the PM). Without this every stage
  stayed `todo` forever and the PM's day view, bay board and workload were always empty.
- `fn_submit_stage` → one pending `stage_approvals` row addressed to the build's PM. Refuses a
  duplicate submission and refuses outright when the build has no PM.
- `fn_decide_stage` → approve: stage `done` + `actual_end`, **next stage auto-starts**, submitter
  and client notified; reject: stage `rework` with a note the assignee sees on their task card.
- `fn_install_component` (Hero #2) validates the part is in stock and the caller owns the stage.
- ⚠️ **Only Workshop has a Start / Submit UI** (`workshop/task_detail.dart`). A stage assigned to a
  design or service member can't be started or submitted from the app (`PROJECT_LOG.md` §3 #1).

`BuildScreen` flags (passed to every tab): the PM opens with `canAssign / materialsEditable /
canEditTimeline = true`, and the Overview banner says "You manage this build". Admin opens with
`canAssignPm: true` only, and the banner says "Oversight · read-only".
