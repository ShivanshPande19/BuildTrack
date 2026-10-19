// The workflow builder, driven the way a PM drives it — no network.
//
// The repository is faked at the one call that leaves the device
// (saveTemplate), so these tests check what the screen *sends*, not only what
// it shows: the step grouping a PM sees on the rail has to be the grouping that
// reaches fn_save_template.
import 'package:buildtrack/data/models.dart';
import 'package:buildtrack/data/repositories.dart';
import 'package:buildtrack/features/admin/create_template.dart';
import 'package:buildtrack/features/admin/workflows_screen.dart';
import 'package:buildtrack/shared/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeAdminRepo extends AdminRepo {
  String? savedName;
  List<StageDraft>? savedStages;

  @override
  Future<OptRef> saveTemplate(String name, String? truckType, List<StageDraft> stages) async {
    savedName = name;
    savedStages = stages;
    return OptRef('new-id', name.trim());
  }
}

/// A screen that opens the builder and keeps what it popped with.
class _Launcher extends StatefulWidget {
  const _Launcher();
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  Object? result = 'not popped';
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: TextButton(
    onPressed: () async {
      final r = await Navigator.of(context).push<OptRef>(
        MaterialPageRoute(builder: (_) => const CreateTemplate()));
      setState(() => result = r);
    },
    child: Text(result is OptRef ? 'saved ${(result as OptRef).label}' : 'open builder'),
  )));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _FakeAdminRepo repo;

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    repo = _FakeAdminRepo();
    await t.pumpWidget(ProviderScope(
      overrides: [
        adminRepoProvider.overrideWithValue(repo),
        itemsProvider.overrideWith((ref) async => [OptRef('i1', 'Chassis frame')]),
      ],
      child: MaterialApp(theme: ThemeData(useMaterial3: true), home: const _Launcher()),
    ));
    await t.tap(find.text('open builder'));
    await t.pumpAndSettle();
  }

  /// Adds a stage through its sheet: name, then optionally "runs alongside".
  Future<void> addStage(WidgetTester t, String name, {bool alongside = false}) async {
    final first = find.text('Add the first stage');
    await t.tap(first.evaluate().isNotEmpty ? first : find.text('Add a stage'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, name);
    await t.pump();
    if (alongside) {
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
  }

  /// The summary bar's three numbers: stages, steps, days.
  List<num> summary(WidgetTester t) =>
      [for (final c in t.widgetList<CountUp>(find.byType(CountUp))) c.value];

  testWidgets('opens empty — nothing pre-filled', (t) async {
    await open(t);
    expect(find.text('NEW WORKFLOW'), findsOneWidget);
    expect(find.text('Plan how a build runs'), findsOneWidget);
    expect(summary(t), [0, 0, 0]);
  });

  testWidgets('a named stage lands on the rail, and the estimate follows', (t) async {
    await open(t);
    await addStage(t, 'Chassis');
    expect(find.text('Chassis'), findsOneWidget);
    expect(find.text('Plan how a build runs'), findsNothing);
    expect(summary(t), [1, 1, 3]); // a new stage is 3 days
  });

  testWidgets('a new stage closed without a name was never added', (t) async {
    await open(t);
    await t.tap(find.text('Add the first stage'));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Plan how a build runs'), findsOneWidget);
    expect(summary(t), [0, 0, 0]);
  });

  testWidgets('"runs alongside" shares a step, and the days drop to match', (t) async {
    await open(t);
    await addStage(t, 'Chassis');
    await addStage(t, 'Countertop');
    expect(summary(t), [2, 2, 6]);
    await addStage(t, 'Electricals', alongside: true);
    expect(find.text('Together'), findsOneWidget);
    // Countertop and Electricals run together: three stages, two steps, 3 + 3.
    expect(summary(t), [3, 2, 6]);
  });

  testWidgets('a workshop stage offers the standard flow, and fills it in one tap', (t) async {
    await open(t);
    await t.tap(find.text('Add the first stage'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, 'Workshop');
    await t.pump();
    final offer = find.text('Use the standard workshop flow');
    await t.scrollUntilVisible(offer, 200, scrollable: find.byType(Scrollable).last);
    await t.tap(offer);
    await t.pumpAndSettle();
    expect(offer, findsNothing);
    // The jobs count beside the JOBS heading.
    expect(find.text('${standardWorkshopFlow.length}'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('15 jobs'), findsOneWidget);
  });

  testWidgets('Save without a name says what is missing, and sends nothing', (t) async {
    await open(t);
    await addStage(t, 'Chassis');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Give this workflow a name.'), findsOneWidget);
    expect(repo.savedName, isNull);
  });

  testWidgets('Save sends the grouping the rail shows, and pops with the new workflow', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField).first, 'Food truck · standard');
    await addStage(t, 'Chassis');
    await addStage(t, 'Countertop');
    await addStage(t, 'Electricals', alongside: true);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(repo.savedName, 'Food truck · standard');
    expect([for (final s in repo.savedStages!) s.name], ['Chassis', 'Countertop', 'Electricals']);
    expect(stepsFor(repo.savedStages!), [1, 2, 2]);
    expect(find.text('saved Food truck · standard'), findsOneWidget);
  });

  testWidgets('leaving with unsaved work asks first', (t) async {
    await open(t);
    await addStage(t, 'Chassis');
    await t.tap(find.byIcon(Icons.chevron_left_rounded));
    await t.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('Chassis'), findsOneWidget);

    await t.tap(find.byIcon(Icons.chevron_left_rounded));
    await t.pumpAndSettle();
    await t.tap(find.text('Leave'));
    await t.pumpAndSettle();
    expect(find.text('open builder'), findsOneWidget);
  });

  testWidgets('leaving untouched does not ask', (t) async {
    await open(t);
    await t.tap(find.byIcon(Icons.chevron_left_rounded));
    await t.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsNothing);
    expect(find.text('open builder'), findsOneWidget);
  });

  group('Workflows · the list and the preview', () {
    final summaries = [
      WorkflowSummary(id: 'w1', name: 'Food truck · standard', truckType: 'Food truck',
        createdByName: 'Priya Nair', createdAt: DateTime.utc(2026, 10, 18),
        stageCount: 4, stepCount: 3, estimatedDays: 21),
      WorkflowSummary(id: 'w2', name: 'Momo cart', stageCount: 1, stepCount: 1, estimatedDays: 1),
    ];

    Future<void> list(WidgetTester t, List<WorkflowSummary> ws) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          workflowSummariesProvider.overrideWith((ref) async => ws),
          workflowDraftsProvider('w1').overrideWith((ref) async => (
            name: 'Food truck · standard', truckType: 'Food truck',
            stages: [
              StageDraft('Layout', 5, discipline: 'design'),
              StageDraft('Fabrication', 14, discipline: 'workshop',
                tasks: [for (final (title, w) in standardWorkshopFlow) TaskDraft(title, runsWithPrevious: w)]),
              StageDraft('Branding', 3, runsWithPrevious: true),
              StageDraft('Handover', 2, checks: [CheckDraft('Keys handed over', photoRequired: true)]),
            ])),
        ],
        child: MaterialApp(theme: ThemeData(useMaterial3: true), home: const WorkflowsScreen()),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('each workflow shows its shape and who made it', (t) async {
      await list(t, summaries);
      expect(find.text('Food truck · standard'), findsOneWidget);
      expect(find.text('4 stages'), findsOneWidget);
      expect(find.text('3 steps'), findsOneWidget);
      expect(find.text('~21 days'), findsOneWidget);
      expect(find.text('by Priya Nair · 18 Oct 2026'), findsOneWidget);
      // Singulars read as singulars.
      expect(find.text('1 stage'), findsOneWidget);
      expect(find.text('~1 day'), findsOneWidget);
    });

    testWidgets('no workflows yet offers to make the first', (t) async {
      await list(t, []);
      expect(find.text('No workflows yet'), findsOneWidget);
      expect(find.text('Create the first workflow'), findsOneWidget);
    });

    testWidgets('the preview draws every stage and offers a copy, not an edit', (t) async {
      await list(t, summaries);
      await t.tap(find.text('Food truck · standard'));
      await t.pumpAndSettle();
      for (final n in ['Layout', 'Fabrication', 'Branding', 'Handover']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('15 jobs'), findsOneWidget);
      expect(find.text('1 check'), findsOneWidget);
      expect(find.text('Start a new workflow from this'), findsOneWidget);
    });
  });
}
