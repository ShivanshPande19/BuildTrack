## What this is

A line-by-line read of the project against its own documentation, then the fixes.

The docs held up — nine `PROJECT_LOG.md` §3 items were spot-checked and all nine were exactly as
described, which is rare. So most of what follows was **not** previously known. Every RPC the app calls
was diffed against the latest SQL signature (all 30 matched), every table, view and column the app reads
or writes was diffed against the schema (all present), and `full_setup.sql` was regenerated and confirmed
byte-identical.

**The main reason to open this PR is the backend job.** `supabase/tests/run.sh` was not run locally — no
Docker on the machine this was written on — so migration `0026` and its 42 new assertions
(`supabase/tests/80_hardening_tests.sql`) are unproven until CI runs them.

---

## Backend — migration `0026` (idempotent, 15 sections)

| | Defect | Fix |
|---|---|---|
| 1 | **Hero #1 went stale on a re-plan.** `needed_by_date` was written once, at onboarding, and `order_by_date` is derived *from* it — so after "Log delay + push the delivery date" every material still alerted against the old schedule, and `fn_recompute_status` held the build `at_risk` off a dead date. | A rebaseline moves each still-pending requirement onto the new plan. |
| 2 | **The build's status went stale too.** A `planned_*` change does not fire `t_stage_progress` (it is `after update of status`), so a build kept reading `delayed` after its date was pushed out. | `fn_recompute_schedule` refreshes the status. |
| 3 | **`fn_resubmit_po` lost data.** Notes / ship-to / payment terms were wiped by a null argument, and a vendor or delivery-date change was discarded entirely unless the lines were resent — the header UPDATE sat inside `if p_lines is not null`. | Header always updates; optional fields keep their value when the argument is null. |
| 4 | **`fn_receive_po` had no row lock** — two taps doubled the stock and wrote two GRNs. | `select … for update`. |
| 5 | **`fn_reopen_ticket` had no caller check at all** — any signed-in user could force any ticket to high priority. | The ticket's client, service, or an admin. |
| 6 | **`trg_guard_stages` did not guard `status` / `actual_*`** — an assignee could approve themselves with a direct UPDATE, skipping submit and the PM entirely. | The three sanctioned transitions mark the transaction (`fn_stage_rpc_begin`); anything else is refused. |
| 7 | **A disabled account could still read everything.** `profiles.status` was shown but enforced nowhere. | `my_role()` returns NULL for one, so every role test built on it denies. |
| 8 | **`is_admin()` was three-valued.** `if not public.is_admin()` is *false* when `is_admin()` is NULL, so every admin-guarded RPC skipped its own guard for any caller without a profile — and those functions are `SECURITY DEFINER` and granted to PUBLIC, so an anonymous `/rpc/fn_assign_pm` could reassign a build. | `coalesce`. |
| 9 | **A PM hand-over stranded the work in flight** — `approver_id` and `purchase_orders.pm_id` are snapshots, so the new PM's queue was empty while the team waited and nobody could sign the PO. | Pending approvals and unsigned POs move with the build. |
| 10 | **A PO closed only the requirement it was raised from**, so a PO from the blank FAB left its materials alerting forever. | It closes every pending requirement its lines cover. |
| 11 | `fn_notify*` / `fn_audit` were callable by anyone over RPC (spoofed notifications). | Revoked from `authenticated`. |
| 12 | Store could not create a catalogue item, so its own "new item" sheets failed on RLS. | `item_catalog` writes include `store`. |
| 13 | **Invited members stayed `invited` forever** — set-password's own update was silently dropped by RLS. | A member may update their own row; a trigger holds role / email / team / status on the admin's side. This is also what makes Settings → Account details able to save. |
| 14 | **Submitting a design told the client nothing**, while the screen said "they've been notified". | `fn_create_design` (new, atomic) and `fn_add_design_version` notify the client and the PM. |
| 15 | Offboarding failed on the seven FKs added after `0009`'s sweep; a fresh database had no essential items. | Sweep re-run; essentials bootstrapped only when nothing is essential yet. |

## App

- **Photos could take the screen down.** `Image.memory` had no `errorBuilder` at either site and
  `image_picker` does not always transcode a HEIC, so an undecodable frame threw *during layout*. Picked
  bytes are decoded once before any widget sees them, the content type is sniffed from the file's magic
  number rather than its name (JPEG bytes were being stored as `image/heic`, which then rendered
  nowhere), a second tap while the picker is open is ignored, and the three `FilePicker` call sites are
  wrapped — an unhandled throw in an async callback was taking the screen with it.
- **Settings is real.** Account details, Company details (moved out of the Team screen, read-only for
  non-admins), Roles & permissions, Notifications. Three "coming soon" snackbars gone.
- **Admin's "Needs attention" reads builds, not just materials.** It said *All caught up* while a build
  sat in `delayed`. Now: delayed, no PM, at risk, then overdue order-by — worst first, each row opening
  the build.
- **Design and Service can work their own stages.** The RPCs always allowed it; only Workshop had a
  screen. This is what kept a build's progress from ever reaching 100% and made handover need
  *Deliver anyway*.
- **Notifications open what they are about**, resolved per role. Every `fn_notify` already recorded an
  `entity_type` and `entity_id`; the feed just never selected them.
- **Documents open** — PDF to the OS preview sheet (print / share / save), image to a viewer. Staff can
  open what they upload, too. No new dependency.
- **Every cached provider is auth-aware** via `currentUserIdProvider`, which emits only on a real user
  change. The unwatched ones served the previous user's rows after switching accounts on one device —
  which a multi-role demo on a single phone hits immediately — and the ones watching `authStateProvider`
  directly refetched on every token refresh.
- Smaller: a non-standard GST rate is no longer silently rewritten to 18%; CGST + SGST add up to the tax,
  and the document carries a rate-wise breakup and a per-line GST %; one warranty threshold instead of
  two, with calendar arithmetic so "ends today" is not "expired"; an undated requirement no longer reads
  "Order today"; a serialized item with none on hand appears in Store → Stock; `findBySerial` escapes the
  scan; intake *reserves* a part for a build instead of marking it installed by nobody; submitting a
  stage with checks still open asks first; one `invalidateBuild()` so an action refreshes everything it
  touches.

## iOS / CI

Flutter 3.47 migrates the iOS project to Swift Package Manager and raises the deployment target to
**15.0**. Committed rather than reverted, and CI's pin moved `3.44.8` → `3.47.2` to match — otherwise
`pod install` and the `pubspec.lock` check disagree with every developer machine. **iOS 13 and 14 are no
longer supported;** `NATIVE_SETUP.md`, both READMEs and the steering docs say so.

## Verified

- `flutter analyze` — 0 errors, 0 warnings
- `flutter test` — **89/89** (was 62): the needs-attention feed, order-by urgency, warranty state,
  notification targets, and a new `test/po_document_test.dart` covering the GST rate-wise split, the
  paise rounding and `rupeesInWords`
- `flutter build ios --simulator` succeeds and the app boots on an iPhone 15 Pro simulator

## Not verified

`supabase/tests/run.sh` — no Docker on the machine this ran on. **The Postgres job in this PR is the
first real run of `0026`.**

## Deploying this

The app requires the database to be at `0026` — "New design" fails outright without it. Run
`supabase/check_migrations.sql` (read-only) to see what the live database has.

Three behaviour changes worth saying out loud before deploying:

1. A **disabled account can no longer read anything**.
2. A stage moves **only** through Start / Submit / Approve — never a direct write.
3. `fn_assign_pm`, `fn_onboard_project`, `fn_final_approve_po` and `fn_set_po_priority` now **refuse a
   caller with no JWT**, so running them by hand in the SQL editor fails. Do them from the app, as an
   admin. (That is the other half of the `is_admin()` fix.)

## Still open

`PROJECT_LOG.md` §3 has the full numbered list. The biggest remaining one for a production deploy: both
storage buckets are **public-read**, so contracts and invoices under `builds/docs/` are readable by
anyone with the URL. The app now downloads documents through the Storage client rather than a bare URL,
so making the bucket private is a one-function change (`downloadFromUrl`) rather than a sweep of call
sites.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
