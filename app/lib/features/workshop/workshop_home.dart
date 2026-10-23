import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/role_header.dart';
import '../../shared/animations.dart';
import 'task_detail.dart';
import 'scan_install.dart';

/// Workshop shell — Tasks · Parts · Week. Hero #2 install side + submit-for-approval.
class WorkshopHome extends ConsumerStatefulWidget {
  const WorkshopHome({super.key});
  @override
  ConsumerState<WorkshopHome> createState() => _WorkshopHomeState();
}

class _WorkshopHomeState extends ConsumerState<WorkshopHome> {
  int _tab = 0;
  static const _labels = ['Tasks', 'Parts', 'Week'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: TabSwitcher(index: _tab, child: const <Widget>[
        _TasksTab(), _PartsTab(), _WeekTab(),
      ][_tab])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.checklist_rounded, Icons.inventory_2_rounded, Icons.calendar_today_rounded],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        actionIcon: Icons.qr_code_scanner_rounded,
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanInstall())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 110); // bottom clears the floating nav (extendBody)

Widget _wsHeader(BuildContext context, String title) =>
    FadeSlideIn(child: RoleHeader(role: 'workshop', eyebrow: 'Workshop', title: title));

({String label, Color color}) _taskPill(String s) => switch (s) {
  'in_progress' => (label: 'In progress', color: BT.amber),
  'done'        => (label: 'Done', color: BT.lime),
  'rework'      => (label: 'Rework', color: BT.coral),
  _             => (label: 'Queued', color: BT.sky),
};

// ───────────────────────────────────────────────────────────── TASKS

class _TasksTab extends ConsumerWidget {
  const _TasksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myTasksProvider);
    // A worker holds work items, not stages (0033). With open items below,
    // "No tasks assigned" above them read as "you have nothing to do".
    final hasWorkItems = ref.watch(myStageTasksProvider).valueOrNull
        ?.any((i) => !i.task.isDone) ?? false;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myStageTasksProvider);
        return ref.refresh(myTasksProvider.future);
      },
      child: tasks.when(
        loading: () => ListView(padding: _pad, children: [
          _wsHeader(context, 'My Tasks'), const SizedBox(height: 20),
          const SkeletonList(count: 4),
        ]),
        error: (e, _) => ListView(padding: _pad, children: [
          _wsHeader(context, 'My Tasks'), const SizedBox(height: 20),
          ErrorCard('Could not load tasks.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(myTasksProvider)),
        ]),
        data: (list) {
          // A stage on a truck that has already gone out is a record, not work.
          // fn_mark_delivered(force) leaves open stages open on purpose, and
          // they used to sit at the top of this list forever with a live
          // "Start work" button on a customer's truck.
          final live = list.where((t) => !t.isDelivered).toList();
          final active = live.where((t) =>
              !t.isWaitingOnEarlierWork &&
              (t.status == 'in_progress' || t.status == 'rework')).toList();
          final next   = live.where((t) =>
              !t.isWaitingOnEarlierWork && t.status == 'todo').toList();
          // A build runs in steps (0031), so some of what is assigned to this
          // person genuinely cannot be picked up yet. Showing it in "Up next"
          // read as work they were ignoring.
          final waiting = live.where((t) => t.isWaitingOnEarlierWork).toList();
          final closed = list.where((t) => t.isDelivered && t.status != 'done').toList();

          // SliverList, not Column: a fitter on eight builds had every card
          // built up front, off-screen ones included.
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _wsHeader(context, 'My Tasks'),
                const SizedBox(height: 20),
                if (list.isEmpty && !hasWorkItems)
                  const EmptyState(icon: Icons.checklist_rounded, tint: BT.amber,
                    title: 'No tasks assigned',
                    subtitle: 'Stages your PM assigns to you will show here.')
                else if (active.isEmpty && next.isEmpty && !hasWorkItems)
                  const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                    title: 'All done', subtitle: 'No active or queued stages right now.'),
                if (active.isNotEmpty) const SectionLabel('In progress'),
              ]))),
            // Sorted worst-first by the repository (rework, then overdue, then
            // due soonest) so the cards nearest the top are the ones that need
            // the person today — `ord` used to interleave builds meaninglessly.
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: active.length,
                itemBuilder: (ctx, i) => _bigCard(ctx, active[i]))),
            if (next.isNotEmpty) SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const SectionLabel('Up next'))),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: next.length,
                itemBuilder: (ctx, i) => _row(ctx, next[i]))),
            // A worker is not the assignee of a stage — their supervisor is —
            // so none of their actual jobs are in the list above. This is what
            // they open the app for.
            SliverToBoxAdapter(child: _MyWorkItems(ref: ref)),
            if (waiting.isNotEmpty) ...[
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionLabel('Waiting on earlier work'),
                  const Padding(padding: EdgeInsets.only(bottom: 10, left: 2),
                    child: Text('Yours, but the build has not reached them yet.',
                      style: TextStyle(fontSize: 12, color: BT.mut))),
                ]))),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: waiting.length,
                  itemBuilder: (ctx, i) => _row(ctx, waiting[i]))),
            ],
            if (closed.isNotEmpty) ...[
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionLabel('Delivered with this stage open'),
                  const Padding(padding: EdgeInsets.only(bottom: 10, left: 2),
                    child: Text('Kept as a record. Talk to your PM if work is still needed.',
                      style: TextStyle(fontSize: 12, color: BT.mut))),
                ]))),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: closed.length,
                  itemBuilder: (ctx, i) => _row(ctx, closed[i]))),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ]);
        },
      ),
    );
  }

  Widget _bigCard(BuildContext context, WorkshopTask t) {
    final p = _taskPill(t.status);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: PressableScale(pressedScale: 0.98, haptic: true, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t))),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFFBF4E4), Color(0xFFFBFAF5)]),
          borderRadius: BorderRadius.circular(BT.radiusCard), border: Border.all(color: const Color(0xFFF0E4C8)),
          boxShadow: const [BoxShadow(color: Color(0x11695228), blurRadius: 24, offset: Offset(0, 12))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusPill(t.awaitingApproval ? 'Awaiting approval' : p.label,
              color: t.awaitingApproval ? BT.amber : p.color),
            if (t.isOverdue) ...[
              const SizedBox(width: 7),
              const StatusPill('Overdue', color: BT.coral),
            ],
          ]),
          const SizedBox(height: 12),
          Text(t.stageName, style: display(21, w: FontWeight.w600)),
          const SizedBox(height: 3),
          Text('${t.projectCode} · ${t.projectName}', style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          // The PM's reason for sending it back, right where the work is picked up.
          if (t.status == 'rework' && t.reworkNote != null) ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(11)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.rate_review_rounded, size: 14, color: BT.coral),
                const SizedBox(width: 7),
                Expanded(child: Text(t.reworkNote!, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.3))),
              ])),
          ],
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            if (t.assignedDue != null)
              Text('Due ${DateFormat('d MMM').format(t.assignedDue!)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: t.isOverdue ? BT.coral : BT.mut))
            else const SizedBox.shrink(),
            const Row(children: [
              Text('Open task', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Icon(Icons.arrow_forward_rounded, size: 16),
            ]),
          ]),
        ]),
      ),
    ));
  }

  Widget _row(BuildContext context, WorkshopTask t) => Padding(padding: const EdgeInsets.only(bottom: 11),
    child: PressableScale(pressedScale: 0.98, haptic: true, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t))),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.stageName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text([
            t.projectCode,
            if (t.isWaitingOnEarlierWork) t.waitingLabel.toLowerCase()
            else if (t.assignedDue != null) 'due ${DateFormat('d MMM').format(t.assignedDue!)}',
          ].join(' · '), style: TextStyle(
            color: t.isOverdue && !t.isWaitingOnEarlierWork ? BT.coral : BT.mut, fontSize: 12,
            fontWeight: t.isOverdue && !t.isWaitingOnEarlierWork
              ? FontWeight.w600 : FontWeight.normal)),
        ])),
        StatusPill(
          t.awaitingApproval ? 'Awaiting approval'
            : t.isWaitingOnEarlierWork ? 'Locked'
            : 'Queued',
          color: t.awaitingApproval ? BT.amber
            : t.isWaitingOnEarlierWork ? BT.card2
            : BT.sky),
      ])),
    ));
}

// ───────────────────────────────────────────────────────────── PARTS

class _PartsTab extends ConsumerWidget {
  const _PartsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = ref.watch(workshopPartsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(workshopPartsProvider.future),
      child: parts.when(
        loading: () => ListView(padding: _pad, children: [
          _wsHeader(context, 'Components'), const SizedBox(height: 16),
          const SkeletonList(count: 4),
        ]),
        error: (e, _) => ListView(padding: _pad, children: [
          _wsHeader(context, 'Components'), const SizedBox(height: 16),
          ErrorCard('Could not load.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(workshopPartsProvider)),
        ]),
        data: (list) {
          // Reserved is not installed.
          //
          // Store's intake *earmarks* a part for a build (0026): it stays on
          // the shelf as `in_stock` while naming the truck it was bought for.
          // This list filters on the build alone, so those rows arrived here
          // looking exactly like parts already fitted — on a tab whose empty
          // state claimed "parts you scan-to-install appear here".
          final fitted   = list.where((c) => c.isFitted).toList();
          final reserved = list.where((c) => c.isReserved).toList();

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _wsHeader(context, 'Components'),
                const SizedBox(height: 16),
                if (list.isEmpty)
                  const EmptyState(icon: Icons.inventory_2_outlined, tint: BT.sky,
                    title: 'No parts yet',
                    subtitle: 'Parts fitted to your builds — and parts Store has set '
                              'aside for them — show up here.'),
                if (fitted.isNotEmpty) SectionLabel('Fitted · ${fitted.length}'),
              ]))),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: fitted.length,
                itemBuilder: (_, i) => _partCard(fitted[i]))),
            if (reserved.isNotEmpty) SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionLabel('Waiting in store · ${reserved.length}'),
                const Padding(padding: EdgeInsets.only(bottom: 10, left: 2),
                  child: Text('Set aside for your builds. Scan one into a stage to fit it.',
                    style: TextStyle(fontSize: 12, color: BT.mut))),
              ]))),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: reserved.length,
                itemBuilder: (_, i) => _partCard(reserved[i], reserved: true))),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ]);
        },
      ),
    );
  }

  Widget _partCard(ComponentRow c, {bool reserved = false}) {
    // One warranty definition, app-wide. This read `c.warrantyActive`, which
    // compared a date-only column against `DateTime.now()` — so a part whose
    // cover ended today showed "Expired" all through its own last day. The
    // third copy of the bug 0026 fixed in the other two.
    final w = switch (c.warrantyState) {
      'active'   => (label: 'In wty', color: BT.lime),
      'expiring' => (label: 'Wty ending', color: BT.amber),
      'expired'  => (label: 'Expired', color: BT.coral),
      _          => (label: 'No wty', color: BT.mut2),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 11),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(children: [
          Container(width: 46, height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: reserved ? BT.card2 : BT.sky,
              borderRadius: BorderRadius.circular(14),
              border: reserved ? Border.all(color: BT.line) : null),
            child: Icon(reserved ? Icons.schedule_rounded : Icons.memory_rounded,
              size: 21, color: reserved ? BT.mut : const Color(0xFF123040))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.model.isEmpty ? c.name : '${c.name} · ${c.model}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text([
              c.serial,
              if (c.projectCode != null) c.projectCode!,
              if (c.isFitted && c.installDate != null)
                'fitted ${DateFormat('d MMM').format(c.installDate!)}',
            ].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 11.5)),
          ])),
          const SizedBox(width: 8),
          StatusPill(w.label, color: w.color),
        ])));
  }
}

// ───────────────────────────────────────────────────────────── WEEK

class _WeekTab extends ConsumerWidget {
  const _WeekTab();

  /// "My Week" showed `myTasksProvider` in full — every stage, including ones
  /// already approved, with no date filter, no order, and no overdue flag. It
  /// was the Tasks tab again with worse cards, and on a long-running build it
  /// filled with finished work.
  ///
  /// These are the same five buckets the PM's Schedule uses, which is the point:
  /// the fitter and their PM should be looking at the week the same way.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myTasksProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myTasksProvider.future),
      child: tasks.when(
        loading: () => ListView(padding: _pad, children: [
          _wsHeader(context, 'My Week'), const SizedBox(height: 16),
          const SkeletonList(count: 4),
        ]),
        error: (e, _) => ListView(padding: _pad, children: [
          _wsHeader(context, 'My Week'), const SizedBox(height: 16),
          ErrorCard('Could not load.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(myTasksProvider)),
        ]),
        data: (all) {
          // Locked stages are kept out of the date buckets on purpose. A stage
          // whose turn has not come can be "overdue" on the plan, but putting
          // it in Overdue reads as the fitter being behind on something they
          // are not allowed to touch.
          final open = all.where((t) =>
              !t.isClosed && !t.awaitingApproval && !t.isWaitingOnEarlierWork).toList();
          final blocked = all.where((t) => t.isWaitingOnEarlierWork).toList();
          final overdue = open.where((t) => t.isOverdue).toList();
          final today   = open.where((t) => t.isDueToday).toList();
          final soon    = open.where((t) {
            final d = t.daysLeft; return d != null && d > 0 && d <= 7;
          }).toList();
          final later   = open.where((t) {
            final d = t.daysLeft; return d != null && d > 7;
          }).toList();
          final undated = open.where((t) => t.daysLeft == null).toList();
          final waiting = all.where((t) => t.awaitingApproval).toList();

          final groups = <({String label, Color tint, List<WorkshopTask> items})>[
            (label: 'Overdue', tint: BT.coral, items: overdue),
            (label: 'Due today', tint: BT.amber, items: today),
            (label: 'Next 7 days', tint: BT.lime, items: soon),
            (label: 'Later', tint: BT.sky, items: later),
            (label: 'No date set', tint: BT.card2, items: undated),
            (label: 'With your PM', tint: BT.lav, items: waiting),
            (label: 'Waiting on earlier work', tint: BT.card2, items: blocked),
          ].where((g) => g.items.isNotEmpty).toList();

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _wsHeader(context, 'My Week'),
                const SizedBox(height: 16),
                if (groups.isEmpty)
                  const EmptyState(icon: Icons.calendar_today_rounded, tint: BT.sky,
                    title: 'Nothing scheduled',
                    subtitle: 'Stages your PM assigns you, with their dates, show up here.')
                else _weekStrip(overdue.length, today.length, soon.length),
              ]))),
            for (final g in groups) ...[
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SectionLabel('${g.label} · ${g.items.length}'))),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: g.items.length,
                  itemBuilder: (ctx, i) => _weekCard(ctx, g.items[i], g.tint))),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ]);
        },
      ),
    );
  }

  /// The shape of the week in one line, before the lists.
  Widget _weekStrip(int overdue, int today, int soon) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Expanded(child: _tile('Overdue', overdue, BT.coral)),
      const SizedBox(width: 10),
      Expanded(child: _tile('Today', today, BT.amber)),
      const SizedBox(width: 10),
      Expanded(child: _tile('This week', soon, BT.lime)),
    ]),
  );

  Widget _tile(String label, int n, Color tint) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$n', style: display(21, w: FontWeight.w600)),
      const SizedBox(height: 1),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BT.ink)),
    ]),
  );

  Widget _weekCard(BuildContext context, WorkshopTask t, Color tint) {
    final p = _taskPill(t.status);
    return Padding(padding: const EdgeInsets.only(bottom: 11),
      child: PressableScale(pressedScale: 0.98, haptic: true,
        // These cards did nothing when tapped — a list of your own work that
        // you cannot open from.
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TaskDetailScreen(task: t)));
        },
        child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(width: 4, height: 34,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t.projectCode} · ${t.stageName}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text([
                t.projectName,
                if (t.assignedDue != null)
                  t.isOverdue
                    ? 'was due ${DateFormat('d MMM').format(t.assignedDue!)}'
                    : 'due ${DateFormat('d MMM').format(t.assignedDue!)}',
              ].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12,
                  color: t.isOverdue ? BT.coral : BT.mut)),
            ])),
            const SizedBox(width: 8),
            StatusPill(t.awaitingApproval ? 'Awaiting approval' : p.label,
              color: t.awaitingApproval ? BT.amber : p.color),
          ]))));
  }
}

/// The work items assigned to me, across every build (0033).
///
/// A workshop stage belongs to the supervisor the PM handed it to; the people
/// actually doing the jobs hold *items* inside it. Without this they would open
/// the app to an empty Tasks tab while having a fortnight of work in front of
/// them.
class _MyWorkItems extends ConsumerWidget {
  final WidgetRef ref;
  const _MyWorkItems({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final async = ref.watch(myStageTasksProvider);
    return async.when(
      // Quiet while loading: the stage list above already shows a skeleton,
      // and two shimmer blocks stacked read as a broken screen.
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: ErrorCard('Could not load your work items.\n${friendlyError(e)}',
          onRetry: () => ref.invalidate(myStageTasksProvider)),
      ),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final open = items.where((i) => !i.task.isDone).toList();
        if (open.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionLabel('My work items · ${open.length}'),
            for (final i in open) _card(context, i),
          ]),
        );
      },
    );
  }

  Widget _card(BuildContext context, MyStageTask i) {
    final t = i.task;
    final tone = i.isLocked
        ? (label: 'Waiting', color: BT.card2)
        : t.isActive
            ? (label: 'In progress', color: BT.amber)
            : (label: 'To do', color: BT.sky);

    return Padding(padding: const EdgeInsets.only(bottom: 11),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 3),
            Text('${i.projectCode} · ${i.stageName}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: BT.mut)),
            if (i.isLocked) ...[
              const SizedBox(height: 4),
              Text('Waiting on ${i.blockedBy ?? 'earlier work'}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: BT.mut2)),
            ],
          ])),
          const SizedBox(width: 10),
          // Start / Finish right here: this is the whole screen for somebody
          // whose day is four of these.
          if (!i.isLocked)
            StageTaskMoveButton(task: t, stageId: t.stageId)
          else
            StatusPill(tone.label, color: tone.color),
        ])),
    );
  }
}
