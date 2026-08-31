import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/animations.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
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

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 100); // bottom clears the floating nav (extendBody)

Widget _wsHeader(BuildContext context, String title) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('WORKSHOP',
      style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
    const SizedBox(height: 2),
    Text(title, style: display(29, w: FontWeight.w500)),
  ]),
  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
        child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
    ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Builder(builder: (_) {
        final u = sb.auth.currentUser;
        final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'A';
        return Container(width: 42, height: 42, alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFF4D07A), Color(0xFFE9B84A)])),
          child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : 'A',
            style: display(15, w: FontWeight.w600, c: const Color(0xFF4A3410))));
      }),
    ),
  ])),
]);

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
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myTasksProvider.future),
      child: ListView(padding: _pad, children: [
        _wsHeader(context, 'My Tasks'),
        const SizedBox(height: 20),
        tasks.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load tasks.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.checklist_rounded, tint: BT.amber,
                title: 'No tasks assigned', subtitle: 'Stages your PM assigns to you will show here.');
            }
            final active = list.where((t) => t.status == 'in_progress' || t.status == 'rework').toList();
            final next = list.where((t) => t.status == 'todo').toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (active.isNotEmpty) ...[
                const SectionLabel('In progress'),
                ...active.map((t) => _bigCard(context, t)),
              ],
              if (next.isNotEmpty) ...[
                const SectionLabel('Up next'),
                ...next.map((t) => _row(context, t)),
              ],
              if (active.isEmpty && next.isEmpty) const EmptyState(
                icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                title: 'All done', subtitle: 'No active or queued stages right now.'),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _bigCard(BuildContext context, WorkshopTask t) {
    final p = _taskPill(t.status);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t))),
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
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t))),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.stageName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text([
            t.projectCode,
            if (t.assignedDue != null) 'due ${DateFormat('d MMM').format(t.assignedDue!)}',
          ].join(' · '), style: TextStyle(
            color: t.isOverdue ? BT.coral : BT.mut, fontSize: 12,
            fontWeight: t.isOverdue ? FontWeight.w600 : FontWeight.normal)),
        ])),
        StatusPill(t.awaitingApproval ? 'Awaiting approval' : 'Queued',
          color: t.awaitingApproval ? BT.amber : BT.sky),
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
      child: ListView(padding: _pad, children: [
        _wsHeader(context, 'Components'),
        const SizedBox(height: 16),
        parts.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.inventory_2_outlined, tint: BT.sky,
                title: 'No parts installed', subtitle: 'Parts you scan-to-install appear here.')
            : Column(children: list.map((c) => Padding(padding: const EdgeInsets.only(bottom: 11),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14), child: Row(children: [
                  Container(width: 46, height: 46, alignment: Alignment.center,
                    decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.memory_rounded, size: 21, color: Color(0xFF123040))),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.model.isEmpty ? c.name : '${c.name} · ${c.model}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('${c.serial}${c.projectCode != null ? ' · ${c.projectCode}' : ''}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                  ])),
                  StatusPill(c.warrantyEnd == null ? 'No wty' : (c.warrantyActive ? 'In wty' : 'Expired'),
                    color: c.warrantyEnd == null ? BT.amber : (c.warrantyActive ? BT.lime : BT.coral)),
                ])))).toList()),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────── WEEK

class _WeekTab extends ConsumerWidget {
  const _WeekTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myTasksProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myTasksProvider.future),
      child: ListView(padding: _pad, children: [
        _wsHeader(context, 'My Week'),
        const SizedBox(height: 16),
        tasks.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.calendar_today_rounded, tint: BT.sky,
                title: 'Nothing scheduled', subtitle: 'Your assigned stages will show here.')
            : Column(children: list.map((t) {
                final p = _taskPill(t.status);
                return Padding(padding: const EdgeInsets.only(bottom: 11),
                  child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t.projectCode} · ${t.stageName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(t.projectName, style: const TextStyle(color: BT.mut, fontSize: 12)),
                    ])),
                    StatusPill(p.label, color: p.color),
                  ])));
              }).toList()),
        ),
      ]),
    );
  }
}
