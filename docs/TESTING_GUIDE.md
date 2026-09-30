# BuildTrack — Testing & Go-Live Guide

A practical way to **deploy** the latest changes and to **test the whole app end to end
with only 2 devices**, so you can see for yourself that each role and each hand-off works.

Read top to bottom the first time. After that, §3 (the golden flow) is the one you'll reuse.

---

## 1. Deploy checklist — do this before testing

> You said you'll do these in one go, one by one. Here's the exact order.

### 1.1 Merge the code
- Merge **PR #46** (`fix/tier1-ui-multiuser-hardening`) into `main`. It carries Tier 1 + 2
  fixes and the Tier 3 UX work (role-mode banner, one canonical build screen, tabbed
  Overview/Pipeline/Materials/Record). CI (analyze · test · Android build · Postgres) is
  green on it.

### 1.2 Run the Supabase migrations (SQL editor), IN ORDER
The live project was last known to have **0001–0011** applied. Run everything after that
that isn't applied yet, **in order**:

```
0012_template_checklists.sql      0019_essential_items.sql
0013_stock_movement.sql           0020_po_approvals.sql
0014_client_ticket_visibility.sql 0021_ops_command_center.sql
0015_rebaseline_on_delivery_change.sql  0022_project_delays.sql
0016_receive_requires_dispatch.sql      0023_truck_record.sql
0017_stock_requests.sql           0024_status_delivery_date.sql
0018_intake_serialized.sql        0025_design_version_atomic.sql   ← new in this work
```
- **Not sure what's already applied?** Check with, e.g., `select * from pg_tables where tablename='po_approval_events';` (exists ⇒ 0020 is in). When unsure, run them in order and skip any that error with "already exists".
- **Fresh project instead?** Paste `supabase/full_setup.sql` once (it's the whole chain + seed, regenerated — includes 0025).

### 1.3 Re-deploy the Edge Functions
- `admin-create-member` (it returns `client_account_id` now — needed by inline client
  creation) and `admin-delete-member`. Both live in `supabase/functions/`.

### 1.4 Confirm storage buckets exist (public read)
- `designs` (from 0008) and `builds` (from 0011). If missing, the migrations create them;
  otherwise create as public.

### 1.5 (Recommended) schedule the daily status refresh
- A daily cron: `select public.fn_refresh_all_statuses();` — otherwise at-risk/delayed only
  recompute when a stage is touched. (The dashboards also call it on load, so this is a
  belt-and-braces.)

### 1.6 App build
```
cd app && flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```
Native permissions (camera etc.) are already committed — see `docs/NATIVE_SETUP.md`.

---

## 2. Set up a test team (one-time)

The app has **8 roles**. Accounts are **not** in the SQL seed (auth users are created
through the app / dashboard). Create them once:

1. Sign in as an **admin**. (No admin yet? In Supabase → Authentication → add a user, then
   in the SQL editor set its profile role: `update profiles set role='admin' where id='<uid>';`)
2. Admin → **Team → ＋ Add member**. The "set a password now" path needs **no email/SMTP** —
   the member signs in with exactly the email + password you type. Create one per role:

| Role | Suggested email | Notes |
|---|---|---|
| Project Manager | `pm@azimuth.test` | needed for every build |
| Procurement | `proc@azimuth.test` | |
| Workshop | `workshop@azimuth.test` | the "doer" |
| Store | `store@azimuth.test` | |
| Design | `design@azimuth.test` | |
| Service | `service@azimuth.test` | after-sales |
| Client | *created during onboarding* | see §3, step 1 — don't pre-create |

Use the same password for all test accounts to make the login/logout shuffle painless.

> The demo seed build **AZ-118** has **no PM and no client login**, so it can't flow. For a
> real test, **onboard a fresh build** (§3, step 1) — that creates the client login and
> assigns a PM in one go.

---

## 3. Testing with only 2 devices — the golden flow

You can't have 8 roles logged in at once. You don't need to: the build chain is **naturally
sequential** — Admin acts, then the PM, then the workshop, and so on. So:

- **Device A = "staff shuttle."** Log in / out as each staff role *as the step needs it*.
  You rarely jump backwards.
- **Device B = "the client."** Stay logged in as the client the whole time, and
  **pull-to-refresh** after each staff action to watch the build move. (There's no realtime
  yet, so refresh is how the client sees updates — that's expected, not a bug.)

Walk these steps in order. Each step says **who · where · do · expect**. This exercises
every role and every hand-off.

| # | Device / role | Do | You should see |
|---|---|---|---|
| 1 | A · **Admin** | Home → ＋ Onboard project. Pick the template, set a delivery date, **＋ New** client (creates the client login — note the email/password), assign **PM** (`pm@…`). | New build appears in **Projects**. Opening it shows the tabbed **build screen** (Overview / Pipeline / Materials / Record) with an **"Oversight · read-only"** banner. |
| 2 | A · **Admin** | Open the build → **Materials** tab. | Auto-generated requirements with **order-by** dates (Hero #1). Read-only for admin. |
| 3 | A → **PM** (`pm@…`) | Log out, log in as PM. My Builds → open the build. | The **same tabbed build screen**, now with a **"You manage this build"** banner. **Pipeline** tab lists the stages. |
| 4 | A · **PM** | ＋ **Assign work** (or a stage → Assign). Assign the **Design** stage to `design@…`, build stages to `workshop@…`, with dates. | Each stage shows its assignee; the discipline is recommended (override needed to mismatch). |
| 5 | A → **Design** | Log in as `design@…`. | Only **this build** shows (design is scoped to assigned builds). Upload a `.glb` + preview → submit for approval. |
| 6 | **B · Client** | Log in as the client from step 1. Truck → **Docs/Design**. Pull to refresh. | The design shows as **awaiting your approval**. Approve it (or request changes). |
| 7 | B · Client | (after approving) | The truck's **3D showcase** now shows the approved model. |
| 8 | A → **Procurement** | Log in as `proc@…`. **To Order** → create a PO from an alert (rate + GST). | PO enters the **approval chain** (pending PM). |
| 9 | A → **PM** | Log in as PM → **PO Approvals** (on home) → sign. Then Admin → **PO Approvals** → approve. | PO becomes approved; procurement can now **dispatch → receive**. |
| 10 | A → **Procurement** | Mark dispatched (set ETA) → **Receive & verify**. | Stock goes up; the requirement drops off To-Order. |
| 11 | A → **Store** (`store@…`) | **Log component**: serial + warranty + a bill photo, assign to the build. | It appears in inventory / components; the bill opens from the component. |
| 12 | A → **Workshop** (`workshop@…`) | My Tasks → open the in-progress stage → **Start work** → **Scan to install** the part (or manual serial) → add a **photo** → tick the checklist → **Submit for approval**. | The part links to the truck/stage; the task shows "awaiting approval". |
| 13 | A → **PM** | **Approvals** → you see the **photos + checklist + installed parts** → **Approve**. | Stage → done, **next stage auto-starts**, client notified. Reject instead → the task shows the **rework reason**. |
| 14 | B · Client | Pull to refresh on the truck. | Progress % moved; the **build journey** shows the completed stage + its photos. |
| 15 | A · **PM** | (once stages are done) Build → **Mark delivered**. | Build → delivered; it enters after-sales. |
| 16 | B · Client | Raise a **support request** (with a photo). | It appears under **My requests** with a status. |
| 17 | A → **Service** (`service@…`) | **Tickets** (SLA-sorted) → open the client's ticket → triage to a technician → **schedule a visit** → **resolve** (with a note). | SLA countdown is live; resolving writes a note the **client reads**. |
| 18 | B · Client | Pull to refresh → **My requests**. | The **resolution** shows; a **"still not fixed"** reopen is available (jumps the queue). |

If all 18 pass, the whole product — every role and every hand-off — works.

### Faster: smoke-test one role at a time
Just want to eyeball a single role's screens? Log in as that role on Device A and open its
tabs. Because a fresh build (§3 step 1) seeds real data, every role has something to show
without driving the whole chain each time.

---

## 4. Verifying without the UI (backend truth)

Two ways to confirm a write really happened, independent of the app:

- **Query Supabase** (SQL editor / Table editor): e.g. after step 12,
  `select serial_number, installed_stage_id from component_instances where installed_stage_id is not null;`
- **Run the backend test suite** (needs only Docker): `sh supabase/tests/run.sh` — applies the
  whole migration chain, proves the newest migration is idempotent, and runs the workflow +
  service assertions **as real non-superuser users** (so RLS + guard triggers are genuinely
  tested). This is the fastest way to know the *rules* are intact.

---

## 5. Notes & gotchas

- **No realtime yet.** A change one user makes is visible to another only after
  pull-to-refresh. This is a known Phase-3 item — not a bug. (It's why Device B refreshes.)
- **One session per device.** Supabase auth is one logged-in user per device, so staff-role
  testing is a login/logout shuffle on Device A. That matches the sequential chain.
- **Reset a test build:** delete the project row in Supabase (stages/requirements cascade),
  or just onboard a new one — each fresh onboard is a clean slate.
- **Something looks off?** Note the role + screen + step number from §3 and tell me — I can
  reproduce it against the code and fix it.
