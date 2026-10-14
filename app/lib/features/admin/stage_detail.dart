import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';

/// Everything about one build stage of a truck: photos, installed parts
/// (traceability), checklist and any logged delays. Visible to admin/PM.
class StageDetailScreen extends ConsumerWidget {
  final Stage stage;
  final String? projectCode;
  const StageDetailScreen({super.key, required this.stage, this.projectCode});

  static final _fmt = DateFormat('d MMM');
  static final _fmtY = DateFormat('d MMM yyyy');
  String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  ({String label, Color color}) _statusPill(String s) => switch (s) {
    'done'        => (label: 'Done', color: BT.lime),
    'in_progress' => (label: 'In progress', color: BT.sky),
    'rework'      => (label: 'Rework', color: BT.coral),
    _             => (label: 'To do', color: BT.mut2),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(stageBundleProvider(stage.id));
    final s = _statusPill(stage.status);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(stageBundleProvider(stage.id).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const BackChip(),
              StatusPill(s.label, color: s.color),
            ]),
            const SizedBox(height: 14),
            if (projectCode != null)
              Text(projectCode!, style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(stage.name, style: display(27, w: FontWeight.w600)),
            const SizedBox(height: 14),

            // meta card: dates + assignee
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _metaRow('Planned', '${_d(stage.plannedStart)} → ${_d(stage.plannedEnd)}'),
                const SizedBox(height: 10),
                _metaRow('Actual', '${_d(stage.actualStart)} → ${_d(stage.actualEnd)}'),
                bundle.maybeWhen(
                  data: (b) => b.assignee == null ? const SizedBox.shrink()
                    : Padding(padding: const EdgeInsets.only(top: 10), child: _metaRow('Assignee', b.assignee!)),
                  orElse: () => const SizedBox.shrink()),
              ]),
            ),

            ContentReveal(child: bundle.when(
              loading: () => const SkeletonList(count: 3),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 16),
                child: ErrorCard('Could not load stage details.\n${friendlyError(e)}', onRetry: () => ref.invalidate(stageBundleProvider(stage.id)))),
              data: (b) => _body(context, ref, b),
            )),
          ],
        ),
      )),
    );
  }

  Widget _metaRow(String k, String v) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(k, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
    Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
  ]);

  Widget _body(BuildContext context, WidgetRef ref, StageBundle b) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // delay banner
    if (b.delays.isNotEmpty) ...[
      const SizedBox(height: 14),
      ...b.delays.map((d) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: BT.coral, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(
            'Delayed ${d.days}d · ${d.reason}${d.note != null ? ' — ${d.note}' : ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A2E18), fontWeight: FontWeight.w500))),
        ]),
      )),
    ],

    // photos
    const SectionLabel('Photos'),
    if (b.photos.isEmpty)
      const EmptyState(
        icon: Icons.photo_library_outlined, tint: BT.sky,
        title: 'No photos yet',
        subtitle: 'Workshop adds on-site photos as this stage progresses.')
    else
      SizedBox(height: 172, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: b.photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _photoCard(b.photos[i]),
      )),

    // installed parts
    const SectionLabel('Parts installed'),
    if (b.parts.isEmpty)
      const EmptyState(
        icon: Icons.inventory_2_outlined, tint: BT.lav,
        title: 'No parts logged',
        subtitle: 'Parts appear here once Store logs them and Workshop scans them in.')
    else
      ...b.parts.map(_partCard),

    // checklist
    _checklistHeader(context, ref),
    if (b.checklist.isEmpty)
      const EmptyState(
        icon: Icons.checklist_rounded, tint: BT.lime,
        title: 'No checklist items',
        subtitle: 'A workflow template fills this in when a build is onboarded. '
                  'Tap Edit to write one for this stage.')
    else
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: b.checklist.map(_checkRow).toList()),
      ),
  ]);

  /// "CHECKLIST" with an Edit affordance for the people who own it.
  ///
  /// A checklist comes from the workflow template and, until now, could never
  /// be corrected: a line written wrong once was wrong on that build forever,
  /// and there is still no screen for editing the template itself. This edits
  /// *this build's* copy — fixing a typo on a live build should not rewrite
  /// every future build, and vice versa.
  Widget _checklistHeader(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Text('CHECKLIST', style: TextStyle(fontSize: 11, letterSpacing: 1.6,
        fontWeight: FontWeight.w600, color: BT.mut)),
      // Only the PM and an admin get here; trg_guard_checklist (0028) enforces
      // it server-side regardless, because the stage's assignee also holds
      // write on these rows so they can tick them.
      Consumer(builder: (_, r, __) {
        final role = r.watch(myRoleProvider).valueOrNull;
        if (role != 'admin' && role != 'pm') return const SizedBox.shrink();
        return PressableScale(
          pressedScale: 0.97, haptic: true,
          onTap: () => _editChecklist(context, ref),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit_rounded, size: 14, color: BT.ink),
            SizedBox(width: 5),
            Text('Edit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BT.ink)),
          ]),
        );
      }),
    ]),
  );

  Future<void> _editChecklist(BuildContext context, WidgetRef ref) async {
    await showAppSheet<void>(
      context: context,
      builder: (sheetCtx) => _ChecklistEditor(stageId: stage.id, stageName: stage.name),
    );
    ref.invalidate(stageBundleProvider(stage.id));
  }

  Widget _photoCard(StagePhoto p) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(width: 232, child: Stack(fit: StackFit.expand, children: [
      Container(color: BT.card2),
      Image.network(p.url, fit: BoxFit.cover,
        loadingBuilder: (c, w, prog) => prog == null ? w
          : const Center(child: CircularProgressIndicator(color: BT.mut2, strokeWidth: 2)),
        errorBuilder: (c, e, s) => const Center(child: Icon(Icons.image_not_supported_outlined, color: BT.mut2, size: 30))),
      if (p.caption != null) Positioned(left: 0, right: 0, bottom: 0, child: Container(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)])),
        child: Text(p.caption!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
    ])),
  );

  Widget _partCard(StagePart p) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.model.isEmpty ? p.name : '${p.name} · ${p.model}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
          StatusPill(p.status, color: p.status == 'faulty' ? BT.coral : BT.mint),
        ]),
        const SizedBox(height: 8),
        _kv('Serial', p.serial),
        _kv('Vendor', p.vendor),
        _kv('Warranty till', p.warrantyEnd == null ? '—' : _fmtY.format(p.warrantyEnd!)),
      ]),
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(children: [
      SizedBox(width: 96, child: Text(k, style: const TextStyle(color: BT.mut, fontSize: 12.5))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _checkRow(ChecklistItem c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(children: [
      Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.done ? BT.lime : Colors.transparent, shape: BoxShape.circle,
          border: c.done ? null : Border.all(color: BT.mut2, width: 1.5)),
        child: c.done ? const Icon(Icons.check_rounded, size: 13, color: BT.ink) : null),
      const SizedBox(width: 12),
      Expanded(child: Text(c.label, style: TextStyle(fontSize: 14,
        color: c.done ? BT.ink : BT.mut,
        decoration: c.done ? TextDecoration.lineThrough : null,
        decorationColor: BT.mut2))),
    ]),
  );
}

/// Edit one stage's checklist: rename an item, add one, remove one.
///
/// Scoped to this build. The workflow template it was copied from is a
/// separate thing with no screen of its own yet — correcting a line here fixes
/// the build in front of you and leaves every other build alone, which is the
/// behaviour you want when the mistake is already costing someone time.
class _ChecklistEditor extends ConsumerStatefulWidget {
  final String stageId, stageName;
  const _ChecklistEditor({required this.stageId, required this.stageName});
  @override
  ConsumerState<_ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends ConsumerState<_ChecklistEditor> {
  final _add = TextEditingController();
  String? _busyId;      // the row currently saving
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _run(String? id, Future<void> Function() action) async {
    setState(() { _busyId = id; _adding = id == null; _error = null; });
    try {
      await action();
      ref.invalidate(stageBundleProvider(widget.stageId));
      await ref.read(stageBundleProvider(widget.stageId).future);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() { _busyId = null; _adding = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(stageBundleProvider(widget.stageId));
    final items = bundle.valueOrNull?.checklist ?? const <ChecklistItem>[];

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text('Checklist', style: display(20, w: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(widget.stageName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 12.5)),
        ),

        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text('Nothing on this checklist yet. Add the first item below.',
              style: TextStyle(color: BT.mut, fontSize: 12.5)))
        else
          Flexible(child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              for (final c in items)
                _EditableCheckRow(
                  key: ValueKey(c.id),
                  item: c,
                  busy: _busyId == c.id,
                  onRename: (v) => _run(c.id,
                    () => ref.read(workshopRepoProvider).renameCheck(c.id, v)),
                  onRemove: () => _run(c.id,
                    () => ref.read(workshopRepoProvider).removeCheck(c.id)),
                ),
            ],
          )),

        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: LabelledField('NEW ITEM', controller: _add,
            hint: 'e.g. Client signed off on the layout')),
          const SizedBox(width: 10),
          SizedBox(width: 54, height: 54, child: PressableScale(
            pressedScale: 0.94, haptic: true,
            onTap: _adding ? null : () {
              if (_add.text.trim().isEmpty) {
                setState(() => _error = 'Type the item first.');
                return;
              }
              final v = _add.text;
              _run(null, () async {
                await ref.read(workshopRepoProvider).addCheck(widget.stageId, v);
                _add.clear();
              });
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(16)),
              child: _adding
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: BT.lime))
                : const Icon(Icons.add_rounded, color: BT.lime, size: 22)),
          )),
        ]),

        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

        const SizedBox(height: 12),
        // Ticking is the assignee's job and stays on their screen; this sheet
        // is only about what the list says.
        const Text('Only the project manager and an admin can change these. '
                   'Whoever is working the stage ticks them off.',
          style: TextStyle(color: BT.mut2, fontSize: 11.5, height: 1.35)),
      ]);
  }
}

/// One editable row. The label commits on blur or submit rather than on every
/// keystroke, so a slow connection cannot turn typing into a queue of writes.
class _EditableCheckRow extends StatefulWidget {
  final ChecklistItem item;
  final bool busy;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;
  const _EditableCheckRow({super.key, required this.item, required this.busy,
    required this.onRename, required this.onRemove});
  @override
  State<_EditableCheckRow> createState() => _EditableCheckRowState();
}

class _EditableCheckRowState extends State<_EditableCheckRow> {
  late final _ctl = TextEditingController(text: widget.item.label);
  late final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() { if (!_focus.hasFocus) _commit(); });
  }

  @override
  void didUpdateWidget(covariant _EditableCheckRow old) {
    super.didUpdateWidget(old);
    // A refetch landed with a different label (someone else edited it): take it,
    // unless this field is being typed in right now.
    if (old.item.label != widget.item.label && !_focus.hasFocus) {
      _ctl.text = widget.item.label;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _ctl.text.trim();
    if (v.isEmpty) { _ctl.text = widget.item.label; return; }
    if (v != widget.item.label) widget.onRename(v);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Container(
      padding: const EdgeInsets.fromLTRB(13, 4, 6, 4),
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BT.line)),
      child: Row(children: [
        Icon(widget.item.done ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 18, color: widget.item.done ? BT.lime : BT.mut2),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _ctl,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commit(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BT.ink),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12)),
        )),
        if (widget.busy)
          const Padding(padding: EdgeInsets.all(12),
            child: SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut2)))
        else
          PressableScale(
            pressedScale: 0.88, haptic: true,
            onTap: widget.onRemove,
            child: const Padding(padding: EdgeInsets.all(10),
              child: Icon(Icons.delete_outline_rounded, size: 19, color: BT.mut2))),
      ]),
    ),
  );
}
