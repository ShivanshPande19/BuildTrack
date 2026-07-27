import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import 'models.dart';

/// Emits on every auth change (sign in/out, token refresh, user update).
final authStateProvider = StreamProvider<AuthState>((ref) => sb.auth.onAuthStateChange);

/// The signed-in user's role, fetched once and cached for the session.
/// Re-fetches automatically when auth changes (e.g. a different user logs in),
/// so screens never show a stale or flickering role.
final myRoleProvider = FutureProvider<String?>((ref) {
  ref.watch(authStateProvider); // invalidate + refetch on auth change
  return fetchMyRole();
});

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
        .select('id,name,ord,status,assignee_id,planned_start,planned_end,actual_start,actual_end')
        .eq('project_id', id).order('ord', ascending: true);
    return ProjectDetailData(
      Project.fromMap(p),
      parseDate(p['target_delivery_date']),
      (st as List).map((e) => Stage.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }

  // ── Hero #1: project requirements (customizable) ──────────────────
  Future<List<Requirement>> requirements(String projectId) async {
    final d = await sb.from('procurement_requirements')
        .select('id,item_catalog_id,qty,needed_by_date,order_by_date,status,item_catalog(name)')
        .eq('project_id', projectId)
        .order('order_by_date', ascending: true);
    return (d as List).map((e) => Requirement.fromMap(e as Map<String, dynamic>)).toList();
  }

  String? _dateStr(DateTime? d) => d?.toIso8601String().split('T').first;

  Future<void> addRequirement({
    required String projectId, required String itemId, required int qty, DateTime? neededBy,
  }) async {
    await sb.from('procurement_requirements').insert({
      'project_id': projectId, 'item_catalog_id': itemId, 'qty': qty,
      'needed_by_date': _dateStr(neededBy), 'status': 'pending',
    });
    await sb.rpc('fn_recompute_schedule', params: {'p_project': projectId}); // fills order_by
  }

  Future<void> updateRequirement({
    required String id, required String projectId, int? qty, DateTime? neededBy,
  }) async {
    final patch = <String, dynamic>{};
    if (qty != null) patch['qty'] = qty;
    if (neededBy != null) patch['needed_by_date'] = _dateStr(neededBy);
    if (patch.isNotEmpty) await sb.from('procurement_requirements').update(patch).eq('id', id);
    await sb.rpc('fn_recompute_schedule', params: {'p_project': projectId});
  }

  Future<void> deleteRequirement(String id) async {
    await sb.from('procurement_requirements').delete().eq('id', id);
  }

  /// Everything for a single stage: assignee, checklist, photos, installed parts, delays.
  Future<StageBundle> stageBundle(String stageId) async {
    final checklist = await sb.from('checklist_items')
        .select('id,label,done').eq('stage_id', stageId).order('id', ascending: true);
    final photos = await sb.from('attachments')
        .select('file_url,caption')
        .eq('owner_type', 'stage').eq('owner_id', stageId)
        .order('created_at', ascending: true);
    final parts = await sb.from('component_instances')
        .select('serial_number,status,install_date,warranty_end,item_catalog(name,model),vendors(name)')
        .eq('installed_stage_id', stageId);
    final delays = await sb.from('delay_logs')
        .select('reason_code,days_delayed,note').eq('stage_id', stageId);

    // assignee name (best-effort)
    String? assignee;
    final srow = await sb.from('stages').select('assignee_id').eq('id', stageId).maybeSingle();
    final aid = srow?['assignee_id'] as String?;
    if (aid != null) {
      final pr = await sb.from('profiles').select('full_name').eq('id', aid).maybeSingle();
      assignee = pr?['full_name'] as String?;
    }

    return StageBundle(
      assignee: assignee,
      checklist: (checklist as List).map((e) => ChecklistItem.fromMap(e as Map<String, dynamic>)).toList(),
      photos: (photos as List).map((e) => StagePhoto.fromMap(e as Map<String, dynamic>)).toList(),
      parts: (parts as List).map((e) => StagePart.fromMap(e as Map<String, dynamic>)).toList(),
      delays: (delays as List).map((e) => StageDelay.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// Procurement actions (Hero #1).
class ProcurementRepo {
  Future<List<OrderDue>> toOrder() async {
    final data = await sb.from('v_order_due').select();
    return (data as List).map((e) => OrderDue.fromMap(e as Map<String, dynamic>)).toList();
  }

  static const _poSelect =
      'id,po_number,status,order_date,expected_date,vendors(name),projects(code),po_lines(id)';

  /// All purchase orders (newest first).
  Future<List<PurchaseOrder>> purchaseOrders() async {
    final d = await sb.from('purchase_orders').select(_poSelect).order('po_number', ascending: false);
    return (d as List).map((e) => PurchaseOrder.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// One PO with its line items.
  Future<PoDetail> poDetail(String id) async {
    final po = await sb.from('purchase_orders').select(_poSelect).eq('id', id).single();
    final lines = await sb.from('po_lines')
        .select('qty,received_qty,item_catalog(name)').eq('po_id', id);
    return PoDetail(
      PurchaseOrder.fromMap(po),
      (lines as List).map((e) => PoLineItem.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Advance a PO to 'dispatched' (Procurement marks this when the vendor ships).
  Future<void> markDispatched(String poId) async {
    await sb.from('purchase_orders').update({'status': 'dispatched'}).eq('id', poId);
  }

  /// Item catalog options (for building a PO manually).
  Future<List<OptRef>> items() async {
    final d = await sb.from('item_catalog').select('id,name').order('name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['name'] ?? '') as String)).toList();
  }

  /// Add a new catalog item inline (from the New PO flow) and return it.
  Future<OptRef> createItem({required String name, String? category, int leadTimeDays = 0}) async {
    final d = await sb.from('item_catalog')
        .insert({'name': name, 'category': category, 'lead_time_days': leadTimeDays})
        .select('id,name').single();
    return OptRef(d['id'] as String, d['name'] as String);
  }

  /// Create a purchase order manually (project + vendor + line items).
  Future<void> createManualPo({
    required String projectId, required String vendorId,
    required DateTime orderDate, DateTime? expectedDate,
    required List<({String itemId, int qty})> lines,
  }) async {
    final poNum = 'PO-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final po = await sb.from('purchase_orders').insert({
      'po_number': poNum, 'vendor_id': vendorId, 'project_id': projectId, 'status': 'ordered',
      'order_date': orderDate.toIso8601String().split('T').first,
      'expected_date': expectedDate?.toIso8601String().split('T').first,
    }).select('id').single();
    final poId = po['id'] as String;
    if (lines.isNotEmpty) {
      await sb.from('po_lines').insert([
        for (final l in lines) {'po_id': poId, 'item_catalog_id': l.itemId, 'qty': l.qty},
      ]);
    }
  }

  /// Add a new vendor.
  Future<void> addVendor({required String name, String? category, int avgLead = 0}) async {
    await sb.from('vendors').insert({
      'name': name, 'category': category, 'avg_lead_time_days': avgLead, 'reliability_score': 100,
    });
  }

  /// Mark a PO received: status→received, lines fully received, GRN logged,
  /// linked requirements closed. (Store then logs individual components at intake.)
  Future<void> markReceived(String poId) async {
    await sb.from('purchase_orders').update({'status': 'received'}).eq('id', poId);
    final lines = await sb.from('po_lines').select('id,qty').eq('po_id', poId);
    for (final l in (lines as List)) {
      await sb.from('po_lines').update({'received_qty': l['qty']}).eq('id', l['id']);
    }
    await sb.from('goods_receipts').insert({'po_id': poId, 'status': 'complete'});
    await sb.from('procurement_requirements').update({'status': 'received'}).eq('po_id', poId);
  }

  /// Vendors with reliability + lead time.
  Future<List<VendorRow>> vendors() async {
    final d = await sb.from('vendors')
        .select('id,name,category,avg_lead_time_days,reliability_score')
        .order('name', ascending: true);
    return (d as List).map((e) => VendorRow.fromMap(e as Map<String, dynamic>)).toList();
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

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>(
    (ref) => ref.read(procurementRepoProvider).purchaseOrders());
final poDetailProvider = FutureProvider.family<PoDetail, String>(
    (ref, id) => ref.read(procurementRepoProvider).poDetail(id));
final vendorsProvider = FutureProvider<List<VendorRow>>(
    (ref) => ref.read(procurementRepoProvider).vendors());
final allProjectsProvider = FutureProvider<List<Project>>(
    (ref) => ref.read(projectsRepoProvider).all());
final itemsProvider = FutureProvider<List<OptRef>>(
    (ref) => ref.read(procurementRepoProvider).items());

/// Project detail (project + stages), keyed by project id.
final projectDetailProvider = FutureProvider.family<ProjectDetailData, String>(
    (ref, id) => ref.read(projectsRepoProvider).detail(id));

/// Stage detail bundle (photos + parts + checklist + delays), keyed by stage id.
final stageBundleProvider = FutureProvider.family<StageBundle, String>(
    (ref, stageId) => ref.read(projectsRepoProvider).stageBundle(stageId));

/// A project's procurement requirements (Hero #1, editable), keyed by project id.
final requirementsProvider = FutureProvider.family<List<Requirement>, String>(
    (ref, projectId) => ref.read(projectsRepoProvider).requirements(projectId));

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

/// Notifications (per-user; RLS restricts rows to the signed-in user).
class NotificationsRepo {
  Future<List<AppNotification>> all() async {
    final d = await sb.from('notifications')
        .select('id,title,body,type,read,created_at')
        .order('created_at', ascending: false);
    return (d as List).map((e) => AppNotification.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Mark every unread notification as read (RLS keeps this to the current user).
  Future<void> markAllRead() async {
    await sb.from('notifications').update({'read': true}).eq('read', false);
  }
}

final notificationsRepoProvider = Provider<NotificationsRepo>((ref) => NotificationsRepo());
final notificationsProvider = FutureProvider<List<AppNotification>>(
    (ref) => ref.read(notificationsRepoProvider).all());

final adminRepoProvider = Provider<AdminRepo>((ref) => AdminRepo());
final membersProvider   = FutureProvider<List<Member>>((ref) => ref.read(adminRepoProvider).members());
final templatesProvider = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).templates());
final clientsProvider   = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).clients());
final pmsProvider       = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).pms());
