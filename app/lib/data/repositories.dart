import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import 'models.dart';

/// Emits on every auth change (sign in/out, token refresh, user update).
final authStateProvider = StreamProvider<AuthState>((ref) => sb.auth.onAuthStateChange);

/// Who is signed in, and nothing else.
///
/// **Every cached query provider watches this.** Two bugs came out of not
/// having it:
///
///   * Providers that watched nothing at all kept the previous user's rows
///     after a sign-out and sign-in on the same device — so demoing admin →
///     PM → client on one phone showed the admin's builds under the client's
///     login until something forced a refresh. With role-scoped RLS the rows
///     were already fetched and cached; only the cache was wrong.
///   * Providers that watched [authStateProvider] directly re-ran on *every*
///     auth event, token refresh included, so dashboards refetched on a timer
///     for no reason.
///
/// A `Provider` recomputes when auth changes but only notifies its listeners
/// when the value actually differs, so this is distinct-until-changed on the
/// user id: exactly what a cached query cares about.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return sb.auth.currentUser?.id;
});

/// The signed-in user's role, fetched once and cached for the session.
/// Re-fetches automatically when auth changes (e.g. a different user logs in),
/// so screens never show a stale or flickering role.
final myRoleProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserIdProvider); // refetch when the user changes
  return fetchMyRole();
});

/// Download a file the app stored, given the public URL it saved.
///
/// Goes through the Supabase Storage client rather than a bare HTTP GET, so the
/// request carries the session. Today both buckets are public-read, but the
/// documents under `builds/docs/` are contracts and invoices — when those are
/// made private this keeps working, and nothing at the call sites changes.
Future<Uint8List> downloadFromUrl(String publicUrl) async {
  // …/storage/v1/object/public/<bucket>/<path>
  final marker = RegExp(r'/storage/v1/object/(?:public/|sign/)?([^/]+)/(.+)$');
  final m = marker.firstMatch(Uri.parse(publicUrl).path);
  if (m == null) throw Exception('That document link is not one this app stored.');
  final bucket = Uri.decodeComponent(m.group(1)!);
  final path = Uri.decodeComponent(m.group(2)!);
  return sb.storage.from(bucket).download(path);
}

/// The signed-in user's own profile row (Settings → Account details).
///
/// Read from `profiles` rather than from the auth user's metadata, because the
/// metadata copy is only written at invite time: an admin renaming someone, or
/// moving them to another sub-team, never touches it. The profiles row is the
/// one the rest of the app reads, so this is what Settings should show.
final myProfileProvider = FutureProvider<MyProfile?>((ref) async {
  ref.watch(currentUserIdProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  final d = await sb.from('profiles')
      .select('id,full_name,email,role,status,phone,created_at,sub_team_id,sub_teams(name)')
      .eq('id', uid).maybeSingle();
  return d == null ? null : MyProfile.fromMap(d);
});

/// Save the parts of your own profile that are yours to change.
///
/// Role, email, team and status stay the admin's — `trg_profiles_self_update`
/// (0026) enforces that server-side, so a tampered client gets a clear error
/// rather than a silent partial write. The auth user's metadata is updated too,
/// so the name in the header and avatar changes without a re-login.
Future<void> saveMyProfile({required String fullName, String? phone}) async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) throw Exception('You are signed out.');
  final name = fullName.trim();
  if (name.isEmpty) throw Exception('Your name cannot be empty.');
  final tel = phone?.trim();
  await sb.from('profiles').update({
    'full_name': name,
    'phone': (tel == null || tel.isEmpty) ? null : tel,
  }).eq('id', uid);
  await sb.auth.updateUser(UserAttributes(data: {'full_name': name}));
}

/// Invalidate everything a change to one build touches.
///
/// A build-level action (assign the PM, log a delay, push the delivery date,
/// approve a stage, mark it delivered) moves data that at least six screens
/// cache. Each call site used to invalidate the two or three providers whoever
/// wrote it happened to think of, so there were real holes: logging a delay
/// never refreshed the Pipeline's delay ledger, and assigning a PM or approving
/// a stage never refreshed the owner's Command Center or the PM's Schedule —
/// the action worked, the screen you were looking at just kept showing the old
/// answer. One list, in one place, so the next action cannot forget one.
void invalidateBuild(WidgetRef ref, String projectId) {
  ref.invalidate(projectDetailProvider(projectId));
  ref.invalidate(projectDelaysProvider(projectId));   // the Pipeline delay ledger
  ref.invalidate(requirementsProvider(projectId));
  ref.invalidate(truckComponentsProvider(projectId));
  ref.invalidate(fleetProvider);                      // Admin home + Projects
  ref.invalidate(opsBoardProvider);                   // the Command Center
  ref.invalidate(myProjectsProvider);                 // PM Projects
  ref.invalidate(pmDashboardProvider);                // PM home counts
  ref.invalidate(pmScheduleProvider);                 // PM Schedule
  ref.invalidate(pendingApprovalsProvider);
  ref.invalidate(stagesToAssignProvider);
}

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
/// How long an upload may take before we give up and say so.
///
/// Generous, because a 1600px photo over a weak site connection is genuinely
/// slow — but finite, because the alternative is what shipped: no timeout at
/// all, so a request that never completes left the caller awaiting forever
/// behind a "Uploading photo…" snackbar, which reads as the app having frozen
/// rather than as a bad connection.
const uploadTimeout = Duration(seconds: 45);

Future<String> uploadToBuilds(Uint8List bytes, {
  required String filename, required String contentType, required String folder,
}) async {
  final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safe';
  try {
    await sb.storage.from('builds').uploadBinary(
      path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true))
      .timeout(uploadTimeout);
  } on TimeoutException {
    throw Exception('The upload timed out. Check your connection and try again — '
                    'nothing was saved.');
  }
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

  /// The factory board (v_ops_board): every active build with where it is, which
  /// department/team + person is on it, and how long it's been there.
  Future<List<OpsRow>> opsBoard() async {
    final data = await sb.from('v_ops_board').select();
    return (data as List).map((e) => OpsRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Which build a stage belongs to — used to turn a stage notification into
  /// the build screen the PM or admin should land on.
  Future<String?> projectIdForStage(String stageId) async {
    final d = await sb.from('stages').select('project_id').eq('id', stageId).maybeSingle();
    return d?['project_id'] as String?;
  }

  /// A single project + its ordered build stages (Project detail screen).
  Future<ProjectDetailData> detail(String id) async {
    final p = await sb.from('projects')
        .select('$_projectSelect,target_delivery_date')
        .eq('id', id).single();
    final st = await sb.from('stages')
        .select('id,name,ord,step,status,assignee_id,discipline,planned_start,planned_end,'
                'actual_start,actual_end,assigned_start,assigned_due')
        .eq('project_id', id).order('ord', ascending: true);
    return ProjectDetailData(
      Project.fromMap(p),
      parseDate(p['target_delivery_date']),
      (st as List).map((e) => Stage.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Every delay logged across a build (v_project_delays) — which stage, who,
  /// why, how many days. Powers the dossier's delay-attribution section.
  Future<List<ProjectDelay>> projectDelays(String projectId) async {
    final d = await sb.from('v_project_delays')
        .select()
        .eq('project_id', projectId)
        .order('created_at', ascending: true);
    return (d as List).map((e) => ProjectDelay.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Recompute every build's status against today's date (delayed / at-risk /
  /// on-track drift with the calendar, not only with edits). Cheap for the
  /// fleet sizes here; the dashboards call it so the owner always sees the truth
  /// even without the daily cron scheduled.
  Future<void> refreshStatuses() => sb.rpc('fn_refresh_all_statuses');

  /// Every component installed on a build (v_truck_components) — the truck's
  /// complete physical record: parts, serials, vendors, bills, warranties.
  Future<List<TruckComponent>> truckComponents(String projectId) async {
    final d = await sb.from('v_truck_components')
        .select()
        .eq('project_id', projectId)
        .order('stage_ord', ascending: true)
        .order('install_date', ascending: true);
    return (d as List).map((e) => TruckComponent.fromMap(e as Map<String, dynamic>)).toList();
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
    // Disambiguate the embed: stages ↔ projects has two FKs (stages.project_id
    // and projects.current_stage_id), so PostgREST needs the explicit one.
    final d = await sb.from('stages')
        .select('project_id,projects!stages_project_id_fkey($_projectSelect)')
        .eq('assignee_id', uid);
    final byId = <String, Project>{};
    for (final r in (d as List)) {
      final p = (r as Map<String, dynamic>)['projects'] as Map<String, dynamic>?;
      if (p != null) byId[p['id'] as String] = Project.fromMap(p);
    }
    final out = byId.values.toList()..sort((a, b) => a.code.compareTo(b.code));
    return out;
  }

  /// The builds I hold a stage on, with my stage's due date + the build's
  /// delivery date — for the "Assigned to me" carousel. One row per build (the
  /// nearest-due stage wins), soonest due first.
  Future<List<AssignedBuild>> myAssignedBuilds() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return [];
    final d = await sb.from('stages')
        .select('name,assigned_due,planned_end,'
            'projects!stages_project_id_fkey(id,code,name,status,progress_pct,target_delivery_date)')
        .eq('assignee_id', uid);
    final byId = <String, AssignedBuild>{};
    for (final r in (d as List)) {
      final m = r as Map<String, dynamic>;
      final p = m['projects'] as Map<String, dynamic>?;
      if (p == null) continue;
      final pid = p['id'] as String;
      final cand = AssignedBuild(
        projectId: pid,
        code: p['code'] as String? ?? '',
        name: p['name'] as String? ?? '',
        status: p['status'] as String? ?? 'on_track',
        progressPct: (p['progress_pct'] as num?)?.toInt() ?? 0,
        stageName: m['name'] as String?,
        due: parseDate(m['assigned_due']) ?? parseDate(m['planned_end']),
        targetDelivery: parseDate(p['target_delivery_date']),
      );
      final existing = byId[pid];
      if (existing == null ||
          (cand.due != null && (existing.due == null || cand.due!.isBefore(existing.due!)))) {
        byId[pid] = cand;
      }
    }
    final out = byId.values.toList()
      ..sort((a, b) {
        if (a.due == null && b.due == null) return a.code.compareTo(b.code);
        if (a.due == null) return 1;
        if (b.due == null) return -1;
        return a.due!.compareTo(b.due!);
      });
    return out;
  }

  /// Record why a build slipped, against the stage that slipped. delay_logs was
  /// read (stage detail shows delays) but nothing ever wrote it, so "tag the
  /// reason" did not exist. RLS lets admin/pm/workshop insert.
  Future<void> logDelay({
    required String stageId, required String reasonCode, required int daysDelayed, String? note,
  }) async {
    await sb.from('delay_logs').insert({
      'stage_id': stageId,
      'reason_code': reasonCode,
      'days_delayed': daysDelayed,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'logged_by': sb.auth.currentUser?.id,
    });
  }

  /// A build's documents (staff view). Nothing used to create these, so the
  /// client's Documents tab was always empty; this is the read side for the
  /// staff screen that now uploads them.
  Future<List<ClientDoc>> documents(String projectId) async {
    final d = await sb.from('documents')
        .select('id,type,file_url,available')
        .eq('project_id', projectId)
        .order('type', ascending: true);
    return (d as List).map((e) => ClientDoc.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Upload a document (contract / invoice / warranty pack / handover cert) to
  /// builds/docs/<project> and record it as available, so the client sees it on
  /// their truck. Staff hold the write policy on documents (p_docs_staff).
  Future<void> addDocument({
    required String projectId, required String type,
    required Uint8List bytes, required String filename, required String contentType,
  }) async {
    final url = await uploadToBuilds(bytes,
      filename: filename, contentType: contentType, folder: 'docs/$projectId');
    await sb.from('documents').insert({
      'project_id': projectId, 'type': type, 'file_url': url, 'available': true,
    });
  }

  /// Change a project's target delivery date, then re-run backward scheduling.
  ///
  /// A delivery-date change is a full re-plan, so it also re-baselines each
  /// stage's committed (assigned) dates to the new plan — otherwise a stage
  /// could still read "Due" after the new delivery date. (0015)
  Future<void> setDeliveryDate(String projectId, DateTime date) async {
    await sb.from('projects')
        .update({'target_delivery_date': date.toIso8601String().split('T').first}).eq('id', projectId);
    await sb.rpc('fn_recompute_schedule',
        params: {'p_project': projectId, 'p_rebaseline_assigned': true});
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
        // `projects!stages_project_id_fkey`: stages ↔ projects has TWO foreign
        // keys — stages.project_id → projects.id, and projects.current_stage_id
        // → stages.id (fk_current_stage, from 0001). Without the hint PostgREST
        // refuses the whole query with PGRST201 "more than one relationship was
        // found", so this screen could not load at all. The other three queries
        // that cross the same pair already name the FK; this one was missed.
        .select('id,stage_id,status,created_at,approver_id,'
                'profiles:submitted_by(full_name),'
                'stages!inner(name,projects!stages_project_id_fkey!inner(code))')
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
  /// Everything the person working a stage needs on one screen.
  ///
  /// The reads run **together**. They were six sequential awaits, which on a
  /// workshop-floor connection is six round trips before anything draws; they
  /// do not depend on each other, so there was never a reason to wait.
  Future<StageBundle> stageBundle(String stageId) async {
    // The stage first, for its project — the BOM is per build, and the
    // assignee's name needs a second hop either way.
    // `profiles` must be named by its foreign key: `stages` points at it twice
    // (assignee_id and assigned_by), so a bare `profiles(...)` embed is
    // ambiguous and PostgREST refuses the whole query with PGRST201. This is
    // the same trap that silently broke PM Approvals (§3) — the embed has to
    // say which relationship it means.
    final srow = await sb.from('stages')
        .select('assignee_id,template_stage_id,project_id,'
                'profiles!stages_assignee_id_fkey(full_name)')
        .eq('id', stageId).maybeSingle();

    final results = await Future.wait([
      // done_by / done_at / photo_required / the proof photo are 0029: the
      // record of a tick, which the old bare `done` column never kept.
      sb.from('checklist_items')
        .select('id,label,done,done_at,photo_required,'
                'done_by_profile:profiles!checklist_items_done_by_fkey(full_name),'
                'proof:attachments!checklist_items_proof_attachment_id_fkey(file_url)')
        .eq('stage_id', stageId).order('id', ascending: true),
      sb.from('attachments')
        .select('id,file_url,caption')
        .eq('owner_type', 'stage').eq('owner_id', stageId)
        .order('created_at', ascending: true),
      sb.from('component_instances')
        .select('serial_number,status,install_date,warranty_end,item_catalog(name,model),vendors(name)')
        .eq('installed_stage_id', stageId),
      sb.from('delay_logs')
        .select('reason_code,days_delayed,note').eq('stage_id', stageId),
      _stageMaterials(srow),
    ]);

    final pr = srow?['profiles'] as Map<String, dynamic>?;
    return StageBundle(
      assignee: pr?['full_name'] as String?,
      checklist: [for (final e in results[0]) ChecklistItem.fromMap(e as Map<String, dynamic>)],
      photos: [for (final e in results[1]) StagePhoto.fromMap(e as Map<String, dynamic>)],
      parts: [for (final e in results[2]) StagePart.fromMap(e as Map<String, dynamic>)],
      delays: [for (final e in results[3]) StageDelay.fromMap(e as Map<String, dynamic>)],
      materials: [for (final e in results[4]) StageMaterial.fromMap(e as Map<String, dynamic>)],
    );
  }

  /// This stage's slice of the build's BOM.
  ///
  /// `procurement_requirements` carries no stage, only the build — the BOM
  /// originates per *template* stage (`template_stage_items`), so the stage's
  /// own items are the catalogue ids its template stage listed. A stage added
  /// by hand has no template stage, and therefore no BOM, which is the honest
  /// answer rather than showing the whole build's materials.
  Future<List<dynamic>> _stageMaterials(Map<String, dynamic>? srow) async {
    final tsId = srow?['template_stage_id'] as String?;
    final projectId = srow?['project_id'] as String?;
    if (tsId == null || projectId == null) return const [];
    final items = await sb.from('template_stage_items')
        .select('item_catalog_id').eq('template_stage_id', tsId);
    final ids = [for (final e in (items as List)) e['item_catalog_id'] as String];
    if (ids.isEmpty) return const [];
    return await sb.from('procurement_requirements')
        .select('qty,status,item_catalog(name)')
        .eq('project_id', projectId)
        .inFilter('item_catalog_id', ids)
        .order('status', ascending: true);
  }
}

/// Procurement actions (Hero #1).
class ProcurementRepo {
  Future<List<OrderDue>> toOrder() async {
    final data = await sb.from('v_order_due').select();
    return (data as List).map((e) => OrderDue.fromMap(e as Map<String, dynamic>)).toList();
  }

  static const _poSelect =
      'id,po_number,status,approval_status,amount,order_date,expected_date,vendors(name),projects(code),po_lines(id)';
  static const _poDetailSelect =
      'id,po_number,status,approval_status,amount,subtotal,tax_total,order_date,expected_date,'
      'delivery_date,needed_by,ship_to,payment_terms,notes,pm_id,vendor_id,submitted_at,pm_signed_at,'
      'final_signed_at,rejected_at,rejection_reason,vendors(name),projects(code)';

  /// All purchase orders (newest first).
  Future<List<PurchaseOrder>> purchaseOrders() async {
    final d = await sb.from('purchase_orders').select(_poSelect).order('po_number', ascending: false);
    return (d as List).map((e) => PurchaseOrder.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// One PO with its line items and its approval trail.
  Future<PoDetail> poDetail(String id) async {
    final po = await sb.from('purchase_orders').select(_poDetailSelect).eq('id', id).single();
    final lines = await sb.from('po_lines')
        .select('qty,received_qty,unit_price,tax_rate,hsn_code,description,item_catalog_id,item_catalog(name)')
        .eq('po_id', id);
    final events = await sb.from('po_approval_events')
        .select('event,note,from_status,to_status,created_at,profiles(full_name)')
        .eq('po_id', id).order('created_at', ascending: true);
    return PoDetail(
      PurchaseOrder.fromMap(po),
      (lines as List).map((e) => PoLineItem.fromMap(e as Map<String, dynamic>)).toList(),
      events: (events as List).map((e) => PoApprovalEvent.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Advance a PO to 'dispatched' (Procurement marks this when the vendor ships).
  /// Advance a PO to 'dispatched'. An expected arrival date (ETA) is required —
  /// "dispatched" with no idea when it lands isn't useful, and the Receive tab
  /// shows this date. Receiving is then gated on this status by fn_receive_po.
  Future<void> markDispatched(String poId, {required DateTime expectedDate}) async {
    await sb.from('purchase_orders').update({
      'status': 'dispatched',
      'expected_date': expectedDate.toIso8601String().split('T').first,
    }).eq('id', poId);
  }

  /// Item catalog options (for building a PO manually).
  Future<List<OptRef>> items() async {
    final d = await sb.from('item_catalog').select('id,name').order('name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['name'] ?? '') as String)).toList();
  }

  /// Essentials only — general stock the Store keeps (sheets, metal, wheels),
  /// not project-specific parts. Feeds the Store's "Request from procurement"
  /// picker so a project item like an LED screen never shows up there.
  Future<List<OptRef>> essentials() async {
    final d = await sb.from('item_catalog').select('id,name')
        .eq('is_essential', true).order('name', ascending: true);
    return (d as List).map((e) => OptRef(e['id'] as String, (e['name'] ?? '') as String)).toList();
  }

  /// Add a new catalog item inline (from the New PO flow, or as a Store
  /// essential). Essentials the Store reorders are bulk by default, so callers
  /// creating one pass essential: true, serialized: false.
  Future<OptRef> createItem({
    required String name, String? category, int leadTimeDays = 0,
    bool essential = false, bool serialized = true,
  }) async {
    final d = await sb.from('item_catalog')
        .insert({
          'name': name, 'category': category, 'lead_time_days': leadTimeDays,
          'is_essential': essential, 'serialized': serialized,
        })
        .select('id,name').single();
    return OptRef(d['id'] as String, d['name'] as String);
  }

  /// Raise a purchase order through fn_create_po, which enters it into the
  /// approval chain (PM sign → final approval) — a PO can no longer be inserted
  /// directly. Captures per-line rate + GST so the header totals (and the PO
  /// document) are real. Optionally links the requirement / stock request it
  /// fulfils, which parks that demand off the To-Order list until approved.
  Future<String> createPo({
    String? projectId, String? vendorId,
    DateTime? deliveryDate, String? paymentTerms, String? notes, String? shipTo,
    String? requirementId, String? stockRequestId,
    required List<({String itemId, int qty, double unitPrice, double taxRate, String? hsnCode})> lines,
  }) async {
    final id = await sb.rpc('fn_create_po', params: {
      'p_vendor': vendorId,
      'p_project': projectId,
      'p_delivery_date': deliveryDate?.toIso8601String().split('T').first,
      'p_lines': [
        for (final l in lines)
          {'item_catalog_id': l.itemId, 'qty': l.qty, 'unit_price': l.unitPrice, 'tax_rate': l.taxRate, 'hsn_code': l.hsnCode},
      ],
      'p_notes': notes,
      'p_payment_terms': paymentTerms,
      'p_ship_to': shipTo,
      'p_requirement': requirementId,
      'p_stock_request': stockRequestId,
    });
    return id as String;
  }

  /// PM signs a project PO (moves it to final approval).
  Future<void> pmSignPo(String poId, {String? note}) =>
      sb.rpc('fn_pm_sign_po', params: {'p_po': poId, 'p_note': note});

  /// Final approver (admin / owner) signs off — the order is now placed.
  Future<void> finalApprovePo(String poId, {String? note}) =>
      sb.rpc('fn_final_approve_po', params: {'p_po': poId, 'p_note': note});

  /// Reject a PO with a reason — sends it back to procurement to fix & resubmit.
  Future<void> rejectPo(String poId, String reason) =>
      sb.rpc('fn_reject_po', params: {'p_po': poId, 'p_reason': reason});

  /// Fix a rejected PO and send it round the approval chain again. Replaces the
  /// lines + vendor/terms and re-enters at the PM (project PO) or final approval.
  Future<void> resubmitPo(String poId, {
    String? vendorId, DateTime? deliveryDate, String? paymentTerms, String? notes, String? shipTo,
    required List<({String itemId, int qty, double unitPrice, double taxRate, String? hsnCode})> lines,
  }) =>
      sb.rpc('fn_resubmit_po', params: {
        'p_po': poId,
        'p_vendor': vendorId,
        'p_delivery_date': deliveryDate?.toIso8601String().split('T').first,
        'p_lines': [
          for (final l in lines)
            {'item_catalog_id': l.itemId, 'qty': l.qty, 'unit_price': l.unitPrice, 'tax_rate': l.taxRate, 'hsn_code': l.hsnCode},
        ],
        'p_notes': notes,
        'p_payment_terms': paymentTerms,
        'p_ship_to': shipTo,
      });

  /// POs awaiting a signature — the approvals inbox (PM + final approver),
  /// already carrying a deterministic priority + sort rank.
  Future<List<PoApproval>> poApprovals() async {
    final d = await sb.from('v_po_pending_approvals').select();
    return (d as List).map((e) => PoApproval.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Admin sets or clears a PO's approval priority (null → back to the auto rule).
  Future<void> setPoPriority(String poId, String? priority) =>
      sb.rpc('fn_set_po_priority', params: {'p_po': poId, 'p_priority': priority});

  /// Pending stock reorder requests raised by Store (general essentials, no
  /// project). These sit alongside project order-by alerts in "To Order".
  Future<List<StockRequest>> stockRequests() async {
    final d = await sb.from('stock_requests')
        .select('id,qty,note,status,created_at,item_catalog_id,item_catalog(name)')
        .eq('status', 'pending').order('created_at', ascending: true);
    return (d as List).map((e) => StockRequest.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Add a new vendor, with the tax identity a PO document needs.
  Future<void> addVendor({required String name, String? category, int avgLead = 0,
      String? gstin, String? address, String? state, String? email}) async {
    await sb.from('vendors').insert({
      'name': name, 'category': category, 'avg_lead_time_days': avgLead, 'reliability_score': 100,
      'gstin': gstin, 'address': address, 'state': state, 'email': email,
    });
  }

  /// One vendor with full detail (for the PO document's supplier block).
  Future<VendorRow?> vendorById(String id) async {
    final d = await sb.from('vendors')
        .select('id,name,category,gstin,address,state,email,avg_lead_time_days,reliability_score')
        .eq('id', id).maybeSingle();
    return d == null ? null : VendorRow.fromMap(d);
  }

  /// The buyer identity shown at the top of a PO document.
  Future<CompanySettings> companySettings() async {
    final d = await sb.from('company_settings').select().limit(1).maybeSingle();
    return CompanySettings.fromMap(d ?? const <String, dynamic>{});
  }

  /// Save the buyer identity (admin only, enforced by RLS).
  Future<void> saveCompanySettings({required String name, String? address,
      String? gstin, String? state, String? phone, String? email}) async {
    await sb.from('company_settings').update({
      'name': name, 'address': address, 'gstin': gstin, 'state': state,
      'phone': phone, 'email': email, 'updated_at': DateTime.now().toIso8601String(),
    }).eq('only_one', true);
  }

  /// Everything needed to render a PO document: buyer + supplier + the PO.
  Future<PoDocData> poDocData(String poId) async {
    final detail = await poDetail(poId);
    final company = await companySettings();
    final vendor = detail.po.vendorId == null ? null : await vendorById(detail.po.vendorId!);
    return PoDocData(company: company, vendor: vendor, detail: detail);
  }

  /// Mark a PO received: status→received, lines fully received, GRN logged,
  /// linked requirements closed. (Store then logs individual components at intake.)
  /// Mark a PO received. Goes through fn_receive_po (0013) so it happens in one
  /// transaction and the received quantities actually land in stock_items —
  /// which procurement can't write directly, and which nothing used to update,
  /// so Store's inventory and low-stock alerts stayed frozen at the seed values.
  Future<void> markReceived(String poId) =>
      sb.rpc('fn_receive_po', params: {'p_po': poId});

  /// Vendors with reliability + lead time.
  Future<List<VendorRow>> vendors() async {
    final d = await sb.from('vendors')
        .select('id,name,category,gstin,address,state,email,avg_lead_time_days,reliability_score')
        .order('name', ascending: true);
    return (d as List).map((e) => VendorRow.fromMap(e as Map<String, dynamic>)).toList();
  }

}

// ---- Riverpod providers ----
final projectsRepoProvider = Provider<ProjectsRepo>((ref) => ProjectsRepo());
final procurementRepoProvider = Provider<ProcurementRepo>((ref) => ProcurementRepo());

final fleetProvider = FutureProvider<FleetData>((ref) async {
  ref.watch(currentUserIdProvider);
  final repo = ref.read(projectsRepoProvider);
  await repo.refreshStatuses(); // statuses drift with the calendar, so refresh on load
  final projects = await repo.all();
  final due = await repo.orderDue();
  return FleetData(projects, due);
});

final toOrderProvider = FutureProvider<List<OrderDue>>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).toOrder();
});

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).purchaseOrders();
});
final poDetailProvider = FutureProvider.family<PoDetail, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).poDetail(id);
});
final stockRequestsProvider = FutureProvider<List<StockRequest>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).stockRequests();
});
final vendorsProvider = FutureProvider<List<VendorRow>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).vendors();
});
final allProjectsProvider = FutureProvider<List<Project>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).all();
});
final itemsProvider = FutureProvider<List<OptRef>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).items();
});
final essentialItemsProvider = FutureProvider<List<OptRef>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).essentials();
});

/// POs awaiting a signature — feeds the PM's and the final approver's inbox.
/// (Distinct from `pendingApprovalsProvider`, which is stage-completion approvals.)
final poApprovalsProvider = FutureProvider<List<PoApproval>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).poApprovals();
});

/// The buyer identity for the PO document (and the Company Settings screen).
final companySettingsProvider = FutureProvider<CompanySettings>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).companySettings();
});

/// Everything needed to render a PO document, keyed by PO id.
final poDocProvider = FutureProvider.family<PoDocData, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(procurementRepoProvider).poDocData(id);
});

/// Project detail (project + stages), keyed by project id.
final projectDetailProvider = FutureProvider.family<ProjectDetailData, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).detail(id);
});

/// Delays logged across a build (dossier attribution), keyed by project id.
final projectDelaysProvider = FutureProvider.family<List<ProjectDelay>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).projectDelays(id);
});

/// Every component installed on a build (truck record), keyed by project id.
final truckComponentsProvider = FutureProvider.family<List<TruckComponent>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).truckComponents(id);
});

/// A build's documents, staff view (keyed by project id).
final projectDocsProvider = FutureProvider.family<List<ClientDoc>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).documents(id);
});

/// Stage detail bundle (photos + parts + checklist + delays), keyed by stage id.
final stageBundleProvider = FutureProvider.family<StageBundle, String>((ref, stageId) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).stageBundle(stageId);
});

/// A project's procurement requirements (Hero #1, editable), keyed by project id.
final requirementsProvider = FutureProvider.family<List<Requirement>, String>((ref, projectId) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).requirements(projectId);
});

/// Execution staff a PM can assign stages to (workshop/design/store/service).
final assignableMembersProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).assignableMembers();
});

/// Same list, but ordered so the stage's own discipline comes first.
/// Keyed by discipline ('design', 'workshop', 'store', 'service').
final assignableForDisciplineProvider =
    FutureProvider.family<List<Member>, String?>((ref, discipline) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).assignableMembers(discipline: discipline);
});

/// The builds I personally hold a stage on — "my work" for any execution role.
/// Design/Store/Service screens scope to this instead of the whole fleet.
final assignedProjectsProvider = FutureProvider<List<Project>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).myAssignedProjects();
});

/// Same builds, enriched with my stage's due date + the delivery date, soonest
/// first — for the "Assigned to me" carousel.
final myAssignedBuildsProvider = FutureProvider<List<AssignedBuild>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).myAssignedBuilds();
});

/// Stages across the signed-in PM's builds that still need handing out.
final stagesToAssignProvider = FutureProvider<List<AssignableStage>>((ref) async {
  ref.watch(currentUserIdProvider);
  final repo = ref.read(projectsRepoProvider);
  final mine = await ref.read(pmRepoProvider).myProjects();
  return repo.stagesNeedingAssignment(mine);
});

/// Pending stage-completion approvals for the signed-in PM's projects.
final pendingApprovalsProvider = FutureProvider<List<ApprovalItem>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(projectsRepoProvider).pendingApprovals();
});

/// Store / Inventory — component traceability (Hero #2) + stock.
class StoreRepo {
  static const _compSelect =
      'id,serial_number,status,warranty_end,install_date,bill_url,item_catalog_id,item_catalog(name,model),projects(code),vendors(name)';

  Future<List<ComponentRow>> components() async {
    final d = await sb.from('component_instances').select(_compSelect).order('serial_number', ascending: true);
    return (d as List).map((e) => ComponentRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// On-hand inventory — the *truthful* count.
  ///
  /// Two kinds of item live side by side:
  ///  • Bulk / consumable items (item_catalog.serialized = false) — screws,
  ///    sheet, wire. Their on-hand is the running quantity in stock_items.
  ///  • Serialized items (serialized = true) — LED screens, inverters. Each
  ///    physical unit is a component_instance with a serial, so on-hand is
  ///    simply how many of them are still 'in_stock'. Installing one flips it
  ///    to 'installed', so the count drops on its own — no manual decrement.
  ///
  /// stock_items is deliberately ignored for serialized items: fn_receive_po
  /// tops it up on receipt, but Store also logs each unit as a component, so
  /// trusting both would double-count. The component ledger is the source of
  /// truth for anything serialized.
  Future<List<StockRow>> stock() async {
    // The catalogue is the spine of the list: every tracked item should appear,
    // whether or not it has stock yet. Building the serialized rows from the
    // component ledger alone meant a serialized item with no units logged was
    // absent from Store → Stock entirely — which is exactly the state in which
    // you need to see it ("we have none of these") rather than nothing at all.
    final catalog = await sb.from('item_catalog')
        .select('id,name,category,low_stock_threshold,serialized,unit,is_essential');
    final si = await sb.from('stock_items').select('quantity,unit,item_catalog_id');
    final comps = await sb.from('component_instances').select('status,item_catalog_id');

    final bulkQty = <String, num>{};
    final bulkUnit = <String, String?>{};
    for (final e in (si as List)) {
      final m = e as Map<String, dynamic>;
      final id = m['item_catalog_id'] as String?;
      if (id == null) continue;
      bulkQty[id] = (bulkQty[id] ?? 0) + ((m['quantity'] as num?) ?? 0);
      bulkUnit[id] ??= m['unit'] as String?;
    }

    // Serialized on-hand = how many of its units are still 'in_stock'.
    // Installing one flips it to 'installed', so the count drops on its own.
    final onHand = <String, int>{};
    for (final e in (comps as List)) {
      final m = e as Map<String, dynamic>;
      final id = m['item_catalog_id'] as String?;
      if (id == null) continue;
      onHand[id] = (onHand[id] ?? 0) + (m['status'] == 'in_stock' ? 1 : 0);
    }

    final rows = <StockRow>[];
    for (final e in (catalog as List)) {
      final ic = e as Map<String, dynamic>;
      final id = ic['id'] as String;
      final serialized = (ic['serialized'] as bool?) ?? true;
      // stock_items is deliberately ignored for a serialized item: fn_receive_po
      // leaves it alone on purpose (0018) and the component ledger is the truth.
      final qty = serialized ? (onHand[id] ?? 0) : (bulkQty[id] ?? 0);
      rows.add(StockRow(
        itemCatalogId: id,
        name: ic['name'] as String? ?? 'Item',
        category: ic['category'] as String?,
        unit: (serialized ? null : bulkUnit[id]) ?? ic['unit'] as String? ?? 'pcs',
        quantity: qty,
        threshold: (ic['low_stock_threshold'] as num?)?.toInt() ?? 0,
        isEssential: (ic['is_essential'] as bool?) ?? false,
      ));
    }

    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  /// Raise a reorder request to Procurement for a general essential (wheels,
  /// sheets, metal…). Goes through fn_request_stock, which notifies Procurement.
  Future<void> requestStock({required String itemId, required int qty, String? note}) =>
      sb.rpc('fn_request_stock', params: {
        'p_item': itemId, 'p_qty': qty,
        'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      });

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

  /// Log a component at intake: serial + warranty + bill, and optionally
  /// **reserve** it for a build.
  ///
  /// Reserving is not installing. This used to write `status: 'installed'` with
  /// an install date and no stage the moment a build was picked — so a part that
  /// had merely arrived was recorded as fitted, by nobody, into no stage. It then
  /// appeared in the truck's record under "at intake" with an empty history, it
  /// was counted out of Store's on-hand, and Workshop could no longer scan it in
  /// (`fn_install_component` only accepts in-stock parts), which skipped the one
  /// step that records who fitted it and where.
  ///
  /// So a reserved part stays `in_stock` — it is physically on the shelf — and
  /// carries the build it is earmarked for. Workshop's scan-to-install is still
  /// what turns it into an installed part, through `fn_install_component`.
  Future<void> logComponent({
    required String itemId, required String serial, String? vendorId,
    DateTime? warrantyEnd, String? projectId, String? billUrl,
  }) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    await sb.from('component_instances').insert({
      'item_catalog_id': itemId,
      'serial_number': serial,
      'vendor_id': vendorId,
      'warranty_start': today,
      'warranty_end': warrantyEnd?.toIso8601String().split('T').first,
      'status': 'in_stock',
      'installed_in_project_id': projectId,   // an earmark, not an installation
      'bill_url': billUrl,
    });
  }

  /// Upload a part's bill/invoice image to the public `builds` bucket (under
  /// `bills/`) and return its URL, to store on the component at intake. This is
  /// the other half of Hero #2: warranty told you the part is covered, the bill
  /// is what a vendor actually needs to honour it.
  Future<String> uploadBill(Uint8List bytes, {required String filename, required String contentType}) =>
      uploadToBuilds(bytes, filename: filename, contentType: contentType, folder: 'bills');
}

final storeRepoProvider = Provider<StoreRepo>((ref) => StoreRepo());
final componentsProvider = FutureProvider<List<ComponentRow>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(storeRepoProvider).components();
});
final stockProvider = FutureProvider<List<StockRow>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(storeRepoProvider).stock();
});
final recallProvider = FutureProvider.family<List<RecallRow>, String>((ref, itemId) {
  ref.watch(currentUserIdProvider);
  return ref.read(storeRepoProvider).recall(itemId);
});

/// Workshop — stages assigned to me, install parts (Hero #2), submit for approval.
class WorkshopRepo {
  String? get _uid => sb.auth.currentUser?.id;

  /// The stages assigned to me, enriched with what the PM did with my last
  /// submission — so a task can show "waiting for approval" or the reason it
  /// was sent back instead of silently sitting there.
  Future<List<WorkshopTask>> myTasks() async {
    final uid = _uid;
    if (uid == null) return [];
    // Disambiguate: stages ↔ projects has two FKs, so name the one we mean.
    final d = await sb.from('stages')
        .select('id,name,status,project_id,assigned_due,'
                'projects!stages_project_id_fkey(code,name,status)')
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
    // Which of these cannot start yet, and what they are waiting for (0031).
    //
    // Read from `v_stage_gate` — the same rule fn_start_stage enforces — rather
    // than worked out here, because this list only holds *my* stages: the
    // stage blocking me usually belongs to somebody else and is not in it.
    // One round trip, like the approvals lookup above.
    final gates = await sb.from('v_stage_gate')
        .select('stage_id,is_locked,blocked_by,blocked_by_count')
        .inFilter('stage_id', tasks.map((t) => t.stageId).toList());
    final locked = <String, ({String? by, int count})>{};
    for (final g in (gates as List)) {
      if (g['is_locked'] == true) {
        locked[g['stage_id'] as String] = (
          by: g['blocked_by'] as String?,
          count: (g['blocked_by_count'] as num?)?.toInt() ?? 1,
        );
      }
    }

    // Sorted worst-first across every build, not by `ord`.
    //
    // `ord` is a stage's position *inside its own build*, so ordering a mixed
    // list by it interleaves two trucks meaninglessly — and an overdue stage on
    // AZ-205 could sort below a not-yet-started one on AZ-101. The person
    // holding stages on eight builds is exactly who this list is for.
    return [
      for (final t in tasks)
        t.copyWith(
          awaitingApproval: pending.contains(t.stageId),
          reworkNote: t.status == 'rework' ? notes[t.stageId] : null,
          isLocked: locked.containsKey(t.stageId),
          blockedBy: locked[t.stageId]?.by,
          blockedByCount: locked[t.stageId]?.count ?? 0,
        ),
    ]..sort(WorkshopTask.compare);
  }

  /// Mark a stage as actually started.
  ///
  /// Nothing used to make this transition, so every stage sat on 'todo' forever
  /// and the PM's "in progress today" and workload numbers were both
  /// permanently empty.
  Future<void> startTask(String stageId) async {
    await sb.rpc('fn_start_stage', params: {'p_stage': stageId});
  }

  /// Edit a build's checklist. PM and admin only — `trg_guard_checklist` (0028)
  /// enforces that server-side, because the assignee holds write on the same
  /// rows so they can tick items and could otherwise rewrite what "done" means.
  ///
  /// This edits *this build's* checklist, not the workflow template it came
  /// from: fixing a typo on a live build should not silently change every
  /// future build, and changing the template should not rewrite history on
  /// builds already running.
  Future<void> renameCheck(String id, String label) async {
    final v = label.trim();
    if (v.isEmpty) throw Exception('A checklist item needs a label.');
    await sb.from('checklist_items').update({'label': v}).eq('id', id);
  }

  Future<void> addCheck(String stageId, String label) async {
    final v = label.trim();
    if (v.isEmpty) throw Exception('A checklist item needs a label.');
    await sb.from('checklist_items').insert({'stage_id': stageId, 'label': v, 'done': false});
  }

  Future<void> removeCheck(String id) async {
    await sb.from('checklist_items').delete().eq('id', id);
  }

  /// Tick (or un-tick) one check.
  ///
  /// Through `fn_tick_check` since 0029, not a direct column write — that is
  /// what records **who** ticked it and **when**, puts it in the audit log,
  /// refuses it on a stage the PM has already approved, and enforces a
  /// photo-required check. A direct update of `done` is now refused by
  /// `trg_guard_checklist`, so there is no path around the record.
  ///
  /// [proofAttachmentId] is the stage photo that discharges a photo-required
  /// check. The server checks the photo really is on this stage.
  Future<void> toggleChecklist(String id, bool done, {String? proofAttachmentId}) async {
    await sb.rpc('fn_tick_check', params: {
      'p_item': id, 'p_done': done,
      if (proofAttachmentId != null) 'p_proof': proofAttachmentId,
    });
  }

  /// Whether a check needs a photo. The PM's call, on one build's stage —
  /// `trg_guard_checklist` holds it to them and an admin.
  Future<void> setCheckPhotoRequired(String id, bool required) async {
    await sb.from('checklist_items').update({'photo_required': required}).eq('id', id);
  }

  /// Report why this stage slipped.
  ///
  /// The fitter is the one who knows — 0029 narrowed `delay_logs` from "any
  /// workshop member, any stage" to the stage's own assignee, their PM and an
  /// admin, which is what made it safe to offer here.
  Future<void> logStageDelay(String stageId, {
    required String reasonCode, required int days, String? note,
  }) async {
    await sb.from('delay_logs').insert({
      'stage_id': stageId,
      'reason_code': reasonCode,
      'days_delayed': days,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'logged_by': _uid,
    });
  }

  /// Components sitting in store (available to install).
  ///
  /// Ordered so the parts bought **for this build** come first. The fitter used
  /// to get every serialised part in the building in one flat alphabetical
  /// list, with the build each was earmarked for not even shown — which is how
  /// the wrong part gets fitted. Parts reserved for a *different* build are
  /// kept in the list rather than hidden: they are the ones most likely to be
  /// reached for by mistake, and saying who they belong to is the point
  /// (0029 refuses the install outright).
  Future<List<ComponentRow>> inStock({String? forProjectId}) async {
    final d = await sb.from('component_instances').select(StoreRepo._compSelect)
        .eq('status', 'in_stock').order('serial_number', ascending: true);
    final rows = (d as List).map((e) => ComponentRow.fromMap(e as Map<String, dynamic>)).toList();
    if (forProjectId == null) return rows;

    final mine = await sb.from('component_instances').select('id')
        .eq('status', 'in_stock').eq('installed_in_project_id', forProjectId);
    final reservedHere = {for (final e in (mine as List)) e['id'] as String};
    int rank(ComponentRow c) {
      if (reservedHere.contains(c.id)) return 0;   // bought for this truck
      if (!c.isReserved) return 1;                 // free stock
      return 2;                                   // someone else's
    }
    rows.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.serial.compareTo(b.serial);
    });
    return rows;
  }

  /// The ids of in-stock parts earmarked for this build, so the install screen
  /// can say which row is the one that was bought for this truck.
  Future<Set<String>> reservedFor(String projectId) async {
    final d = await sb.from('component_instances').select('id')
        .eq('status', 'in_stock').eq('installed_in_project_id', projectId);
    return {for (final e in (d as List)) e['id'] as String};
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
  /// Returns the new attachment's id, because a photo is not only a photo any
  /// more: 0029 lets a check demand one, and the check records *which* photo
  /// discharged it.
  Future<String> addStagePhoto(String stageId, Uint8List bytes, {
    required String filename, required String contentType, String? caption,
  }) async {
    final url = await uploadToBuilds(bytes,
      filename: filename, contentType: contentType, folder: 'stages/$stageId');
    final row = await sb.from('attachments').insert({
      'owner_type': 'stage', 'owner_id': stageId, 'uploaded_by': _uid,
      'file_url': url,
      'caption': (caption == null || caption.trim().isEmpty) ? 'Work photo' : caption.trim(),
    }).select('id').single();
    return row['id'] as String;
  }

  /// Remove a stage photo.
  ///
  /// A photo could be added and never taken back, so a fitter who uploaded the
  /// wrong shot — or one with a face, or a whiteboard — had no way out. 0030
  /// puts the rule behind it: whoever took it, the build's PM, or an admin,
  /// and nobody at all once the PM has approved the stage, which is the same
  /// freeze the checklist has.
  ///
  /// `checklist_items.proof_attachment_id` is ON DELETE SET NULL, so deleting a
  /// photo that discharged a check leaves the check ticked but without proof —
  /// which the row then says out loud rather than implying it still has one.
  Future<void> deleteStagePhoto(String attachmentId) async {
    await sb.from('attachments').delete().eq('id', attachmentId);
  }

  /// Find a part by the serial the camera just read.
  ///
  /// Case-insensitive and whitespace-tolerant, because a scan can pick up
  /// padding and labels aren't consistent about case.
  Future<ComponentRow?> findBySerial(String serial) async {
    final q = serial.trim();
    if (q.isEmpty) return null;
    // Escaped, not raw: `%` and `_` are LIKE wildcards, so a serial containing
    // an underscore — plenty of them do — used to match a *different* part, and
    // a scan picking up a stray `%` would match the first part in the table.
    // Still case-insensitive and whitespace-tolerant, because labels are not
    // consistent about case and a scanner can pick up padding.
    final pattern = q.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
    final d = await sb.from('component_instances')
        .select(StoreRepo._compSelect)
        .ilike('serial_number', pattern)
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
  ref.watch(currentUserIdProvider);
  return ref.read(workshopRepoProvider).myTasks();
});
final inStockProvider = FutureProvider<List<ComponentRow>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(workshopRepoProvider).inStock();
});
/// Parts on the builds I hold a stage on.
///
/// Watches [myTasksProvider] rather than calling `myTasks()` again: this used
/// to re-run the stages query *and* its approvals follow-up every time the
/// Parts tab opened, and could then disagree with the Tasks tab it was derived
/// from.
final workshopPartsProvider = FutureProvider<List<ComponentRow>>((ref) async {
  final tasks = await ref.watch(myTasksProvider.future);
  final ids = tasks.map((t) => t.projectId).toSet().toList();
  return ref.read(workshopRepoProvider).installedForProjects(ids);
});

/// In-stock components, with the ones bought for [projectId] first.
final inStockForProvider = FutureProvider.family<List<ComponentRow>, String?>((ref, projectId) {
  ref.watch(currentUserIdProvider);
  return ref.read(workshopRepoProvider).inStock(forProjectId: projectId);
});

/// Which in-stock parts are earmarked for this build.
final reservedForProvider = FutureProvider.family<Set<String>, String>((ref, projectId) {
  ref.watch(currentUserIdProvider);
  return ref.read(workshopRepoProvider).reservedFor(projectId);
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
  ref.watch(currentUserIdProvider);
  return ref.read(clientRepoProvider).myTrucks();
});
final truckPhotosProvider = FutureProvider.family<List<StagePhoto>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(clientRepoProvider).photos(id);
});
final stagePhotosProvider = FutureProvider.family<List<StagePhoto>, String>((ref, stageId) {
  ref.watch(currentUserIdProvider);
  return ref.read(clientRepoProvider).stagePhotos(stageId);
});
final truckDocsProvider = FutureProvider.family<List<ClientDoc>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(clientRepoProvider).documents(id);
});
final truckDesignsProvider = FutureProvider.family<List<DesignRow>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(clientRepoProvider).designs(id);
});
final myTicketsProvider = FutureProvider<List<TicketRow>>((ref) {
  ref.watch(currentUserIdProvider);
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
    // `step` is what waits for what; `ord` is only the order they are listed
    // in (0031). A stage marked "runs alongside the one above" shares its step.
    final steps = stepsFor(stages);
    for (var i = 0; i < stages.length; i++) {
      final st = await sb.from('template_stages').insert({
        'template_id': tid, 'name': stages[i].name, 'ord': i + 1,
        'step': steps[i], 'default_duration_days': stages[i].days,
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

  /// List all team members (with their sub-team, if any).
  Future<List<Member>> members() async {
    final d = await sb.from('profiles')
        .select('id,full_name,email,role,status,sub_team_id,sub_teams(name)')
        .order('full_name', ascending: true);
    return (d as List).map((e) => Member.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// The sub-teams (department → team). Used by Add Member + the ops rollups.
  Future<List<SubTeam>> subTeams() async {
    final d = await sb.from('sub_teams').select('id,role,name').order('name', ascending: true);
    return (d as List).map((e) => SubTeam.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Create a new sub-team under a department (admin only, enforced by RLS).
  Future<SubTeam> createSubTeam(String role, String name) async {
    final d = await sb.from('sub_teams')
        .insert({'role': role, 'name': name}).select('id,role,name').single();
    return SubTeam.fromMap(d);
  }

  /// Create a member via the admin-create-member Edge Function (server-side, secure).
  /// If [password] is given → direct create (no email needed); else → email invite.
  /// [subTeamId] (optional) places them in a team within their department; it is
  /// set here as a follow-up profile update (admin RLS allows it), so the Edge
  /// Function doesn't need redeploying.
  Future<void> createMember({
    required String fullName, required String email,
    String? phone, required String role, String? businessName, String? password,
    String? subTeamId,
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
    final uid = data is Map ? data['user_id'] as String? : null;
    if (subTeamId != null && uid != null) {
      await sb.from('profiles').update({'sub_team_id': subTeamId}).eq('id', uid);
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
  /// Create a build and, when a template is chosen, generate its plan.
  ///
  /// [templateId] is optional since 0031. An admin knows the client, the code
  /// and who is managing it; the **PM** is the one who knows what this
  /// particular truck involves, so the admin can hand the build over with no
  /// plan at all and the PM builds it from their own screen. The project row
  /// is identical either way — `projects.template_id` has always been nullable
  /// — it simply has no stages until somebody chooses one.
  Future<void> onboard({
    required String code, required String name, String? templateId,
    required String pmId, String? clientId, required DateTime target,
  }) async {
    final proj = await sb.from('projects').insert({
      'code': code.trim(), 'name': name.trim(), 'template_id': templateId,
      'client_account_id': clientId,
      // With a template, the PM is set here and fn_onboard_project tells them.
      // Without one, the row goes in PM-less and fn_assign_pm does both, so the
      // hand-over is a real assignment rather than a column write nobody hears.
      if (templateId != null) ...{
        'pm_id': pmId,
        'pm_assigned_at': DateTime.now().toIso8601String(),
      },
      'target_delivery_date': target.toIso8601String().split('T').first,
    }).select('id').single();
    if (templateId != null) {
      await sb.rpc('fn_onboard_project', params: {'p_project': proj['id']});
    } else {
      // No plan yet, so fn_onboard_project — which is what normally tells the
      // PM the build is theirs — is not being called. fn_assign_pm does the
      // same job and is the sanctioned path for it: fn_notify itself is
      // revoked from `authenticated` (0026) precisely so notifications cannot
      // be written by a client.
      await sb.rpc('fn_assign_pm', params: {
        'p_project': proj['id'], 'p_pm': pmId,
      });
    }
  }

  /// Choose the workflow template for a build that was handed over without one,
  /// and generate its stages. The build's own PM may do this, or an admin
  /// (0031).
  Future<void> setUpPlan(String projectId, String templateId) async {
    await sb.from('projects').update({'template_id': templateId}).eq('id', projectId);
    await sb.rpc('fn_onboard_project', params: {'p_project': projectId});
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
        .select('id,title,body,type,read,created_at,entity_type,entity_id')
        .order('created_at', ascending: false);
    return (d as List).map((e) => AppNotification.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Mark one notification read — what tapping it should do, on top of opening
  /// whatever it is about.
  Future<void> markRead(String id) async {
    await sb.from('notifications').update({'read': true}).eq('id', id);
  }

  /// Mark every unread notification as read (RLS keeps this to the current user).
  Future<void> markAllRead() async {
    await sb.from('notifications').update({'read': true}).eq('read', false);
  }
}

final notificationsRepoProvider = Provider<NotificationsRepo>((ref) => NotificationsRepo());
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(notificationsRepoProvider).all();
});

/// Unread count for the bell badges. Now that assignments and approvals actually
/// write notifications, this is a real number.
final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull;
  if (list == null) return 0;
  var n = 0;
  for (final x in list) { if (!x.read) n++; }
  return n;
});

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
      projectId: e['project_id'] as String? ?? '',
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
  /// The PM's builds, each with its whole pipeline and what is blocking it.
  ///
  /// Three things the flat schedule query could not provide:
  ///   * **finished stages** — the strip shows the shape of the build, and a
  ///     build four stages in looks nothing like one that has not started;
  ///   * **the delivery date** — `myProjects` does not select it, and "late"
  ///     means nothing without it;
  ///   * **pending approvals** — a stage sitting with the PM is the one kind of
  ///     blockage the PM is causing themselves, and it looked like any other row.
  Future<List<BuildSchedule>> buildSchedules() async {
    final uid = _uid;
    if (uid == null) return [];

    final pr = await sb.from('projects')
        .select('id,code,name,status,progress_pct,pm_id,target_delivery_date')
        .eq('pm_id', uid).order('code', ascending: true);
    final projects = (pr as List).cast<Map<String, dynamic>>();
    if (projects.isEmpty) return [];

    final ids = [for (final p in projects) p['id'] as String];

    final st = await sb.from('stages')
        .select('id,name,status,ord,step,project_id,assignee_id,discipline,assigned_due,planned_end')
        .inFilter('project_id', ids).order('ord', ascending: true);
    final rows = (st as List).cast<Map<String, dynamic>>();

    // Assignee names in one round-trip rather than one per stage.
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

    // Which stages are sitting with this PM. Filtered on stage_id rather than
    // approver_id so a build handed over mid-flight still reports correctly.
    final pending = <String>{};
    if (rows.isNotEmpty) {
      final ap = await sb.from('stage_approvals')
          .select('stage_id')
          .eq('status', 'pending')
          .inFilter('stage_id', [for (final r in rows) r['id'] as String]);
      for (final a in (ap as List)) {
        pending.add(a['stage_id'] as String);
      }
    }

    final byProject = <String, List<StageTick>>{};
    for (final r in rows) {
      final aid = r['assignee_id'] as String?;
      final nm = aid == null ? null : names[aid];
      (byProject[r['project_id'] as String] ??= []).add(StageTick(
        id: r['id'] as String,
        name: r['name'] as String? ?? '',
        status: r['status'] as String? ?? 'todo',
        ord: (r['ord'] as num?)?.toInt() ?? 0,
        step: (r['step'] as num?)?.toInt() ?? (r['ord'] as num?)?.toInt() ?? 0,
        assigneeName: (nm == null || nm.isEmpty) ? null : nm,
        discipline: r['discipline'] as String?,
        // The PM's own commitment if there is one, else the backward-scheduled plan.
        due: parseDate(r['assigned_due']) ?? parseDate(r['planned_end']),
        awaitingApproval: pending.contains(r['id'] as String),
      ));
    }

    final out = [
      for (final p in projects)
        BuildSchedule(
          project: Project.fromMap(p),
          targetDelivery: parseDate(p['target_delivery_date']),
          stages: byProject[p['id'] as String] ?? const [],
        ),
    ]..sort(BuildSchedule.compare);
    return out;
  }

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
  ref.watch(currentUserIdProvider);
  return ref.read(pmRepoProvider).myProjects();
});
final pmDashboardProvider = FutureProvider<({List<Project> projects, List<ActiveStage> stages})>((ref) async {
  ref.watch(currentUserIdProvider);
  await ref.read(projectsRepoProvider).refreshStatuses(); // statuses drift with the calendar
  final repo = ref.read(pmRepoProvider);
  final projects = await repo.myProjects();
  final stages = await repo.activeStages(projects);
  return (projects: projects, stages: stages);
});
/// The signed-in PM's schedule — open stages across their builds, soonest first.
/// The PM's schedule, build by build — the default lens on the Schedule tab.
final pmBuildScheduleProvider = FutureProvider<List<BuildSchedule>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(pmRepoProvider).buildSchedules();
});

final pmScheduleProvider = FutureProvider<List<ScheduleEntry>>((ref) async {
  ref.watch(currentUserIdProvider);
  final projects = await ref.read(pmRepoProvider).myProjects();
  return ref.read(pmRepoProvider).schedule(projects);
});
final workloadProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(pmRepoProvider).workload();
});

final adminRepoProvider = Provider<AdminRepo>((ref) => AdminRepo());
final membersProvider   = FutureProvider<List<Member>>((ref) { ref.watch(authStateProvider); return ref.read(adminRepoProvider).members(); });
final subTeamsProvider  = FutureProvider<List<SubTeam>>((ref) { ref.watch(authStateProvider); return ref.read(adminRepoProvider).subTeams(); });

/// The factory board for the admin command center.
final opsBoardProvider  = FutureProvider<List<OpsRow>>((ref) async {
  ref.watch(currentUserIdProvider);
  final repo = ref.read(projectsRepoProvider);
  await repo.refreshStatuses(); // keep the board honest as the calendar moves
  return repo.opsBoard();
});
final templatesProvider = FutureProvider<List<OptRef>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(adminRepoProvider).templates();
});
final clientsProvider = FutureProvider<List<OptRef>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(adminRepoProvider).clients();
});
final pmsProvider = FutureProvider<List<OptRef>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(adminRepoProvider).pms();
});

/// Legacy client accounts with no login (e.g. the demo seed row). Onboarding
/// hides them from the picker, so it explains the gap using this count.
final loginlessClientsProvider = FutureProvider<int>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(adminRepoProvider).loginlessClientCount();
});


/// Designer — create designs, upload versions (2D image + .glb model),
/// submit for client approval, and track the outcome / feedback loop.
class DesignRepo {
  static const _artifactSelect =
      'id,type,status,project_id,stage_id,current_version_id,client_feedback, projects(code,name)';

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
        .select('id,type,status,project_id,stage_id,current_version_id,client_feedback, projects(code,name)')
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
  ///
  /// Goes through fn_create_design (0026) rather than three separate client
  /// writes. Two reasons: it is one transaction, so a failure halfway can no
  /// longer leave an artifact with no version and a null current_version_id
  /// (which rendered as a broken, un-openable design); and it notifies the
  /// client and the PM when the design is submitted. The screen has always said
  /// "they've been notified" — now that is true.
  /// [stageId] links the design to the stage it is the deliverable for (0028).
  /// Null is allowed — a build may have no design stage, or the designer may be
  /// working ahead of one — and the submit rule then falls back to "any
  /// approved design on this build".
  Future<void> create({
    required String projectId, required String type,
    String? stageId,
    String? modelUrl, String? imageUrl, String? changeNote, required bool submit,
  }) async {
    await sb.rpc('fn_create_design', params: {
      'p_project': projectId,
      'p_type': type,
      'p_stage': stageId,
      'p_model_url': _clean(modelUrl),
      'p_image_url': _clean(imageUrl),
      'p_change_note': _clean(changeNote),
      'p_submit': submit,
    });
  }

  /// Add a new version to an existing artifact (e.g. after a change request).
  ///
  /// Goes through fn_add_design_version (migration 0025), which computes the
  /// next version_no under a row lock on the artifact — so two designers on the
  /// same build submitting a new version at the same time can no longer both
  /// grab the same number and lose one of the uploads.
  Future<void> addVersion({
    required String artifactId,
    String? modelUrl, String? imageUrl, String? changeNote, required bool submit,
  }) async {
    await sb.rpc('fn_add_design_version', params: {
      'p_artifact': artifactId,
      'p_model_url': _clean(modelUrl),
      'p_image_url': _clean(imageUrl),
      'p_change_note': _clean(changeNote),
      'p_submit': submit,
    });
  }

  /// Send an existing draft to the client for approval.
  ///
  /// Routed through fn_add_design_version with the *current* files so the
  /// client and the PM are notified, exactly as they are for a new design or a
  /// revision. The old direct `status = 'pending_approval'` write changed the
  /// row and told nobody, so a design could sit "awaiting approval" while the
  /// client had no idea it was waiting on them.
  Future<void> submitForApproval(String artifactId) async {
    final cur = await sb.from('design_artifacts')
        .select('current_version_id,design_versions!design_versions_artifact_id_fkey(id,model_url,file_url)')
        .eq('id', artifactId).single();
    String? model, image;
    final vs = cur['design_versions'] as List?;
    for (final v in (vs ?? const [])) {
      final m = v as Map<String, dynamic>;
      if (m['id'] == cur['current_version_id']) {
        model = m['model_url'] as String?;
        image = m['file_url'] as String?;
        break;
      }
    }
    await sb.rpc('fn_add_design_version', params: {
      'p_artifact': artifactId,
      'p_model_url': _clean(model),
      'p_image_url': _clean(image),
      'p_change_note': 'Submitted for client approval.',
      'p_submit': true,
    });
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
      stageId: r['stage_id'] as String?,
      versionNo: (v?['version_no'] as num?)?.toInt() ?? 1,
    );
  }
}

final designRepoProvider = Provider<DesignRepo>((ref) => DesignRepo());
final myDesignsProvider = FutureProvider<List<DesignItem>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(designRepoProvider).myDesigns();
});
final designDetailProvider = FutureProvider.family<DesignDetailData, String>((ref, artifactId) {
  ref.watch(currentUserIdProvider);
  return ref.read(designRepoProvider).detail(artifactId);
});

/// The approved .glb for a project (null = none yet). Powers the 3D showcase
/// on the client My Trucks card and the admin/PM project detail screen.
final truckModelUrlProvider = FutureProvider.family<String?, String>((ref, projectId) {
  ref.watch(currentUserIdProvider);
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
      // Calendar days, so a warranty ending today reads 0 rather than -1.
      daysLeft: end == null ? null : daysUntil(end),
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
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).tickets();
});
final serviceTicketProvider = FutureProvider.family<ServiceTicket, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).ticket(id);
});
final ticketVisitsProvider = FutureProvider.family<List<ServiceVisitRow>, String>((ref, ticketId) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).visits(ticketId);
});
final ticketPhotosProvider = FutureProvider.family<List<StagePhoto>, String>((ref, ticketId) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).ticketPhotos(ticketId);
});
final ticketComponentProvider = FutureProvider.family<WarrantyRow?, String>((ref, componentId) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).linkedComponent(componentId);
});
final techniciansProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).technicians();
});
final deliveredTrucksProvider = FutureProvider<List<DeliveredTruck>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).deliveredTrucks();
});
final truckHistoryProvider = FutureProvider.family<TruckHistory, String>((ref, projectId) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).truckHistory(projectId);
});

/// Warranty lookup, keyed by the search box text (empty = the first 100 parts).
final warrantySearchProvider = FutureProvider.family<List<WarrantyRow>, String>((ref, q) {
  ref.watch(currentUserIdProvider);
  return ref.read(serviceRepoProvider).warrantySearch(q);
});
