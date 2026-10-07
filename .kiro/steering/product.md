# BuildTrack — product & UX north-star

Read this before building or changing any screen. It captures WHY the app exists
and the bar every change is held to.

## What this is

**Azimuth Business on Wheels** (Noida, est. 2016) designs and manufactures custom
mobile business units — food trucks, coffee trailers, retail kiosks, vending carts,
brand-activation vehicles and other custom builds — for F&B brands, FMCG, and
government/utility projects. (It also operates the **Eat Truck Love / ETL** street-food
brand.) **BuildTrack** is the one internal app that runs the whole *build phase* of a
confirmed order — from onboarding through delivery and after-sales — across dozens of
parallel builds, so nothing slips.

## The problems it solves (keep these in the foreground)

1. **No visibility.** Leadership couldn't see *which stage a build is in, what work is
   happening right now, and who is on it*. Every screen should make "where is this build
   and who has it" answerable at a glance.
2. **Silent delays.** Slips weren't caught or attributed. Surface overdue/at-risk state
   and *why* it slipped.
3. **Late ordering.** Long-lead items got ordered too late, pushing deliveries. The
   order-by alert engine (Hero #1) exists for exactly this — keep it prominent.
4. **No traceability.** A failed part's bill/warranty and which trucks share a model were
   unfindable. The per-truck digital twin + recall (Hero #2) solve this.

## UX north-star (the bar for every change)

- **Easy to understand.** A user should know what a screen is for and what to do next
  without a manual. Prefer clarity over cleverness.
- **Easy to create things.** The core actions (onboard a build, assign work, raise a PO,
  log a part, submit a stage) should be short, obvious, and forgiving.
- **One action, one place.** Do NOT expose the same action from two different entry
  points with divergent behaviour — duplicate access paths are the app's biggest source
  of confusion. If an action already lives somewhere, link to it; don't re-implement it.
- **Own the design system, never raw Material.** Use the shared components in
  `app/lib/shared/widgets.dart` (`AppCard`, `StatusPill`, `SectionLabel`, `PrimaryButton`,
  `AsyncPrimaryButton`, `PillNav`, `AppSelectField`, `EmptyState`) and the tokens in
  `app/lib/core/theme.dart` (`BT.*`, `display()`), plus the motion layer in
  `app/lib/shared/animations.dart`. No bare `AppBar`, `DropdownButton`, `Switch`,
  hand-rolled buttons, etc. — they read as unfinished.
- **Every list needs loading / empty / error states.** Use `AsyncValue.when` — never
  `.valueOrNull ?? []`, which shows a false "empty" during load and swallows errors.
  Show errors via `friendlyError(e)`, never a raw `$e`.

## Multiple people per role is the norm — design for it

A role is a team, not a person: there can be several PMs, procurement staff, store
keepers, designers, service technicians, admins, and multiple client contacts per
account. So:

- **Scope "my work" by the signed-in user id**, not by role (e.g. a PM sees builds where
  `pm_id == me`; an assignee sees stages where `assignee_id == me`).
- **Guard every mutating action against a double-tap** — use `AsyncPrimaryButton` or a
  local in-flight flag. Two fast taps must never create two POs / two approvals / two
  recall blasts.
- **Concurrency-sensitive numbering/claims belong in the database** (a `SECURITY DEFINER`
  RPC with a row lock / unique constraint), not read-then-write in Dart — two users on the
  same record will race. See `fn_add_design_version` (migration 0025) as the pattern.
  Known exception to fix: `fn_receive_po` still reads the PO status without `FOR UPDATE`.
- **Every provider that reads data must `ref.watch(authStateProvider)`**, so it refetches when
  someone else signs in on the same device. Several (`purchaseOrdersProvider`, `vendorsProvider`,
  `itemsProvider`, `templatesProvider`, `pmsProvider`, `clientsProvider`, the `.family` ones) don't
  yet, and can show the previous user's data.
- **After a mutation, invalidate EVERY provider it affects**, not just the one on the
  current screen (e.g. adding a member must refresh the PM dropdown, the assign picker and
  the technician picker; logging a part must refresh stock + the scan-to-install pool +
  the truck record).
- Cross-user *freshness* (one user seeing another's change without a manual pull) needs
  realtime and is tracked as Phase-3 — until then, invalidate aggressively and lean on
  pull-to-refresh.

## Business rules live in Postgres

RLS + guard triggers + `SECURITY DEFINER` RPCs enforce the workflow, so rules hold no
matter what calls them. The app surfaces their messages via `friendlyError()`. The DB and
the app ship together (from migration 0009 on, direct table writes are blocked). When a
change needs a new rule, add it as a migration and regenerate `supabase/full_setup.sql`
with `cd supabase && sh build_full_setup.sh`.
