# BuildTrack — Worklog

A running, session-by-session record of what changed and why. Newest first.
Unlike `PROJECT_LOG.md` (a snapshot of the product's state), this is the trail:
what we did, what it fixed, and what is still open, so anyone can pick up where
we left off.

Legend: ✅ done · 🔄 in progress · ⏭️ next · ⚠️ needs the dev machine
(no Flutter SDK in the agent sandbox, so `flutter analyze`/`test`/`run` are
verified through CI, not locally).

---

## 15 Oct 2026: The Workshop role aligned, and a checklist that is evidence ✅ (migration `0029`)

Branch `feat/workshop-checklist-evidence`. Same method as the Design pass: read one role end to end
— its screens, the RPCs behind them, and the RLS under those — rather than looking for bugs.

**The question that started it.** *"Does this checklist just tick with no proof? And the parts that
get installed — do they show up anywhere?"*

The second half had a good answer. `v_truck_components` (`0023`) is a proper digital twin: every
part's item and model, serial, vendor, the stage it went into, **who fitted it**, install date,
warranty state and bill. The problem was only that **Workshop could not reach it** — `TruckRecordScreen`
lives inside `BuildScreen`, which Admin and the PM open and Workshop has no tab for. The person
writing the record could not read it. One link on the stage screen.

The first half had no good answer. The table was `(id, stage_id, label, done)` and the write was
`update checklist_items set done = …`. Nothing recorded who or when, there was no column to hang
proof on, `fn_audit` was never called, and the policy allowed the **PM** to tick too — so a PM could
tick the checks and then approve their own evidence. A check on an approved stage could still be
un-ticked. Meanwhile `fn_install_component` on the same stage *was* audited.

Asked which of three options to take — record-only, record + freeze, or per-check proof — the answer
was **both of the last two**.

### `0029`

- `checklist_items` gains `done_by`, `done_at`, `photo_required`, `proof_attachment_id`
  (`ON DELETE SET NULL`: deleting a photo must not delete the check, but it must stop the check
  claiming a photo that is gone). Rows ticked before this keep nulls — the old write stored nothing,
  so there is no name to recover, and the row reads *"ticked before this was recorded"* rather than
  inventing an actor.
- **`fn_tick_check(p_item, p_done, p_proof)`** is the only way `done` moves. It checks the caller,
  refuses an approved stage, enforces the photo rule, verifies the photo is on *this* stage (without
  that, any attachment id in the system would satisfy it), writes the record, and audits. A direct
  write to `done`, `done_by`, `done_at` or the proof is refused by `trg_guard_checklist` — the
  sanctioned-transaction pattern `0026` used for `trg_guard_stages`, so the RPC is not merely the
  polite path.
- **The freeze.** An approved stage's checklist is closed to everyone but an admin — including to
  the PM's rename/add/remove, which `0028` had left open to them.
- **`photo_required` travels.** `template_stage_checks` carries it and `fn_onboard_project` copies it
  onto every build; the PM can also set it per stage, from a camera toggle beside the label.
- `fn_install_component` now refuses an **approved** stage (`fn_start_stage` and `fn_submit_stage`
  have since `0026`; this did not, and the install screen offered approved stages) and refuses a
  part **reserved for another build** instead of overwriting the earmark silently.
- `delay_logs` write narrowed from `{admin,pm,workshop}` by role to the stage's **own assignee**,
  their PM, and an admin.

`tests/83_checklist_evidence_tests.sql`: 31 assertions. Two existing tests changed deliberately —
`80` and `82` both ticked a check with a direct `update`, which is now exactly what is refused.

### The app, nine more defects (§3 #50–#62)

The one that would have shown in a demo: **every stage due today wore a red "Overdue" pill.**
`assigned_due` is a `date`, so it parses to midnight, and `isBefore(DateTime.now())` is true from
00:01. This was the **third** copy of the trap — `AssignedBuild.isOverdue` had it, and
`ComponentRow.warrantyActive` was a **fourth**, so a part whose warranty ended today read *Expired*
in Workshop's Parts tab, Store's Parts list and the component record. `StageTick` and
`ScheduleEntry` were already correct, which is worse than all four being wrong: the fitter and their
PM could look at the same stage and disagree. There is now a test asserting the definitions agree.

The rest: a **delivered** truck still offered *Start work* (`fn_mark_delivered(force)` leaves stages
open on purpose, and `myTasks()` never read the build's status); **"My Week" had no dates in it** and
filled with finished stages, with cards that did nothing when tapped; the task list was ordered by
`ord`, a stage's position *inside its own build*, so two trucks interleaved and an overdue stage
could sort last; all three tabs were eager and unbounded; **reserved parts were drawn as fitted**;
the stage's **BOM** was nowhere and the install list was every serialised part in the building, flat
and alphabetical, with the earmark not even shown; the stage's **photos and delays were fetched on
every open and never rendered** — the client saw the photos, the fitter who took them did not; the
fitter had **no way to report a hold-up** though the schema has allowed it since `0009`; and the
in-app Roles screen told the user Workshop *cannot* see PO rates, which is false
(`purchase_orders_read` is `is_staff()`).

Also fixed on the way: a retry button I had just written pointed at the wrong provider (the screen
watches a build-keyed family now), and Store logging a part did not invalidate the fitter's view of
stock.

### Then the screen was used, not read (15 Oct, migration `0030`)

Three complaints, all fair:

> *"this truck full record ka button bilkul neeche and photos bhi aari h ajeeb jagah pe"*

The screen had no order. The primary action was in the **middle** — after the checklist and the
materials, before the photos, the delays, the fitted parts and the truck record — so *Submit* was
something you scrolled past, and the record link was the last thing on a long scroll. Actions lived
in one block away from what they affected. Now: **what this stage is → what you have recorded → the
whole truck**, each section carrying its own action in its heading, and the primary action in a
**pinned bar** that still explains itself when it is unavailable.

> *"ye photos ka kya scene h delete nhi kr skte h kya"*

No — a photo could be added and never taken back, so the wrong shot stayed on the client's build
timeline forever. Each thumbnail has a remove button now, behind a confirm that names the check it
proves if it proves one. `0030` puts the rule behind it: `attachments` had carried
`for all using (is_staff())` since 0002, so *any* staff member could delete *any* photo on *any*
truck — including after the PM approved the stage and signed off on those photos. A check whose
proof a passer-by can delete is not proof, which made 0029 half a rule. Now: whoever took it, the
build's PM, or an admin; and once approved, only an admin.

> *"ye checklist tick krne pe kehta h ticked before it was recorded"*

My bug, from the previous commit. The provenance line read the **optimistic** flag rather than the
server's `done`. The tick flips instantly so a slow connection does not feel dead, but the name and
date only exist once the write lands — so the moment you ticked anything, the row claimed it had
been ticked before the app started recording. Alarming nonsense for a check you just ticked. It
reads the server now and says *Saving…* in between; the genuinely-old case was reworded to
*"Ticked earlier — before the app recorded who"*.

Verified on the device: the new order, delete (confirm → *Photo removed* → empty state), and a tick
showing *Vikas · 15 Oct*.

### …and the photo found its home (same day)

> *"checklist ko tick krne ke time pe … usme photo upload for the task to mark it complete hona
> chahiye ig, and add photos extra photos add krne ke liye use hojayenge, and even jo checklist m
> photo upload hogi usko bhi photos m show krdenge"*

Half of that already worked and was worth saying so: a check's photo has always been an ordinary
stage attachment, so it already appeared in the Photos list, captioned with the check it came from,
with a **Proof** link on the row. What did not work was the *framing* — a photo was only asked for
on the checks a PM had flagged, so ticking an ordinary check did nothing, and the camera also lived
in a separate *Add photo* action. Three ways to end up with a picture, none of them obviously the
main one.

The disagreement was only about **forcing** it. Some checks have nothing to photograph — *client
sign-off received*, *keys handed over* — and demanding one anyway is how a fitter learns to
photograph the floor to get past the sheet; once the list fills with pictures of the floor, the
checks where a photo genuinely mattered lose their reader too. So: **offered on every tick, forced
only where the PM said so.** Ticking any check opens the sheet — *Take a photo now*, or one already
on the stage, or **Tick it without a photo** — and that last option is absent on a `photo_required`
check, where the server would refuse the tick regardless.

Verified end to end on the device: tick → sheet → gallery → the check reads *Vikas · 15 Oct ·
Proof*, and the photo is in **Photos · 1** captioned *"Base frame weld…"*.

### Then it was actually run (15 Oct, same branch)

`0028` and `0029` were applied to the live project and the app was driven on an iPhone 15 Pro
simulator. Five more defects, none of which any test or code read had surfaced — the first four
because nothing had ever *picked a photo*, and the last because it was introduced by this pass:

- **Choosing a photo from the gallery froze the app** (§3 #63). `AlertDialog` measures its body
  through an `IntrinsicWidth`, which asserts `input.isFinite`; the preview was
  `Image.memory(…, width: double.infinity)`, an infinite intrinsic width. The assertion fired every
  frame, so the dialog's route pushed and dimmed the screen but the dialog never laid out. Dark,
  unresponsive, nothing on it. The log said it plainly once the app was run with `flutter run`:
  `proxy_box.dart:665 'input.isFinite': is not true`, error-causing widget `AlertDialog`.
- **Transient network errors were unhandled exceptions** (§3 #64) — which in debug *pauses the
  isolate*, i.e. actually freezes the app, and Supabase's token refresh throws one on every bad
  connection.
- **Uploads had no timeout** (§3 #65), behind a one-minute "Uploading photo…" snackbar.
- **The camera-unavailable fallback overflowed by 188px** (§3 #66) — the manual-serial escape hatch
  was off-screen on any device without a working camera.
- **`PGRST201` on every stage screen** (§3 #67), introduced here: `profiles(full_name)` added to the
  stages select is ambiguous, because `stages` points at `profiles` twice. The same trap documented
  two passes ago for PM Approvals, walked into while optimising a round trip away.

All five fixed and **verified on the device**: Photo → gallery → pick → preview dialog → Upload →
*Photo uploaded* → the new **Photos · 1** section renders the thumbnail.

**Verified:** `flutter analyze` clean, `flutter test` **169/169** (up from 137, 32 new).
⚠️ **`0029` was unverified locally when first written** — this machine has no Docker and no local Postgres, so
`supabase/tests/run.sh` could not run. CI's Postgres job is the gate.

⏭️ **Next:** apply `0028` **and** `0029` to the live project before demoing. Without `0029` the
**whole stage screen fails to load**, not just the tick: `stageBundle` selects `done_at` /
`photo_required` and embeds `done_by` and the proof attachment, so PostgREST refuses the query.
The app and these migrations ship together. Still open: template management (§3 #2), the PO read scope (§3 #16), and
both storage buckets are public-read.

---

## 14 Oct 2026: Demo walk + the Design role aligned ✅ (migrations `0027`–`0028`)

Branch `feat/design-stage-alignment`. Two passes on one branch.

**Pass 1 — the live walk.** The owner drove the running app against the real Supabase project and reported
what looked wrong, screen by screen. That found two things a code read had not:

- A **purchase order on a build whose PM had been offboarded** skipped the PM's signature and landed in the
  owner's queue looking like a stock order. The rule `pm_id is not null ? pending_pm : pending_final` is
  right for a general PO and wrong for a project PO; nothing distinguished them. `0027` refuses both paths
  (`fn_create_po`, `fn_resubmit_po`) and says which admin action fixes it. 11 assertions in
  `tests/81_po_routing_tests.sql`, including the control case — without it the refusal would pass for the
  wrong reason.
- **"Running low" fired on an LED panel** bought for one truck. `low_stock_threshold` defaults to 0 and a
  per-build part is supposed to sit at zero between builds, so the badge was permanently on for everything
  that should never be reordered, and the consumables that *should* be were buried. `item_catalog.is_essential`
  now draws that line, in the model (`StockRow.low`), the repository and the UI.

**Pass 2 — the Design role, studied end to end.** It started as a question about one checklist item — *"it
says 'Layout approved by client', but what if I tick it and the client never approved?"* — and the answer
was that nothing stopped you. Reading further, the role was running as **two disconnected systems**:
`design_artifacts` had no `stage_id`, so a *Design & Layout* stage and the designs for that build were
unrelated rows. A build could reach 100% and be delivered with nothing the client had approved.

`0028`:

- `design_artifacts.stage_id`, and `fn_create_design(p_stage => …)` to set it — refusing a stage on a
  different build.
- `fn_submit_stage` refuses a **design-discipline** stage until an approved design exists on that build.
  Scoped deliberately: it would be absurd for a welder to wait on a layout approval to report their weld,
  and `tests/82_design_stage_tests.sql` pins that down too.
- `fn_client_decide_design` notifies whoever holds the stage — *"your stage can be submitted"* — under its
  own types `stage_ready` / `stage_waiting`, so it is a different row from the design-approved notification
  and each opens the right thing.
- `trg_guard_checklist`: the PM and an admin can rename, add and remove checklist items; the assignee can
  only tick. A checklist that cannot be corrected outlives its mistake on every build from that template;
  a checklist the assignee can rewrite is worthless as evidence.
- `fn_infer_discipline` widened to *mockup*, *concept*, *render*, *client sign-off*, *artwork* — without
  swallowing a bare *Final approval*, which is the PM's, not the designer's.

**Then the screen that reads it.** Design's Studio had two sections asking "what needs you" and giving
different answers: *My design stages* showed an overdue stage while *Needs your attention* showed a green
**All caught up**, because that panel read `design_artifacts` alone and the designer had no designs at all.
The most blocking fact on their plate was the one thing the screen could not see. Both are now one ranked
list (`designTodos`), worst first, reading the stage **and** its designs — which is the only honest reading
once `0028` makes them one piece of work — with the next action named on every row and the screen that
performs it one tap away. Designs sitting with the client are counted *beside* the list, not in it: a
to-do list that includes things you cannot act on stops being a to-do list.

**Multi-project pass.** The owner asked the same question of screen after screen — *"this looks good for
one build; is it still good when one person holds eight?"* Mostly it was not: summary sections were
`Column(children: …)` over everything, which is both an unbounded screen and an eager build. Every one is
now a `CappedSection` — the worst four, sorted so the cap keeps the right ones, with *See all N* behind a
sheet — and the full lists (Store Stock, the Designs library) are `SliverList.builder` with search and
counted filter chips. The PM's Schedule, which was a flat date list, became two lenses over the same
stages (by date / by build) with a pipeline strip and a member sheet.

**What CI caught that local work could not.** Twice:

1. The new stage notification reused `type = 'approved'`, giving the designer two rows where
   `10_workflow_tests.sql` asserts exactly one. The test was right and stayed; the notification got its own
   type.
2. `create or replace function fn_create_design` with an **added parameter** creates an overload rather than
   a replacement, so every call became `is not unique`. The old signature is dropped first now — the same
   precaution `0015` already takes for `fn_recompute_schedule` — and every migration was swept for the
   pattern (those two were the only signature changes in the chain).

**Verified:** 223/223 backend assertions across 10 suites, `flutter analyze` clean, `flutter test` 137/137.

⏭️ **Next:** apply `0028` to the live project before demoing this branch — the app reads
`design_artifacts.stage_id` and calls `fn_create_design(p_stage => …)`. Still open: the template
management screen (§3 #2), and both storage buckets are public-read, so a contract URL is readable by
anyone who has it (`downloadFromUrl` makes signed URLs a one-function change).

---

## 13 Oct 2026: Pre-demo audit + fix pass ✅ (migration `0026`)

The ask: read the whole project as a senior developer, check it actually does what the docs say, then fix
what it doesn't — the app was going out as a demo, photos were crashing it, Settings answered every tap with
"coming soon", and Admin's home said *All caught up* while a build sat in `delayed`.

**How the audit was run.** The claims in `README.md` / `PROJECT_LOG.md` were checked against the code, not
taken on trust: every RPC the app calls was diffed against the latest SQL signature (all 30 matched), every
table, view and column the app reads or writes was diffed against the schema (all present), and
`full_setup.sql` was regenerated and confirmed byte-identical. `docs/PROJECT_LOG.md` §3 turned out to be
accurate — nine of its items were spot-checked and all nine were exactly as described, which is rare.
The defects below are the ones it did **not** know about.

**Backend — migration `0026` (15 sections, idempotent).**
- **Hero #1 went stale on a re-plan.** `procurement_requirements.needed_by_date` was written once, at
  onboarding, and `order_by_date` is derived *from* it — so after "Log delay + push the delivery date",
  every material still alerted against the old schedule and `fn_recompute_status` kept the build `at_risk`
  off a dead date. A rebaseline now moves each still-pending requirement onto the new plan.
  `fn_recompute_schedule` also refreshes the build's status, because a `planned_*` change does not fire
  `t_stage_progress` (it is `after update of status`) and a build kept reading `delayed` after its date
  was pushed out.
- **`fn_resubmit_po` lost data.** Notes, ship-to and payment terms were wiped by a null argument, and a
  vendor or delivery-date change was discarded entirely unless the lines were resent — the header UPDATE
  sat inside `if p_lines is not null`.
- **`fn_receive_po` had no row lock**, so two taps doubled the stock and wrote two GRNs.
- **`fn_reopen_ticket` had no caller check at all** — any signed-in user could force any ticket to high
  priority.
- **`trg_guard_stages` did not guard `status` / `actual_*`**, so an assignee could approve themselves with
  a direct UPDATE. The three sanctioned transitions mark the transaction (`fn_stage_rpc_begin`) and the
  guard stands aside for them; everything else is refused.
- **A disabled account could still read everything.** `my_role()` now returns NULL for one. `is_admin()`
  was made strictly boolean in the same change — `if not public.is_admin()` is *false* when `is_admin()`
  is NULL, so every RPC guard would have waved a disabled admin straight through.
- **A PM hand-over stranded the work in flight**: pending approvals and unsigned POs now move with the build.
- **A PO only closed the one requirement it was raised from**, so a PO from the blank FAB left its
  materials alerting forever. It now closes every pending requirement its lines cover.
- Plus: `fn_notify*` / `fn_audit` revoked from `authenticated`; Store can create a catalogue item; a member
  owns their own name and phone (which is what makes Settings → Account details able to save); design
  submission notifies the client; the FK sweep re-run for the seven FKs added after `0009`; essentials
  bootstrapped on a fresh database.

**App.**
- **Photos.** `Image.memory` had no `errorBuilder` at either site and `image_picker` does not always
  transcode a HEIC, so an undecodable frame took the screen down during layout. Picked bytes are decoded
  once before any widget sees them, the content type is sniffed from the file's magic number rather than
  its name (JPEG bytes were being stored as `image/heic`, which then rendered nowhere), a second tap while
  the picker is open is ignored, and the three `FilePicker` call sites are wrapped.
- **Settings is real.** Account details, Company details (moved out of the Team screen, read-only for
  non-admins), Roles & permissions, Notifications. Three "coming soon" snackbars gone.
- **Admin's "Needs attention"** reads builds, not just materials — delayed, no PM, at risk, then overdue
  order-by, each row opening the build.
- **Design and Service can work their own stages** (`shared/my_stages.dart` + a reusable
  `TaskDetailScreen`). This is what kept a build's progress from ever reaching 100%.
- **Notifications open what they are about**, resolved per role. The entity was always recorded; the feed
  never selected it.
- **Client and staff can open the documents** they are shown — PDF to the OS preview sheet, image to a
  viewer. No new dependency.
- **Every cached provider is auth-aware** via `currentUserIdProvider`, which emits only on a real user
  change. The un-watched ones served the previous user's rows after switching accounts on one device —
  the thing a multi-role demo on a single phone hits immediately.
- Smaller: a non-standard GST rate is no longer silently rewritten to 18%; CGST + SGST add up to the tax
  (and the document carries a rate-wise breakup and a per-line GST %); one warranty threshold instead of
  two, with calendar arithmetic so "ends today" is not "expired"; an undated requirement no longer shouts
  "Order today"; a serialized item with none on hand appears in Store → Stock; `findBySerial` escapes the
  scan; intake *reserves* a part for a build instead of marking it installed by nobody; submitting a stage
  with checks still open asks first; one `invalidateBuild()` so an action refreshes everything it touches.

**Verified.** `flutter analyze` 0 errors / 0 warnings · `flutter test` **89/89** (up from 62) ·
`flutter build ios --simulator` succeeds and the app boots on an iPhone 15 Pro simulator. Flutter 3.47.2.

**The backend suite was then run by CI**, which is the first time any of `0026` met a real database — and
it caught two things local work could not:

1. `fn_reopen_ticket`'s new guard was **three-valued and therefore never fired**. For any staff member
   `v_ca = public.my_client_account()` is NULL, so `false or false or NULL` came out NULL, and
   `if not NULL then` is *false*. An unrelated welder could reopen anyone's ticket at high priority —
   precisely what the guard was added to stop. The same trap as the `is_admin()` fix two sections above it
   in the same migration, which is why both now carry a comment saying so.
2. The essentials bootstrap **could not do what it claimed**: the migration chain finishes before
   `seed.sql` runs, so `0026` swept an empty `item_catalog` and every seeded item kept the `false`
   default. `seed.sql` sets `is_essential` on its own rows now.

Every other guard condition added by `0026` was then swept for the same NULL-logic trap; those two were
the only ones. **191/191 backend assertions pass**, on both the migration chain and `full_setup.sql`.

**Also decided:** the iOS project's Swift Package Manager migration and its iOS 13 → 15 floor (both of
which Flutter 3.47 applies automatically) are committed rather than reverted, and CI's Flutter pin moved
3.44.8 → 3.47.2 to match. iOS 13 and 14 devices are no longer supported; `NATIVE_SETUP.md`, both READMEs
and the steering docs say so now.

---

## 7 Oct 2026: Premium motion + UI polish, with logic fixes ✅ (branch `feat/premium-motion-ui-polish`)

The ask: make the app feel premium and fluid, not jerky. Fix visible glitches (Admin Team's *Add member* sat
oddly) and make sure the logic is right. This session ran Flutter 3.44.8 in the sandbox, so
`flutter analyze` / `flutter test` were run locally. Each screen was also rendered to PNG (still and
mid-animation) and checked by eye.

- ✅ **Motion system:**
  - M3 duration / easing tokens and haptics, with *Reduce motion* respected.
  - Building blocks: staggered page entrances, spring presses, count-ups that glide, and shimmer skeletons
    instead of spinners.
  - Fade-through for tabs and for skeleton → content (`ContentReveal`). Gliding nav bubble and segment
    indicator.
  - Native Cupertino routes on iOS (keeps swipe-back), predictive back on Android, and one sheet motion.
  - Found and fixed with a regression test: the leaving tab was rebuilt from scratch mid-fade (unkeyed layer
    wrappers), which replayed its entrance and flickered.
- ✅ **Design system:**
  - New: `RoleHeader`, `BackChip`, `PrimaryButton(busy:)`, `SecondaryButton`, `PillAction`, `AppChip` / `ChipBar`,
    `SegmentTabs`, `ErrorCard` (Retry) and `showAppSheet`.
  - Hand-rolled back circles, spinner swaps and buttons replaced across 45 feature files.
- ✅ **Layout glitches:** Team *Add member* / Vendors *Add vendor* became pills beside the title. Fixed the Design
  carousel overflow and the date-chip overflow, the duplicated ticket description, the checklist's last divider and
  the off-centre hint. Pushed screens' loading / error states keep the back button.
- ✅ **Logic:**
  - Delivered builds are excluded from active shares and on-track %. Admin and PM got a Delivered chip and label.
  - Notifications group by local day, not UTC.
  - Every role's bell shows the unread count (Procurement's used to show a different number).
  - PM at-risk / today rows open the build.
  - Workshop Start / Submit are double-tap guarded.
  - Approval cards are keyed by id and fold away after a decision.
  - Delete-requirement errors are handled. The role-load error has Retry + Sign out.
  - Full list in `PROJECT_LOG.md` §6.
- ✅ **Verified:** `flutter analyze --no-fatal-infos`: 0 errors, 0 warnings, 33 infos (down from 51).
  `flutter test`: **62/62** (28 model + 34 widget). No dependency or schema change.
- ✅ **Independent review → 16 findings, all fixed** (second commit). Every regression test was checked to fail on the old code. See `PROJECT_LOG.md` §6.
- ⏭️ **On device:** haptics feel, iOS edge-swipe-back on pushed screens, the 3D truck card (a WebView, so it
  can't render in tests), and real-network loading → content reveals.

---

## 7 Oct 2026: Full code audit + docs refresh ✅

PR #46 merged. Then every line of the app, the 25 migrations, both Edge Functions, the test
suites and the seeds was read to rebuild full context, and every doc was brought back in line with
the code. No app or schema change.

- ✅ **Docs rewritten to match the code:**
  - `API.md`: the real RPC / view / Edge Function surface. The old REST spec was never built.
  - `DataModel.md`: 33 tables, 5 views, enums, triggers, RLS matrix, storage.
  - `Roles.md`: real tabs, FAB and screens per role.
  - Also corrected: `DEPENDENCIES.md`, `BUILD_PROGRESS.md`, `README.md`, `app/README.md`, `OVERVIEW.md`,
    `TechStack_and_BuildPlan.md`, `INVITE_FLOW.md`, `UX_NAVIGATION_AUDIT.md` (Tier 3 status), and the
    `.kiro/steering` working rules.
- ✅ **`supabase/check_migrations.sql`:** a read-only checker that prints `applied` / `RUN THIS` for
  `0004`–`0025`. Verified on Postgres 15 at three levels: base only, through `0011`, and the full chain.
- ✅ **`TESTING_GUIDE.md` rewritten.** It has a deploy checklist built on the checker, and a phased 2-device plan:
  Simulator = office roles, phone = camera roles + client. It fixes three wrong assumptions in the
  previous version: the live DB level, a seed template with no BOM, and Design stages that can't be submitted.
- ✅ **Re-verified:** `supabase/tests/run.sh` gives **149/149** on both paths. CI is green on `main` (`8ea550c`).
- ⏭️ **Findings to fix next**, listed in `PROJECT_LOG.md` §3 and `WORKFLOW_AUDIT.md` §7. Highest impact:
  1. Design / Service stages need a Start / Submit UI.
  2. Store's inline "new item" is blocked by RLS.
  3. Close the DB bypasses: `fn_reopen_ticket` has no caller check, the guard triggers don't
     protect `status` / delivery dates, Procurement can self-approve POs, and definer helpers are
     executable by anyone.
  4. Seven `profiles` FKs block member removal.
  5. `fn_receive_po` race.

---

## Tier 1–3: UI/correctness + multi-user-per-role hardening + canonical build screen ✅ (PR #46, merged 7 Oct 2026)

A line-by-line audit of every role's screens (a role is a *team*, not one person —
multiple PMs, procurement staff, designers, technicians, etc.) turned up a class of
small glitches. This pass fixes the confirmed, low-risk ones:

- ✅ **Double-submit guards.** New shared `AsyncPrimaryButton` (spinner + ignores taps
  while its async action runs). Applied to PO sign/approve/reject/dispatch/receive,
  procurement Receive & Mark-dispatched (the latter also de-hand-rolled to the design
  system), recall **Notify all**, and service **Close ticket**. PM **Approvals** cards
  became stateful with a `_deciding` guard + spinner; client **reopen** and the Store
  inline **new-item** dialog got in-flight guards; **Mark all read** got try/catch +
  `friendlyError`.
- ✅ **New members appear immediately.** `Add member` now invalidates the PM dropdown,
  the assign-work picker and the service technician picker by role — a freshly-added
  PM/technician/doer was invisible until an app restart.
- ✅ **Design version numbering is atomic** (migration `0025`). `addVersion` did
  read-max-then-insert; two designers on the same build could grab the same `version_no`
  and lose an upload. Now a unique index on `(artifact_id, version_no)` + a
  `SECURITY DEFINER` `fn_add_design_version` that computes the next number under a row
  lock. `addVersion` calls the RPC.
- ✅ **Checklist toggle** (workshop task) is now optimistic, guarded against re-taps, and
  surfaces failures instead of silently swallowing them.
- ✅ **Stale-after-write invalidation.** Logging a component refreshes stock + the
  scan-to-install pool + the truck record (not just the component list); approving a
  design refreshes the truck's 3D model + the client's truck list.
- ✅ **Money in words matches figures** on the GST PO document (paise are now spelled out
  instead of rounded away).
- ✅ **`new_ticket` truck picker** uses `.when` — a load/error no longer shows a false
  "No delivered trucks".
- ✅ **`mounted` guards** added to the design upload pickers (no `setState` after backing
  out mid-upload).

**Watch out when deploying:** run `0025_design_version_atomic.sql` (idempotent). From it
on, adding a design version goes through `fn_add_design_version` — an old app build doing
the direct insert still works but without the race guard. `full_setup.sql` regenerated.

### Tier 2 — polish (same pass)

- ✅ **SLA countdown is live.** The Service ticket queue rebuilds once a minute so the
  "2h left" / Overdue labels actually move instead of freezing at open time.
- ✅ **"Fixed today" is a real calendar day** (local), not a rolling 24-hour window
  (Service tickets tab + profile stat).
- ✅ **Raw `$e` sweep.** Every error string across the role screens now renders
  `friendlyError(e)` instead of a raw exception — consistent, and no SQL leaks to users.
- ✅ **Admin bell badge** counts UNREAD notifications (it opens the notifications feed),
  not the urgent order-by items (which have their own "needs attention" section).
- ✅ **Design "assigned to me" carousel** height scales with the text-size setting, so the
  card no longer overflows at large accessibility scales.
- ✅ **Guards / leaks:** the client design title no longer risks a RangeError on an empty
  type; Create-Template and its inline dialogs, the requirements inline dialog and the
  Add-Member sub-team dialog now dispose their controllers.
- ⏭️ **Not done — `truck_3d` load-error fallback:** `model_viewer_plus` exposes no Dart
  `onError`/`onLoad`, so a reliable runtime error state isn't possible without a package
  change. The empty-URL case is already guarded by callers.

### Tier 3: navigation clarity (same PR)

- ✅ **One canonical build screen.** `BuildScreen` has tabs **Overview · Pipeline · Materials ·
  Record**. Every entry point (Admin Projects, Command Center rows, PM Projects, PM Schedule) opens
  it, so the Dossier-vs-Detail fork is gone for users. The old standalone navigation inside
  `ProjectDetailScreen` / `ProjectDossierScreen` is still in the code but unreachable; it's dead code to remove.
- ✅ **Role-mode banner** on Overview: *Oversight · read-only* (Admin) vs *You manage this build* (PM).
- ✅ **Stable FAB per role.** Admin's ＋ is always Onboard project (Add member now lives in the Team tab).
  Procurement's ＋ is always New PO (Add vendor now lives in the Vendors tab).
- ✅ `errorBuilder` on the client's full-screen stage photo.
- ✅ Docs: `TESTING_GUIDE.md`, `UX_NAVIGATION_AUDIT.md` (blueprint), `.kiro/steering/product.md`.

⏭️ Still deferred (bigger / architectural): realtime cross-user freshness (Phase 3), a
shared-queue "claim" concept for service tickets and PO approvals, a shared `StageEvidence` widget,
one Profile pattern for all roles, and the PO one-detail consolidation (see `UX_NAVIGATION_AUDIT.md`).

---

## Phase 1 — closing the broken logic loops ✅ COMPLETE

All seven loops shipped, each its own CI-verified PR, all merged to `main`.
Migrations 0012–0014 have been applied to the live Supabase project.

1. ✅ **PM approvals show the work** *(PR #7)* — photos + checklist + installed
   parts on the approval card, so a PM stops approving blind.
2. ✅ **Template checklists** *(PR #8 · migration 0012)* — a template carries a
   per-stage checklist; `fn_onboard_project` copies it onto every build's stage
   as real `checklist_items`. New `template_stage_checks` table + Create-Template
   UI. Closed the empty-checklist gap PR #7 exposed.
3. ✅ **Stock movement** *(PR #9 · migration 0013)* — receiving a PO adds the
   quantities to `stock_items` via `fn_receive_po` (security-definer, atomic).
   Store's inventory + low-stock were frozen at seed values before this.
4. ✅ **Client ticket visibility** *(PR #10 · migration 0014)* — additive RLS
   policy so a client sees every ticket on their trucks, not only ones they
   raised (Service-raised tickets were invisible).
5. ✅ **Bill capture + viewer** *(PR #11)* — Store attaches a bill/invoice image
   at intake (`builds/bills/`, stored on `component_instances.bill_url`); the
   component detail opens it full-screen. Completes Hero #2.
6. ✅ **Delay logging** *(PR #12)* — PM tags why a build slipped (against the
   slipping stage) and optionally pushes the delivery date by those days, which
   re-runs backward scheduling (the cascade). `delay_logs` was read but never
   written.
7. ✅ **Documents / handover pack** *(PR #13)* — staff upload a build's documents
   (contract / invoice / warranty pack / handover cert) from the project detail
   screen; they become available on the client's truck.

### Gaps these closed (all previously open on `main`)
`stock_items`, `checklist_items`, `documents`, `delay_logs`, `bill_url` — each
had a read path but no write path. PM approvals showed no evidence. Tickets RLS
hid Service-raised tickets from the client. All resolved above.

### Verify on device (Phase 1 acceptance)
Run against the live Supabase (0012–0014 applied). Suggested pass:
- Admin: create a template **with a checklist** → onboard a project → the stages
  carry that checklist.
- Workshop: open a task → tick the checklist, add a photo → submit.
- PM: on the approval, the **photos + checklist + parts** are shown → approve.
- Procurement: receive a PO → **Store stock goes up** for those items.
- Store: log a component **with a bill** → open it from the component detail.
- PM: **log a delay** on a build → the delivery date shifts.
- Admin/PM: **add a document** on a project → it appears on the client's truck.
- Service: raise a ticket for a client → the **client sees it** in their app.

### Deferred (Phase 2 — robustness)
Offline support · push notifications · realtime · pagination · localization ·
dependency upgrades (Riverpod 2→3, go_router 14→17, +24 others).

---

## Phase 0 — foundation (done)

### CI (PR #6, merged `2f7746c`)
- ✅ GitHub Actions: `flutter analyze --no-fatal-infos` + `flutter test` + Android debug build + backend SQL suite, on every push/PR. Flutter pinned to 3.44.8.
- ✅ First time the whole app was compiled/analyzed/tested — all green.
- ✅ CI surfaced and we fixed 3 real dynamic-typing bugs (`strict-casts`): untyped `catalog` list, dynamic `l['id']` in `markReceived`, plus 2 unnecessary casts and 2 no-op `!`.
- ✅ Committed the `pubspec.lock` entries for `flutter_test` (was stale since #5).
- ⚠️ 28 info-level style lints remain (const constructors, deprecated `withOpacity`, curly braces) — non-blocking, deferred to a dedicated style pass.

### Buildable repo + native config (PR #5, merged `82bf548`)
- ✅ Removed the bay board (the `bays` table was never written to); PM Schedule now shows open stages by due date (overdue / today / next 7 days / later / no date).
- ✅ Tracked `app/android`, `app/ios`, `app/web` — a clone can now be built. `.gitignore` reworked to keep build output and signing secrets out.
- ✅ Committed `pubspec.lock` and `ios/Podfile.lock` (regenerated with `mobile_scanner` + `image_picker_ios`, which the iOS build had never included).
- ✅ Applied native config that the docs described but had never been applied: `CAMERA` + `INTERNET` permissions, the `io.supabase.buildtrack` deep link (Android manifest + iOS `CFBundleURLTypes`), iOS camera/photo usage strings, `minSdk = maxOf(23, …)`, `platform :ios, '13.0'`.
- ✅ Added a real test suite (`test/models_test.dart`, 26 tests) and `flutter_test` (was missing from dev_dependencies, so nothing could compile). Replaced the stock counter `widget_test.dart`.
- ✅ Added `analysis_options.yaml` with correctness-focused lints (`strict-casts` on; `strict-inference`/`strict-raw-types` off with reasons).
- ✅ Ignored desktop platforms (linux/macos/windows) — not shipped.

### Review (start of engagement)
- Read the whole repo. Found docs claimed "~90% complete" but code was closer to ~25% production-ready: solid backend (24 RPCs, RLS, guard triggers, 83 assertions), UI shell wired for all 8 roles, but many logic loops open (the list above).
