import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import '../../shared/workflow_visuals.dart';

/// The workflow builder — where an admin or a PM plans how a build runs.
///
/// It used to open pre-filled with seven stages nobody asked for and save them
/// as a chain of client inserts. Now it opens empty, or from an existing
/// workflow ("start from this one"), draws the plan as it is built — what waits
/// for what, what runs together, roughly how long it all takes — and saves the
/// whole thing in one transaction through fn_save_template (0034).
///
/// Pops with the new workflow's [OptRef], so the onboarding screen and the PM's
/// "Set up the plan" sheet can select it the moment it exists.
class CreateTemplate extends ConsumerStatefulWidget {
  /// Load this saved workflow as the starting point. The original is never
  /// changed: running builds point at its stages, so a change to a plan is a
  /// new workflow (see 0034).
  final String? startFrom;
  const CreateTemplate({super.key, this.startFrom});

  @override
  ConsumerState<CreateTemplate> createState() => _CreateTemplateState();
}

class _CreateTemplateState extends ConsumerState<CreateTemplate> {
  final _name = TextEditingController();
  final _truck = TextEditingController();
  final List<StageDraft> _stages = [];
  /// Catalogue items created inline while building, so they are pickable
  /// before the catalogue provider has refetched.
  final List<OptRef> _extraItems = [];
  String? _startedFrom;
  bool _loading = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.startFrom != null) _loadFrom(widget.startFrom!);
  }

  @override
  void dispose() {
    _name.dispose();
    _truck.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_dirty || _error != null) {
      setState(() { _dirty = true; _error = null; });
    }
  }

  Future<void> _loadFrom(String id) async {
    setState(() => _loading = true);
    try {
      final t = await ref.read(adminRepoProvider).templateDrafts(id);
      if (!mounted) return;
      setState(() {
        _stages..clear()..addAll(t.stages);
        _name.text = '${t.name} (copy)';
        _truck.text = t.truckType ?? '';
        _startedFrom = t.name;
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  // ── stage list operations ─────────────────────────────────────────────

  Future<void> _addStage() async {
    final s = StageDraft('', 3);
    setState(() { _stages.add(s); _dirty = true; _error = null; });
    // Straight into the editor: a stage with no name is not a stage yet.
    await _editStage(_stages.length - 1, isNew: true);
  }

  /// Every stage in the step directly above [index] — what this stage waits
  /// for, or joins if it runs alongside. Naming only the one stage above was
  /// wrong whenever that stage was itself running alongside another.
  List<StageDraft> _groupAbove(int index) {
    if (index == 0) return const [];
    final steps = stepsFor(_stages);
    return [for (var j = 0; j < index; j++) if (steps[j] == steps[index - 1]) _stages[j]];
  }

  Future<void> _editStage(int index, {bool isNew = false}) async {
    final stage = _stages[index];
    final removed = await Navigator.of(context).push<bool>(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black26,
      barrierDismissible: true,
      transitionDuration: Motion.base,
      reverseTransitionDuration: Motion.fast,
      pageBuilder: (_, __, ___) => _StageEditor(
        stage: stage,
        index: index,
        aboveGroup: _groupAbove(index),
        extraItems: _extraItems,
        isNew: isNew,
      ),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Motion.curve, reverseCurve: Motion.exit)),
        child: child),
    ));
    if (!mounted) return;
    setState(() {
      _dirty = true;
      // Removed, or a brand-new stage left without a name: it never existed.
      // Located by identity, not index, in case anything moved meanwhile.
      if (removed == true || (isNew && stage.name.trim().isEmpty)) {
        _stages.remove(stage);
      }
      // Whatever is first has nothing above it to run alongside.
      if (_stages.isNotEmpty) _stages.first.runsWithPrevious = false;
    });
  }

  /// [to] is already the index after removal (onReorderItem adjusts it).
  void _reorder(int from, int to) {
    setState(() {
      final s = _stages.removeAt(from);
      _stages.insert(to, s);
      if (_stages.isNotEmpty) _stages.first.runsWithPrevious = false;
      _dirty = true;
    });
    Haptic.tap();
  }

  // ── start from an existing workflow ───────────────────────────────────

  Future<void> _pickStart() async {
    final id = await showAppSheet<String>(context: context, builder: (sctx) =>
      Consumer(builder: (sctx, cref, _) {
        final list = cref.watch(workflowSummariesProvider);
        return Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Start from a workflow', style: display(21, w: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Its stages, checks, parts and jobs are copied in for you to '
                       'change. The original stays exactly as it is.',
              style: TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
            const SizedBox(height: 16),
            Flexible(child: list.when(
              loading: () => const SkeletonList(count: 3),
              error: (e, _) => ErrorCard('Could not load workflows.\n${friendlyError(e)}',
                onRetry: () => cref.invalidate(workflowSummariesProvider)),
              data: (ws) => ws.isEmpty
                ? const EmptyState(icon: Icons.account_tree_outlined, tint: BT.card2,
                    title: 'No workflows yet', subtitle: 'This will be the first one.')
                : ListView(shrinkWrap: true, children: [
                    for (final w in ws)
                      Padding(padding: const EdgeInsets.only(bottom: 9),
                        child: AppCard(
                          onTap: () => Navigator.pop(sctx, w.id),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                const SizedBox(height: 3),
                                Text('${w.stageCount} stages · ${w.stepCount} steps · ~${w.estimatedDays} days',
                                  style: const TextStyle(fontSize: 12, color: BT.mut)),
                              ])),
                            const Icon(Icons.chevron_right_rounded, color: BT.mut),
                          ]))),
                  ]),
            )),
            const SizedBox(height: 6),
          ]);
      }));
    if (id == null || !mounted) return;
    if (_stages.isNotEmpty) {
      final ok = await _confirm('Replace what you have?',
        'The stages you have added so far will be replaced by the ones from that workflow.',
        'Replace');
      if (ok != true || !mounted) return;
    }
    await _loadFrom(id);
  }

  // ── saving ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _name.text.trim();
    final unnamed = _stages.indexWhere((s) => s.name.trim().isEmpty);
    final err = name.isEmpty
        ? 'Give this workflow a name.'
        : _stages.isEmpty
            ? 'Add at least one stage.'
            : unnamed >= 0
                ? 'Stage ${unnamed + 1} needs a name.'
                : null;
    if (err != null) {
      setState(() => _error = err);
      Haptic.warn();
      return;
    }
    try {
      final created = await ref.read(adminRepoProvider)
          .saveTemplate(name, _truck.text, _stages);
      ref.invalidate(templatesProvider);
      ref.invalidate(workflowSummariesProvider);
      Haptic.confirm();
      _dirty = false;
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<bool?> _confirm(String title, String body, String yes) => showDialog<bool>(
    context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title, style: display(18, w: FontWeight.w600)),
      content: Text(body, style: const TextStyle(fontSize: 13.5, color: BT.mut, height: 1.35)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false),
          child: const Text('Keep editing', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, true),
          child: Text(yes, style: const TextStyle(color: BT.coral, fontWeight: FontWeight.w700))),
      ]));

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final steps = stepsFor(_stages);
    return PopScope(
      // A plan half-built is real work; leaving should be a decision.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirm('Leave without saving?',
          'This workflow has not been saved. Everything on this screen will be lost.',
          'Leave');
        if (leave != true || !context.mounted) return;
        setState(() => _dirty = false);
        // Navigator.pop is not held back by canPop — only the back gesture is.
        Navigator.of(context).pop();
      },
      child: Scaffold(
        bottomNavigationBar: _SummaryBar(stages: _stages, error: _error, onSave: _save),
        body: SafeArea(bottom: false, child: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: SkeletonList(count: 4))
          : CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(child: _header())),
              if (_stages.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(child: _emptyState()))
              else ...[
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                  sliver: SliverToBoxAdapter(child: Row(children: [
                    Expanded(child: SectionLabel('The flow')),
                    Text('Hold the grip to reorder',
                      style: TextStyle(fontSize: 11.5, color: BT.mut2)),
                  ]))),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverReorderableList(
                    itemCount: _stages.length,
                    onReorderItem: _reorder,
                    proxyDecorator: (child, _, anim) => AnimatedBuilder(
                      animation: anim,
                      builder: (_, c) => Transform.scale(
                        scale: 1 + 0.03 * Curves.easeOut.transform(anim.value),
                        child: Material(color: Colors.transparent,
                          elevation: 12 * anim.value,
                          shadowColor: Colors.black26,
                          borderRadius: BorderRadius.circular(18),
                          child: c)),
                      child: child),
                    itemBuilder: (_, i) => _stageRow(i, steps),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20 + StepRail.width, 2, 20, 0),
                  sliver: SliverToBoxAdapter(child: _addStageButton())),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ]),
        ),
      ),
    );
  }

  Widget _header() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const BackChip(),
      const Spacer(),
      PressableScale(
        onTap: _pickStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999),
            border: Border.all(color: BT.line)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.copy_all_rounded, size: 15, color: BT.ink),
            SizedBox(width: 6),
            Text('Start from one', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]))),
    ]),
    const SizedBox(height: 18),
    FadeSlideIn(child: Text(
      _startedFrom == null ? 'NEW WORKFLOW' : 'STARTED FROM ${_startedFrom!.toUpperCase()}',
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut,
        fontWeight: FontWeight.w700))),
    const SizedBox(height: 4),
    // The name is the title of the page, edited in place.
    FadeSlideIn(delay: Motion.stagger(1), child: TextField(
      controller: _name,
      onChanged: (_) => _touch(),
      textCapitalization: TextCapitalization.sentences,
      style: display(28, w: FontWeight.w600),
      cursorColor: BT.ink,
      decoration: InputDecoration(
        isDense: true, border: InputBorder.none,
        hintText: 'Name this workflow',
        hintStyle: display(28, w: FontWeight.w600, c: BT.mut2)),
    )),
    const SizedBox(height: 6),
    FadeSlideIn(delay: Motion.stagger(2), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.local_shipping_outlined, size: 16, color: BT.mut),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: _truck,
          onChanged: (_) => _touch(),
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 11),
            hintText: 'Truck type — optional (food truck, momo cart…)',
            hintStyle: TextStyle(fontSize: 13, color: BT.mut2)))),
      ]),
    )),
    const SizedBox(height: 10),
  ]);

  Widget _emptyState() => FadeSlideIn(delay: Motion.stagger(3), child: Container(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(BT.radiusCard),
      border: Border.all(color: BT.line)),
    child: Column(children: [
      // A tiny drawing of what is about to be built: three steps, the middle
      // one with two stages side by side.
      SizedBox(height: 76, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _ghostStep(1, 1), _ghostLink(), _ghostStep(2, 2), _ghostLink(), _ghostStep(3, 1),
      ])),
      const SizedBox(height: 16),
      Text('Plan how a build runs', style: display(19, w: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Add the stages in order. Anything that can happen at the same '
                 'time, mark as running alongside — the estimate below updates as you go.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: BT.mut, height: 1.4)),
      const SizedBox(height: 18),
      PrimaryButton('Add the first stage', icon: Icons.add_rounded, onTap: _addStage),
      const SizedBox(height: 10),
      SecondaryButton('Start from an existing workflow', icon: Icons.copy_all_rounded,
        onTap: _pickStart),
    ]),
  ));

  Widget _ghostStep(int n, int stacked) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < stacked; i++)
        Container(
          width: 44, height: 22, margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: n == 2 ? BT.sky.withValues(alpha: 0.6) : BT.card2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: BT.line)),
        ),
    ]);

  Widget _ghostLink() => Container(width: 18, height: 2, color: BT.line,
    margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _stageRow(int i, List<int> steps) {
    final s = _stages[i];
    final alongside = s.runsWithPrevious && i > 0;
    final meta = stageMeta(s);
    return KeyedSubtree(
      key: ObjectKey(s),
      child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StepRail(step: steps[i], startsStep: !alongside,
          isFirst: i == 0, isLast: i == _stages.length - 1),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PressableScale(
            onTap: () => _editStage(i),
            child: AnimatedContainer(
              duration: Motion.base, curve: Motion.move,
              padding: const EdgeInsets.fromLTRB(15, 13, 6, 13),
              decoration: BoxDecoration(
                color: BT.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: alongside ? BT.sky : BT.line,
                  width: alongside ? 1.4 : 1)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(s.name.trim().isEmpty ? 'Untitled stage' : s.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                        color: s.name.trim().isEmpty ? BT.mut2 : BT.ink))),
                    if (alongside)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: BT.sky.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999)),
                        child: const Text('Together', style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800, color: Color(0xFF123040)))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    DisciplinePill(s.discipline),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999)),
                      child: Text('${s.days} ${s.days == 1 ? 'day' : 'days'}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                  ]),
                  // On its own line: beside the pills it was cut off at
                  // "1 check · 1 part · …", hiding the jobs entirely.
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: BT.mut2)),
                  ],
                ])),
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(padding: EdgeInsets.all(10),
                    child: Icon(Icons.drag_indicator_rounded, size: 20, color: BT.mut2))),
              ]),
            ),
          ),
        )),
      ])),
    );
  }

  Widget _addStageButton() => PressableScale(
    onTap: _addStage,
    child: CustomPaint(
      painter: _DashedBorder(color: BT.mut2, radius: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 18, color: BT.ink),
          SizedBox(width: 6),
          Text('Add a stage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    ),
  );
}

/// The pinned bar: the plan's size, live, and Save.
///
/// The estimate moves as stages are grouped — two stages run alongside each
/// other and the days drop — which is the clearest way to show what grouping
/// is *for*.
class _SummaryBar extends StatelessWidget {
  final List<StageDraft> stages;
  final String? error;
  final Future<void> Function() onSave;
  const _SummaryBar({required this.stages, required this.error, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final stepCount = stepCountFor(stages);
    final days = estimatedDaysFor(stages);
    return Container(
      decoration: const BoxDecoration(color: BT.bg,
        border: Border(top: BorderSide(color: BT.line))),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: Motion.base, curve: Motion.move,
            child: error == null ? const SizedBox(width: double.infinity) : Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
                  borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: BT.coral),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!, style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.ink))),
                ]))),
          ),
          Row(children: [
            Expanded(child: FittedBox(
              fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Row(children: [
                _stat(stages.length, stages.length == 1 ? 'stage' : 'stages'),
                _dot(),
                _stat(stepCount, stepCount == 1 ? 'step' : 'steps'),
                _dot(),
                _stat(days, days == 1 ? 'day' : 'days', prefix: '~'),
              ]))),
            const SizedBox(width: 10),
            SizedBox(width: 120, child: AsyncPrimaryButton('Save',
              icon: Icons.check_rounded, bg: BT.ink, fg: Colors.white, onTap: onSave)),
          ]),
        ]),
      )),
    );
  }

  Widget _stat(int n, String label, {String prefix = ''}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      if (prefix.isNotEmpty) Text(prefix, style: display(17, w: FontWeight.w600, c: BT.mut)),
      CountUp(n, style: display(19, w: FontWeight.w700)),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(fontSize: 11.5, color: BT.mut, fontWeight: FontWeight.w600)),
    ]);

  Widget _dot() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 7),
    child: Text('·', style: TextStyle(color: BT.mut2, fontSize: 16)));
}

/// One stage, edited on its own sheet: what it is called, how long it takes,
/// who does it, what it runs alongside, and its checklist, parts and jobs.
///
/// Edits the [StageDraft] in place. Pops `true` to remove the stage.
class _StageEditor extends ConsumerStatefulWidget {
  final StageDraft stage;
  final int index;
  /// The stages of the step directly above; empty for the first stage.
  final List<StageDraft> aboveGroup;
  final List<OptRef> extraItems;
  final bool isNew;
  const _StageEditor({required this.stage, required this.index, required this.aboveGroup,
    required this.extraItems, required this.isNew});

  @override
  ConsumerState<_StageEditor> createState() => _StageEditorState();
}

class _StageEditorState extends ConsumerState<_StageEditor> {
  StageDraft get s => widget.stage;
  /// The row that should take focus as it appears — the one just added.
  Object? _focusNext;

  bool get _looksLikeWorkshop =>
      s.discipline == 'workshop' ||
      (s.discipline == null && s.name.toLowerCase().contains('workshop'));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // Above the keyboard, never under the status bar: Done stays reachable
    // while a check or a job is being typed.
    final height = (media.size.height * 0.92)
        .clamp(0.0, media.size.height - keyboard - media.viewPadding.top - 8);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: BT.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
            Expanded(child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              children: [
                Text('STAGE ${widget.index + 1}', style: const TextStyle(fontSize: 11,
                  letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w700)),
                TextFormField(
                  initialValue: s.name,
                  autofocus: widget.isNew,
                  textCapitalization: TextCapitalization.sentences,
                  style: display(24, w: FontWeight.w600),
                  cursorColor: BT.ink,
                  onChanged: (v) => setState(() => s.name = v),
                  decoration: InputDecoration(isDense: true, border: InputBorder.none,
                    hintText: 'What is this stage?',
                    hintStyle: display(24, w: FontWeight.w600, c: BT.mut2)),
                ),
                const SizedBox(height: 14),
                _basics(),
                if (widget.aboveGroup.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _alongside(),
                ],
                _section('Checklist', s.checks.length,
                  'What has to be true before the PM approves it.'),
                ..._checkRows(),
                _addRow('Add a check', () => setState(() {
                  final c = CheckDraft('');
                  s.checks.add(c);
                  _focusNext = c;
                })),
                _section('Parts', s.items.length,
                  'What it is built from. Becomes the build\'s order list.'),
                _parts(),
                _section('Jobs', s.tasks.length,
                  'The breakdown a supervisor hands out. Who does each is decided on the day.'),
                if (s.tasks.isEmpty && _looksLikeWorkshop) _standardFlowCard(),
                ..._jobRows(),
                _addRow('Add a job', () => setState(() {
                  final t = TaskDraft('');
                  s.tasks.add(t);
                  _focusNext = t;
                })),
                const SizedBox(height: 24),
                Center(child: TextButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: BT.coral),
                  label: const Text('Remove this stage',
                    style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700)))),
              ],
            )),
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: BT.line))),
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + media.padding.bottom),
              child: PrimaryButton('Done', icon: Icons.check_rounded,
                onTap: () => Navigator.pop(context, false)),
            ),
          ]),
        ),
      ),
    ));
  }

  Widget _basics() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // Days, as a stepper: a number keyboard for "4" is more friction than two taps.
    Container(
      height: 46,
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BT.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _stepBtn(Icons.remove_rounded, s.days > 1 ? () => setState(() => s.days--) : null),
        SizedBox(width: 56, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedSwap(child: Text('${s.days}', key: ValueKey(s.days),
            style: display(18, w: FontWeight.w700))),
          Text(s.days == 1 ? 'day' : 'days', style: const TextStyle(fontSize: 9.5,
            color: BT.mut, fontWeight: FontWeight.w700)),
        ])),
        _stepBtn(Icons.add_rounded, () => setState(() => s.days++)),
      ]),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final d in workflowDisciplines)
          AppChip(disciplineLabel(d),
            selected: s.discipline == d,
            icon: disciplineIcon(d),
            onTap: () => setState(() => s.discipline = s.discipline == d ? null : d)),
      ]),
      const SizedBox(height: 6),
      AnimatedSwap(child: Text(
        s.discipline == null
            ? 'None picked — worked out from the name.'
            : 'Handed to ${disciplineLabel(s.discipline).toLowerCase()} when it opens.',
        key: ValueKey(s.discipline),
        style: const TextStyle(fontSize: 11.5, color: BT.mut2))),
    ])),
  ]);

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap == null ? null : () { Haptic.tap(); onTap(); },
    child: SizedBox(width: 40, height: 46,
      child: Icon(icon, size: 18, color: onTap == null ? BT.mut2 : BT.ink)));

  Widget _alongside() => PressableScale(
    onTap: () => setState(() => s.runsWithPrevious = !s.runsWithPrevious),
    child: AnimatedContainer(
      duration: Motion.base, curve: Motion.move,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: s.runsWithPrevious ? BT.sky.withValues(alpha: 0.35) : BT.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.runsWithPrevious ? BT.sky : BT.line)),
      child: Row(children: [
        AnimatedSwitcher(
          duration: Motion.fast,
          child: Icon(s.runsWithPrevious ? Icons.call_split_rounded : Icons.arrow_downward_rounded,
            key: ValueKey(s.runsWithPrevious), size: 20, color: BT.ink)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.runsWithPrevious
              ? 'Runs alongside $_aboveNames'
              : 'Waits for $_aboveNames',
            maxLines: 3,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 2),
          Text(s.runsWithPrevious
              ? 'They all start once the step before them is approved.'
              : widget.aboveGroup.length > 1
                  ? 'Starts once all of them are approved. Tap if it happens at the same time.'
                  : 'Starts once that stage is approved. Tap if they happen at the same time.',
            style: const TextStyle(fontSize: 12, color: BT.mut, height: 1.3)),
        ])),
        Switch.adaptive(value: s.runsWithPrevious,
          activeTrackColor: BT.ink,
          onChanged: (v) => setState(() => s.runsWithPrevious = v)),
      ]),
    ),
  );

  String _name(StageDraft d) => d.name.trim().isEmpty ? 'the stage above' : d.name.trim();

  /// "Workshop" · "Workshop" and "Kitchen" · "A", "B" and "C".
  String get _aboveNames {
    final n = [for (final d in widget.aboveGroup) '"${_name(d)}"'];
    return n.length == 1 ? n.first : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
  }

  Widget _section(String label, int count, String hint) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 11,
          letterSpacing: 1.2, color: BT.mut, fontWeight: FontWeight.w700)),
        if (count > 0) ...[
          const SizedBox(width: 6),
          AnimatedSwap(child: Text('$count', key: ValueKey(count),
            style: const TextStyle(fontSize: 11, color: BT.ink, fontWeight: FontWeight.w800))),
        ],
      ]),
      const SizedBox(height: 2),
      Text(hint, style: const TextStyle(fontSize: 11.5, color: BT.mut2, height: 1.3)),
    ]),
  );

  List<Widget> _checkRows() => [
    for (final c in s.checks)
      FadeSlideIn(key: ObjectKey(c), offsetY: 8, child: _rowShell(
        leading: const Icon(Icons.check_box_outline_blank_rounded, size: 18, color: BT.mut2),
        field: TextFormField(
          initialValue: c.label,
          autofocus: identical(_focusNext, c),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => c.label = v,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none,
            hintText: 'e.g. Frame squared and welded',
            hintStyle: TextStyle(color: BT.mut2, fontSize: 13.5))),
        trailing: [
          // The camera: this check cannot be ticked without a photo (0029).
          _iconToggle(
            on: c.photoRequired,
            icon: c.photoRequired ? Icons.photo_camera_rounded : Icons.photo_camera_outlined,
            onTap: () => setState(() => c.photoRequired = !c.photoRequired)),
          _iconToggle(on: false, icon: Icons.close_rounded,
            onTap: () => setState(() => s.checks.remove(c))),
        ],
      )),
    if (s.checks.any((c) => c.photoRequired))
      const Padding(padding: EdgeInsets.only(left: 4, bottom: 6),
        child: Row(children: [
          Icon(Icons.photo_camera_rounded, size: 13, color: BT.mut2),
          SizedBox(width: 6),
          Expanded(child: Text('The fitter has to attach a photo to tick these.',
            style: TextStyle(fontSize: 11.5, color: BT.mut2))),
        ])),
  ];

  List<Widget> _jobRows() {
    final steps = stepsFromFlags([for (final t in s.tasks) t.runsWithPrevious]);
    return [
      for (var i = 0; i < s.tasks.length; i++)
        FadeSlideIn(key: ObjectKey(s.tasks[i]), offsetY: 8, child: _rowShell(
          leading: SizedBox(width: 22, child: s.tasks[i].runsWithPrevious && i > 0
            ? const Icon(Icons.subdirectory_arrow_right_rounded, size: 17, color: BT.ink)
            : Text('${steps[i]}', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: BT.mut))),
          tint: s.tasks[i].runsWithPrevious && i > 0,
          field: TextFormField(
            initialValue: s.tasks[i].title,
            autofocus: identical(_focusNext, s.tasks[i]),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) => s.tasks[i].title = v,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none,
              hintText: 'e.g. Hole drilling for electrical work',
              hintStyle: TextStyle(color: BT.mut2, fontSize: 13.5))),
          trailing: [
            if (i > 0) _iconToggle(
              on: s.tasks[i].runsWithPrevious,
              icon: Icons.call_split_rounded,
              onTap: () => setState(() =>
                s.tasks[i].runsWithPrevious = !s.tasks[i].runsWithPrevious)),
            _iconToggle(on: false, icon: Icons.close_rounded, onTap: () => setState(() {
              s.tasks.removeAt(i);
              if (s.tasks.isNotEmpty) s.tasks.first.runsWithPrevious = false;
            })),
          ],
        )),
      if (s.tasks.length > 1)
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Row(children: [
            Icon(Icons.call_split_rounded, size: 13, color: BT.mut2),
            SizedBox(width: 6),
            Expanded(child: Text('Turn this on for a job that runs alongside the one above.',
              style: TextStyle(fontSize: 11.5, color: BT.mut2))),
          ])),
    ];
  }

  Widget _rowShell({required Widget leading, required Widget field,
      required List<Widget> trailing, bool tint = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: AnimatedContainer(
      duration: Motion.base, curve: Motion.move,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: tint ? BT.sky.withValues(alpha: 0.18) : BT.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint ? BT.sky : BT.line)),
      child: Row(children: [
        leading,
        const SizedBox(width: 10),
        Expanded(child: field),
        ...trailing,
      ]),
    ),
  );

  Widget _iconToggle({required bool on, required IconData icon, required VoidCallback onTap}) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { Haptic.tap(); onTap(); },
      child: AnimatedContainer(
        duration: Motion.fast,
        width: 36, height: 36,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: on ? BT.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 17, color: on ? Colors.white : BT.mut2)));

  Widget _addRow(String label, VoidCallback onTap) => PressableScale(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(children: [
        const Icon(Icons.add_circle_outline_rounded, size: 18, color: BT.ink),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      ]),
    ),
  );

  /// The owner's workshop, one tap away — offered on a workshop stage with no
  /// jobs yet, never filled in unasked.
  Widget _standardFlowCard() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: PressableScale(
      onTap: () {
        Haptic.confirm();
        setState(() {
          s.tasks.addAll([
            for (final (title, alongside) in standardWorkshopFlow)
              TaskDraft(title, runsWithPrevious: alongside),
          ]);
          s.discipline ??= 'workshop';
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFFBF4E4), Color(0xFFFBFAF5)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0E4C8))),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.amber, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome_rounded, size: 19, color: BT.ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Use the standard workshop flow',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text('${standardWorkshopFlow.length} jobs, framework to dispatch — paint and '
                 'branding together. Change anything after.',
              style: const TextStyle(fontSize: 12, color: BT.mut, height: 1.3)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: BT.mut),
        ]),
      ),
    ),
  );

  // ── parts ─────────────────────────────────────────────────────────────

  Widget _parts() => Wrap(spacing: 7, runSpacing: 7, children: [
    for (final it in s.items)
      FadeSlideIn(key: ObjectKey(it), offsetY: 6, child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        decoration: BoxDecoration(color: BT.lav.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(it.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999)),
            child: Text('×${it.qty}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => s.items.remove(it)),
            child: const Padding(padding: EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 15, color: Color(0xFF3A2A4A)))),
        ]),
      )),
    PressableScale(
      onTap: _addItem,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999),
          border: Border.all(color: BT.line)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 15, color: BT.ink),
          SizedBox(width: 4),
          Text('Add part', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]))),
  ]);

  Future<void> _addItem() async {
    String? itemId;
    String? itemLabel;
    int qty = 1;
    // Nothing on this screen watches the catalogue, so wait for it: reading
    // `.valueOrNull` here offered an empty list the first time, every time.
    var loaded = const <OptRef>[];
    try {
      loaded = await ref.read(itemsProvider.future);
    } catch (_) {
      // Offline or refused: "Add a new part" still works.
    }
    if (!mounted) return;
    final catalog = {
      for (final o in [...loaded, ...widget.extraItems]) o.id: o,
    }.values.toList();

    await showAppSheet<void>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a part', style: display(20, w: FontWeight.w600)),
          const SizedBox(height: 14),
          AppSelectField<String>(
            value: itemId, hint: 'Choose from the catalogue', title: 'Part',
            options: [for (final o in catalog) SelectOption(o.id, o.label)],
            addLabel: 'Add a new part',
            onAdd: () async {
              final created = await _promptNewItem();
              if (created != null) {
                widget.extraItems.add(created);
                catalog.add(created);
                setS(() { itemId = created.id; itemLabel = created.label; });
              }
            },
            onChanged: (v) => setS(() {
              itemId = v;
              itemLabel = catalog.firstWhere((o) => o.id == v).label;
            }),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Text('How many', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              height: 46,
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BT.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stepBtn(Icons.remove_rounded, qty > 1 ? () => setS(() => qty--) : null),
                SizedBox(width: 34, child: Text('$qty', textAlign: TextAlign.center,
                  style: display(17, w: FontWeight.w700))),
                _stepBtn(Icons.add_rounded, () => setS(() => qty++)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          PrimaryButton('Add', icon: Icons.check_rounded, onTap: itemId == null ? null : () {
            setState(() {
              final same = s.items.where((it) => it.itemId == itemId).firstOrNull;
              if (same != null) {
                same.qty += qty;
              } else {
                s.items.add(StageItemDraft(itemId!, itemLabel ?? 'Part', qty));
              }
            });
            Navigator.pop(ctx);
          }),
          const SizedBox(height: 6),
        ])));
  }

  Future<OptRef?> _promptNewItem() {
    final nameC = TextEditingController();
    final leadC = TextEditingController();
    String? e;
    return showDialog<OptRef>(context: context, builder: (dctx) => StatefulBuilder(
      builder: (dctx, setD) => AlertDialog(
        backgroundColor: BT.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('New part', style: display(18, w: FontWeight.w600)),
        // A finite width: AlertDialog measures its body through an
        // IntrinsicWidth and an unbounded child takes it down (§3 #63).
        content: SizedBox(width: double.maxFinite, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            _dialogField(nameC, 'Part name'),
            const SizedBox(height: 10),
            _dialogField(leadC, 'Lead time (days)', number: true),
            if (e != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(e!, style: const TextStyle(color: BT.coral, fontSize: 12))),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx),
            child: const Text('Cancel', style: TextStyle(color: BT.mut))),
          TextButton(onPressed: () async {
            if (nameC.text.trim().isEmpty) { setD(() => e = 'Name required'); return; }
            try {
              final created = await ref.read(procurementRepoProvider).createItem(
                name: nameC.text.trim(), leadTimeDays: int.tryParse(leadC.text.trim()) ?? 0);
              ref.invalidate(itemsProvider);
              if (dctx.mounted) Navigator.pop(dctx, created);
            } catch (err) {
              setD(() => e = friendlyError(err));
            }
          }, child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
        ],
      ))).whenComplete(() { nameC.dispose(); leadC.dispose(); });
  }

  Widget _dialogField(TextEditingController c, String hint, {bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: TextField(controller: c, keyboardType: number ? TextInputType.number : null,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(hintText: hint, border: InputBorder.none)),
  );
}

/// A dashed rounded border — the "add here" affordance, distinct from a card.
class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorder({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color || old.radius != radius;
}
