# BuildTrack — Worklog

A running, session-by-session record of what changed and why. Newest first.
Unlike `PROJECT_LOG.md` (a snapshot of the product's state), this is the trail:
what we did, what it fixed, and what is still open, so anyone can pick up where
we left off.

Legend: ✅ done · 🔄 in progress · ⏭️ next · ⚠️ needs the dev machine
(no Flutter SDK in the agent sandbox, so `flutter analyze`/`test`/`run` are
verified through CI, not locally).

---

## Phase 1 — closing the broken logic loops

The foundation is in place; now the features that don't actually work end to end.
Order (each its own PR, verified by CI, then merged):

1. ✅ **PM approvals show the work** — photos + checklist + installed parts on the
   approval card, so a PM stops approving blind. *(PR #7, merged)*
2. 🔄 **Template checklists** — a template carries a per-stage checklist;
   `fn_onboard_project` copies it onto every build's stage as real
   `checklist_items`. New `template_stage_checks` table + Create-Template UI.
   Closes the empty-checklist gap PR #7 exposed. *(in progress)*
3. 🔄 **Stock movement** — receiving a PO now adds the quantities to
   `stock_items` via `fn_receive_po` (security-definer, atomic). Store's
   inventory + low-stock were frozen at seed values because nothing wrote
   stock, and procurement can't write `stock_items` directly. *(stacked on #8)*
3. ⏭️ Bill capture + viewer at intake (completes Hero #2).
4. ⏭️ Client sees every ticket about their truck, including ones Service raised.
5. ⏭️ Template checklists — stages are created with a real checklist.
6. ⏭️ Delay logging — tag a reason, reschedule, see the cascade.
7. ⏭️ Documents / handover pack.

### Known gaps confirmed still open on `main` (as of this entry)
- `stock_items` — no writes from app or triggers; Store stock + low-stock are frozen seed data.
- `checklist_items` — nothing creates them; every stage checklist is empty.
- `documents` — no inserts; client Documents tab always empty.
- `delay_logs` — no writes; delay tagging/reschedule missing.
- `bill_url` — never captured or shown ("coming soon" in log_component + component_detail).
- PM approvals — submitted photos/checklist not shown (being fixed as loop #1).
- Tickets RLS — client only sees `raised_by = auth.uid()`, so Service-raised tickets are invisible to them.

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
