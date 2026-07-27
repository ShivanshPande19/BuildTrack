import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Workshop — scan to install (w4): pick an in-stock component → install into a truck/stage.
class ScanInstall extends ConsumerStatefulWidget {
  final WorkshopTask? task;
  const ScanInstall({super.key, this.task});
  @override
  ConsumerState<ScanInstall> createState() => _ScanInstallState();
}

class _ScanInstallState extends ConsumerState<ScanInstall> {
  WorkshopTask? _target;

  @override
  void initState() {
    super.initState();
    _target = widget.task;
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
      await ref.read(workshopRepoProvider).installComponent(c.id, t.stageId, t.projectId);
      ref.invalidate(inStockProvider);
      ref.invalidate(workshopPartsProvider);
      ref.invalidate(stageBundleProvider(t.stageId));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text('${c.serial} installed in ${t.projectCode}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inStock = ref.watch(inStockProvider);
    final tasks = ref.watch(myTasksProvider).valueOrNull ?? [];

    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
          ]),
          const SizedBox(height: 12),
          Text('Scan to install', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Confirm which part goes into this truck.', style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 16),

          // scan placeholder
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(22),
              border: Border.all(color: BT.mut2, width: 2, style: BorderStyle.solid)),
            child: Column(children: [
              Container(width: 60, height: 60, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.qr_code_scanner_rounded, size: 28, color: BT.ink)),
              const SizedBox(height: 12),
              const Text('Scan serial / barcode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('or pick from in-stock below', style: TextStyle(color: BT.mut, fontSize: 12)),
            ]),
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
            Container(
              height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _target?.stageId, isExpanded: true,
                hint: const Text('Select your task', style: TextStyle(color: BT.mut2, fontSize: 14)),
                icon: const Icon(Icons.expand_more_rounded, color: BT.mut2),
                style: const TextStyle(color: BT.ink, fontSize: 14, fontWeight: FontWeight.w600),
                items: [for (final t in tasks) DropdownMenuItem(value: t.stageId, child: Text('${t.projectCode} · ${t.stageName}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() {
                  for (final t in tasks) { if (t.stageId == v) { _target = t; break; } }
                }),
              )),
            ),

          const SectionLabel('In-stock components'),
          inStock.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 30),
              child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not load stock.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.inventory_2_outlined, tint: BT.mint,
                  title: 'Nothing in stock', subtitle: 'Store logs components before they can be installed.')
              : Column(children: list.map((c) => Padding(padding: const EdgeInsets.only(bottom: 11),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _install(c),
                    child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14), child: Row(children: [
                      Container(width: 46, height: 46, alignment: Alignment.center,
                        decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.memory_rounded, size: 21, color: Color(0xFF123040))),
                      const SizedBox(width: 13),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.model.isEmpty ? c.name : '${c.name} · ${c.model}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('${c.serial}${c.vendorName != null ? ' · ${c.vendorName}' : ''}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                      ])),
                      const Icon(Icons.add_circle_outline_rounded, color: BT.ink),
                    ])),
                  ))).toList()),
          ),
        ],
      )),
    );
  }
}
