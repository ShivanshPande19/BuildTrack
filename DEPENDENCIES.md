# BuildTrack — Role & Data Dependencies (authoritative)

> **Read this before building any role.** It maps which role produces which data and which roles consume it, so nothing is built in the wrong order and no screen is left without its data source. Keep this updated as the source of truth.

---

## 1. The golden data-flow chain (create → consume)

```
MASTER DATA (templates, item_catalog, vendors)     ← Admin / Procurement set up once
        │
        ▼
Admin ── onboard project ──► creates: project, stages (from template), procurement_requirements, client_account, client login
        │
        ├──► Procurement  reads requirements ─► creates Purchase Orders ─► marks requirement "ordered"
        │            │
        │            ▼
        ├──► Store   reads POs ─► Goods Receipt ─► creates component_instances (serial + bill + warranty)  +  stock
        │            │
        │            ▼
        ├──► Workshop reads assigned stages + in_stock components ─► "scan to install" (links component → truck/stage)
        │            │                                            ─► add photos (attachments)
        │            ▼                                            ─► submit stage (stage_approvals)
        ├──► PM       assigns stages (feeds Workshop) ─► approves stage_approvals ─► stage=done ─► progress recompute
        │            │
        │            ▼
        ├──► Client   reads own project: progress, stages, photos, documents ─► approves designs ─► raises tickets
        │
        ├──► Design (P2)  creates design_versions ─► send for approval ─► Client approves
        └──► Service (P2) reads tickets (from Client) + component warranty (from Store) ─► resolves
```

---

## 2. Per-role — NEEDS (prerequisites) vs PRODUCES (for others)

| Role | NEEDS (must exist first) | PRODUCES (consumed by) |
|---|---|---|
| **Admin** | workflow_templates, item_catalog, vendors | projects, stages, procurement_requirements, client_accounts, users/roles → **everyone** |
| **Procurement** | projects + requirements (Admin), vendors, item_catalog | purchase_orders, po_lines, requirement status → **Store** |
| **Store** | purchase_orders (Procurement), item_catalog, vendors | component_instances (in_stock), goods_receipts, stock → **Workshop, Service** |
| **Workshop** | stages assigned (PM/Admin), component_instances in_stock (Store) | installed components, attachments (photos), stage_approvals → **PM, Client** |
| **PM** | projects assigned (Admin), stages, stage_approvals (Workshop) | stage assignments (→Workshop), approved stages, progress → **Client** |
| **Client** | own project (Admin), stages/photos, documents, design_versions (Design) | design approvals (→Design), tickets (→Service) |
| **Design** (P2) | project (Admin) | design_artifacts/versions → **Client** |
| **Service** (P2) | delivered projects, tickets (Client), component warranty (Store) | resolutions, service_visits |

---

## 3. Shared repositories (touched by multiple roles)

Build these as **shared** methods so no role re-implements them:

| Repository | Tables | Used by |
|---|---|---|
| `ProjectsRepo` | projects, stages | Admin(create/read), PM(read/update), Procurement(read), Store(read), Workshop(read/update), Client(read) |
| `CatalogRepo` | item_catalog, vendors | Admin/Procurement(write), Store/Workshop(read) |
| `ProcurementRepo` | procurement_requirements, purchase_orders, po_lines | Admin(create reqs), Procurement(read/write) |
| `ComponentsRepo` | component_instances, goods_receipts, stock_items | Store(create), Workshop(install), Store/Service(read), recall |
| `PeopleRepo` | profiles, client_accounts | Admin(manage), all(read own) |
| `NotificationsRepo` | notifications | all |
| `AttachmentsRepo` | attachments | Workshop(create), Client(read) |

---

## 4. Build-order rule & stubbing

- Build in the golden-chain order: **Admin → Procurement → Store → Workshop → PM → Client**.
- When a role's screen needs data a not-yet-built role would produce, **seed it** (demo rows) so the screen is testable now — never leave a screen without a data source.
- Whenever a new role is built, add/extend the **shared repo** it needs (see §3) rather than duplicating queries.

---

## 5. Screen-level dependency matrix (detailed)

### Admin
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Dashboard | projects, v_order_due | — | projects onboarded |
| Onboard project | templates, clients, PMs | projects, stages, requirements | master data (templates/items/vendors) |
| Projects / detail | projects, stages | project fields | — |
| Team / Add member | profiles | profiles (create+role); **if role=client → also create client_account** (contact_user_id = new user) | — |
| Analytics | projects, delay_logs, vendors | — | data over time |

> **Client sourcing rule:** a `client_account` and its **login are always created together** —
> either from Team → Add member (`role='client'`) or inline from **Onboard Project → Client → ＋ New**
> (`createClientLogin()`, which calls the same `admin-create-member` Edge Function and returns the new
> `client_account_id` so it can be selected immediately).
> The onboarding dropdown lists **only accounts that have `contact_user_id` set**: an account with no
> login is unreachable (`my_client_account()` returns null, so RLS matches no rows) and the client
> could never see their truck. Legacy login-less rows are hidden and counted in a hint on the screen.

### Procurement
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| To-Order | v_order_due | purchase_orders, po_lines, requirement status | Admin onboarded (requirements exist) |
| POs / detail | purchase_orders, po_lines | po status | POs created |
| Receive/GRN | purchase_orders | goods_receipts, component_instances/stock | PO exists |
| Vendors | vendors | vendors | — |

### Store
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Inbox / Receive | purchase_orders | goods_receipts | Procurement PO |
| Log component | item_catalog, vendors | component_instances (+bill+warranty) | GRN/PO |
| Inventory | stock_items | stock qty | — |
| Components / detail | component_instances | — | logged components |
| Recall | component_instances (by model) | notifications | components installed |

### Workshop
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| My Tasks | stages (assignee=me) | — | PM assigned / Admin stages |
| Task detail | stages, checklist_items | checklist, status | — |
| Scan to install | component_instances (in_stock) | component install fields | **Store logged component** |
| Add photo | — | attachments | — |
| Mark complete | — | stage_approvals | — |

### PM
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| Dashboard/Projects | projects (pm=me) | — | Admin set pm_id |
| Assign task | profiles(workshop), stages | stages.assignee/dates | — |
| Approvals | stage_approvals | stage=done | **Workshop submitted** |
| Schedule | stages (assigned_due → planned_end), profiles | — | PM assigned dates / backward schedule |

### Client
| Screen | Reads | Writes | Depends on |
|---|---|---|---|
| My Trucks / dashboard | projects (client=me), stages | — | Admin onboarded with this client |
| Photos | attachments | — | Workshop photos |
| Approve design | design_versions | design_approvals | Design sent |
| Documents | documents | — | Admin/system |
| Raise request | — | tickets | — |

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

1. **Template BOM** (`template_stage_items`): which catalog items each template stage needs (+ qty). *(editing UI: TODO — currently via `seed_bom_demo.sql` or SQL)*
2. **Onboarding** (`fn_onboard_project`): creates stages → backward-schedules them → **auto-generates `procurement_requirements`** from the BOM with `needed_by = stage.planned_start` → computes `order_by`.
3. **View / customize per project** (`ProjectRequirementsScreen`, has `editable` flag):
   - **Admin = read-only (monitor)** — sees materials + order-by risk, cannot edit. Admin's job is oversight only.
   - **Editing owner = PM (Project Manager)** — opens it `editable: true` to add / change qty / change needed-by / remove. Any change calls `fn_recompute_schedule` to refresh `order_by`.
   - *(PM role not built yet — editable entry point ships with the PM role.)*
4. **Alerts**: `order_by = needed_by − item.lead_time − item.buffer`. Surfaced via `v_order_due` (`days_left`) in Admin "Needs attention" + Procurement "To Order".
5. **Act**: Procurement Create PO → requirement `pending → ordered` (drops off the due list).

Editing requirements invalidates `requirementsProvider`, `toOrderProvider`, `fleetProvider`.


---

## ⭐ Role ownership — build planning belongs to PM (decided)

**Admin = oversight only** (monitor dashboards, team/user management). Admin does NOT do
operational data entry.

**PM (Project Manager) owns build planning**, i.e. all of:
- **Workflow templates + their BOM** (define "which parts each stage needs" per truck type) — the one-time setup that powers auto-generated requirements.
- **Per-project materials / requirements** — add / edit qty / edit needed-by / remove (`ProjectRequirementsScreen` with `editable: true`).
- (later) schedule / bays, task assignment, stage approvals.

**Procurement** consumes what PM plans: sees order-by alerts (To Order) and creates POs.
**Store / Workshop** execute intake + install. **Client** views progress.

> These planning features currently sit under Admin only because PM isn't built yet.
> When the PM role is built, Create-Template(+BOM) and the editable Materials screen
> move/attach there; Admin keeps them **read-only**.


---

## Assignment architecture (two levels) — enforced in the database

See `docs/WORKFLOW_AUDIT.md` for the problems this replaced and
`supabase/migrations/0009_workflow.sql` for the implementation.

**Level 1 — Admin assigns the PM** (`projects.pm_id`)

- Set at **Onboard Project** (PM dropdown, **required**) and changeable any time from
  **Project detail → Project manager → Assign / Change** (`canAssignPm: true`, Admin only).
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
  `stagesToAssignProvider`) and **Project detail → stage → Assign / Reassign / Unassign**.
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

`ProjectDetailScreen` flags: PM opens with `canAssign / materialsEditable / canEditTimeline = true`;
Admin opens with `canAssignPm: true` and everything else read-only (oversight).
