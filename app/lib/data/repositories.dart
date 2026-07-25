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

/// Admin actions (onboarding + option lists).
class AdminRepo {
  Future<List<OptRef>> templates() async {
    final d = await sb.from('workflow_templates').select('id,name').order('name');
    return (d as List).map((e) => OptRef(e['id'] as String, (e['name'] ?? '') as String)).toList();
  }
  Future<List<OptRef>> clients() async {
    final d = await sb.from('client_accounts').select('id,business_name').order('business_name');
    return (d as List).map((e) => OptRef(e['id'] as String, (e['business_name'] ?? '') as String)).toList();
  }
  Future<List<OptRef>> pms() async {
    final d = await sb.from('profiles').select('id,full_name').eq('role', 'pm').order('full_name');
    return (d as List).map((e) => OptRef(e['id'] as String, (e['full_name'] ?? '') as String)).toList();
  }

  /// Create a custom workflow template + its stages.
  Future<OptRef> createTemplate(String name, String? truckType, List<StageDraft> stages) async {
    final t = await sb.from('workflow_templates')
        .insert({'name': name, 'truck_type': truckType}).select('id,name').single();
    final tid = t['id'] as String;
    if (stages.isNotEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < stages.length; i++) {
        rows.add({'template_id': tid, 'name': stages[i].name, 'ord': i + 1, 'default_duration_days': stages[i].days});
      }
      await sb.from('template_stages').insert(rows);
    }
    return OptRef(tid, name);
  }

  /// Create a new client account.
  Future<OptRef> createClient(String businessName, String? phone) async {
    final c = await sb.from('client_accounts')
        .insert({'business_name': businessName, 'phone': phone}).select('id,business_name').single();
    return OptRef(c['id'] as String, c['business_name'] as String);
  }

  /// Insert a project then generate its stages + schedule (fn_onboard_project).
  Future<void> onboard({
    required String code, required String name, required String templateId,
    String? clientId, String? pmId, required DateTime target,
  }) async {
    final proj = await sb.from('projects').insert({
      'code': code, 'name': name, 'template_id': templateId,
      'client_account_id': clientId, 'pm_id': pmId,
      'target_delivery_date': target.toIso8601String().split('T').first,
    }).select('id').single();
    await sb.rpc('fn_onboard_project', params: {'p_project': proj['id']});
  }
}

final adminRepoProvider = Provider<AdminRepo>((ref) => AdminRepo());
final templatesProvider = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).templates());
final clientsProvider   = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).clients());
final pmsProvider       = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).pms());
