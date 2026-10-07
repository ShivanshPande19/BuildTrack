# Azimuth BuildTrack: Flutter app

One app, 8 role-based experiences. Project overview, backend setup and CI are in the
[root README](../README.md). Current state and known gaps are in [`docs/PROJECT_LOG.md`](../docs/PROJECT_LOG.md).

## Run

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

The defaults in `lib/core/supabase_client.dart` are placeholders and don't connect.
iOS: `cd ios && pod install` after any dependency change. CI pins Flutter **3.44.8**.

## Check

```bash
flutter analyze      # must report 0 errors (strict-casts is on; see analysis_options.yaml)
flutter test         # pure-Dart model/domain tests in test/models_test.dart
```

## Layout

```
lib/
├── main.dart            # edge-to-edge system UI, top safe area only, ProviderScope, MaterialApp.router
├── core/
│   ├── supabase_client.dart   # init (PKCE), dart-define config, invite deep link, fetchMyRole
│   ├── router.dart            # go_router: /login · /set-password · /home (auth redirect)
│   └── theme.dart             # Equora tokens: BT.* colours, display(), roleColor(), page transitions
├── data/
│   ├── models.dart            # every model + pure logic (SLA label, warranty state, schedule buckets)
│   └── repositories.dart      # 10 repos + every Riverpod provider + friendlyError() + uploadToBuilds()
├── shared/
│   ├── widgets.dart           # AppCard, StatusPill, SectionLabel, PrimaryButton, AsyncPrimaryButton,
│   │                          #   PillNav, AppSelectField, EmptyState
│   ├── animations.dart        # Motion, FadeSlideIn, PressableScale, CountUp, AnimatedBar, TabSwitcher
│   ├── photo_picker.dart      # camera/gallery sheet, downscaled to 1600px at q82
│   └── barcode_scanner.dart   # mobile_scanner viewfinder + torch + manual serial entry
└── features/
    ├── auth/            # login, set password (invite)
    ├── home/role_home   # role → home shell
    ├── admin/           # dashboard, onboard, create template, team, company, ops center,
    │                    #   build_screen (Overview/Pipeline/Materials/Record) + its tabs, stage detail
    ├── pm/              # home (Home/Projects/Schedule/Team), assign work, approvals
    ├── procurement/     # home, new PO, PO detail, PO document (PDF), PO approvals, add vendor
    ├── store/           # home (Inbox/Stock/Parts), log component, component detail + recall
    ├── workshop/        # home (Tasks/Parts/Week), task detail, scan to install
    ├── design/          # home (Studio/Designs/Approvals), new design, design detail
    ├── service/         # home (Tickets/Trucks/Warranty/Profile), ticket detail, resolve, visit, new ticket, history
    ├── client/          # home (My Trucks/Support/Profile), truck detail, stage photos, approve design,
    │                    #   raise request, truck_3d (model viewer)
    └── common/          # notifications, profile
```

## Rules of the road

The working rules are in `.kiro/steering/`. In short:
- Business rules live in Postgres (RPCs + RLS). Screens call repository methods and never enforce a rule alone.
- Use the shared widgets and `BT.*` tokens, not raw Material.
- Every list needs loading, empty and error states (`AsyncValue.when`).
- Show errors with `friendlyError(e)`.
- Guard every mutating action against double taps (`AsyncPrimaryButton`).
- After a write, invalidate every provider it affects.
