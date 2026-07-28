import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Client — review + approve/request-changes on a design version.
class ApproveDesign extends ConsumerStatefulWidget {
  final DesignRow design;
  final String projectId;
  const ApproveDesign({super.key, required this.design, required this.projectId});
  @override
  ConsumerState<ApproveDesign> createState() => _ApproveDesignState();
}

class _ApproveDesignState extends ConsumerState<ApproveDesign> {
  bool _saving = false;

  Future<void> _decide(bool approve) async {
    setState(() => _saving = true);
    try {
      await ref.read(clientRepoProvider).decideDesign(widget.design.id, approve);
      ref.invalidate(truckDesignsProvider(widget.projectId));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text(approve ? 'Design approved 🎉' : 'Change request sent')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.design;
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
            const StatusPill('Needs approval', color: BT.amber),
          ]),
          const SizedBox(height: 14),
          Text('${d.type[0].toUpperCase()}${d.type.substring(1)} design', style: display(27, w: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('From the Azimuth design team', style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 16),

          // preview placeholder
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3EA),
              borderRadius: BorderRadius.circular(20), border: Border.all(color: BT.line)),
            child: const Center(child: Icon(Icons.image_outlined, size: 44, color: BT.mut2)),
          ),
          const SizedBox(height: 14),
          AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
            Container(width: 36, height: 36, alignment: Alignment.center,
              decoration: const BoxDecoration(color: BT.pink, shape: BoxShape.circle),
              child: const Text('N', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4A2438)))),
            const SizedBox(width: 12),
            const Expanded(child: Text('"Updated the layout as discussed — let us know if this works!"',
              style: TextStyle(fontSize: 13, height: 1.4))),
          ])),

          const SizedBox(height: 20),
          if (_saving) const Center(child: CircularProgressIndicator(color: BT.ink))
          else Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _decide(false),
              child: Container(height: 54, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.edit_rounded, size: 18, color: BT.ink), SizedBox(width: 8),
                  Text('Request changes', style: TextStyle(fontWeight: FontWeight.w600)),
                ])),
            )),
            const SizedBox(width: 11),
            Expanded(child: PrimaryButton('Approve', icon: Icons.check_rounded, onTap: () => _decide(true))),
          ]),
        ],
      )),
    );
  }
}
