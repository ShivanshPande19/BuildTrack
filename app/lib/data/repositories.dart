import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_client.dart';
import 'models.dart';

/// Data access — thin wrappers over Supabase queries.
class ProjectsRepo {
  Future<List<Project>> all() async {
    final data = await sb
        .from('projects')
        .select('id,code,name,status,progress_pct')
        .order('code', ascending: true);
    return (data as List).map((e) => Project.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Reads the v_order_due view (Hero #1: order-by alerts).
  Future<List<OrderDue>> orderDue() async {
    final data = await sb.from('v_order_due').select();
    return (data as List).map((e) => OrderDue.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// A single project + its ordered build stages (Project detail screen).
  Future<ProjectDetailData> detail(String id) async {
    final p = await sb.from('projects')
        .select('id,code,name,status,progress_pct,target_delivery_date')
        .eq('id', id).single();
    final st = await sb.from('stages')
        .select('id,name,ord,status,planned_start,planned_end,actual_start,actual_end')
        .eq('project_id', id).order('ord', ascending: true);
    return ProjectDetailData(
      Project.fromMap(p),
      parseDate(p['target_delivery_date']),
      (st as List).map((e) => Stage.fromMap(e as Map<String, dynamic>)).toList(),
    );
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

/// Project detail (project + stages), keyed by project id.
final projectDetailProvider = FutureProvider.family<ProjectDetailData, String>(
    (ref, id) => ref.read(projectsRepoProvider).detail(id));

/// Admin actions (onboarding + option lists).
class AdminRepo {
  Future<List<OptRef>> templates() async {
    final d = await sb.from('workflow_templates').select('id,name').order('name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['name'] ?? '') as String)).toList();
  }
  Future<List<OptRef>> clients() async {
    final d = await sb.from('client_accounts').select('id,business_name').order('business_name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['business_name'] ?? '') as String)).toList();
  }
  Future<List<OptRef>> pms() async {
    final d = await sb.from('profiles').select('id,full_name').eq('role', 'pm').order('full_name', ascending: true);
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

  /// List all team members.
  Future<List<Member>> members() async {
    final d = await sb.from('profiles').select('id,full_name,email,role,status').order('full_name', ascending: true);
    return (d as List).map((e) => Member.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Invite a member via the admin-create-member Edge Function (server-side, secure).
  /// Supabase emails an invite link; the member sets their own password on arrival.
  Future<void> createMember({
    required String fullName, required String email,
    String? phone, required String role, String? businessName,
  }) async {
    final res = await sb.functions.invoke('admin-create-member', body: {
      'full_name': fullName, 'email': email,
      'phone': phone, 'role': role, 'business_name': businessName,
      'redirect_to': inviteRedirectUrl,
    });
    final data = res.data;
    if (res.status != 200 || (data is Map && data['error'] != null)) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'Failed (${res.status})');
    }
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
final membersProvider   = FutureProvider<List<Member>>((ref) => ref.read(adminRepoProvider).members());
final templatesProvider = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).templates());
final clientsProvider   = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).clients());
final pmsProvider       = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).pms());
