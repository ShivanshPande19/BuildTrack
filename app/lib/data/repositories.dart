import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_client.dart';
import 'models.dart';

/// Data access — thin wrappers over Supabase queries.
class ProjectsRepo {
  Future<List<Project>> all() async {
    final data = await sb
        .from('projects')
        .select('id,code,name,status,progress_pct')
        .order('code');
    return (data as List).map((e) => Project.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Reads the v_order_due view (Hero #1: order-by alerts).
  Future<List<OrderDue>> orderDue() async {
    final data = await sb.from('v_order_due').select();
    return (data as List).map((e) => OrderDue.fromMap(e as Map<String, dynamic>)).toList();
  }
}

/// Procurement actions (Hero #1).
class ProcurementRepo {
  Future<List<OrderDue>> toOrder() async {
    final data = await sb.from('v_order_due').select();
    return (data as List).map((e) => OrderDue.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Create a PO for a due requirement + mark it ordered.
  Future<void> createPO(OrderDue d) async {
    final poNum = 'PO-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final today = DateTime.now().toIso8601String().split('T').first;
    final po = await sb.from('purchase_orders').insert({
      'po_number': poNum, 'project_id': d.projectId, 'status': 'ordered', 'order_date': today,
    }).select().single();
    await sb.from('po_lines').insert({
      'po_id': po['id'], 'item_catalog_id': d.itemCatalogId, 'qty': d.qty,
    });
    await sb.from('procurement_requirements')
        .update({'status': 'ordered', 'po_id': po['id']}).eq('id', d.id);
  }
}

// ---- Riverpod providers ----
final projectsRepoProvider = Provider<ProjectsRepo>((ref) => ProjectsRepo());
final procurementRepoProvider = Provider<ProcurementRepo>((ref) => ProcurementRepo());

final fleetProvider = FutureProvider<FleetData>((ref) async {
  final repo = ref.read(projectsRepoProvider);
  final projects = await repo.all();
  final due = await repo.orderDue();
  return FleetData(projects, due);
});

final toOrderProvider = FutureProvider<List<OrderDue>>((ref) async =>
    ref.read(procurementRepoProvider).toOrder());
