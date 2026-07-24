# Azimuth BuildTrack — API Design (v1)

REST API derived from the data model + role UIs. Every screen maps to endpoints here. Built for a mobile app used by all 8 roles.

## Conventions

- **Base URL:** `/api/v1`
- **Auth:** JWT bearer token. `Authorization: Bearer <token>`. Token carries `user_id` + `role`.
- **Access control:** every endpoint is role-guarded (see the permission matrix in the Data Model). Server always scopes data to what the role may see (e.g. a client only ever gets their own projects).
- **Format:** JSON. Standard envelope: `{ "data": ..., "meta": {...} }`; errors: `{ "error": { "code", "message" } }`.
- **Lists:** support `?page=`, `?limit=`, `?search=`, `?status=` where relevant. Return `meta.total`.
- **Files:** uploads are `multipart/form-data` (bills, photos, design files) → return stored `file` URL.
- **IDs:** UUIDs.

---

## 1. Auth & Me

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/auth/login` | all | email + password → token + user (role decides home screen) |
| POST | `/auth/logout` | all | invalidate token |
| POST | `/auth/forgot-password` | all | reset link |
| GET | `/me` | all | current user profile + role + permissions |
| PATCH | `/me` | all | update own profile |

---

## 2. Users & Roles — *Admin only*

| Method | Path | Purpose |
|---|---|---|
| GET | `/users?role=&search=` | Team list |
| POST | `/users` | **Create member + assign role** (Add Member screen). Body: `{full_name, email, phone, role}` → sends invite |
| GET | `/users/{id}` | member detail |
| PATCH | `/users/{id}` | change role / status (activate/disable) |
| GET | `/roles` | role list + permission matrix |

---

## 3. Clients

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/clients?search=` | admin, pm | client accounts |
| POST | `/clients` | admin | create client account (+ client login) |
| GET | `/clients/{id}` | admin, pm | client + **their projects list** |

---

## 4. Projects & Stages

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/projects?status=&search=&pm=` | admin (all), pm (assigned) | project list w/ progress + status |
| POST | `/projects` | admin | **Onboard project** — body `{code,name,client_account_id,template_id,pm_id,target_delivery_date}`. Server auto-creates STAGES + PROCUREMENT_REQUIREMENTS with backward-scheduled dates |
| GET | `/projects/{id}` | admin, pm | full project detail |
| PATCH | `/projects/{id}` | admin, pm | update (target date, pm, advance_received…) — triggers reschedule |
| GET | `/projects/{id}/stages` | admin, pm | stage timeline (with assignees) |
| GET | `/projects/{id}/components` | admin, pm, store | installed components (traceability list) |
| GET | `/projects/{id}/analytics` | admin, pm | per-project health |

### Stages

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/stages/{id}` | pm, workshop | stage + checklist |
| PATCH | `/stages/{id}/assign` | pm | `{assignee_id, start, due, bay_id}` (Assign Task) |
| PATCH | `/stages/{id}` | pm | edit dates → downstream reschedule |
| POST | `/stages/{id}/checklist/{itemId}/toggle` | workshop | tick a sub-step |
| POST | `/stages/{id}/photos` | workshop | add progress photo(s) (multipart, offline-syncable) |
| POST | `/stages/{id}/submit` | workshop | Mark complete → submit for PM approval (+photos) |
| POST | `/stages/{id}/approve` | pm | approve submitted stage |
| POST | `/stages/{id}/reject` | pm | request changes |
| POST | `/stages/{id}/delay` | pm | `{reason_code, days, note}` → downstream reschedule + client notified |

### Templates, Schedule, Bays

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET/POST/PATCH | `/templates`, `/templates/{id}` | admin | workflow templates + stage durations/deps |
| GET | `/schedule?week=` | pm, workshop | week view (stages by day) |
| GET | `/bays` | pm | bay allocation |
| PATCH | `/bays/{id}` | pm | assign/free a bay |

---

## 5. Scheduling & Procurement Requirements — *Hero #1*

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/procurement/requirements?status=&project=&due=` | procurement | **To-Order list** with computed `order_by_date`, sorted by urgency |
| GET | `/procurement/requirements/{id}` | procurement | one requirement |

> `order_by_date = needed_by_date − item.lead_time_days − item.buffer_days`. A **daily scheduler job** recomputes these when any stage date shifts and pushes alerts/escalations for `pending` items whose `order_by_date` is near/past.

---

## 6. Procurement — Vendors, POs, Receiving

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/vendors?search=` | admin, procurement | vendor list + reliability scores |
| POST | `/vendors` | procurement | add vendor |
| GET | `/vendors/{id}` | procurement | vendor detail (lead time, perf, orders) |
| GET | `/pos?status=&project=` | procurement, admin | purchase orders |
| POST | `/pos` | procurement | **Create PO** — `{vendor_id, project_id, lines:[{item_catalog_id, qty}], expected_date}`. Links requirements → `status=ordered` |
| GET | `/pos/{id}` | procurement | PO detail (status stepper, lines) |
| PATCH | `/pos/{id}/status` | procurement | ordered → dispatched |
| POST | `/pos/{id}/receive` | store | **Goods receipt (GRN)** — `{lines:[{po_line_id, received_qty}], status, note}`. Creates COMPONENT_INSTANCE rows / updates STOCK |

---

## 7. Inventory & Traceability — *Hero #2*

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/components?search=&model=&project=&warranty=` | store, admin, service | search tracked components |
| POST | `/components` | store | **Log component at intake** — `{item_catalog_id, serial_number, vendor_id, grn_id, warranty_start, warranty_end}` + `bill_file` (multipart) |
| GET | `/components/{id}` | store, service | digital-twin record (serial, bill, warranty, truck) |
| POST | `/components/{id}/install` | workshop | **Scan to install** — `{project_id, stage_id}` → sets installed_* + `status=installed`. No bill re-entry |
| GET | `/components/recall?model=` | store, admin | **Recall check** — all trucks with a given model |
| POST | `/components/recall/notify` | store, admin | notify all affected clients |
| GET | `/stock?low=&category=` | store | stock levels + low flags |
| PATCH | `/stock/{id}` | store | adjust quantity |

---

## 8. Design & Approvals

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/designs?status=&mine=` | design | My Designs / Library |
| GET | `/projects/{id}/designs` | design, pm | designs for a project |
| POST | `/projects/{id}/designs` | design | create design artifact |
| POST | `/designs/{id}/versions` | design | **Upload new version** (multipart file + change_note) |
| GET | `/designs/{id}` | design | design + version history |
| POST | `/designs/{id}/send-approval` | design | send current version to client (notifies client) |
| GET | `/designs/approvals?status=` | design | approvals tracker |
| POST | `/design-versions/{id}/approve` | client | approve |
| POST | `/design-versions/{id}/request-changes` | client | `{feedback}` |

---

## 9. Service — Tickets & Visits *(post-delivery)*

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/tickets?status=&sla=` | service | ticket queue (SLA sorted) |
| GET | `/tickets/{id}` | service | ticket + **auto-linked component + warranty** |
| PATCH | `/tickets/{id}/assign` | service | assign to agent |
| POST | `/tickets/{id}/resolve` | service | `{resolution_type, note}` → notify client |
| POST | `/tickets/{id}/visits` | service | **Schedule visit** — `{technician_id, scheduled_date}` |
| GET | `/service/trucks?search=` | service | delivered trucks (open-ticket flags) |
| GET | `/service/trucks/{id}/history` | service | truck service history + components |
| GET | `/warranty?search=` | service | warranty lookup (active/expiring/expired) |

---

## 10. Client-facing — *scoped to the logged-in client (multi-project aware)*

| Method | Path | Purpose |
|---|---|---|
| GET | `/me/projects` | **My Trucks** — all projects under this client (list; app shows selector if >1) |
| GET | `/me/projects/{id}` | one truck dashboard: progress %, current stage, ETA, status |
| GET | `/me/projects/{id}/timeline` | friendly build journey |
| GET | `/me/projects/{id}/photos` | build photo gallery |
| GET | `/me/projects/{id}/documents` | contract, invoices, warranty pack, handover |
| GET | `/me/designs/pending` | designs awaiting my approval (across my projects) |
| POST | `/me/design-versions/{id}/approve` \| `/request-changes` | approve / feedback |
| GET | `/me/projects/{id}/tickets` | my requests for this truck |
| POST | `/me/projects/{id}/tickets` | **Raise a request** — `{category, description}` + photos |
| GET | `/me/tickets` | all my requests across trucks |

> All `/me/...` endpoints resolve the client from the token and enforce that the `project_id` belongs to them. This is how **one client with multiple projects** is handled end-to-end.

---

## 11. Cross-cutting

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/notifications` | all | user's notifications |
| POST | `/notifications/read-all` | all | mark all read |
| POST | `/notifications/{id}/read` | all | mark one read |
| POST | `/attachments` | internal roles | upload photo/file (multipart) `{owner_type, owner_id}` |
| GET | `/documents/{id}/download` | admin, client(own) | download a document |
| GET | `/analytics/fleet` | admin | on-track/at-risk/delayed, on-time %, trend |
| GET | `/analytics/delay-reasons` | admin | top delay reasons |
| GET | `/analytics/vendors` | admin, procurement | vendor performance |
| GET | `/audit?entity=` | admin | activity log |

---

## 12. Key flows (endpoint sequences)

**Onboard a project (Admin)**
`POST /projects` → server generates stages + `order_by_date`s → `POST /users`(if new client login) → client & PM notified.

**Order-by lifecycle (Procurement)**
Daily job flags `GET /procurement/requirements` → `POST /pos` → `PATCH /pos/{id}/status` (dispatched) → `POST /pos/{id}/receive` (Store, creates components).

**Part into a truck (Store → Workshop)**
Store `POST /components` (serial+bill+warranty) → Workshop `POST /components/{id}/install` (scan → truck+stage).

**Design approval (Design ↔ Client)**
`POST /designs/{id}/versions` → `POST /designs/{id}/send-approval` → client `POST /me/design-versions/{id}/approve`.

**Stage done (Workshop → PM → Client)**
`POST /stages/{id}/submit` → PM `POST /stages/{id}/approve` → project progress recomputed → client sees update.

**Recall (Store)**
`GET /components/recall?model=` → `POST /components/recall/notify`.

**Post-delivery issue (Client → Service)**
Client `POST /me/projects/{id}/tickets` → Service `GET /tickets/{id}` (warranty auto-pulled) → `POST /tickets/{id}/resolve` or `/visits`.

---

## 13. Realtime / notifications (delivery)

- **Push (FCM)** for alerts: order-by due, stage assigned, approval needed, ticket raised, SLA breach.
- **WebSocket / polling** for live dashboards (fleet health, ticket queue).
- **WhatsApp/SMS** (later phase) for client milestone updates.

---

*Azimuth BuildTrack · API Design · v1 · derived from data model + role UIs*
