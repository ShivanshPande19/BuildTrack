# BuildTrack: Testing & Go-Live Guide

How to deploy the current `main` and test every role and every hand-off with **two devices**:
an iOS Simulator and one real phone. Read it top to bottom once; after that, §3 is the part you reuse.

---

## 1. Deploy checklist (do it once, in order)

### 1.1 Database: apply only what's missing
1. Supabase → SQL editor → paste and run **`supabase/check_migrations.sql`**. It is read-only.
   You get one row per migration, `0004`–`0025`, marked `applied` or `RUN THIS`.
2. **Before `0025`**, this must return 0 rows (`0025` adds a UNIQUE index):
   ```sql
   select artifact_id, version_no, count(*) from design_versions
   group by 1, 2 having count(*) > 1;
   ```
3. Run each `RUN THIS` file from `supabase/migrations/`, **one at a time, in number order**. If one errors,
   stop and fix it; don't skip ahead.
4. Run the checker again. Every row should say `applied`.

Don't re-run `0019` (it resets every bulk item to "essential") or `0020` after `0021` (it brings back the old
PO-approvals view). **A fresh project instead?** Paste `supabase/full_setup.sql` once; it's the whole chain + seed.

> The app on `main` needs the DB at **`0025`**. "Upload new version" in Design calls `fn_add_design_version`.

### 1.2 Edge Functions
`admin-create-member` and `admin-delete-member` (`supabase/functions/`). Neither has changed since 30 Jul 2026.
Re-deploy only if they were never deployed or are older than that.

### 1.3 Storage
Buckets `designs` and `builds` must exist and be **public**. `0008` / `0011` create them.

### 1.4 (Recommended) daily status refresh
Supabase → Database → Cron: `select public.fn_refresh_all_statuses();` once a day.

### 1.5 Build the app
```bash
cd app && flutter pub get
flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=<anon-key>
```
Use the **same** URL and key on both devices. iOS: `cd ios && pod install` after any dependency change.

---

## 2. Devices and accounts

| Device | Use it for | Why |
|---|---|---|
| 💻 **SIM** (iOS Simulator) | Admin, PM, Procurement, Design, Service | Office roles; no camera needed |
| 📱 **PHONE** (real device) | Store, Workshop, Client | Barcode scan, bill and site photos, client ticket photo |

The Simulator has no camera. The scanner shows *Camera not available* with **Enter serial manually**, and
the photo picker's **gallery** option works. Android Emulator: same idea; its virtual camera can't scan a real label.

**Accounts.** Admin → Team → **Add member** sets the email and password directly (no email needed).
Use one password for all of them:

| Role | Email | |
|---|---|---|
| Admin | your admin login | No admin yet? See the SQL below the table |
| PM | `pm@azimuth.test` | |
| Procurement | `proc@azimuth.test` | |
| Store | `store@azimuth.test` | |
| Workshop | `workshop@azimuth.test` | |
| Design | `design@azimuth.test` | |
| Service | `service@azimuth.test` | |
| Client | created during onboarding (Phase 1) | Don't pre-create it |

First admin: Supabase → Authentication → **Add user** (auto-confirm), copy its UID, then:
```sql
insert into profiles (id, full_name, email, role, status)
values ('<uid>', 'Owner', '<email>', 'admin', 'active')
on conflict (id) do update set role = 'admin', status = 'active';
```

**Prep, one time:**
- Get `Astronaut.glb` onto **both** devices: Safari → `https://modelviewer.dev/shared-assets/models/Astronaut.glb`
  → it saves to Files → Downloads.
- SIM photos: drag 2–3 images onto the Simulator window; they land in Photos.
- Find any **physical barcode**, like a product box, or a QR code on your laptop screen. It plays the part serial.

**Rules while testing:**
1. There's no realtime, so **pull to refresh** after the other device acts. This is expected behaviour.
2. **After switching accounts on the same device, pull to refresh every tab you open**, or restart the app.
   A few lists (orders, vendors, items, templates, clients, PMs) can still show the previous login's data
   until refreshed. This is a known gap, not a new bug.
3. The demo seed build **AZ-118 has no PM and no client login**, so always onboard a fresh build.

---

## 3. The plan: 6 phases (≈ 2.5 h; data persists, so you can stop between phases)

| Phase | 💻 SIM | 📱 PHONE |
|---|---|---|
| 0 Setup | Admin | n/a |
| 1 Template + onboard + assign | Admin | PM |
| 2 Design loop | Design | Client |
| 3 PO chain | Procurement | PM → Admin |
| 4 Shop floor | PM | Store → Workshop |
| 5 Delivery + after-sales | PM → Service | Client |
| 6 Multi-user & robustness | Design / Admin | Design |

### Phase 0: Setup (💻 Admin)
- [ ] Add every member in §2. Right after adding `pm@`, open ＋ **Onboard project**: `pm@` should already be in
  the PM list, with no restart.
- [ ] Team → **Company details**: name, GSTIN, state. These print on every PO.

### Phase 1: Template, onboard, assign (💻 Admin · 📱 PM)
- [ ] 💻 ＋ Onboard project → Workflow template → **New**. Name it "QA Mini". Replace the 7 default stages with 3:

  | Stage | Days | BOM ("+ item") | Checklist ("+ check") |
  |---|---|---|---|
  | Design & Layout | 2 | — | Layout signed off |
  | Chassis & Structure | 3 | Steel sheet 4x8 × 4 | Frame welded · Frame inspected |
  | Electrical work | 3 | Inverter 2kW × 1 | Wiring done · Inverter tested |

  *Why this template:* the seed template has **no BOM**, so Materials and To Order would be empty. Also,
  "Testing/QC/Delivery" stages map to Service, which can't submit a stage (§4).
- [ ] 💻 Finish onboarding:
  - code, truck name, template **QA Mini**;
  - Client → **New**: leave *Set a password now* **ticked** (it's on by default), type a password (≥ 6 characters)
    and note the login. Unticking it sends an email invite instead, which needs SMTP;
  - PM `pm@`; delivery **today + 13 days**.
  - Expected: you're back on Admin Home with "*<code> onboarded and assigned to <PM>*".
- [ ] 💻 Projects → tap the build. It opens on the tabbed build screen (Overview · Pipeline · Materials · Record) with
  **Oversight · read-only**. **Materials** (read-only) shows two items:
  - **Steel sheet: "Order today"**;
  - **Inverter: "On time"**.

  That's the alert engine working (backward schedule → needed-by − lead − buffer). The build shows **At-risk** until the
  steel is ordered.
- [ ] 📱 Log in as PM → Projects → the build. Expected: **You manage this build**. Each stage's **View details** shows its checklist.
- [ ] 📱 ＋ **Assign work**: Design & Layout → `design@`, Chassis → `workshop@`, Electrical → `workshop@`, with dates.
  Try Chassis → `design@`: it should say "Tap again" (override). Don't confirm.
- [ ] 📱 Materials: tap the inverter and move its **needed-by** date. The order-by date moves with it. Quantity isn't part
  of the formula, so changing only the quantity won't move it.

### Phase 2: Design loop (💻 Design · 📱 Client)
- [ ] 💻 Log in as `design@`. Studio's *Assigned to me* shows **only this build**.
- [ ] 💻 ＋ New design: the build, type Layout, **Upload .glb** (Files → Downloads → Astronaut.glb) and a preview → **Submit**.
- [ ] 📱 Log in as the client → My Trucks → truck → **Approve layout design** → *Request changes* with "make it red".
- [ ] 💻 Approvals: the feedback is shown → open it → **Upload revised version** → submit (v2).
- [ ] 📱 Refresh → **Approve**. The truck card now shows the model (rotate / zoom; AR works on the phone only).

### Phase 3: PO chain (💻 Procurement · 📱 PM → Admin)
- [ ] 💻 Log in as `proc@` → Vendors → **Add vendor** with a **GSTIN** and **the same state** as your Company details.
  The seed vendors have neither, so the PO document would show one plain "GST" line and no supplier GSTIN.
- [ ] 💻 To Order. The **hero card is the most urgent item across all builds**. It should be your build's **Steel sheet**.
  If it's something else (e.g. the demo build AZ-118's espresso machine, which has no PM), clear that once in SQL:
  `update procurement_requirements set status = 'ordered' where project_id = '55555555-0000-0000-0000-000000000001';`
  Then pull to refresh.
- [ ] 💻 Hero → **Create Purchase Order**:
  - pick the new vendor; rate **with paise** (e.g. `12345.50`); GST 18%;
  - **Add item → Inverter 2kW × 1** as a second line.
  - Raise. Expected: *Awaiting PM*, and the steel drops off To Order.
- [ ] 📱 Log in as PM → Home → **PO approvals** → open the PO → **Sign & send for approval**. Tap it twice fast:
  you should get one signature.
- [ ] 📱 Switch to Admin → **PO approvals** → **Reject** with "rate too high".
- [ ] 💻 Orders → the PO shows the reason → **Fix & resubmit** (change the rate). It goes back to *Awaiting PM*.
- [ ] 📱 Switch to PM → sign. Switch to Admin → **Approve — place the order**.
- [ ] 💻 Open the PO → **View / print PO document**. Check:
  - both GSTINs;
  - **CGST + SGST** (same state). Edit the vendor's state to see IGST; if either state is blank you get one "GST" line;
  - the amount in words includes **paise**;
  - signatories are filled in.
- [ ] 💻 Receive tab: the PO sits under *Awaiting dispatch* only. There is no receive button until it's dispatched.
  **Mark dispatched** (pick an ETA) → it moves to *Ready to receive* → **Receive & verify**. Expected: steel stock goes up.
  The inverter does **not** go up yet; serialized parts count once Store logs their serial.

### Phase 4: Shop floor (💻 PM · 📱 Store → Workshop)
- [ ] 📱 Log in as `store@`. **Stock** shows the steel quantity higher.
- [ ] 📱 ＋ **Log component**:
  - item Inverter 2kW;
  - **scan your barcode** as the serial;
  - warranty end in 12 months;
  - **Attach bill** (camera);
  - leave *Assign to build* empty.
  - Expected: the part appears in Parts. Open it: **View bill** works.
- [ ] 📱 Switch to `workshop@` → Tasks → Chassis → **Start work** → tick the checklist (instant) → **Photo** (camera) →
  **Submit for approval**.
- [ ] 💻 Log in as PM → Home → **Approvals**. The card shows the photo and checklist → **Reject** → type "weld not clean"
  → **Send back**.
- [ ] 📱 Refresh the task: it shows *Sent back for rework* with the reason → **Start work** → **Submit for approval**.
  💻 **Approve**. Expected: Chassis done and **Electrical starts automatically**.
- [ ] 📱 Electrical → **Install part** → scan the **same barcode** → confirm → photo → checklist → submit. 💻 Approve.
  Build → **Record** tab: the inverter appears with serial, warranty and bill.
- [ ] 📱 Switch to `store@` → Parts → the inverter → **Recall check**. The truck is listed → **Notify all**; it fires once
  even if you double-tap. The PM and the client get a recall notice; check the client's bell in Phase 5.
- [ ] 💻 **Design-stage workaround** (§4): build → Overview → Design & Layout → **Reassign** to `workshop@` (tap twice to
  override). 📱 Start and submit it. 💻 Approve. Expected: progress **100%**.
- [ ] 💻 **Log a delay** (reason, 2 days, push on). The delivery date moves. Pipeline shows the delay after a refresh.
- [ ] 💻 **Add document** → Handover certificate → any file.

### Phase 5: Delivery + after-sales (💻 PM → Service · 📱 Client)
- [ ] 📱 Log in as the client → refresh. You should see a 100% ring, the journey with photos, and the handover document listed.
  The bell has the recall notice and the "stage complete" notices.
- [ ] 💻 PM → build → **Mark delivered**.
- [ ] 📱 Client ＋ **Raise request**: Electrical, description, **camera photo**. If you see "Request sent, but the photo did
  not upload", note it. Uploads use `upsert`, and Supabase can require an UPDATE storage policy that clients don't have.
- [ ] 💻 Log in as `service@` → Tickets. The request shows an SLA of ~24h. Wait 1–2 minutes and the countdown **moves**.
- [ ] 💻 Open it → photo visible → **Assigned to** `service@` → **Schedule visit** → **Resolve** (Replaced under warranty + note).
- [ ] 📱 Refresh Support: the resolution is shown → **Still not fixed** → reopen.
- [ ] 💻 The ticket is back on top at **high** priority → resolve → **Close ticket** (double-tap closes once). *Fixed today* counts it.
- [ ] 💻 ＋ **New ticket** for this truck (the delivered-truck picker loads). 📱 The client sees it in Support.

### Phase 6: Multi-user & robustness
- [ ] **Version race.** Log in as `design@` on **both** devices (the same account on two devices is fine). Open the same design →
  **Upload new version** on both → submit at the same moment. Expected: two **different** version numbers and
  nothing lost. Confirm with the SQL in §5.
- [ ] 💻 Any role: the bell badge equals the **unread** count. **Mark all read** clears it.
- [ ] 📱 Airplane mode → tap any action. You should see a friendly message, not raw SQL.
- [ ] 💻 Simulator Settings → Accessibility → Display & Text Size → Larger Text at max: the Design *Assigned to me*
  card doesn't overflow.

---

## 4. Known gaps (already known; log only if the behaviour differs)

These are tracked in `PROJECT_LOG.md` §3.
- **Design and Service can't start or submit their own stage.** Only Workshop has that screen. Workaround: the PM
  reassigns the stage to a workshop member with an override (Phase 4), or delivers with *Deliver anyway*.
- **Templates** can only be created inside Onboard project, and can't be edited later.
- **Store's inline "New item"** is refused (RLS). Create items from Procurement's New PO instead.
- **Client documents don't open.** The tap only shows "Opening document…".
- **Notifications aren't tappable.** No realtime.
- **The "They've been notified" banner** on a submitted design is untrue; the client is not notified.
- **Two devices pressing Receive on the same PO at the same instant** could double the stock (no row lock).
  It's very hard to hit by hand.

---

## 5. Backend truth (optional checks)

```sql
-- Phase 6: must be 0 rows
select artifact_id, version_no, count(*) from design_versions group by 1, 2 having count(*) > 1;

-- Phase 4: the scanned part is linked to a stage
select serial_number, status, installed_stage_id from component_instances
where installed_stage_id is not null;
```

`sh supabase/tests/run.sh` (Docker only) applies the whole chain twice: the migrations, then `full_setup.sql`. It runs
**149 assertions** as real non-superuser users, so RLS and the guard triggers are genuinely exercised.

---

## 6. Bug log

| Phase.step | Device · role | What I did | What happened | Screenshot |
|---|---|---|---|---|
| | | | | |

To reset, onboard a new build; each one is a clean slate. Or delete the project row (stages and requirements cascade).
