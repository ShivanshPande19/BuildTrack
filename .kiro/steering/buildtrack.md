---
inclusion: always
---

# BuildTrack — working rules

## Start here

`docs/PROJECT_LOG.md` is the source of truth for the project's current state: what works per role,
what's pending, deploy facts, and a dated change log. **Read it before planning any change, and
update it as part of every change** (it has a "How to maintain this log" section at the bottom).

Supporting docs:
- `docs/WORKFLOW_AUDIT.md`: known issues + fix status; §7 = open findings.
- `DEPENDENCIES.md`: who produces which data for whom, repos, screen matrix.
- `docs/Roles.md`: real tabs and screens per role.
- `docs/DataModel.md`: schema + RLS matrix.
- `docs/API.md`: RPCs, views, Edge Functions, direct writes.
- `docs/TESTING_GUIDE.md`: deploy checklist + 2-device plan.
- `BUILD_PROGRESS.md`: history.

Product / UX rules are in `product.md` (this folder).

## Non-negotiables

- **Business rules belong in the database**, exposed as `SECURITY DEFINER` RPCs, protected by RLS +
  guard triggers. Never enforce a rule only in the Flutter UI. The app surfaces DB messages through
  `friendlyError()` in `data/repositories.dart`.
- **Role ownership:**
  - Admin = oversight, people, builds, client logins; assigns the PM; gives POs final approval.
  - PM = build planning: stage assignment, materials, delivery date, delays, stage approvals, PO signatures, delivery.
  - Stage assignees = workshop / design / store / service only.
- **Every build must have a PM.** A PM-less build is stranded — invisible to PMs, unassignable,
  unapprovable.
- **A client's `client_account` and login are always created together.** No `contact_user_id` means
  the client can never see their truck.
- **Execution roles only ever see their assigned work** (`assignedProjectsProvider`). Never widen a
  role's screens to the whole fleet.
- **DB and app ship together.** Direct table writes for assignment/approval are blocked by triggers.

## Verify before claiming done

```bash
sh supabase/tests/run.sh     # backend, Docker only: 149 assertions in 7 suites as real non-superuser users
cd app && flutter analyze && flutter test   # app: 0 errors; CI (Flutter 3.47.2) is the gate if the sandbox has no SDK
```

When you add a rule, add assertions to the matching suite: `10_workflow`, `20_service`, `30_po_approval`,
`40_ops`, `50_dossier`, `60_truck_record`, `70_status`, `80_hardening`, `81_po_routing`,
`82_design_stage`, `83_checklist_evidence`, or a new `NN_*_tests.sql`. They use the `t_assert` /
`t_expect_error` helpers defined in `10_workflow_tests.sql`. Read the real count off the run. Don't carry an old number forward.
A command exiting 0 is not proof; check the actual result.

## Conventions

- New backend behaviour goes in a **new numbered migration** (`supabase/migrations/00NN_*.sql`),
  written to be **idempotent** and safe to re-run. Never edit an applied migration. Add a detector row
  for it to `supabase/check_migrations.sql`: an object only that migration creates.
- Two traps this codebase has already been bitten by, both twice:
  - **`create or replace function` with a changed parameter list makes an overload, not a replacement**,
    and every existing call then fails as `is not unique`. `drop function if exists <name>(<old types>);`
    first — see `0015` (`fn_recompute_schedule`) and `0028` (`fn_create_design`).
  - **plpgsql is three-valued.** `if not <expr>` is *false* when `<expr>` is NULL, so a guard written as
    `if not (a or b) then raise` silently lets everything through the moment one side is NULL (and
    `my_client_account()` is NULL for every staff member). Wrap the condition in `coalesce(…, false)`.
- A summary section must stay **bounded**: a role carrying eight builds has to get the worst four and a
  *See all N* sheet, not an unbounded `Column`. And it must read every source of the fact it claims —
  twice now a section said "all caught up" because it read one table and the blocking thing was in another.
- **Never compare a Postgres `date` against `DateTime.now()`.** It parses to local midnight, so
  `isBefore(now)` is true from 00:01 and `isAfter(now)` is false all day: a stage due *today* read
  "Overdue" and a warranty ending *today* read "Expired". This has now been fixed **four** times
  (`0026` for two warranty sites, `0029` for `WorkshopTask`, `AssignedBuild` and
  `ComponentRow.warrantyActive`). Use `daysUntil()` / `warrantyStateFor()`, never a new comparison,
  and when adding a date predicate add a test that it agrees with the existing one — the real damage
  was two screens disagreeing about the same stage, not either being wrong alone.
- A column the app writes directly cannot carry a record of **who** changed it or **when**. If that
  matters, make it an RPC and force it with a guard trigger plus a transaction-local flag
  (`fn_stage_rpc_begin`, `fn_check_rpc_begin`) — otherwise the audit trail has a hole the client
  library walks straight through.
- **Replacing a function? Copy the parts you are not changing — do not retype
  them.** `create or replace` needs the whole body, so most of what you write is
  code that already exists and must come back byte-for-byte. Twice now a
  from-memory rewrite shipped something subtly wrong: `trg_guard_stages` came
  back with a different error message, and `fn_recompute_schedule` came back
  joining `vendors` on an `ic.preferred_vendor_id` that does not exist (the real
  line reads `ic.lead_time_days` and `ic.buffer_days` off item_catalog and needs
  no join), which took the whole seed down. Read the current definition, paste
  it, change only the part that is the point of the migration — comments
  included, so the diff shows what actually moved.
- Something approved is frozen. `fn_submit_stage` / `fn_start_stage` / `fn_install_component` /
  `fn_tick_check` all refuse a `done` stage; a new RPC that touches a stage's evidence should too.
- `supabase/full_setup.sql` is **generated** — regenerate with `cd supabase && sh build_full_setup.sh`,
  never hand-edit.
- Flutter: Riverpod providers in `data/repositories.dart`, models in `data/models.dart`, design
  tokens from `core/theme.dart` (`BT.*`, `display()`, `roleColor()`), shared widgets from
  `shared/widgets.dart` (full list and motion rules in `product.md`), the role header from
  `shared/role_header.dart`, motion from `shared/animations.dart`.
  Match the existing Equora visual style; don't introduce new UI primitives.
- Builds open in `BuildScreen` (`features/admin/build_screen.dart`). Don't add a new standalone
  build or stage screen; add a tab or section there.
- Comments explain *why*, especially where a subtle bug was fixed. Keep them.
- Empty states should explain *how to get data here*, not just say "nothing here".

## Environment notes

- `android/`, `ios/`, `web/` **are tracked**, with native config committed (camera/photo permissions,
  `io.supabase.buildtrack` deep link, `minSdk` 23, iOS 15). `flutter create .` silently overwrites
  them, so `git diff` afterwards. CI fails if the Android manifest loses `CAMERA`, `INTERNET` or the deep link.
- The live DB's migration level isn't recorded anywhere reliable. Ask the user to run
  `supabase/check_migrations.sql` before assuming a migration is applied.
- Supabase config comes from `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`.
- Adding members with an explicit password needs no SMTP; email invites do.

#[[file:docs/PROJECT_LOG.md]]
