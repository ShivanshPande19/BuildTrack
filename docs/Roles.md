# Azimuth BuildTrack — Roles & Responsibilities

**One app, role-based access.** Every user logs into the same app. The **Admin** creates each user's ID and assigns a role — the app then opens straight to that role's own set of screens. Nobody sees more than their role needs (e.g. Workshop can't see costs, Client can't see vendors).

Design language is consistent across all roles: warm beige canvas, cream cards, candy-coloured status pills, lime accent, and a floating pill navigation bar with a prominent action button.

---

## Roles at a glance

| Role | Primary job | Data scope | Nav tabs | Key action |
|---|---|---|---|---|
| 👑 **Admin / Owner** | Run the whole operation | Fleet-wide (all 35+) | Home · Projects · Team · Analytics | Create user + assign role |
| 📋 **Project Manager** | Deliver assigned builds on time | Assigned projects | Home · Projects · Schedule · Team | Assign task |
| 🛒 **Procurement** | Order the right thing on time | All materials/POs | Home · Orders · Receive · Vendors | Create PO |
| 🔧 **Workshop** | Build the truck, log parts | Own tasks only | Tasks · Parts · Week · Profile | Scan & log part |
| 📦 **Store / Inventory** | Receive, track, stock, recall | All components/stock | Inbox · Stock · Parts · Profile | Log component |
| 🎨 **Design** | Layouts + client approvals | Own design tasks | Home · Library · Approvals · Profile | Upload design |
| 🛠️ **Service** | Post-delivery support | Delivered trucks | Tickets · Trucks · Warranty · Profile | New ticket |
| 🙋 **Client** | Track their truck | Their 1 truck only | Progress · Photos · Docs · Support | Raise request |

---

## 👑 Admin / Owner

**Who:** The owner / operations head. The master account.

**Owns & manages**
- The entire fleet of builds (35+ in parallel)
- All users and their roles (only Admin can create IDs and assign roles)
- Master setup: workflow templates, stage durations, item lead-times, vendors, holiday calendar
- Company-wide analytics and health

**How they work:** Lands on a fleet dashboard, spots at-risk/delayed builds, drills into any project, reviews analytics, and manages the team. Approves template changes the system suggests from real data.

**Screens (9):** Login · Dashboard (fleet health) · Projects (all) · Project detail · Analytics · Team & Roles · **Add Member (assign role)** · Notifications · Profile/Settings

**Features**
- Fleet status: On-track / At-risk / Delayed counts + "needs attention today"
- All-projects list with filters & search
- Analytics: on-time %, trend chart, top delay reasons, vendor performance
- User management: create ID, assign any role, view team
- Roles & permissions control

**Sees:** everything. **Only role that can:** create users, assign roles, edit master settings.

---

## 📋 Project Manager

**Who:** Owns delivery of a set of assigned builds.

**Owns & manages**
- Timelines & milestones for assigned projects
- Task assignment to workshop/design members
- Workshop bay & resource allocation
- Delays: tag reason, reschedule, see cascade impact
- Approving stage completions submitted by workshop

**How they work:** Reviews "needs you today" (approvals + at-risk), assigns stages to team members with dates, manages the weekly schedule and bays, and keeps builds on track.

**Screens (9):** Dashboard (my builds) · My Projects · Project detail (with assignees) · **Assign Task** · Schedule & bays · Team workload · Approvals · Notifications · Profile

**Features**
- My builds status + today's focus
- Assign task: pick member + set start/due dates
- Schedule: workshop bay allocation + this week's stages
- Team workload view (who's overloaded)
- Approve/reject workshop stage completions (with photos)

**Sees:** assigned projects, team, schedule. **Cannot:** create users.

---

## 🛒 Procurement

**Who:** Orders all materials and equipment; manages vendors. *(Core of Hero Feature #1 — never miss a lead time.)*

**Owns & manages**
- "To-Order" list driven by auto-calculated order-by dates
- Purchase Orders (ordered → dispatched → received)
- Vendors, their lead-times and reliability scores
- Goods receipt handoff to Store

**How they work:** Opens to order-by alerts (order today / X days left), creates POs to vendors, tracks dispatch/receipt, and watches vendor performance.

**Screens (9):** To-Order (dashboard) · Purchase Orders · PO detail (status tracker) · **Create PO** · Receive / GRN · Vendors · Vendor detail · Notifications · Profile

**Features**
- Backward-scheduled order-by alerts + escalation
- Create PO: vendor + items + dates
- PO status stepper (Ordered → Dispatched → Received)
- Vendor reliability scores + lead-times
- Low-lead vs long-lead handling (e.g. 45-day imports flagged early)

**Sees:** materials, POs, vendors, costs. **Cannot:** manage team/timelines.

---

## 🔧 Workshop / Fabrication

**Who:** The people physically building the truck. Mobile-first, on the floor. *(Core of Hero Feature #2 — traceability capture.)*

**Owns & manages**
- Their assigned stages/tasks only
- Progress photos
- Confirming each part **installed** into the truck (scan serial → linked to truck + stage). Bill/warranty are **not** re-entered here — Store already captured them at intake.
- Submitting completed stages for PM approval

**How they work:** Big-button, offline-friendly screens. Opens their current task, updates a checklist, adds photos, scans & logs each component, and marks the stage complete.

**Screens (9):** My Tasks · Task detail (checklist) · Add photo · **Scan to install** · Components (installed) · Mark complete · My week · Notifications · Profile

**Features**
- My tasks (in-progress + up next) with offline sync
- Stage checklist + progress
- Add progress photo (works offline)
- **Scan to install**: scan a part's serial → it matches a component already logged by Store (bill on file) → confirm it's installed in this truck & stage
- Mark stage complete → sends to PM for approval

> **Store vs Workshop (clear split):** **Store** creates the component record — serial + bill + warranty — when goods arrive. **Workshop** only *scans to install* — linking that existing record to the truck & stage. No duplicate data entry.

**Sees:** only their tasks. **Cannot:** see fleet data, costs, vendors.

---

## 📦 Store / Inventory

**Who:** Receives deliveries, tracks every component, manages stock. *(Completes Hero Feature #2 — the traceability master + recall.)*

**Owns & manages**
- Incoming deliveries (goods receipt / GRN)
- Component instances: serial, bill, warranty, which truck
- Stock levels + low-stock alerts
- **Recall check** — find every truck with a defective part model

**How they work:** Opens an inbox of arriving deliveries, verifies items, logs each with bill+warranty, and monitors stock. Can search any component and run a recall across the fleet.

**Screens (9):** Inbox · Receive / GRN · Log component · Inventory · Components (search) · Component detail · **Recall check** · Notifications · Profile

**Features**
- Goods receipt with item verification (qty check)
- Log component: serial + bill + warranty + assign to build
- Inventory with low-stock flags
- Search 1,000s of tracked components by serial/model/truck
- Recall: pick a model → list all affected trucks → notify all (in-build + delivered)

**Sees:** all components, stock, bills, warranties.

---

## 🎨 Design

**Who:** Creates layouts/designs and manages client approvals.

**Owns & manages**
- Design tasks per project
- Design versions (v1, v2, v3…)
- Sending designs to client for approval
- Client feedback & revisions

**How they work:** Works through design tasks, uploads new versions, sends to the client, and handles revision requests — all versioned.

**Screens (9):** My Designs · Design detail (versions) · Upload version · **Send for approval** · Client feedback · Library · Approvals · Notifications · Profile

**Features**
- Design status: Draft / Pending / Revise / Approved
- Version history with preview
- Send for approval → client notified instantly
- Client feedback thread → upload revised version
- Design library across all projects

**Sees:** design tasks, client feedback. **Cannot:** see costs, vendors, workshop tasks.

---

## 🛠️ Service & Support

**Who:** Handles issues after the truck is delivered.

**Owns & manages**
- Post-delivery tickets with SLA timers
- Linking tickets to the exact installed component + its warranty
- Scheduling technician visits
- Delivered-truck service history & warranty lookups

**How they work:** Works a ticket queue sorted by SLA, opens a ticket to see the linked part & warranty, resolves (warranty replacement or repair), or schedules a visit.

**Screens (9):** Tickets queue · Ticket detail (linked component) · Resolve · Schedule visit · Delivered trucks · Truck history · Warranty lookup · Notifications · Profile

**Features**
- Ticket queue with SLA countdown (Open / Overdue / Resolved)
- Ticket → auto-linked component + warranty status
- Resolve: warranty replace / on-site repair + notify client
- Schedule technician visit
- Warranty lookup across delivered fleet

**Sees:** delivered trucks, tickets, warranties.

---

## 🙋 Client

**Who:** The customer whose truck is being built. Simplest, read-mostly, fully transparent.

**Owns & manages**
- Tracking their own single truck
- Approving designs sent to them
- Their documents
- Raising post-delivery requests

**How they work:** Opens to a big progress ring and current status, browses build photos, approves designs, downloads documents, and can raise a request any time.

**Screens (10):** **My Trucks (list)** · Truck dashboard (progress) · Build journey · Photos · **Approve design** · Documents · Raise request · Support · Notifications · Profile

> If the client has more than one truck, the app opens on **My Trucks** (a list of all their builds); tapping one opens that truck's dashboard. With a single truck it opens the dashboard directly.

**Features**
- Live progress % + current stage + ETA (and delay reasons if any)
- Build photo gallery
- Approve / request changes on designs
- Documents: contract, invoices, warranty pack, handover certificate
- Raise a request + track it; chat with Azimuth

**Sees:** only their own truck. **Never sees:** costs, vendors, other clients, internal data.

---

## How the roles connect (a build's flow)

1. **Admin** onboards the project → app auto-builds the timeline & order-by dates.
2. **Design** creates the layout → **Client** approves it.
3. **Procurement** gets order-by alerts → creates POs → items arrive.
4. **Store** receives & logs each part (serial + bill + warranty).
5. **PM** assigns stages → **Workshop** builds, logs parts, submits for approval.
6. **PM** approves stages; **Client** watches progress + photos live.
7. On delivery, **Store** generates the handover pack (all bills/warranties).
8. Post-delivery, **Client** raises tickets → **Service** resolves (warranty-linked).
9. If a part is faulty, **Store** runs a **recall check** across the whole fleet.

---

*Azimuth BuildTrack · Roles reference · v1.0*
