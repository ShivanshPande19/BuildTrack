# BuildTrack — Worklog

A running, session-by-session record of what changed and why. Newest first.
Unlike `PROJECT_LOG.md` (a snapshot of the product's state), this is the trail:
what we did, what it fixed, and what is still open, so anyone can pick up where
we left off.

Legend: ✅ done · 🔄 in progress · ⏭️ next · ⚠️ needs the dev machine
(no Flutter SDK in the agent sandbox, so `flutter analyze`/`test`/`run` are
verified through CI, not locally).

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
