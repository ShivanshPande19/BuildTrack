---
inclusion: always
---

# BuildTrack — working rules

## Start here

`docs/PROJECT_LOG.md` is the source of truth for the project's current state: what works per role,
what's pending, deploy facts, and a dated change log. **Read it before planning any change, and
update it as part of every change** (it has a "How to maintain this log" section at the bottom).

Supporting docs: `docs/WORKFLOW_AUDIT.md` (known issues + fix status) · `DEPENDENCIES.md` (who
produces which data for whom) · `docs/Roles.md` · `docs/DataModel.md` · `BUILD_PROGRESS.md`.

## Non-negotiables

- **Business rules belong in the database**, exposed as `SECURITY DEFINER` RPCs, protected by RLS +
  guard triggers. Never enforce a rule only in the Flutter UI. The app surfaces DB messages through
  `friendlyError()` in `data/repositories.dart`.
- **Role ownership:** Admin = oversight, people, builds, client logins, assigns the PM.
  PM = build planning (stage assignment, materials, delivery date, approvals).
  Stage assignees = workshop / design / store / service only.
- **Every build must have a PM.** A PM-less build is stranded — invisible to PMs, unassignable,
  unapprovable.
- **A client's `client_account` and login are always created together.** No `contact_user_id` means
  the client can never see their truck.
- **Execution roles only ever see their assigned work** (`assignedProjectsProvider`). Never widen a
  role's screens to the whole fleet.
- **DB and app ship together.** Direct table writes for assignment/approval are blocked by triggers.

## Verify before claiming done

```bash
sh supabase/tests/run.sh     # backend — Docker only, ~49 assertions as real non-superuser users
cd app && flutter analyze    # app — must be 0 errors
```

Add assertions to `supabase/tests/10_workflow_tests.sql` when you add a rule.
A command exiting 0 is not proof — check the actual result.

## Conventions

- New backend behaviour goes in a **new numbered migration** (`supabase/migrations/00NN_*.sql`),
  written to be **idempotent** and safe to re-run. Never edit an applied migration.
- `supabase/full_setup.sql` is **generated** — regenerate with `cd supabase && sh build_full_setup.sh`,
  never hand-edit.
- Flutter: Riverpod providers in `data/repositories.dart`, models in `data/models.dart`, design
  tokens from `core/theme.dart` (`BT.*`, `display()`, `roleColor()`), shared widgets from
  `shared/widgets.dart` (`AppCard`, `StatusPill`, `SectionLabel`, `PrimaryButton`, `PillNav`,
  `EmptyState`). Match the existing Equora visual style — don't introduce new UI primitives.
- Comments explain *why*, especially where a subtle bug was fixed. Keep them.
- Empty states should explain *how to get data here*, not just say "nothing here".

## Environment notes

- `android/`, `ios/`, `web/` are **not tracked in git**. `flutter create .` regenerates them and
  wipes the deep-link edits — re-apply from `docs/INVITE_FLOW.md` §3–4. It does not touch `lib/` or
  `pubspec.yaml`.
- Supabase config comes from `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`.
- Adding members with an explicit password needs no SMTP; email invites do.

#[[file:docs/PROJECT_LOG.md]]
