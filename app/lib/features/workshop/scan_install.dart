import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import '../../shared/barcode_scanner.dart';

/// Workshop — scan to install (w4): scan a part's label (or pick from in-stock)
/// → install it into a truck/stage. This is the install half of Hero #2.
class ScanInstall extends ConsumerStatefulWidget {
  final WorkshopTask? task;
  const ScanInstall({super.key, this.task});
  @override
  ConsumerState<ScanInstall> createState() => _ScanInstallState();
}

class _ScanInstallState extends ConsumerState<ScanInstall> {
  WorkshopTask? _target;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _target = widget.task;
  }

  /// Scan a label, resolve it to a part, then run the same install confirmation
  /// as tapping the part in the list.
  Future<void> _scan() async {
    if (_target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: BT.coral, content: Text('Pick a task to install into first.')));
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (code == null || !mounted) return;

    setState(() => _scanning = true);
    try {
      final c = await ref.read(workshopRepoProvider).findBySerial(code);
      if (!mounted) return;
      if (c == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral,
          content: Text('No part found for "$code". Ask Store to log it first.')));
        return;
      }
      // Only in-stock parts can be fitted; the DB enforces this too, but saying
      // it here is clearer than letting the install fail.
      if (c.status != 'in_stock') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral,
          content: Text('${c.serial} is marked "${c.status}"'
                        '${c.projectCode != null ? ' on ${c.projectCode}' : ''} — not in stock.')));
        return;
      }
      await _install(c);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral, content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _install(ComponentRow c) async {
    final t = _target;
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.coral, content: Text('Pick a task to install into first.')));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Confirm install', style: display(18, w: FontWeight.w600)),
      content: Text('Install ${c.name} (${c.serial}) into ${t.projectCode} · ${t.stageName}?',
        style: const TextStyle(fontSize: 13.5, color: BT.mut)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Install', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    ));
    if (ok != true) return;
    try {
      await ref.read(workshopRepoProvider).installComponent(c.id, t.stageId);
      ref.invalidate(inStockProvider);
      ref.invalidate(inStockForProvider);     // every build's view of stock
      ref.invalidate(reservedForProvider);
      ref.invalidate(workshopPartsProvider);
      ref.invalidate(truckComponentsProvider(t.projectId));
      ref.invalidate(stageBundleProvider(t.stageId));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text('${c.serial} installed in ${t.projectCode}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }

  /// One in-stock part, saying who it belongs to.
  ///
  /// `forThisBuild` is a part Store set aside for this truck — the one the
  /// fitter is most likely looking for. `heldElsewhere` belongs to another
  /// build: shown rather than hidden, because it is the one most likely to be
  /// reached for by mistake, and 0029 refuses the install anyway.
  Widget _stockCard(ComponentRow c, {
    required bool forThisBuild, required bool heldElsewhere,
  }) => Padding(padding: const EdgeInsets.only(bottom: 11),
    child: PressableScale(pressedScale: heldElsewhere ? 1 : 0.98, haptic: !heldElsewhere,
      onTap: () => heldElsewhere ? _sayHeld(c) : _install(c),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(children: [
          Container(width: 46, height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: heldElsewhere ? BT.card2 : (forThisBuild ? BT.lime : BT.sky),
              borderRadius: BorderRadius.circular(14),
              border: heldElsewhere ? Border.all(color: BT.line) : null),
            child: Icon(heldElsewhere ? Icons.lock_outline_rounded : Icons.memory_rounded,
              size: 21,
              color: heldElsewhere ? BT.mut
                : (forThisBuild ? BT.ink : const Color(0xFF123040)))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.model.isEmpty ? c.name : '${c.name} · ${c.model}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
              if (forThisBuild) ...[
                const SizedBox(width: 8),
                const StatusPill('For this build', color: BT.lime),
              ],
            ]),
            const SizedBox(height: 2),
            Text([
              c.serial,
              if (heldElsewhere && c.projectCode != null) 'held for ${c.projectCode}',
              if (!heldElsewhere && c.vendorName != null) c.vendorName!,
            ].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5,
                color: heldElsewhere ? BT.coral : BT.mut)),
          ])),
          Icon(heldElsewhere ? Icons.block_rounded : Icons.add_circle_outline_rounded,
            color: heldElsewhere ? BT.mut2 : BT.ink),
        ]))));

  void _sayHeld(ComponentRow c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: BT.coral,
    content: Text('${c.serial} is set aside for ${c.projectCode ?? 'another build'} — '
                  'ask Store to release it first.')));

  @override
  Widget build(BuildContext context) {
    // Scoped to the build being worked, so the parts bought for this truck
    // come first. It used to be every serialised part in the building, flat
    // and alphabetical, with the build each was earmarked for not even shown.
    final projectId = _target?.projectId;
    final inStock = ref.watch(inStockForProvider(projectId));
    final reserved = projectId == null
        ? const <String>{}
        : (ref.watch(reservedForProvider(projectId)).valueOrNull ?? const <String>{});
    // Only stages a part can actually go into. The picker offered every stage
    // the person had ever been assigned — including ones the PM had already
    // approved, which 0029 now refuses server-side, and ones sitting with the
    // PM, where adding a part changes the evidence after it was submitted.
    final tasks = (ref.watch(myTasksProvider).valueOrNull ?? const <WorkshopTask>[])
        .where((t) => !t.isClosed && !t.awaitingApproval).toList();

    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Row(children: [
            BackChip(),
          ]),
          const SizedBox(height: 12),
          Text('Scan to install', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Confirm which part goes into this truck.', style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 16),

          // real camera scan — the fast path on a workshop floor
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _scan,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: BT.ink, width: 2)),
              child: Column(children: [
                Container(width: 60, height: 60, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.qr_code_scanner_rounded, size: 28, color: BT.ink)),
                const SizedBox(height: 12),
                const Text('Scan serial / barcode',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(_scanning ? 'Looking up…' : 'or pick from in-stock below',
                  style: const TextStyle(color: BT.mut, fontSize: 12)),
              ]),
            ),
          ),

          // target task
          const SectionLabel('Install into'),
          if (widget.task != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14)),
              child: Text('${widget.task!.projectCode} · ${widget.task!.stageName}',
                style: const TextStyle(fontWeight: FontWeight.w600)))
          else
            AppSelectField<String>(
              hint: 'Select your task', title: 'Your tasks', value: _target?.stageId,
              options: [for (final t in tasks) SelectOption(t.stageId, '${t.projectCode} · ${t.stageName}')],
              onChanged: (v) => setState(() {
                for (final t in tasks) { if (t.stageId == v) { _target = t; break; } }
              }),
            ),

          const SectionLabel('In-stock components'),
          ContentReveal(child: inStock.when(
            loading: () => const SkeletonList(count: 3),
            // Retry the provider this screen actually watches — it is keyed by
            // the build being worked, so invalidating the unkeyed one did
            // nothing and the retry button looked broken.
            error: (e, _) => ErrorCard('Could not load stock.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(inStockForProvider(projectId))),
            data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.inventory_2_outlined, tint: BT.mint,
                  title: 'Nothing in stock', subtitle: 'Store logs components before they can be installed.')
              : Column(children: [
                  for (final c in list) _stockCard(c,
                    forThisBuild: reserved.contains(c.id),
                    heldElsewhere: c.isReserved && !reserved.contains(c.id)),
                ]),
          )),
        ],
      )),
    );
  }
}
