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

> **Client sourcing rule:** clients are **not** created inline during onboarding. When Admin adds a user with `role='client'`, a `client_account` is created and linked. The onboarding **Client dropdown lists those existing client accounts** only.

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
| Schedule/bays | stages, bays | bay assignment | — |

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
