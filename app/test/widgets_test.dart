// Widget-level tests for the shared design system + motion layer.
//
// These render real widgets (no network) and pump their animations to the end,
// so a layout overflow, an exception inside an animation, or a broken state
// transition fails CI instead of showing up on a device. Fonts fall back to the
// test font (google_fonts doesn't fetch in tests).
import 'package:buildtrack/core/theme.dart';
import 'package:buildtrack/shared/animations.dart';
import 'package:buildtrack/shared/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _host(Widget child, {Size size = const Size(390, 844), double textScale = 1}) => MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, pageTransitionsTheme: appPageTransitions()),
        home: Scaffold(backgroundColor: BT.bg, body: child),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('PillNav', () {
    const icons = [Icons.home_rounded, Icons.grid_view_rounded, Icons.people_rounded, Icons.bar_chart_rounded];

    Widget nav(int active, String label, {ValueChanged<int>? onTap, VoidCallback? onAction}) => Align(
          alignment: Alignment.bottomCenter,
          child: PillNav(icons: icons, active: active, activeLabel: label, onTap: onTap, onAction: onAction),
        );

    testWidgets('renders every tab and slides to a new one without overflow', (t) async {
      var tapped = -1;
      await t.pumpWidget(_host(nav(0, 'Home', onTap: (i) => tapped = i)));
      await t.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      for (final i in icons) {
        expect(find.byIcon(i), findsOneWidget);
      }

      await t.tap(find.byIcon(Icons.people_rounded));
      expect(tapped, 2);

      // Parent switches tab → bubble glides, label morphs.
      await t.pumpWidget(_host(nav(2, 'Team', onTap: (i) => tapped = i)));
      for (var f = 0; f < 30; f++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.pumpAndSettle();
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('long label on a narrow phone at large text never overflows', (t) async {
      await t.pumpWidget(_host(nav(1, 'Procurement orders'), size: const Size(320, 640), textScale: 1.6));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('action button fires', (t) async {
      var fired = false;
      await t.pumpWidget(_host(nav(0, 'Home', onAction: () => fired = true)));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.add));
      expect(fired, isTrue);
    });
  });

  group('AsyncPrimaryButton', () {
    testWidgets('ignores a double tap while the action runs', (t) async {
      var calls = 0;
      await t.pumpWidget(_host(Center(
        child: AsyncPrimaryButton('Approve', onTap: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }),
      )));
      await t.tap(find.text('Approve'));
      await t.pump(const Duration(milliseconds: 50));
      // Label has morphed into a spinner; a second tap lands on it.
      await t.tap(find.byType(AsyncPrimaryButton));
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Approve'), findsOneWidget);
    });
  });

  group('Motion primitives', () {
    testWidgets('staggered list reveals every item', (t) async {
      await t.pumpWidget(_host(ListView(children: staggered([for (var i = 0; i < 12; i++) Text('row $i')]))));
      await t.pumpAndSettle();
      expect(find.text('row 0'), findsOneWidget);
      expect(find.text('row 11'), findsOneWidget);
    });

    testWidgets('CountUp glides to new values instead of restarting', (t) async {
      await t.pumpWidget(_host(const CountUp(10)));
      await t.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
      await t.pumpWidget(_host(const CountUp(14)));
      await t.pump(const Duration(milliseconds: 30));
      // Mid-animation it is between the old and the new value, never back at 0.
      final mid = int.parse((t.widget(find.byType(Text)) as Text).data!);
      expect(mid, inInclusiveRange(10, 14));
      await t.pumpAndSettle();
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('reduce-motion renders final state immediately', (t) async {
      await t.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: Column(children: [CountUp(42), FadeSlideIn(child: Text('hi'))]))),
      ));
      await t.pump();
      expect(find.text('42'), findsOneWidget);
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('skeleton list shimmers without layout errors', (t) async {
      await t.pumpWidget(_host(const SingleChildScrollView(child: SkeletonList(count: 4))));
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(SkeletonCard), findsNWidgets(4));
      expect(t.takeException(), isNull);
    });

    testWidgets('tab switcher swaps bodies smoothly', (t) async {
      await t.pumpWidget(_host(const TabSwitcher(index: 0, child: Text('A'))));
      await t.pumpWidget(_host(const TabSwitcher(index: 1, child: Text('B'))));
      await t.pump(const Duration(milliseconds: 60));
      await t.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('tab switcher keeps the leaving tab alive and fades it through, not over', (t) async {
      final inits = <String, int>{};
      var tappedA = 0;
      Widget tab(String id) => _Probe(id, inits, onTap: id == 'A' ? () => tappedA++ : null);

      await t.pumpWidget(_host(TabSwitcher(index: 0, child: tab('A'))));
      await t.pumpAndSettle();
      expect(inits['A'], 1);

      await t.pumpWidget(_host(TabSwitcher(index: 1, child: tab('B'))));
      await t.pump(const Duration(milliseconds: 60));
      // Leaving tab is the same element (not rebuilt from scratch, so it
      // doesn't replay its entrance) and is still fading out.
      expect(inits['A'], 1);
      expect(find.text('A'), findsOneWidget);
      // Fade-through: the old tab is gone before the new one starts to show,
      // so the two never overlap as a ghost.
      double opacityOf(String s) => t
          .widgetList<FadeTransition>(find.ancestor(of: find.text(s), matching: find.byType(FadeTransition)))
          .first
          .opacity
          .value;
      expect(opacityOf('A'), greaterThan(0));
      expect(opacityOf('B'), 0);
      await t.pump(const Duration(milliseconds: 70)); // 130ms of 350
      expect(opacityOf('A'), 0);
      expect(opacityOf('B'), greaterThan(0));
      // And it can't be tapped while leaving.
      await t.tap(find.text('A'), warnIfMissed: false);
      expect(tappedA, 0);

      await t.pumpAndSettle();
      expect(find.text('A'), findsNothing);
      expect(inits['B'], 1);
    });
  });

  group('ContentReveal', () {
    testWidgets('skeleton fades through to content, and a refresh does not replay it', (t) async {
      final inits = <String, int>{};
      Widget slot(Widget child) => _host(ListView(children: [ContentReveal(child: child)]));

      await t.pumpWidget(slot(const SkeletonList(count: 3)));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(SkeletonCard), findsNWidgets(3));

      await t.pumpWidget(slot(_Probe('data', inits)));
      await t.pump(const Duration(milliseconds: 50));
      // Mid-switch: skeleton still fading out, content not shown yet.
      expect(find.byType(SkeletonCard), findsNWidgets(3));
      await t.pumpAndSettle();
      expect(find.byType(SkeletonCard), findsNothing);
      expect(find.text('data'), findsOneWidget);
      expect(inits['data'], 1);

      // Same kind of widget again (a data refresh) updates in place.
      await t.pumpWidget(slot(_Probe('data', inits)));
      await t.pump();
      expect(inits['data'], 1);
      expect(t.takeException(), isNull);
    });
  });

  group('Buttons', () {
    testWidgets('busy PrimaryButton keeps its size, shows a spinner and ignores taps', (t) async {
      var taps = 0;
      Widget btn(bool busy) => _host(Center(child: SizedBox(width: 300,
          child: PrimaryButton('Save', onTap: () => taps++, busy: busy))));
      await t.pumpWidget(btn(false));
      final idle = t.getSize(find.byType(PrimaryButton));
      await t.pumpWidget(btn(true));
      // A spinning indicator never "settles", so pump a fixed 400ms.
      for (var i = 0; i < 25; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.getSize(find.byType(PrimaryButton)), idle);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byType(PrimaryButton));
      expect(taps, 0);
      await t.pumpWidget(btn(false));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      expect(taps, 1);
    });

    testWidgets('SecondaryButton locks when its partner is busy', (t) async {
      var taps = 0;
      await t.pumpWidget(_host(const Center(child: SecondaryButton('Draft', onTap: null, icon: Icons.edit))));
      await t.tap(find.text('Draft'));
      expect(taps, 0);
      await t.pumpWidget(_host(Center(child: SecondaryButton('Draft', onTap: () => taps++))));
      await t.pumpAndSettle();
      await t.tap(find.text('Draft'));
      expect(taps, 1);
    });
  });

  group('Components', () {
    testWidgets('AppChip and ChipBar lay out at large text', (t) async {
      await t.pumpWidget(_host(
        ChipBar(chips: [
          AppChip('All', selected: true, count: 12, onTap: () {}),
          AppChip('On-track', selected: false, onTap: () {}),
          AppChip('No PM', selected: false, count: 2, tint: BT.coral, icon: Icons.person_off_rounded, onTap: () {}),
        ]),
        textScale: 1.4,
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('SegmentTabs slides to the tapped tab and reports it', (t) async {
      var index = 0;
      await t.pumpWidget(_host(StatefulBuilder(builder: (ctx, set) => SegmentTabs(
            labels: const ['Overview', 'Pipeline', 'Materials', 'Record'],
            index: index,
            onChanged: (i) => set(() => index = i),
          ))));
      await t.pumpAndSettle();
      await t.tap(find.text('Materials'));
      await t.pumpAndSettle();
      expect(index, 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('SegmentTabs scrolls when wider than a small phone at large text', (t) async {
      await t.pumpWidget(_host(SegmentTabs(
            labels: const ['Overview', 'Pipeline', 'Materials', 'Record'], index: 3, onChanged: (_) {}),
          size: const Size(320, 600), textScale: 1.6));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('AppCard with onTap is pressable', (t) async {
      var taps = 0;
      await t.pumpWidget(_host(Center(child: AppCard(onTap: () => taps++, child: const Text('card')))));
      await t.tap(find.text('card'));
      await t.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('app sheet opens with its content and closes', (t) async {
      await t.pumpWidget(_host(Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () => showAppSheet<void>(context: ctx, builder: (_) => const Text('sheet body')),
            child: const Text('open'),
          ),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('sheet body'), findsOneWidget);
      await t.tapAt(const Offset(195, 40));
      await t.pumpAndSettle();
      expect(find.text('sheet body'), findsNothing);
    });
  });
}

/// Counts how many times a tab body is created, so tests can tell "kept alive
/// while fading" apart from "rebuilt from scratch".
class _Probe extends StatefulWidget {
  final String id;
  final Map<String, int> inits;
  final VoidCallback? onTap;
  const _Probe(this.id, this.inits, {this.onTap});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.inits[widget.id] = (widget.inits[widget.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: GestureDetector(onTap: widget.onTap, child: Text(widget.id)));
}
