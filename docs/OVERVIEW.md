# BuildTrack — Overview

A short but complete picture of what the app is, who uses it, and how a build
moves through it end to end. If you read only one document, read this one.

---

## What it is

BuildTrack is the build-management app for **Azimuth Business on Wheels**, which
makes premium food trucks, carts and kiosks. It is **one mobile app with eight
role-based experiences** that runs the entire build phase — from the moment a
confirmed order is handed to the workshop, through fabrication and design, to
delivery and after-sales support — across many builds running in parallel.

The backend is **Supabase** (Postgres + Auth + Storage), with the business rules
enforced in the database itself (row-level security + server-side functions), so
no client can bypass them. The app is **Flutter** (Android, iOS, and web for
office use).

## The two problems it solves

1. **Timelines slip.** A missed order-by date on one part pushes the whole
   delivery late. → BuildTrack works the schedule *backwards* from the promised
   delivery date and raises an **order-by alert** for every material, so nothing
   is ordered too late.
2. **No traceability.** When a part fails after delivery, nobody can find its
   bill, its warranty, or which other trucks use the same part. → BuildTrack
   keeps a **digital record per part** (serial, vendor, warranty, bill) and can
   run a **recall** across every truck that has it.

## The eight roles

| Role | What they do |
|---|---|
| **Admin** | Onboards projects, creates logins, assigns the project manager, manages the team and workflow templates, sees fleet-wide health. |
| **Project Manager (PM)** | Owns a set of builds: plans materials, assigns each stage to the right person with dates, approves completed work, logs delays, and hands the truck over. |
| **Procurement** | Turns the PM's material needs into purchase orders, tracks dispatch, and receives goods. |
| **Store** | Logs every received part (serial, warranty, bill), keeps inventory, and can trigger a recall. |
| **Workshop** | Does the physical build: works assigned stages, ticks checklists, scans and installs parts, uploads site photos, submits work for approval. |
| **Design** | Creates the truck's designs (2D + 3D), and gets them approved by the client. |
| **Service** | After-sales: handles support tickets on delivered trucks, schedules technician visits, tracks warranties. |
| **Client** | Watches their truck's progress, photos and designs; approves designs; downloads documents; raises support requests. |

*(There is no marketing/sales role and no payments module in the app — the deal,
the client conversation and the advance payment happen outside BuildTrack. The
app begins when Admin onboards the confirmed project.)*

---

## The workflow, end to end

**Before the app:** a client is signed up, terms are agreed, and the advance is
collected — all offline. Then:

1. **Admin onboards the project.** Picks a workflow template, assigns a PM, links
   the client, sets the target delivery date. The system then automatically:
   - creates the build's **stages** from the template (each tagged with the
     discipline that owns it),
   - **backward-schedules** them from the delivery date (planned start/end),
   - generates a **materials list** (procurement requirements) from the
     template's bill of materials,
   - seeds each stage's **checklist** from the template,
   - notifies the PM.

2. **PM plans and assigns.** The PM reviews the materials (adjusting quantities
   and "needed-by" dates per build), and assigns each stage to a team member with
   start/due dates. Each material's **order-by date** is computed as
   `needed-by − vendor lead time − buffer`.

3. **Procurement orders.** The order-by dates appear as alerts. Procurement
   raises purchase orders, marks them dispatched, and **receives** them — which
   adds the quantities to Store's stock.

4. **Store logs parts.** Each received part is recorded with its serial number,
   warranty dates, vendor and **bill image** — the digital record that powers
   traceability and recall.

5. **Design gets approved** (for builds with a design stage). The designer
   uploads a 2D preview and a 3D model; the **client approves** or requests
   changes. An approved 3D model becomes the client's truck showcase.

6. **Workshop builds.** For each assigned stage the worker starts it, ticks the
   checklist, **scans and installs** the required parts, uploads **site photos**,
   and submits the stage for approval.

7. **PM approves.** The approval screen shows the submitted **photos, checklist
   and installed parts**, so the PM decides on evidence. Approving marks the
   stage done, **auto-starts the next stage**, updates progress, and notifies the
   client. Rejecting sends it back with a reason.

8. **Delays are tracked.** If a build slips, the PM logs the **reason** and can
   push the delivery date, which re-runs the schedule for every remaining stage.

9. **Handover.** When the stages are done, the PM **marks the truck delivered**.
   The build moves into after-sales, and staff upload the client's **documents**
   (contract, invoice, warranty pack, handover certificate).

10. **After-sales (Service).** The client (or Service, on their behalf) raises a
    **support ticket** with an SLA deadline. Service triages it, assigns a
    technician, schedules a visit, resolves and closes it — and the client can
    reopen it if the problem persists. Service also runs warranty lookups and
    recalls.

Throughout, each build's **status** (on-track / at-risk / delayed) and
**progress %** update automatically, and the client sees their truck's progress,
photos, designs and documents live.

```
Admin onboard → PM plan + assign → Procurement order → Store receive & log
   → (Design approve) → Workshop build & submit → PM approve → next stage
   → … → PM deliver + documents → Service after-sales
```

---

## What's live today

All eight roles are usable and wired to the backend. The core chain above works
end to end, including the two "hero" features (order-by scheduling and part
traceability/recall), real camera photos and barcode scanning, template
checklists, stock movement on receipt, bill capture, delay logging, document
handover, and client-visible support tickets.

## What's not in the app (yet)

- **Payments / finance** — the advance and later payments are handled outside the
  app; there is no billing module.
- **Robustness features planned next:** offline support for the shop floor, push
  notifications, live/realtime updates, list pagination at scale, and Hindi
  localization.

---

## In one line

BuildTrack takes a confirmed food-truck order and carries it — with the whole
team on the same page — from planning and procurement, through fabrication and
design approval, to a documented handover and after-sales support, while keeping
every timeline and every part accounted for.
