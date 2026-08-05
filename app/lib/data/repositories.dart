import 'dart:typed_data';
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

/// Turns a Supabase/Postgres failure into something a human can act on.
///
/// The workflow rules live in the database (fn_assign_stage, fn_submit_stage, …)
/// and raise plain-English messages, so those are surfaced as-is. Everything
/// else gets mapped away from raw SQL codes.
String friendlyError(Object e) {
  if (e is PostgrestException) {
    final msg = e.message;
    if (e.code == '23505' || msg.contains('duplicate key')) {
      if (msg.contains('projects_code_key') || msg.contains('code')) {
        return 'That project code is already used by another build.';
      }
      return 'That record already exists.';
    }
    if (e.code == '42501' || msg.contains('row-level security')) {
      return 'You do not have permission to do that.';
    }
    if (e.code == '23503') {
      return 'Something this depends on is missing — refresh and try again.';
    }
    if (e.code == '23502') {
      return 'A required field is missing.';
    }
    return msg;
  }
  if (e is AuthException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] != null) return d['error'].toString();
    return 'Server rejected the request (${e.status}).';
  }
  return e.toString().replaceFirst('Exception: ', '');
}

/// Upload bytes to the public `builds` bucket and return the public URL.
///
/// Shared by workshop site photos (`stages/<stageId>/…`) and client ticket
/// photos (`tickets/<ticketId>/…`) — the storage policy in 0011 only lets a
/// client write under `tickets/`.
Future<String> uploadToBuilds(Uint8List bytes, {
  required String filename, required String contentType, required String folder,
}) async {
  final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safe';
  await sb.storage.from('builds').uploadBinary(
    path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true));
  return sb.storage.from('builds').getPublicUrl(path);
}

/// Data access — thin wrappers over Supabase queries.
class ProjectsRepo {
  /// pm_id comes along so Admin can spot builds with no project manager —
  /// those are stranded: no PM sees them and their stages cannot be assigned.
  static const _projectSelect = 'id,code,name,status,progress_pct,pm_id';

  Future<List<Project>> all() async {
    final data = await sb
        .from('projects')
        .select(_projectSelect)
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
        .select('$_projectSelect,target_delivery_date')
        .eq('id', id).single();
    final st = await sb.from('stages')
        .select('id,name,ord,status,assignee_id,discipline,planned_start,planned_end,'
                'actual_start,actual_end,assigned_start,assigned_due')
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

  // ── PM assigns build tasks (stages) to execution staff ─────────────
  /// The roles that actually execute build stages. A PM/admin/procurement member
  /// can never be a stage assignee (the DB enforces this too).
  static const doerRoles = ['workshop', 'design', 'store', 'service'];

  /// Members a PM can assign build stages to (the doers), active ones only.
  /// Sorted so the stage's own discipline comes first — assigning a design stage
  /// should offer designers before it offers welders.
  Future<List<Member>> assignableMembers({String? discipline}) async {
    final d = await sb.from('profiles')
        .select('id,full_name,email,role,status')
        .inFilter('role', doerRoles)
        .neq('status', 'disabled')
        .order('full_name', ascending: true);
    final list = (d as List).map((e) => Member.fromMap(e as Map<String, dynamic>)).toList();
    if (discipline != null) {
      list.sort((a, b) {
        final ra = a.role == discipline ? 0 : 1;
        final rb = b.role == discipline ? 0 : 1;
        return ra != rb ? ra - rb : a.name.compareTo(b.name);
      });
    }
    return list;
  }

  /// Assign (assigneeId) or unassign (null) a stage, optionally with the dates
  /// the PM committed to.
  ///
  /// Goes through fn_assign_stage so the server checks that the caller really is
  /// this build's PM, that the member's role matches the stage's discipline, that
  /// the account is active, and that the dates make sense — then notifies both the
  /// new and the previous assignee. Set [override] only when the PM has explicitly
  /// confirmed moving the stage to a different discipline.
  Future<void> assignStage(String stageId, String? assigneeId,
      {DateTime? start, DateTime? due, bool override = false}) async {
    await sb.rpc('fn_assign_stage', params: {
      'p_stage': stageId,
      'p_assignee': assigneeId,
      'p_start': _dateStr(start),
      'p_due': _dateStr(due),
      'p_override': override,
    });
  }

  /// Every stage across the PM's builds that still needs handing out
  /// (never assigned, or sent back for rework) — powers the Assign work screen.
  Future<List<AssignableStage>> stagesNeedingAssignment(List<Project> projects) async {
    if (projects.isEmpty) return [];
    final byId = {for (final p in projects) p.id: p};
    final d = await sb.from('stages')
        .select('id,name,ord,status,assignee_id,discipline,planned_start,planned_end,'
                'actual_start,actual_end,assigned_start,assigned_due,project_id')
        .inFilter('project_id', byId.keys.toList())
        .order('ord', ascending: true);

    final out = <AssignableStage>[];
    for (final r in (d as List)) {
      final m = r as Map<String, dynamic>;
      final s = Stage.fromMap(m);
      final p = byId[m['project_id']];
      if (p == null) continue;
      // unassigned work, plus anything the PM sent back that nobody now owns
      if (s.needsAssigning || s.status == 'rework') {
        out.add(AssignableStage(
          stage: s, projectId: p.id, projectCode: p.code, projectName: p.name));
      }
    }
    return out;
  }

  /// The builds a PM has actually put me on (I hold at least one stage).
  ///
  /// This is what "my work" means for an execution role. Screens must scope to
  /// it — otherwise every designer sees every truck in the company and can start
  /// uploading designs onto builds nobody asked them to touch.
  Future<List<Project>> myAssignedProjects() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return [];
    final d = await sb.from('stages')
        .select('project_id,projects($_projectSelect)')
        .eq('assignee_id', uid);
    final byId = <String, Project>{};
    for (final r in (d as List)) {
      final p = (r as Map<String, dynamic>)['projects'] as Map<String, dynamic>?;
      if (p != null) byId[p['id'] as String] = Project.fromMap(p);
    }
    final out = byId.values.toList()..sort((a, b) => a.code.compareTo(b.code));
    return out;
  }

  /// Change a project's target delivery date, then re-run backward scheduling.
  Future<void> setDeliveryDate(String projectId, DateTime date) async {
    await sb.from('projects')
        .update({'target_delivery_date': date.toIso8601String().split('T').first}).eq('id', projectId);
    await sb.rpc('fn_recompute_schedule', params: {'p_project': projectId});
  }

  /// Hand the truck over: the build becomes 'delivered' and enters after-sales,
  /// where the Service role picks it up. Nothing used to set actual_delivery_date,
  /// so no build could ever reach 'delivered'.
  ///
  /// fn_mark_delivered checks the caller is this build's PM (or an admin) and
  /// refuses while stages are still unapproved unless [force] is set.
  Future<void> markDelivered(String projectId, {DateTime? date, bool force = false}) async {
    await sb.rpc('fn_mark_delivered', params: {
      'p_project': projectId,
      'p_date': _dateStr(date),
      'p_force': force,
    });
  }

  // ── PM approvals: stage completions submitted by the assignee ──────
  /// Submissions waiting on the signed-in PM.
  ///
  /// fn_submit_stage stamps approver_id with the build's PM, so this filters on
  /// the server instead of pulling every pending approval in the database and
  /// sifting through it in Dart.
  Future<List<ApprovalItem>> pendingApprovals() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return [];
    final d = await sb.from('stage_approvals')
        .select('id,stage_id,status,created_at,approver_id,'
                'profiles:submitted_by(full_name),stages!inner(name,projects!inner(code))')
        .eq('status', 'pending')
        .eq('approver_id', uid)
        .order('created_at', ascending: true);

    return (d as List).map((r) {
      final st = r['stages'] as Map<String, dynamic>?;
      final pr = st?['projects'] as Map<String, dynamic>?;
      final by = r['profiles'] as Map<String, dynamic>?;
      return ApprovalItem(
        id: r['id'] as String,
        stageId: r['stage_id'] as String,
        stageName: st?['name'] as String? ?? 'Stage',
        projectCode: pr?['code'] as String? ?? '',
        submittedBy: by?['full_name'] as String?,
        submittedAt: parseDate(r['created_at']),
      );
    }).toList();
  }

  /// Approve → stage done, next stage auto-starts, client is told.
  /// Reject → stage back to rework with a reason the assignee can read.
  ///
  /// fn_decide_stage checks the caller owns the build, refuses a second decision
  /// on the same submission, stamps actual_end, pulls the next stage into
  /// progress, recomputes progress/status, and sends the notifications.
  Future<void> decideApproval(String approvalId, bool approve, {String? note}) async {
    await sb.rpc('fn_decide_stage', params: {
      'p_approval': approvalId,
      'p_approve': approve,
      'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    });
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
    for (final l in (lines as List).cast<Map<String, dynamic>>()) {
      await sb.from('po_lines').update({'received_qty': l['qty']}).eq('id', l['id'] as Object);
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
  ref.watch(authStateProvider);
  final repo = ref.read(projectsRepoProvider);
  final projects = await repo.all();
  final due = await repo.orderDue();
  return FleetData(projects, due);
});

final toOrderProvider = FutureProvider<List<OrderDue>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(procurementRepoProvider).toOrder();
});

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

/// Execution staff a PM can assign stages to (workshop/design/store/service).
final assignableMembersProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(projectsRepoProvider).assignableMembers();
});

/// Same list, but ordered so the stage's own discipline comes first.
/// Keyed by discipline ('design', 'workshop', 'store', 'service').
final assignableForDisciplineProvider =
    FutureProvider.family<List<Member>, String?>((ref, discipline) {
  ref.watch(authStateProvider);
  return ref.read(projectsRepoProvider).assignableMembers(discipline: discipline);
});

/// The builds I personally hold a stage on — "my work" for any execution role.
/// Design/Store/Service screens scope to this instead of the whole fleet.
final assignedProjectsProvider = FutureProvider<List<Project>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(projectsRepoProvider).myAssignedProjects();
});

/// Stages across the signed-in PM's builds that still need handing out.
final stagesToAssignProvider = FutureProvider<List<AssignableStage>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.read(projectsRepoProvider);
  final mine = await ref.read(pmRepoProvider).myProjects();
  return repo.stagesNeedingAssignment(mine);
});

/// Pending stage-completion approvals for the signed-in PM's projects.
final pendingApprovalsProvider = FutureProvider<List<ApprovalItem>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(projectsRepoProvider).pendingApprovals();
});

/// Store / Inventory — component traceability (Hero #2) + stock.
class StoreRepo {
  static const _compSelect =
      'id,serial_number,status,warranty_end,install_date,item_catalog_id,item_catalog(name,model),projects(code),vendors(name)';

  Future<List<ComponentRow>> components() async {
    final d = await sb.from('component_instances').select(_compSelect).order('serial_number', ascending: true);
    return (d as List).map((e) => ComponentRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<StockRow>> stock() async {
    final d = await sb.from('stock_items').select('quantity,unit,item_catalog(name,category,low_stock_threshold)');
    return (d as List).map((e) => StockRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Hero #2 — every truck that has a given item model installed.
  Future<List<RecallRow>> recall(String itemCatalogId) async {
    final d = await sb.rpc('fn_recall', params: {'p_item': itemCatalogId});
    return (d as List).map((e) => RecallRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Actually send the recall notice: every affected build's PM and client get a
  /// notification. Returns how many trucks were notified.
  ///
  /// The "Notify all N" button previously only showed a snackbar.
  Future<int> recallNotify(String itemCatalogId, {String? note}) async {
    final d = await sb.rpc('fn_recall_notify', params: {
      'p_item': itemCatalogId,
      'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    });
    return (d as num?)?.toInt() ?? 0;
  }

  /// Log a component at intake (serial + warranty + optional assign to a build).
  Future<void> logComponent({
    required String itemId, required String serial, String? vendorId,
    DateTime? warrantyEnd, String? projectId,
  }) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    await sb.from('component_instances').insert({
      'item_catalog_id': itemId,
      'serial_number': serial,
      'vendor_id': vendorId,
      'warranty_start': today,
      'warranty_end': warrantyEnd?.toIso8601String().split('T').first,
      'status': projectId != null ? 'installed' : 'in_stock',
      'installed_in_project_id': projectId,
      'install_date': projectId != null ? today : null,
    });
  }
}

final storeRepoProvider = Provider<StoreRepo>((ref) => StoreRepo());
final componentsProvider = FutureProvider<List<ComponentRow>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(storeRepoProvider).components();
});
final stockProvider = FutureProvider<List<StockRow>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(storeRepoProvider).stock();
});
final recallProvider = FutureProvider.family<List<RecallRow>, String>(
    (ref, itemId) => ref.read(storeRepoProvider).recall(itemId));

/// Workshop — stages assigned to me, install parts (Hero #2), submit for approval.
class WorkshopRepo {
  String? get _uid => sb.auth.currentUser?.id;

  /// The stages assigned to me, enriched with what the PM did with my last
  /// submission — so a task can show "waiting for approval" or the reason it
  /// was sent back instead of silently sitting there.
  Future<List<WorkshopTask>> myTasks() async {
    final uid = _uid;
    if (uid == null) return [];
    final d = await sb.from('stages')
        .select('id,name,status,project_id,assigned_due,projects(code,name)')
        .eq('assignee_id', uid).order('ord', ascending: true);
    final tasks = (d as List).map((e) => WorkshopTask.fromMap(e as Map<String, dynamic>)).toList();
    if (tasks.isEmpty) return tasks;

    final appr = await sb.from('stage_approvals')
        .select('stage_id,status,note,created_at')
        .inFilter('stage_id', tasks.map((t) => t.stageId).toList())
        .order('created_at', ascending: true);

    final pending = <String>{};
    final notes = <String, String>{};
    for (final r in (appr as List)) {
      final sid = r['stage_id'] as String;
      if (r['status'] == 'pending') {
        pending.add(sid);
      } else if (r['status'] == 'rejected') {
        final n = r['note'] as String?;
        if (n != null && n.trim().isNotEmpty) notes[sid] = n.trim();
      }
    }
    return [
      for (final t in tasks)
        t.copyWith(
          awaitingApproval: pending.contains(t.stageId),
          reworkNote: t.status == 'rework' ? notes[t.stageId] : null,
        ),
    ];
  }

  /// Mark a stage as actually started.
  ///
  /// Nothing used to make this transition, so every stage sat on 'todo' forever
  /// and the PM's "in progress today" and workload numbers were both
  /// permanently empty.
  Future<void> startTask(String stageId) async {
    await sb.rpc('fn_start_stage', params: {'p_stage': stageId});
  }

  Future<void> toggleChecklist(String id, bool done) async {
    await sb.from('checklist_items').update({'done': done}).eq('id', id);
  }

  /// Components sitting in store (available to install).
  Future<List<ComponentRow>> inStock() async {
    final d = await sb.from('component_instances').select(StoreRepo._compSelect)
        .eq('status', 'in_stock').order('serial_number', ascending: true);
    return (d as List).map((e) => ComponentRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Install a component into a truck+stage (Hero #2 install side).
  ///
  /// fn_install_component checks the part is genuinely in stock and that the
  /// caller is the member on that stage, so a mis-scan can't quietly re-install
  /// a part that is already fitted to another truck.
  Future<void> installComponent(String componentId, String stageId) async {
    await sb.rpc('fn_install_component', params: {
      'p_component': componentId, 'p_stage': stageId,
    });
  }

  /// Submit a stage completion for PM approval.
  ///
  /// fn_submit_stage addresses it to the build's PM, refuses a duplicate
  /// submission, and refuses outright if the build has no PM — which used to
  /// send the work into a black hole nobody could approve.
  Future<void> submitForApproval(String stageId) async {
    await sb.rpc('fn_submit_stage', params: {'p_stage': stageId});
  }

  /// Attach a real site photo to a stage.
  ///
  /// This used to insert a random `picsum.photos` URL — the client's build
  /// gallery was showing stock photography. Now the bytes go to the public
  /// `builds` bucket (0011) and the attachment points at them.
  Future<void> addStagePhoto(String stageId, Uint8List bytes, {
    required String filename, required String contentType, String? caption,
  }) async {
    final url = await uploadToBuilds(bytes,
      filename: filename, contentType: contentType, folder: 'stages/$stageId');
    await sb.from('attachments').insert({
      'owner_type': 'stage', 'owner_id': stageId, 'uploaded_by': _uid,
      'file_url': url,
      'caption': (caption == null || caption.trim().isEmpty) ? 'Work photo' : caption.trim(),
    });
  }

  /// Find a part by the serial the camera just read.
  ///
  /// Case-insensitive and whitespace-tolerant, because a scan can pick up
  /// padding and labels aren't consistent about case.
  Future<ComponentRow?> findBySerial(String serial) async {
    final q = serial.trim();
    if (q.isEmpty) return null;
    final d = await sb.from('component_instances')
        .select(StoreRepo._compSelect)
        .ilike('serial_number', q)
        .limit(1);
    final list = (d as List);
    if (list.isEmpty) return null;
    return ComponentRow.fromMap(list.first as Map<String, dynamic>);
  }

  Future<List<ComponentRow>> installedForProjects(List<String> projectIds) async {
    if (projectIds.isEmpty) return [];
    final d = await sb.from('component_instances').select(StoreRepo._compSelect)
        .inFilter('installed_in_project_id', projectIds);
    return (d as List).map((e) => ComponentRow.fromMap(e as Map<String, dynamic>)).toList();
  }
}

final workshopRepoProvider = Provider<WorkshopRepo>((ref) => WorkshopRepo());
final myTasksProvider = FutureProvider<List<WorkshopTask>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(workshopRepoProvider).myTasks();
});
final inStockProvider = FutureProvider<List<ComponentRow>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(workshopRepoProvider).inStock();
});
final workshopPartsProvider = FutureProvider<List<ComponentRow>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.read(workshopRepoProvider);
  final tasks = await repo.myTasks();
  final ids = tasks.map((t) => t.projectId).toSet().toList();
  return repo.installedForProjects(ids);
});

/// Client — read-only build views of their own trucks (RLS scopes to their account).
class ClientRepo {
  Future<List<Project>> myTrucks() async {
    final d = await sb.from('projects')
        .select('id,code,name,status,progress_pct').order('code', ascending: true);
    return (d as List).map((e) => Project.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<StagePhoto>> photos(String projectId) async {
    final stages = await sb.from('stages').select('id').eq('project_id', projectId);
    final ids = (stages as List).map((e) => e['id'] as String).toList();
    if (ids.isEmpty) return [];
    final d = await sb.from('attachments')
        .select('file_url,caption,created_at')
        .eq('owner_type', 'stage').inFilter('owner_id', ids)
        .order('created_at', ascending: false);
    return (d as List).map((e) => StagePhoto.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<ClientDoc>> documents(String projectId) async {
    final d = await sb.from('documents').select('id,type,file_url,available').eq('project_id', projectId);
    return (d as List).map((e) => ClientDoc.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Photos uploaded against a single stage (client sees these per stage).
  Future<List<StagePhoto>> stagePhotos(String stageId) async {
    final d = await sb.from('attachments')
        .select('file_url,caption,created_at')
        .eq('owner_type', 'stage').eq('owner_id', stageId)
        .order('created_at', ascending: false);
    return (d as List).map((e) => StagePhoto.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<DesignRow>> designs(String projectId) async {
    final rows = await sb.from('design_artifacts')
        .select('id,type,status,current_version_id,client_feedback')
        .eq('project_id', projectId);
    final list = (rows as List).cast<Map<String, dynamic>>();
    final verIds = <String>[
      for (final r in list) if (r['current_version_id'] != null) r['current_version_id'] as String
    ];
    final vmap = <String, Map<String, dynamic>>{};
    if (verIds.isNotEmpty) {
      final vs = await sb.from('design_versions')
          .select('id,model_url,file_url,change_note').inFilter('id', verIds);
      for (final v in (vs as List)) {
        vmap[v['id'] as String] = v as Map<String, dynamic>;
      }
    }
    return list.map((r) {
      final v = r['current_version_id'] != null ? vmap[r['current_version_id']] : null;
      return DesignRow(
        id: r['id'] as String,
        type: r['type'] as String? ?? 'layout',
        status: r['status'] as String? ?? 'draft',
        modelUrl: v?['model_url'] as String?,
        imageUrl: v?['file_url'] as String?,
        changeNote: v?['change_note'] as String?,
        clientFeedback: r['client_feedback'] as String?,
      );
    }).toList();
  }

  /// Approve a design, or send it back with the changes the client wants.
  ///
  /// This used to UPDATE design_artifacts directly — but a client only holds a
  /// SELECT policy on that table, so the update matched zero rows and Postgres
  /// reported success. The client saw "Design approved" and nothing changed.
  /// fn_client_decide_design verifies the caller owns the build, records a real
  /// design_approvals row, and notifies the designer and the PM.
  Future<void> decideDesign(String artifactId, bool approve, {String? feedback}) async {
    await sb.rpc('fn_client_decide_design', params: {
      'p_artifact': artifactId,
      'p_approve': approve,
      'p_feedback': (feedback == null || feedback.trim().isEmpty) ? null : feedback.trim(),
    });
  }

  Future<List<TicketRow>> myTickets() async {
    final d = await sb.from('tickets')
        .select('id,ticket_number,category,description,status,created_at,'
                'resolution_note,resolution_type,resolved_at')
        .order('created_at', ascending: false);
    return (d as List).map((e) => TicketRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Raise a support request.
  ///
  /// The ticket number and the SLA deadline are set by the database
  /// (trg_ticket_defaults), and every service member is notified — previously
  /// a client request went nowhere because nothing consumed it.
  /// Returns the new ticket's id so a photo can be attached to it.
  Future<String> raiseTicket({
    required String projectId, required String category, required String description,
    String priority = 'medium',
  }) async {
    final d = await sb.from('tickets').insert({
      'project_id': projectId,
      'category': category,
      'description': description,
      'priority': priority,
      'status': 'open',
    }).select('id').single();
    return d['id'] as String;
  }

  /// Attach a photo of the problem to a request you raised.
  ///
  /// A picture is usually worth more than the description here — the service
  /// team can often tell what's wrong before anyone drives out.
  Future<void> attachTicketPhoto(String ticketId, Uint8List bytes, {
    required String filename, required String contentType, String? caption,
  }) async {
    final url = await uploadToBuilds(bytes,
      filename: filename, contentType: contentType, folder: 'tickets/$ticketId');
    await sb.from('attachments').insert({
      'owner_type': 'ticket', 'owner_id': ticketId, 'uploaded_by': sb.auth.currentUser?.id,
      'file_url': url,
      'caption': (caption == null || caption.trim().isEmpty) ? null : caption.trim(),
    });
  }

  /// "It's still not fixed" — puts the ticket back in the service queue at high
  /// priority and tells the team.
  Future<void> reopenTicket(String ticketId, String reason) =>
      sb.rpc('fn_reopen_ticket', params: {
        'p_ticket': ticketId,
        'p_reason': reason.trim().isEmpty ? null : reason.trim(),
      });
}

final clientRepoProvider = Provider<ClientRepo>((ref) => ClientRepo());
final myTrucksProvider = FutureProvider<List<Project>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(clientRepoProvider).myTrucks();
});
final truckPhotosProvider = FutureProvider.family<List<StagePhoto>, String>(
    (ref, id) => ref.read(clientRepoProvider).photos(id));
final stagePhotosProvider = FutureProvider.family<List<StagePhoto>, String>(
    (ref, stageId) => ref.read(clientRepoProvider).stagePhotos(stageId));
final truckDocsProvider = FutureProvider.family<List<ClientDoc>, String>(
    (ref, id) => ref.read(clientRepoProvider).documents(id));
final truckDesignsProvider = FutureProvider.family<List<DesignRow>, String>(
    (ref, id) => ref.read(clientRepoProvider).designs(id));
final myTicketsProvider = FutureProvider<List<TicketRow>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(clientRepoProvider).myTickets();
});

/// Admin actions (onboarding + option lists).
class AdminRepo {
  Future<List<OptRef>> templates() async {
    final d = await sb.from('workflow_templates').select('id,name').order('name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['name'] ?? '') as String)).toList();
  }
  /// Client accounts that actually have a login attached.
  ///
  /// An account with no contact_user_id is unreachable: my_client_account()
  /// returns null for it, so RLS matches no rows and the client can never see
  /// their truck. Those are filtered out here so a build can't be attached to one.
  Future<List<OptRef>> clients() async {
    final d = await sb.from('client_accounts')
        .select('id,business_name')
        .not('contact_user_id', 'is', null)
        .order('business_name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['business_name'] ?? '') as String)).toList();
  }

  /// How many legacy client accounts have no login (e.g. the demo seed row), so
  /// the onboarding screen can explain why they aren't in the list.
  Future<int> loginlessClientCount() async {
    final d = await sb.from('client_accounts')
        .select('id')
        .isFilter('contact_user_id', null);
    return (d as List).length;
  }

  /// Only active PMs — assigning a build to a disabled account would strand it.
  Future<List<OptRef>> pms() async {
    final d = await sb.from('profiles')
        .select('id,full_name,email')
        .eq('role', 'pm')
        .neq('status', 'disabled')
        .order('full_name', ascending: true);
    return (d as List).map((e) {
      final name = (e['full_name'] ?? '') as String;
      return OptRef(e['id'] as String, name.isEmpty ? (e['email'] ?? '') as String : name);
    }).toList();
  }

  /// Create a custom workflow template + its stages + each stage's BOM items.
  /// The BOM powers auto-generated requirements on onboarding (Hero #1).
  Future<OptRef> createTemplate(String name, String? truckType, List<StageDraft> stages) async {
    final t = await sb.from('workflow_templates')
        .insert({'name': name, 'truck_type': truckType}).select('id,name').single();
    final tid = t['id'] as String;
    for (var i = 0; i < stages.length; i++) {
      final st = await sb.from('template_stages').insert({
        'template_id': tid, 'name': stages[i].name, 'ord': i + 1, 'default_duration_days': stages[i].days,
      }).select('id').single();
      final sid = st['id'] as String;
      if (stages[i].items.isNotEmpty) {
        await sb.from('template_stage_items').insert([
          for (final it in stages[i].items) {'template_stage_id': sid, 'item_catalog_id': it.itemId, 'qty': it.qty},
        ]);
      }
      // The checklist labels for this stage. fn_onboard_project copies these
      // onto every build's stage as real checklist_items.
      final checks = [for (final c in stages[i].checks) c.trim()]..removeWhere((c) => c.isEmpty);
      if (checks.isNotEmpty) {
        await sb.from('template_stage_checks').insert([
          for (var j = 0; j < checks.length; j++)
            {'template_stage_id': sid, 'label': checks[j], 'ord': j},
        ]);
      }
    }
    return OptRef(tid, name);
  }

  /// List all team members.
  Future<List<Member>> members() async {
    final d = await sb.from('profiles').select('id,full_name,email,role,status').order('full_name', ascending: true);
    return (d as List).map((e) => Member.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Create a member via the admin-create-member Edge Function (server-side, secure).
  /// If [password] is given → direct create (no email needed); else → email invite.
  Future<void> createMember({
    required String fullName, required String email,
    String? phone, required String role, String? businessName, String? password,
  }) async {
    final res = await sb.functions.invoke('admin-create-member', body: {
      'full_name': fullName, 'email': email,
      'phone': phone, 'role': role, 'business_name': businessName,
      'redirect_to': inviteRedirectUrl,
      if (password != null) 'password': password,
    });
    final data = res.data;
    if (res.status != 200 || (data is Map && data['error'] != null)) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'Failed (${res.status})');
    }
  }

  /// Delete a member (auth user + profile) via the admin-delete-member Edge Function.
  Future<void> deleteMember(String userId) async {
    final res = await sb.functions.invoke('admin-delete-member', body: {'target_user_id': userId});
    final data = res.data;
    if (res.status != 200 || (data is Map && data['error'] != null)) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'Failed (${res.status})');
    }
  }

  /// Create a client's login **and** their client_account in one step, so the
  /// two can never drift apart. Returns the account for immediate selection in
  /// the onboarding form.
  ///
  /// Runs through the same admin-create-member Edge Function as staff, which
  /// links contact_user_id and rolls the auth user back if anything downstream
  /// fails. Pass [password] for a straight-to-login account, or leave it null to
  /// email an invite.
  Future<OptRef> createClientLogin({
    required String businessName, required String email,
    String? contactName, String? phone, String? password,
  }) async {
    final res = await sb.functions.invoke('admin-create-member', body: {
      'full_name': (contactName == null || contactName.trim().isEmpty)
          ? businessName : contactName.trim(),
      'email': email.trim(),
      'phone': phone,
      'role': 'client',
      'business_name': businessName.trim(),
      'redirect_to': inviteRedirectUrl,
      if (password != null && password.isNotEmpty) 'password': password,
    });
    final data = res.data;
    if (res.status != 200 || (data is Map && data['error'] != null)) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'Failed (${res.status})');
    }
    final id = data is Map ? data['client_account_id'] as String? : null;
    if (id == null) {
      // Older deployment of the function — fall back to looking the account up.
      final row = await sb.from('client_accounts')
          .select('id,business_name').eq('email', email.trim()).maybeSingle();
      if (row == null) throw Exception('Client created, but could not be selected. Reopen this screen.');
      return OptRef(row['id'] as String, (row['business_name'] ?? businessName) as String);
    }
    return OptRef(id, businessName.trim());
  }

  /// Insert a project then generate its stages + schedule (fn_onboard_project).
  ///
  /// [pmId] is required: fn_onboard_project refuses a build with no project
  /// manager, because such a build is invisible to every PM and none of its
  /// stages can ever be assigned or approved.
  Future<void> onboard({
    required String code, required String name, required String templateId,
    required String pmId, String? clientId, required DateTime target,
  }) async {
    final proj = await sb.from('projects').insert({
      'code': code.trim(), 'name': name.trim(), 'template_id': templateId,
      'client_account_id': clientId, 'pm_id': pmId,
      'pm_assigned_at': DateTime.now().toIso8601String(),
      'target_delivery_date': target.toIso8601String().split('T').first,
    }).select('id').single();
    await sb.rpc('fn_onboard_project', params: {'p_project': proj['id']});
  }

  /// Assign or change a build's project manager (admin only).
  ///
  /// fn_assign_pm verifies the target really is an active PM, records who
  /// assigned them, notifies the new PM and — on a hand-over — the old one.
  Future<void> assignPm(String projectId, String pmId) async {
    await sb.rpc('fn_assign_pm', params: {'p_project': projectId, 'p_pm': pmId});
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
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(notificationsRepoProvider).all();
});

/// Unread count for the bell badges. Now that assignments and approvals actually
/// write notifications, this is a real number.
final unreadCountProvider = Provider<int>((ref) =>
    ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);

/// Project Manager — builds assigned to the signed-in PM, schedule, workload.
class PmRepo {
  String? get _uid => sb.auth.currentUser?.id;

  Future<List<Project>> myProjects() async {
    final uid = _uid;
    if (uid == null) return [];
    final d = await sb.from('projects')
        .select('id,code,name,status,progress_pct,pm_id')
        .eq('pm_id', uid).order('code', ascending: true);
    return (d as List).map((e) => Project.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// In-progress stages across the PM's projects (dashboard "today").
  Future<List<ActiveStage>> activeStages(List<Project> projects) async {
    if (projects.isEmpty) return [];
    final ids = projects.map((p) => p.id).toList();
    final codeById = {for (final p in projects) p.id: p.code};
    final d = await sb.from('stages')
        .select('id,name,project_id')
        .eq('status', 'in_progress').inFilter('project_id', ids);
    return (d as List).map((e) => ActiveStage(
      id: e['id'] as String,
      name: e['name'] as String? ?? '',
      projectCode: codeById[e['project_id']] ?? '',
    )).toList();
  }

  /// The PM's real schedule: every stage still open across their builds, with
  /// the date it is due and who holds it.
  ///
  /// This replaced the bay board. `bays` was never written to by anything — no
  /// screen and no database function ever set `stages.bay_id` or
  /// `bays.current_stage_id` — so that tab was permanently empty. A PM's actual
  /// question is "what is due, and what has slipped", which the stage dates can
  /// already answer.
  ///
  /// `assigned_due` (what the PM committed to) wins over `planned_end` (what
  /// backward scheduling worked out), and the caller is told which one it got.
  Future<List<ScheduleEntry>> schedule(List<Project> projects) async {
    if (projects.isEmpty) return [];
    final byId = {for (final p in projects) p.id: p};

    final d = await sb.from('stages')
        .select('id,name,status,project_id,assignee_id,discipline,'
                'assigned_start,assigned_due,planned_start,planned_end')
        .inFilter('project_id', byId.keys.toList())
        .neq('status', 'done')
        .order('ord', ascending: true);
    final rows = (d as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return [];

    // One round-trip for every assignee name, instead of one per stage.
    final assigneeIds = <String>{
      for (final r in rows) if (r['assignee_id'] != null) r['assignee_id'] as String,
    };
    final names = <String, String>{};
    if (assigneeIds.isNotEmpty) {
      final ps = await sb.from('profiles')
          .select('id,full_name').inFilter('id', assigneeIds.toList());
      for (final p in (ps as List)) {
        names[p['id'] as String] = (p['full_name'] ?? '') as String;
      }
    }

    final out = <ScheduleEntry>[];
    for (final r in rows) {
      final p = byId[r['project_id']];
      if (p == null) continue;
      final committed = parseDate(r['assigned_due']);
      final planned = parseDate(r['planned_end']);
      final aid = r['assignee_id'] as String?;
      out.add(ScheduleEntry(
        stageId: r['id'] as String,
        stageName: r['name'] as String? ?? '',
        status: r['status'] as String? ?? 'todo',
        projectId: p.id,
        projectCode: p.code,
        projectName: p.name,
        assigneeId: aid,
        assigneeName: aid == null ? null : names[aid],
        discipline: r['discipline'] as String?,
        start: parseDate(r['assigned_start']) ?? parseDate(r['planned_start']),
        due: committed ?? planned,
        dueIsPlanned: committed == null && planned != null,
      ));
    }

    // Soonest first; anything with no date at all sinks to the bottom, because
    // it cannot be planned around until someone gives it a date.
    out.sort((a, b) {
      if (a.due == null && b.due == null) return a.projectCode.compareTo(b.projectCode);
      if (a.due == null) return 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    });
    return out;
  }

  /// assignee_id → number of stages still on their plate.
  ///
  /// Counts everything open, not just in_progress: a member holding five queued
  /// stages used to show up as "Free", which made the Team tab useless for
  /// deciding who to hand the next stage to.
  Future<Map<String, int>> workload() async {
    final d = await sb.from('stages')
        .select('assignee_id')
        .inFilter('status', ['todo', 'in_progress', 'rework'])
        .not('assignee_id', 'is', null);
    final m = <String, int>{};
    for (final r in (d as List)) {
      final a = r['assignee_id'] as String?;
      if (a != null) m[a] = (m[a] ?? 0) + 1;
    }
    return m;
  }
}

final pmRepoProvider = Provider<PmRepo>((ref) => PmRepo());

// Auth-aware: re-fetch when the signed-in user changes, so data is correct
// immediately after login (no manual refresh needed).
final myProjectsProvider = FutureProvider<List<Project>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(pmRepoProvider).myProjects();
});
final pmDashboardProvider = FutureProvider<({List<Project> projects, List<ActiveStage> stages})>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.read(pmRepoProvider);
  final projects = await repo.myProjects();
  final stages = await repo.activeStages(projects);
  return (projects: projects, stages: stages);
});
/// The signed-in PM's schedule — open stages across their builds, soonest first.
final pmScheduleProvider = FutureProvider<List<ScheduleEntry>>((ref) async {
  ref.watch(authStateProvider);
  final projects = await ref.read(pmRepoProvider).myProjects();
  return ref.read(pmRepoProvider).schedule(projects);
});
final workloadProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(pmRepoProvider).workload();
});

final adminRepoProvider = Provider<AdminRepo>((ref) => AdminRepo());
final membersProvider   = FutureProvider<List<Member>>((ref) { ref.watch(authStateProvider); return ref.read(adminRepoProvider).members(); });
final templatesProvider = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).templates());
final clientsProvider   = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).clients());
final pmsProvider       = FutureProvider<List<OptRef>>((ref) => ref.read(adminRepoProvider).pms());

/// Legacy client accounts with no login (e.g. the demo seed row). Onboarding
/// hides them from the picker, so it explains the gap using this count.
final loginlessClientsProvider = FutureProvider<int>(
    (ref) => ref.read(adminRepoProvider).loginlessClientCount());


/// Designer — create designs, upload versions (2D image + .glb model),
/// submit for client approval, and track the outcome / feedback loop.
class DesignRepo {
  static const _artifactSelect =
      'id,type,status,project_id,current_version_id,client_feedback, projects(code,name)';

  /// Design work that is actually mine: artifacts on the builds a PM assigned me
  /// a stage on, plus anything I authored myself.
  ///
  /// This used to select every design_artifacts row in the database, so the
  /// Design role ignored assignment completely — each designer saw (and could
  /// revise) every truck's designs.
  Future<List<DesignItem>> myDesigns() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return [];

    final projectIds =
        (await ProjectsRepo().myAssignedProjects()).map((p) => p.id).toList();

    final list = <Map<String, dynamic>>[];
    if (projectIds.isNotEmpty) {
      final r = await sb.from('design_artifacts')
          .select(_artifactSelect).inFilter('project_id', projectIds);
      list.addAll((r as List).cast<Map<String, dynamic>>());
    }
    // keep drafts I started even if the stage has since moved to someone else
    final mine = await sb.from('design_artifacts')
        .select(_artifactSelect).eq('created_by', uid);
    final seen = list.map((e) => e['id']).toSet();
    for (final m in (mine as List).cast<Map<String, dynamic>>()) {
      if (seen.add(m['id'])) list.add(m);
    }
    if (list.isEmpty) return [];
    final vmap = await _versionsById(
      [for (final r in list) if (r['current_version_id'] != null) r['current_version_id'] as String],
    );
    return list.map((r) => _itemFrom(r, vmap[r['current_version_id']])).toList();
  }

  Future<DesignDetailData> detail(String artifactId) async {
    final r = await sb.from('design_artifacts')
        .select('id,type,status,project_id,current_version_id,client_feedback, projects(code,name)')
        .eq('id', artifactId).single();
    final vs = await sb.from('design_versions')
        .select('id,model_url,file_url,version_no,change_note,created_at')
        .eq('artifact_id', artifactId).order('version_no', ascending: false);
    final versions = (vs as List).map((e) => DesignVersionRow.fromMap(e as Map<String, dynamic>)).toList();
    Map<String, dynamic>? cur;
    for (final e in vs) {
      if (e['id'] == r['current_version_id']) { cur = e; break; }
    }
    return DesignDetailData(_itemFrom(r, cur), versions);
  }

  /// Create a brand-new design artifact with its first version.
  Future<void> create({
    required String projectId, required String type,
    String? modelUrl, String? imageUrl, String? changeNote, required bool submit,
  }) async {
    final a = await sb.from('design_artifacts').insert({
      'project_id': projectId, 'type': type,
      'status': submit ? 'pending_approval' : 'draft',
      'created_by': sb.auth.currentUser?.id,
    }).select('id').single();
    final aid = a['id'] as String;
    final v = await sb.from('design_versions').insert({
      'artifact_id': aid, 'version_no': 1,
      'file_url': _clean(imageUrl), 'model_url': _clean(modelUrl), 'change_note': _clean(changeNote),
    }).select('id').single();
    await sb.from('design_artifacts').update({'current_version_id': v['id']}).eq('id', aid);
  }

  /// Add a new version to an existing artifact (e.g. after a change request).
  Future<void> addVersion({
    required String artifactId,
    String? modelUrl, String? imageUrl, String? changeNote, required bool submit,
  }) async {
    final existing = await sb.from('design_versions')
        .select('version_no').eq('artifact_id', artifactId)
        .order('version_no', ascending: false).limit(1);
    final nextNo = (existing as List).isEmpty ? 1 : ((existing.first['version_no'] as num).toInt() + 1);
    final v = await sb.from('design_versions').insert({
      'artifact_id': artifactId, 'version_no': nextNo,
      'file_url': _clean(imageUrl), 'model_url': _clean(modelUrl), 'change_note': _clean(changeNote),
    }).select('id').single();
    await sb.from('design_artifacts').update({
      'current_version_id': v['id'],
      'status': submit ? 'pending_approval' : 'draft',
      'client_feedback': null,
    }).eq('id', artifactId);
  }

  Future<void> submitForApproval(String artifactId) async {
    await sb.from('design_artifacts').update({'status': 'pending_approval'}).eq('id', artifactId);
  }

  /// Upload a design file (.glb model or preview image) to the public 'designs'
  /// bucket and return its public URL. Path is namespaced by the uploader.
  Future<String> uploadFile(Uint8List bytes, {required String filename, required String contentType}) async {
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final uid = sb.auth.currentUser?.id ?? 'anon';
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await sb.storage.from('designs').uploadBinary(
      path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true));
    return sb.storage.from('designs').getPublicUrl(path);
  }

  /// The .glb of an approved design for this project (drives the 3D showcase).
  Future<String?> approvedModelUrl(String projectId) async {
    final rows = await sb.from('design_artifacts')
        .select('current_version_id').eq('project_id', projectId).eq('status', 'approved');
    final ids = <String>[
      for (final r in (rows as List)) if (r['current_version_id'] != null) r['current_version_id'] as String
    ];
    if (ids.isEmpty) return null;
    final vs = await sb.from('design_versions').select('model_url').inFilter('id', ids);
    for (final v in (vs as List)) {
      final m = v['model_url'] as String?;
      if (m != null && m.trim().isNotEmpty) return m;
    }
    return null;
  }

  // ── helpers ──────────────────────────────────────────────
  String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<Map<String, Map<String, dynamic>>> _versionsById(List<String> ids) async {
    final map = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return map;
    final vs = await sb.from('design_versions')
        .select('id,model_url,file_url,version_no,change_note').inFilter('id', ids);
    for (final v in (vs as List)) {
      map[v['id'] as String] = v as Map<String, dynamic>;
    }
    return map;
  }

  DesignItem _itemFrom(Map<String, dynamic> r, Map<String, dynamic>? v) {
    final pj = r['projects'] as Map<String, dynamic>?;
    return DesignItem(
      id: r['id'] as String,
      type: r['type'] as String? ?? 'layout',
      status: r['status'] as String? ?? 'draft',
      projectId: r['project_id'] as String? ?? '',
      projectCode: pj?['code'] as String?,
      projectName: pj?['name'] as String?,
      modelUrl: v?['model_url'] as String?,
      imageUrl: v?['file_url'] as String?,
      changeNote: v?['change_note'] as String?,
      clientFeedback: r['client_feedback'] as String?,
      versionNo: (v?['version_no'] as num?)?.toInt() ?? 1,
    );
  }
}

final designRepoProvider = Provider<DesignRepo>((ref) => DesignRepo());
final myDesignsProvider = FutureProvider<List<DesignItem>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(designRepoProvider).myDesigns();
});
final designDetailProvider = FutureProvider.family<DesignDetailData, String>(
    (ref, artifactId) => ref.read(designRepoProvider).detail(artifactId));

/// The approved .glb for a project (null = none yet). Powers the 3D showcase
/// on the client My Trucks card and the admin/PM project detail screen.
final truckModelUrlProvider = FutureProvider.family<String?, String>((ref, projectId) {
  ref.watch(authStateProvider);
  return ref.read(designRepoProvider).approvedModelUrl(projectId);
});


/// Service — after-sales support on delivered trucks.
///
/// Every mutation goes through an RPC from `0010_service.sql`, which owns the
/// rules: who may triage, that a technician is actually a service/workshop
/// member, that a resolution carries a note the client will read, that a ticket
/// can't be closed before it's resolved, and who gets notified at each step.
class ServiceRepo {
  static const _ticketSelect =
      'id,ticket_number,category,description,status,priority,sla_due,created_at,'
      'resolved_at,resolution_type,resolution_note,assigned_to,linked_component_id,'
      'project_id,projects(code,name,client_accounts(business_name))';

  /// The whole queue, soonest SLA deadline first — that's the order to work in.
  Future<List<ServiceTicket>> tickets() async {
    final d = await sb.from('tickets')
        .select(_ticketSelect)
        .order('sla_due', ascending: true, nullsFirst: false);
    return (d as List).map((e) => ServiceTicket.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<ServiceTicket> ticket(String id) async {
    final d = await sb.from('tickets').select(_ticketSelect).eq('id', id).single();
    return ServiceTicket.fromMap(d);
  }

  /// The part a ticket points at, with its warranty state (drives the
  /// "In warranty / Expired" pill on the ticket).
  Future<WarrantyRow?> linkedComponent(String componentId) async {
    final d = await sb.from('component_instances')
        .select('id,serial_number,warranty_end,status,item_catalog(name,model),vendors(name)')
        .eq('id', componentId).maybeSingle();
    if (d == null) return null;
    final ic = d['item_catalog'] as Map<String, dynamic>?;
    final vn = d['vendors'] as Map<String, dynamic>?;
    final end = parseDate(d['warranty_end']);
    return WarrantyRow(
      componentId: d['id'] as String,
      itemName: ic?['name'] as String? ?? 'Component',
      model: ic?['model'] as String? ?? '',
      serial: d['serial_number'] as String? ?? '—',
      vendorName: vn?['name'] as String? ?? '',
      projectCode: '',
      compStatus: d['status'] as String? ?? '',
      warrantyEnd: end,
      daysLeft: end?.difference(DateTime.now()).inDays,
    );
  }

  /// Photos the client attached to the request — often the fastest way to see
  /// what's actually wrong.
  Future<List<StagePhoto>> ticketPhotos(String ticketId) async {
    final d = await sb.from('attachments')
        .select('file_url,caption,created_at')
        .eq('owner_type', 'ticket').eq('owner_id', ticketId)
        .order('created_at', ascending: true);
    return (d as List).map((e) => StagePhoto.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<ServiceVisitRow>> visits(String ticketId) async {
    final d = await sb.from('service_visits')
        .select('id,ticket_id,technician_id,scheduled_date,status,note')
        .eq('ticket_id', ticketId)
        .order('scheduled_date', ascending: false);
    return (d as List).map((e) => ServiceVisitRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Members who can be sent on a visit — service + workshop only.
  Future<List<Member>> technicians() async {
    final d = await sb.from('profiles')
        .select('id,full_name,email,role,status')
        .inFilter('role', ['service', 'workshop'])
        .neq('status', 'disabled')
        .order('full_name', ascending: true);
    return (d as List).map((e) => Member.fromMap(e as Map<String, dynamic>)).toList();
  }

  // ── actions ────────────────────────────────────────────────────────
  Future<String> createTicket({
    required String projectId, required String category, required String description,
    String priority = 'medium', String? componentId,
  }) async {
    final d = await sb.rpc('fn_create_ticket', params: {
      'p_project': projectId, 'p_category': category, 'p_description': description,
      'p_priority': priority, 'p_component': componentId,
    });
    return d as String;
  }

  Future<void> assign(String ticketId, String? technicianId) =>
      sb.rpc('fn_assign_ticket', params: {'p_ticket': ticketId, 'p_technician': technicianId});

  Future<void> scheduleVisit({
    required String ticketId, required String technicianId,
    required DateTime when, String? note,
  }) => sb.rpc('fn_schedule_visit', params: {
        'p_ticket': ticketId, 'p_technician': technicianId,
        'p_when': when.toUtc().toIso8601String(),
        'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      });

  Future<void> resolve(String ticketId, String resolutionType, String note) =>
      sb.rpc('fn_resolve_ticket', params: {
        'p_ticket': ticketId, 'p_resolution': resolutionType, 'p_note': note,
      });

  Future<void> close(String ticketId) =>
      sb.rpc('fn_close_ticket', params: {'p_ticket': ticketId});

  // ── delivered trucks ───────────────────────────────────────────────
  /// Trucks that have actually been handed over — the Service role's fleet.
  Future<List<DeliveredTruck>> deliveredTrucks() async {
    final d = await sb.from('projects')
        .select('id,code,name,status,progress_pct,pm_id,actual_delivery_date')
        .eq('status', 'delivered')
        .order('actual_delivery_date', ascending: false);
    final rows = (d as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return [];

    final ids = rows.map((e) => e['id'] as String).toList();

    // open ticket count per truck
    final open = await sb.from('tickets')
        .select('project_id')
        .inFilter('project_id', ids)
        .inFilter('status', ['open', 'in_progress']);
    final openBy = <String, int>{};
    for (final r in (open as List)) {
      final p = r['project_id'] as String?;
      if (p != null) openBy[p] = (openBy[p] ?? 0) + 1;
    }

    // warranties running out in the next 60 days
    final exp = await sb.rpc('fn_warranty_expiring', params: {'p_days': 60});
    final expBy = <String, int>{};
    for (final r in (exp as List)) {
      final p = (r as Map<String, dynamic>)['project_id'] as String?;
      if (p != null) expBy[p] = (r['expiring'] as num?)?.toInt() ?? 0;
    }

    return rows.map((e) => DeliveredTruck(
      project: Project.fromMap(e),
      deliveredOn: parseDate(e['actual_delivery_date']),
      openTickets: openBy[e['id']] ?? 0,
      expiringParts: expBy[e['id']] ?? 0,
    )).toList();
  }

  Future<TruckHistory> truckHistory(String projectId) async {
    final p = await sb.from('projects')
        .select('id,code,name,status,progress_pct,pm_id,actual_delivery_date,'
                'client_accounts(business_name)')
        .eq('id', projectId).single();

    final comps = await sb.from('component_instances')
        .select('id,warranty_end')
        .eq('installed_in_project_id', projectId);
    DateTime? earliest;
    for (final c in (comps as List)) {
      final w = parseDate(c['warranty_end']);
      if (w == null) continue;
      if (earliest == null || w.isBefore(earliest)) earliest = w;
    }

    final t = await sb.from('tickets')
        .select(_ticketSelect)
        .eq('project_id', projectId)
        .order('created_at', ascending: false);

    final ca = p['client_accounts'] as Map<String, dynamic>?;
    return TruckHistory(
      project: Project.fromMap(p),
      deliveredOn: parseDate(p['actual_delivery_date']),
      clientName: ca?['business_name'] as String?,
      componentCount: (comps).length,
      earliestWarrantyEnd: earliest,
      tickets: (t as List).map((e) => ServiceTicket.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }

  // ── warranty lookup ────────────────────────────────────────────────
  Future<List<WarrantyRow>> warrantySearch(String query) async {
    final d = await sb.rpc('fn_warranty_search', params: {'p_q': query});
    return (d as List).map((e) => WarrantyRow.fromMap(e as Map<String, dynamic>)).toList();
  }
}

final serviceRepoProvider = Provider<ServiceRepo>((ref) => ServiceRepo());

final serviceTicketsProvider = FutureProvider<List<ServiceTicket>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(serviceRepoProvider).tickets();
});
final serviceTicketProvider = FutureProvider.family<ServiceTicket, String>(
    (ref, id) => ref.read(serviceRepoProvider).ticket(id));
final ticketVisitsProvider = FutureProvider.family<List<ServiceVisitRow>, String>(
    (ref, ticketId) => ref.read(serviceRepoProvider).visits(ticketId));
final ticketPhotosProvider = FutureProvider.family<List<StagePhoto>, String>(
    (ref, ticketId) => ref.read(serviceRepoProvider).ticketPhotos(ticketId));
final ticketComponentProvider = FutureProvider.family<WarrantyRow?, String>(
    (ref, componentId) => ref.read(serviceRepoProvider).linkedComponent(componentId));
final techniciansProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(serviceRepoProvider).technicians();
});
final deliveredTrucksProvider = FutureProvider<List<DeliveredTruck>>((ref) {
  ref.watch(authStateProvider);
  return ref.read(serviceRepoProvider).deliveredTrucks();
});
final truckHistoryProvider = FutureProvider.family<TruckHistory, String>(
    (ref, projectId) => ref.read(serviceRepoProvider).truckHistory(projectId));

/// Warranty lookup, keyed by the search box text (empty = the first 100 parts).
final warrantySearchProvider = FutureProvider.family<List<WarrantyRow>, String>(
    (ref, q) => ref.read(serviceRepoProvider).warrantySearch(q));
