# Azimuth BuildTrack: Roles & Screens

**One app, eight role experiences.** An admin creates every login and gives it a role. On sign-in,
`role_home.dart` opens that role's home. Every home is a floating `PillNav` with 3–4 tabs and a
round **＋ action button (FAB)**. The FAB does one thing per role, whatever tab is open.
Permissions are enforced in Postgres (RLS + RPCs), not just in the UI. See [`DataModel.md`](DataModel.md) §8.

**A role is a team.** There can be several PMs, designers, technicians or client contacts. "My
work" is always scoped by user id: a PM sees builds where `pm_id = me`, and an assignee sees stages where
`assignee_id = me`.

The design language (Equora) is a warm beige canvas, cream cards, candy-coloured status pills, a lime accent and the floating
pill nav. It lives in `core/theme.dart` and `shared/widgets.dart`.

---

## At a glance

| Role | Tabs | ＋ FAB | Scope |
|---|---|---|---|
| 👑 Admin | Home · Projects · Team · Insights | Onboard project | Whole fleet |
| 📋 PM | Home · Projects · Schedule · Team | Assign work | Builds where I'm the PM |
| 🛒 Procurement | To Order · Orders · Receive · Vendors | New PO | All requirements and POs |
| 📦 Store | Inbox · Stock · Parts | Log component | All stock and components |
| 🔧 Workshop | Tasks · Parts · Week | Scan to install | Stages assigned to me |
| 🎨 Design | Studio · Designs · Approvals | New design | Builds where I hold a stage |
| 🛠️ Service | Tickets · Trucks · Warranty · Profile | New ticket | All tickets, delivered trucks |
| 🙋 Client | My Trucks · Support · Profile | Raise request | My client account's trucks |

**Shared:**
- The bell opens **Notifications** (Today / Earlier, Mark all read; rows aren't tappable).
- The avatar opens **Profile** (identity + log out; the settings rows are coming-soon). Service and Client have their own Profile tab instead.

---

## 👑 Admin / Owner

**Job:** oversight and people. Onboard builds, create logins, assign the PM, give POs final approval, and watch the fleet.

- **Home:**
  - fleet status (active builds, on-track / at-risk / delayed);
  - **Command Center**, a live factory board: by department, a needs-attention list (delayed, at-risk,
    > 7 days in one stage, order-by passed), and every build's current stage, assignee + sub-team and PM;
  - **PO approvals** (final sign-off, sorted by priority; tap the badge to override);
  - **Needs attention** (order-by items due within 3 days);
  - the bell's unread badge.
- **Projects:** All / On-track / At-risk / Delayed chips, plus **No PM** (shown when a build has no PM). A row opens
  the **build screen**.
- **Team:**
  - members grouped by department, with a department filter;
  - **Add member**: the admin sets the email and **password**, picks the role (all 8) and optionally a sub-team (with a new-team option). A credentials dialog follows;
  - swipe to remove a member (Edge Function);
  - **Company details**: the buyer name, address, GSTIN and state printed on every PO.
- **Insights** (screen title "Analytics"): on-track %, on-track / at-risk / delayed counts, distribution bars.
- **＋ Onboard project:**
  - code, name and template, with **New**, which opens *Create template*: stages, days, BOM items per stage, checklist per stage;
  - client, with **New**, which creates the client account + login (password, or an email invite);
  - PM (required) and target delivery date.
- **On the build screen:** *Oversight · read-only*. Admin can **assign / change the PM** and add documents.
  Materials, Pipeline and Record are read-only.

**Admin has no UI to** assign stages, edit materials, change the delivery date, log delays or mark delivered (all PM).
The database does let an admin do these through the RPCs.

---

## 📋 Project Manager

**Job:** plan and run their builds.

- **Home (My Builds):**
  - assigned / at-risk / delayed / delivered counts;
  - **Assign work** (stages with no owner or in rework);
  - **Approvals**: each card shows the stage's **photos, checklist and installed parts**. Approve auto-starts the next stage.
    **Reject** opens a *Send back* dialog ("What needs fixing?"; a blank reason is accepted) and puts the stage into rework;
  - **PO approvals**: sign or reject POs on my builds;
  - at-risk / delayed builds;
  - today's in-progress stages.
- **Projects:** my builds with status chips. A row opens the **build screen** as *You manage this build*:
  - **Assign / Reassign** a stage. The sheet recommends the stage's discipline first and shows each person's open load.
    Another role needs a second tap (override). Start and due dates. Unassign.
  - **Materials** (editable): add or edit an item, qty and needed-by. The order-by date recomputes. Delete.
  - **Delivery date**: tap to change it. The plan and assigned dates re-baseline.
  - **Log a delay**: reason, days, note, and "push delivery date" (on by default).
  - **Mark delivered**: asks *Deliver anyway?* if stages are still open.
  - **Documents**: contract / invoice / warranty pack / handover certificate. The client sees them.
- **Schedule:** open stages grouped as Overdue · Due today · Next 7 days · Later · No date yet.
- **Team:** read-only workload (open stages per workshop / design / store / service member).
- **＋ Assign work.**

**PM can't:** create builds, take over another PM's build, or change a build's code / client / template (DB-enforced).
Templates have no PM screen (§ gaps).

---

## 🛒 Procurement

**Job:** turn needs into approved POs, and get the goods in.

- **To Order:**
  - the most urgent order-by item as a hero card; **Create Purchase Order** pre-fills the PO;
  - upcoming order-by dates;
  - **Essentials to reorder · from Store**; each opens a *general* PO.
- **Orders:** All / For approval / Ordered / Dispatched / Received. A row opens **PO detail**:
  - approval stepper (Raised → PM signed → Approved) and the signature trail;
  - **Fix & resubmit** after a rejection;
  - fulfilment stepper; **Mark as dispatched** (expected arrival date); **Mark as received**;
  - **View / print PO document**: a GST purchase order PDF with buyer + supplier GSTIN, HSN, CGST+SGST (same state) or
    IGST, the amount in words with paise, and signatories filled from the trail.
- **Receive:** *Awaiting dispatch* (Mark dispatched) and *Ready to receive* (Receive & verify; bulk stock goes up).
- **Vendors:** list with lead time and reliability %, **Add vendor** (GSTIN, address, state, email).
- **＋ New PO:**
  - project or *General (no project)*, vendor;
  - lines (item, qty, rate, GST %, HSN; inline new item);
  - expected delivery, payment terms, totals.
  - A project PO goes to the PM to sign, then to admin for final approval. A general PO goes straight to admin.

**Procurement can't:** sign or approve POs, or dispatch / receive before approval (DB-enforced).

---

## 📦 Store / Inventory

**Job:** log every part (Hero #2), keep stock, and run recalls.

- **Inbox:** tracked components, low-stock count, stock lines, and the low-stock list.
- **Stock:**
  - All / Low; OK / Fair / Low against the item's threshold;
  - bulk items come from `stock_items`; serialized items count their in-stock units;
  - tap a row to **request a reorder**; **Request from procurement** picks from essentials.
- **Parts** (screen title "Components"): search by serial, model or truck. A row opens the **component record**:
  - warranty banner;
  - **View bill**;
  - **Recall check**: every truck with that model, then **Notify all** (each build's PM and client).
- **＋ Log component:** item, serial (**scan** the label, or type it), vendor, warranty end, **bill photo**,
  optional *assign to build*. "Save & log another" keeps the fields for the next unit.

---

## 🔧 Workshop / Fabrication

**Job:** build the assigned stages and record the evidence.

- **Tasks** (My Tasks):
  - *In progress* (with rework reason, *Awaiting approval*, due / overdue) and *Up next*;
  - a row opens **Task detail**:
    - **Start work**;
    - checklist (instant tick);
    - **Photo** (camera or gallery, with caption);
    - **Install part**;
    - **Submit for approval**. The button reads "Mark stage complete" while checks are open; it does the same thing.
- **Parts:** parts installed on builds where I have a stage.
- **Week:** all my stages with status.
- **＋ Scan to install:**
  - scan a serial (torch, manual entry if the label is damaged) or pick an in-stock part;
  - confirm → installed into the chosen stage.
  - Refused unless the part is in stock and you are the assignee.

**Only role with a stage Start / Submit UI.** Design and Service stages can't be submitted (see gaps).

---

## 🎨 Design

**Job:** designs and client approvals, for builds where a PM gave me a stage.

- **Studio:** *Assigned to me* carousel (stage, due, delivery), draft / awaiting / changes / approved counts, *Needs your attention*.
- **Designs:** library with filters (All / Drafts / Awaiting / Changes / Approved).
- **Approvals:** everything sent to clients, with their outcome and feedback.
- **Design detail:**
  - interactive 3D (`.glb`) or 2D preview, client feedback, version history;
  - **Submit for approval** (drafts);
  - **Upload revised version** / **Upload new version**: atomic `vN` numbering, which is safe with several designers.
- **＋ New design:**
  - pick an assigned build and a type (layout / interior / exterior / branding);
  - upload a `.glb` (≤ 25 MB, or Demo) and/or a preview image;
  - add a note, then save as draft or submit.
- Profile is reached from the header avatar.

An **approved** model becomes the truck's 3D showcase for the Client, Admin and PM.

---

## 🛠️ Service & Support

**Job:** after-sales on delivered trucks.

- **Tickets:**
  - Open / Overdue / Resolved / All, sorted by SLA deadline, with a live countdown;
  - stats: open, overdue, fixed today.
  - A ticket opens **Ticket detail**:
    - client photos, assign technician (service or workshop), visits and the resolution;
    - **Schedule visit** (technician, date, time, note; re-booking cancels the old one);
    - **Resolve**: Replaced under warranty / Repaired on-site / Guided remotely, plus a note the client reads;
    - **Close ticket** once resolved.
- **Trucks** (screen title "Delivered"): every delivered build, tagged *N open*, *Wty soon* or *Healthy*. A truck opens its history
  (client, parts, warranty, every request).
- **Warranty:** search by serial, model or truck.
- **Profile** tab: assigned to me, resolved today, log out.
- **＋ New ticket:** delivered truck, category, priority (sets the SLA: high 4h, medium 24h, low 72h), issue.

---

## 🙋 Client

**Job:** follow their truck, approve designs and ask for help. They never see costs, vendors or other clients.

- **My Trucks:** one card per truck with a live **3D model** (the approved design, else a demo), status and progress.
  A card opens the truck.
- **Truck** (one scrolling screen):
  - progress ring, current stage, delivery date;
  - **Approve design** cards when a design waits for them (approve, or *Request changes* with feedback);
  - the **build journey**; tapping a stage shows its photos;
  - documents;
  - **Raise a request**.
- **Support:**
  - every request on their trucks, including ones Service logged for them;
  - status, the resolution note;
  - **Still not fixed** to reopen, which puts it back at high priority.
- **Profile** tab: notifications, log out.
- **＋ Raise request:** pick the truck (if more than one), category, description, optional photo.

---

## Known gaps by role (Oct 2026)

Full list: [`PROJECT_LOG.md`](PROJECT_LOG.md) §3.

| Role | Gap |
|---|---|
| Design, Service | Can't **start or submit** an assigned stage. Workaround: the PM reassigns it to a workshop member with an override. |
| Admin, PM | Templates can't be listed or edited, and there's no per-stage discipline picker. The PM has no template screen at all. |
| Store | Inline **New item** is refused by RLS. No incoming-PO / GRN list. |
| Procurement | Only the hero To-Order item pre-fills a PO. No vendor detail. No partial receipt. |
| Client | Documents don't open (the tap only shows a snackbar). No priority on requests. |
| Everyone | Notifications aren't tappable. No realtime; pull to refresh. Disabled accounts can still sign in. |
