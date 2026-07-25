import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Procurement — To Order (Hero #1: backward-scheduled order-by alerts + create PO).
class ProcurementToOrder extends ConsumerWidget {
  const ProcurementToOrder({super.key});

  Future<void> _createPO(BuildContext context, WidgetRef ref, OrderDue d) async {
    try {
      await ref.read(procurementRepoProvider).createPO(d);
      ref.invalidate(toOrderProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PO created for ${d.itemName}'), backgroundColor: BT.ink));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: BT.coral));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(toOrderProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(toOrderProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('PROCUREMENT',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('To Order', style: display(29, w: FontWeight.w500)),
                ]),
                GestureDetector(
                  onTap: () => sb.auth.signOut().then((_) => context.go('/login')),
                  child: const CircleAvatar(radius: 21, backgroundColor: BT.lav,
                    child: Text('R', style: TextStyle(color: Color(0xFF31234A), fontWeight: FontWeight.w700))),
                ),
              ]),
              const SizedBox(height: 20),
              items.when(
                loading: () => const Padding(padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator(color: BT.ink))),
                error: (e, _) => AppCard(child: Text('Could not load.\n$e',
                  style: const TextStyle(color: BT.coral, fontSize: 13))),
                data: (list) {
                  if (list.isEmpty) {
                    return const AppCard(child: Text('Nothing to order right now. 🎉',
                      style: TextStyle(color: BT.mut, fontSize: 13)));
                  }
                  return Column(children: list.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Text(d.itemName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        StatusPill(
                          d.daysLeft <= 0 ? 'Order today' : '${d.daysLeft}d left',
                          color: d.daysLeft <= 0 ? BT.coral : (d.daysLeft <= 3 ? BT.amber : BT.lime)),
                      ]),
                      const SizedBox(height: 4),
                      Text('${d.projectCode} · order-by ${d.orderByDate?.toString().split(' ').first ?? '—'} · qty ${d.qty}',
                        style: const TextStyle(color: BT.mut, fontSize: 12.5)),
                      const SizedBox(height: 14),
                      PrimaryButton('Create Purchase Order', icon: Icons.add,
                        onTap: () => _createPO(context, ref, d)),
                    ])),
                  )).toList());
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const PillNav(
        icons: [Icons.home_rounded, Icons.receipt_long_rounded, Icons.inventory_2_rounded, Icons.storefront_rounded],
        active: 0, activeLabel: 'Home'),
    );
  }
}
