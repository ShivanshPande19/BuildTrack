/// Domain models (map 1:1 to Supabase tables / views).
library;

import 'package:intl/intl.dart';

class Project {
  final String id, code, name, status;
  final int progressPct;
  /// The project manager who owns this build. Null = nobody can work on it yet:
  /// no PM sees it and its stages cannot be assigned, so Admin must fix that.
  final String? pmId;
  Project({required this.id, required this.code, required this.name, required this.status,
    required this.progressPct, this.pmId});
  factory Project.fromMap(Map<String, dynamic> m) => Project(
    id: m['id'] as String,
    code: m['code'] as String? ?? '',
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'on_track',
    progressPct: (m['progress_pct'] as num?)?.toInt() ?? 0,
    pmId: m['pm_id'] as String?,
  );

  bool get hasPm => pmId != null;
}

class OrderDue {
  final String id, itemName, projectCode, projectId, itemCatalogId;
  final int qty;
  /// `order_by_date - today`, straight from v_order_due. **Null when the
  /// requirement has no order-by date yet** (the PM hasn't given it a needed-by,
  /// so nothing can be computed). It used to default to 0, which made every
  /// undated material shout "Order today" on Admin's home and Procurement's
  /// To-Order list — a false alarm on data that simply isn't planned yet.
  final int? daysLeft;
  final DateTime? orderByDate;
  OrderDue({required this.id, required this.itemName, required this.projectCode,
    required this.projectId, required this.itemCatalogId, required this.qty,
    this.orderByDate, this.daysLeft});
  factory OrderDue.fromMap(Map<String, dynamic> m) => OrderDue(
    id: m['id'] as String,
    projectId: m['project_id'] as String? ?? '',
    itemCatalogId: m['item_catalog_id'] as String? ?? '',
    qty: (m['qty'] as num?)?.toInt() ?? 1,
    itemName: m['item_name'] as String? ?? '',
    projectCode: m['project_code'] as String? ?? '',
    orderByDate: m['order_by_date'] != null ? DateTime.tryParse(m['order_by_date'].toString()) : null,
    daysLeft: (m['days_left'] as num?)?.toInt(),
  );

  /// Is this material actually planned? An unplanned one can't be urgent.
  bool get isPlanned => daysLeft != null && orderByDate != null;
  /// Sort key that pushes unplanned materials to the end instead of the front.
  int get sortKey => daysLeft ?? 1 << 20;
  /// "Order today" / "3d left" / "Needs a date".
  String get urgencyLabel {
    final d = daysLeft;
    if (d == null) return 'Needs a date';
    if (d < 0) return '${-d}d overdue';
    if (d == 0) return 'Order today';
    return '${d}d left';
  }
}

/// One line in a role's "needs attention" feed: a build or a material that
/// someone has to act on, newest problem first. Admin's home used to build this
/// from order-by alerts alone, so a build sitting in `delayed` with no material
/// alert showed "All caught up" — the exact thing the screen exists to prevent.
enum AttentionKind { delayed, atRisk, noPm, orderBy }

class AttentionItem {
  final AttentionKind kind;
  final String title, detail;
  /// The build to open when the row is tapped (null for a material with no build).
  final String? projectId;
  const AttentionItem(this.kind, {required this.title, required this.detail, this.projectId});

  /// Lower sorts first: a delayed build outranks an at-risk one, a build with
  /// no PM outranks a material that is merely due soon.
  int get rank => switch (kind) {
    AttentionKind.delayed => 0,
    AttentionKind.noPm    => 1,
    AttentionKind.atRisk  => 2,
    AttentionKind.orderBy => 3,
  };
}

/// Lightweight id+label option (for dropdowns: templates, clients, PMs).
/// Named OptRef to avoid clashing with Riverpod's `Ref`.
/// Equality by id so a freshly-created option still matches after a list refresh.
class OptRef {
  final String id, label;
  OptRef(this.id, this.label);
  @override
  bool operator ==(Object other) => other is OptRef && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// One BOM item on a template stage (item + qty).
class StageItemDraft {
  final String itemId, label;
  int qty;
  StageItemDraft(this.itemId, this.label, this.qty);
}

/// One stage while building a custom workflow template — its BOM items and the
/// checklist the assignee will tick off (copied onto every build's stage on
/// onboarding).
class StageDraft {
  String name;
  int days;
  /// This stage runs **alongside the one above it** rather than after it
  /// (0031). Expressed as a flag per stage rather than a group number because
  /// that is the question someone building a template can actually answer:
  /// "does this wait for the one before, or happen at the same time?"
  /// [stepsFor] turns a list of these into the step numbers the database wants.
  bool runsWithPrevious;
  final List<StageItemDraft> items;
  final List<String> checks;
  StageDraft(this.name, this.days, {List<StageItemDraft>? items, List<String>? checks,
    this.runsWithPrevious = false})
      : items = items ?? [],
        checks = checks ?? [];
}

/// Step numbers for a drafted template: each stage joins the previous step or
/// starts the next one. The first stage always starts step 1, whatever its
/// flag says — nothing precedes it to run alongside.
List<int> stepsFor(List<StageDraft> stages) {
  final out = <int>[];
  var step = 0;
  for (var i = 0; i < stages.length; i++) {
    if (i == 0 || !stages[i].runsWithPrevious) step++;
    out.add(step);
  }
  return out;
}

/// A pending stage-completion approval (PM approves work submitted by workshop).
class ApprovalItem {
  final String id, stageId, stageName, projectCode;
  final String? submittedBy;
  final DateTime? submittedAt;
  ApprovalItem({required this.id, required this.stageId, required this.stageName,
    required this.projectCode, this.submittedBy, this.submittedAt});
}

/// A team member (profiles row).
class Member {
  final String id, name, email, role, status;
  final String? subTeamId, subTeamName;   // team within the department (optional)
  Member({required this.id, required this.name, required this.email, required this.role,
    required this.status, this.subTeamId, this.subTeamName});
  factory Member.fromMap(Map<String, dynamic> m) {
    final st = m['sub_teams'] as Map<String, dynamic>?;
    return Member(
      id: m['id'] as String,
      name: m['full_name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      role: m['role'] as String? ?? '',
      status: m['status'] as String? ?? 'active',
      subTeamId: m['sub_team_id'] as String?,
      subTeamName: st?['name'] as String?,
    );
  }
}

/// The signed-in user's own profile row, for Settings → Account details.
/// Separate from [Member] because this one carries the fields a person edits
/// about themselves (phone) and the ones that are the admin's to set (role,
/// department, status, when the account was created).
class MyProfile {
  final String id, name, email, role, status;
  final String? phone, subTeamName;
  final DateTime? createdAt;
  MyProfile({required this.id, required this.name, required this.email,
    required this.role, required this.status, this.phone, this.subTeamName, this.createdAt});
  factory MyProfile.fromMap(Map<String, dynamic> m) {
    final st = m['sub_teams'] as Map<String, dynamic>?;
    return MyProfile(
      id: m['id'] as String,
      name: m['full_name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      role: m['role'] as String? ?? '',
      status: m['status'] as String? ?? 'active',
      phone: (m['phone'] as String?)?.trim().isEmpty ?? true ? null : (m['phone'] as String?),
      subTeamName: st?['name'] as String?,
      createdAt: parseDate(m['created_at']),
    );
  }
}

/// A team within a department (e.g. Workshop → Welding). Departments without
/// sub-teams (Design) simply have none.
class SubTeam {
  final String id, role, name;
  SubTeam({required this.id, required this.role, required this.name});
  factory SubTeam.fromMap(Map<String, dynamic> m) => SubTeam(
    id: m['id'] as String,
    role: m['role'] as String? ?? '',
    name: m['name'] as String? ?? '',
  );
}

/// One active build on the factory board (row of v_ops_board): where it is,
/// which department + team + person is on it, and for how long.
class OpsRow {
  final String projectId, code, name, status;
  final int progressPct;
  final String? pmName, currentStageName, currentDiscipline, currentStageStatus,
      assigneeName, assigneeRole, subTeamName;
  final int? daysInStage;
  final DateTime? stageDue, nextOrderBy;
  OpsRow({required this.projectId, required this.code, required this.name, required this.status,
    this.progressPct = 0, this.pmName, this.currentStageName, this.currentDiscipline,
    this.currentStageStatus, this.assigneeName, this.assigneeRole, this.subTeamName,
    this.daysInStage, this.stageDue, this.nextOrderBy});
  bool get isUnassigned => assigneeName == null || assigneeName!.isEmpty;
  bool get isIdle => currentStageName == null;
  factory OpsRow.fromMap(Map<String, dynamic> m) => OpsRow(
    projectId: m['project_id'] as String,
    code: m['code'] as String? ?? '',
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'on_track',
    progressPct: (m['progress_pct'] as num?)?.toInt() ?? 0,
    pmName: m['pm_name'] as String?,
    currentStageName: m['current_stage_name'] as String?,
    currentDiscipline: m['current_discipline'] as String?,
    currentStageStatus: m['current_stage_status'] as String?,
    assigneeName: m['assignee_name'] as String?,
    assigneeRole: m['assignee_role'] as String?,
    subTeamName: m['sub_team_name'] as String?,
    daysInStage: (m['days_in_stage'] as num?)?.toInt(),
    stageDue: parseDate(m['stage_due']),
    nextOrderBy: parseDate(m['next_order_by']),
  );
}

/// Aggregated data for the Admin fleet dashboard.
class FleetData {
  final List<Project> projects;
  final List<OrderDue> due;
  FleetData(this.projects, this.due);

  int get total     => projects.length;
  int get onTrack   => projects.where((p) => p.status == 'on_track').length;
  int get atRisk    => projects.where((p) => p.status == 'at_risk').length;
  int get delayed   => projects.where((p) => p.status == 'delayed').length;
  int get delivered => projects.where((p) => p.status == 'delivered').length;
  /// Builds still in progress. Delivered builds are finished, so they belong
  /// in neither "active builds" nor the on-track / at-risk / delayed shares.
  int get active    => total - delivered;
  /// Builds nobody can work on: no PM means no assignment and no approval.
  List<Project> get noPm => projects.where((p) => !p.hasPm && p.status != 'delivered').toList();

  /// Materials whose order-by date is near or already passed. Undated
  /// requirements are excluded — they are unplanned, not urgent.
  List<OrderDue> get urgent =>
      due.where((d) => d.isPlanned && d.daysLeft! <= 3).toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  /// Everything the owner has to act on, worst first: builds that have slipped,
  /// builds with no project manager, builds at risk, then materials that must be
  /// ordered now. Empty here genuinely means "all caught up".
  List<AttentionItem> get attention {
    final out = <AttentionItem>[];
    for (final p in projects.where((p) => p.status == 'delayed')) {
      out.add(AttentionItem(AttentionKind.delayed, projectId: p.id,
        title: '${p.code} · ${p.name}',
        detail: 'Behind schedule · ${p.progressPct}% complete — open it to log the delay or re-plan.'));
    }
    for (final p in noPm) {
      out.add(AttentionItem(AttentionKind.noPm, projectId: p.id,
        title: '${p.code} · ${p.name}',
        detail: 'No project manager — nobody can assign or approve this build.'));
    }
    for (final p in projects.where((p) => p.status == 'at_risk')) {
      out.add(AttentionItem(AttentionKind.atRisk, projectId: p.id,
        title: '${p.code} · ${p.name}',
        detail: 'At risk · ${p.progressPct}% complete — a stage or an order is about to slip.'));
    }
    for (final d in urgent) {
      out.add(AttentionItem(AttentionKind.orderBy, projectId: d.projectId,
        title: '${d.projectCode} · ${d.itemName}',
        detail: 'Order by ${d.orderByDate == null ? '—' : _dayMon.format(d.orderByDate!)} · qty ${d.qty}'));
    }
    out.sort((a, b) => a.rank.compareTo(b.rank));
    return out;
  }
}

final _dayMon = DateFormat('d MMM');


/// Safe date parser for nullable Supabase date columns.
DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// Whole days from today until [end], by the calendar.
///
/// `warranty_end` is a DATE, so it parses to local midnight. Comparing that to
/// `DateTime.now()` made a warranty that runs out *today* read as already
/// expired — midnight this morning is before now. Both sides are normalised to
/// a date here, so "ends today" is 0 days, not −1. Both are taken as UTC so the
/// subtraction is calendar arithmetic and `inDays` can't truncate a 23-hour day
/// across a DST boundary.
int daysUntil(DateTime end) {
  final now = DateTime.now();
  return DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(now.year, now.month, now.day)).inDays;
}

/// How much warranty is left on a part: `none` · `expired` · `expiring` · `active`.
///
/// One definition, used by every screen that shows a warranty. The truck record
/// used to call anything inside 30 days "expiring" while Service's warranty
/// search used 60, so the same part read *active* on one screen and *expiring*
/// on the other. 60 days is the one that matters operationally — it is enough
/// notice to get a part replaced under cover before it lapses.
const warrantyExpiringDays = 60;

String warrantyStateFor(DateTime? end, {int? daysLeft}) {
  if (end == null) return 'none';
  final d = daysLeft ?? daysUntil(end);
  if (d < 0) return 'expired';
  if (d <= warrantyExpiringDays) return 'expiring';
  return 'active';
}

/// One build stage (stages row) shown on the project timeline.
class Stage {
  final String id, name, status; // status: todo | in_progress | done | rework
  final int ord;
  /// Which parallel group this stage belongs to (0031). Stages sharing a step
  /// run alongside each other; a step opens only when every earlier step is
  /// approved. Falls back to [ord], which is what every build created before
  /// 0031 was backfilled to.
  final int step;
  final String? assigneeId;
  /// Which role is meant to do this stage (workshop | design | store | service).
  /// Set from the workflow template, so the PM's assign sheet can recommend the
  /// right people instead of offering every staff member.
  final String? discipline;
  final DateTime? plannedStart, plannedEnd, actualStart, actualEnd;
  /// Dates the PM set when assigning this stage (separate from the backward-
  /// scheduled planned_* dates).
  final DateTime? assignedStart, assignedDue;
  Stage({required this.id, required this.name, required this.status, required this.ord, this.step = 1,
    this.assigneeId, this.discipline, this.plannedStart, this.plannedEnd,
    this.actualStart, this.actualEnd, this.assignedStart, this.assignedDue});
  factory Stage.fromMap(Map<String, dynamic> m) => Stage(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'todo',
    ord: (m['ord'] as num?)?.toInt() ?? 0,
    step: (m['step'] as num?)?.toInt() ?? (m['ord'] as num?)?.toInt() ?? 0,
    assigneeId: m['assignee_id'] as String?,
    discipline: m['discipline'] as String?,
    plannedStart: parseDate(m['planned_start']),
    plannedEnd: parseDate(m['planned_end']),
    actualStart: parseDate(m['actual_start']),
    actualEnd: parseDate(m['actual_end']),
    assignedStart: parseDate(m['assigned_start']),
    assignedDue: parseDate(m['assigned_due']),
  );

  bool get isAssigned => assigneeId != null;
  /// Work the PM still has to hand out on this build.
  bool get needsAssigning => assigneeId == null && status != 'done';
}

/// A build the signed-in person holds a stage on, with the dates that matter —
/// powers the "Assigned to me" carousel (Design / Store / Service home).
class AssignedBuild {
  final String projectId, code, name, status;
  final int progressPct;
  final String? stageName;
  final DateTime? due, targetDelivery;
  AssignedBuild({required this.projectId, required this.code, required this.name,
    required this.status, this.progressPct = 0, this.stageName, this.due, this.targetDelivery});
  /// Calendar days — `due` is a date column, so comparing it to `now()` made
  /// a build due today read as overdue. See [WorkshopTask.isOverdue].
  bool get isOverdue =>
      due != null && status != 'delivered' && daysUntil(due!) < 0;
}

/// A stage the PM still has to hand out, with its build context — powers the
/// "Assign work" screen.
class AssignableStage {
  final Stage stage;
  final String projectId, projectCode, projectName;
  AssignableStage({required this.stage, required this.projectId,
    required this.projectCode, required this.projectName});
}

/// A checklist row under a stage.
/// One check on a stage, and — since 0029 — the record of it being ticked.
///
/// The table used to be `(id, stage_id, label, done)` and the only write was a
/// bare `update … set done = …`, so nothing said who ticked a check or when,
/// there was nowhere to attach proof, and a check on an approved stage could
/// still be un-ticked. It was a to-do list presented as evidence.
class ChecklistItem {
  final String id, label;
  final bool done;
  /// Who ticked it, and when. Null on a check ticked before 0029 — the old
  /// write stored nothing, so there is no name to recover and the UI says so
  /// rather than inventing one.
  final String? doneByName;
  final DateTime? doneAt;
  /// This check cannot be ticked without a photo on its stage. Set on the
  /// workflow template, or by the build's PM on one stage.
  final bool photoRequired;
  /// The photo that discharged it, when there is one.
  final String? proofUrl;

  ChecklistItem({required this.id, required this.label, required this.done,
    this.doneByName, this.doneAt, this.photoRequired = false, this.proofUrl});

  factory ChecklistItem.fromMap(Map<String, dynamic> m) {
    final by = m['done_by_profile'] as Map<String, dynamic>?;
    final proof = m['proof'] as Map<String, dynamic>?;
    return ChecklistItem(
      id: m['id'] as String,
      label: m['label'] as String? ?? '',
      done: m['done'] as bool? ?? false,
      doneByName: by?['full_name'] as String?,
      doneAt: parseDate(m['done_at']),
      photoRequired: m['photo_required'] as bool? ?? false,
      proofUrl: proof?['file_url'] as String?,
    );
  }

  /// Ticked, but with no proof behind a check that asks for one. Only reachable
  /// on rows ticked before the rule was added — the RPC refuses it now — and
  /// worth saying out loud rather than showing a tick that means less than the
  /// one beside it.
  bool get proofMissing => done && photoRequired && proofUrl == null;

  /// A check the fitter cannot tick yet, because it wants a photo and the
  /// stage has none to point at.
  bool needsPhotoFirst(int stagePhotoCount) =>
      !done && photoRequired && stagePhotoCount == 0;
}

/// What a stage's own BOM says should go into it — the template's
/// `template_stage_items`, as the build's procurement requirements.
///
/// The fitter never had this. The stage screen showed a checklist and the
/// install screen showed a flat list of everything in the building, so "which
/// parts belong in this stage" was something you had to already know.
class StageMaterial {
  final String name;
  final num qty;
  /// pending · ordered · received — how close it is to being on the shelf.
  final String status;
  StageMaterial({required this.name, required this.qty, required this.status});
  factory StageMaterial.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return StageMaterial(
      name: ic?['name'] as String? ?? 'Item',
      qty: (m['qty'] as num?) ?? 1,
      status: m['status'] as String? ?? 'pending',
    );
  }
  bool get isReceived => status == 'received';
}

/// A photo / image attached to a stage (attachments where owner_type='stage').
///
/// [id] matters since 0029: a photo-required check records **which** photo
/// discharged it, and the server takes the attachment's id, not its URL.
class StagePhoto {
  final String url;
  final String? caption;
  final String? id;
  StagePhoto(this.url, this.caption, {this.id});
  factory StagePhoto.fromMap(Map<String, dynamic> m) =>
    StagePhoto(m['file_url'] as String? ?? '', m['caption'] as String?,
      id: m['id'] as String?);
}

/// A component/part installed during a stage (traceability, Hero #2).
class StagePart {
  final String name, model, serial, vendor, status;
  final DateTime? warrantyEnd, installDate;
  StagePart({required this.name, required this.model, required this.serial,
    required this.vendor, required this.status, this.warrantyEnd, this.installDate});
  factory StagePart.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    final vn = m['vendors'] as Map<String, dynamic>?;
    return StagePart(
      name: ic?['name'] as String? ?? 'Part',
      model: ic?['model'] as String? ?? '',
      serial: m['serial_number'] as String? ?? '—',
      vendor: vn?['name'] as String? ?? '—',
      status: m['status'] as String? ?? 'installed',
      warrantyEnd: parseDate(m['warranty_end']),
      installDate: parseDate(m['install_date']),
    );
  }
}

/// A logged delay on a stage.
class StageDelay {
  final String reason;
  final int days;
  final String? note;
  StageDelay(this.reason, this.days, this.note);
  factory StageDelay.fromMap(Map<String, dynamic> m) => StageDelay(
    (m['reason_code'] as String? ?? 'other').replaceAll('_', ' '),
    (m['days_delayed'] as num?)?.toInt() ?? 0, m['note'] as String?);
}

/// A delay attributed across a build (row of v_project_delays) — which stage
/// slipped, who logged it, whose stage it was, why, and for how many days.
class ProjectDelay {
  final String stageId, stageName;
  final String? discipline, note, loggedByName, assigneeName;
  final String reasonCode;   // raw enum, e.g. workshop_capacity
  final int days;
  final DateTime? at;
  ProjectDelay({required this.stageId, required this.stageName, required this.reasonCode,
    required this.days, this.discipline, this.note, this.loggedByName, this.assigneeName, this.at});
  /// Human label, e.g. "workshop capacity".
  String get reason => reasonCode.replaceAll('_', ' ');
  factory ProjectDelay.fromMap(Map<String, dynamic> m) => ProjectDelay(
    stageId: m['stage_id'] as String,
    stageName: m['stage_name'] as String? ?? '',
    reasonCode: m['reason_code'] as String? ?? 'other',
    days: (m['days_delayed'] as num?)?.toInt() ?? 0,
    discipline: m['discipline'] as String?,
    note: m['note'] as String?,
    loggedByName: m['logged_by_name'] as String?,
    assigneeName: m['assignee_name'] as String?,
    at: parseDate(m['created_at']),
  );
}

/// Everything the Stage detail screen shows for one stage.
class StageBundle {
  final String? assignee;
  final List<ChecklistItem> checklist;
  final List<StagePhoto> photos;
  final List<StagePart> parts;
  final List<StageDelay> delays;
  /// What this stage's BOM says should go into it. The fitter had no way to
  /// see this, so "which parts belong here" was knowledge, not screen.
  final List<StageMaterial> materials;
  StageBundle({this.assignee, required this.checklist, required this.photos,
    required this.parts, required this.delays, this.materials = const []});

  int get checksDone => checklist.where((c) => c.done).length;
  /// Checks that want a photo and have not got one. The fitter's own cue, and
  /// the reason a submit may be worth holding back.
  int get proofOutstanding =>
      checklist.where((c) => !c.done && c.photoRequired).length;
}

/// A project plus its stages — powers the Project detail screen.
class ProjectDetailData {
  final Project project;
  final DateTime? targetDelivery;
  final List<Stage> stages;
  ProjectDetailData(this.project, this.targetDelivery, this.stages);

  /// The stage to highlight: the one in progress, else the next to-do, else last.
  Stage? get currentStage {
    for (final s in stages) { if (s.status == 'in_progress') return s; }
    for (final s in stages) { if (s.status == 'todo') return s; }
    return stages.isNotEmpty ? stages.last : null;
  }
}


/// An in-app notification (notifications row, scoped to the current user by RLS).
class AppNotification {
  final String id, title;
  final String? body, type;
  /// What this notification is about: `project` | `stage` | `purchase_order` |
  /// `ticket` | `design`, plus that row's id. Every `fn_notify` call sets them,
  /// but the feed never selected them, so nothing could be opened from a
  /// notification — the whole point of telling someone was lost at the last step.
  final String? entityType;
  final String? entityId;
  final bool read;
  final DateTime? createdAt;
  AppNotification({required this.id, required this.title, this.body, this.type,
    this.entityType, this.entityId, this.read = false, this.createdAt});
  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    body: m['body'] as String?,
    type: m['type'] as String?,
    entityType: m['entity_type'] as String?,
    entityId: m['entity_id'] as String?,
    read: m['read'] as bool? ?? false,
    createdAt: parseDate(m['created_at']),
  );

  /// Is there somewhere to go when this row is tapped?
  bool get isOpenable => entityId != null &&
      const {'project', 'stage', 'purchase_order', 'ticket'}.contains(entityType);
}


/// Tolerant numeric parse — Postgres `numeric` can arrive as num or as a string.
double toMoney(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);

/// A purchase order row (list + detail header).
///
/// Carries two independent lifecycles:
///   • `approvalStatus` — pending_pm → pending_final → approved / rejected
///   • `status` (fulfilment) — ordered → dispatched → received — which only
///     matters once the PO is approved.
class PurchaseOrder {
  final String id, poNumber, status; // status: ordered | dispatched | received | partial
  final String approvalStatus;       // pending_pm | pending_final | approved | rejected
  final String? vendorName, vendorId, projectCode, pmId, shipTo, paymentTerms, notes, rejectionReason;
  final int itemCount;
  final double amount, subtotal, taxTotal;
  final DateTime? orderDate, expectedDate, deliveryDate, neededBy;
  final DateTime? submittedAt, pmSignedAt, finalSignedAt, rejectedAt;
  PurchaseOrder({
    required this.id, required this.poNumber, required this.status,
    this.approvalStatus = 'approved',
    this.vendorName, this.vendorId, this.projectCode, this.pmId, this.shipTo, this.paymentTerms,
    this.notes, this.rejectionReason,
    this.itemCount = 0, this.amount = 0, this.subtotal = 0, this.taxTotal = 0,
    this.orderDate, this.expectedDate, this.deliveryDate, this.neededBy,
    this.submittedAt, this.pmSignedAt, this.finalSignedAt, this.rejectedAt,
  });

  bool get isApproved => approvalStatus == 'approved';
  bool get isRejected => approvalStatus == 'rejected';
  bool get isAwaitingPm => approvalStatus == 'pending_pm';
  bool get isAwaitingFinal => approvalStatus == 'pending_final';
  bool get isPendingApproval => isAwaitingPm || isAwaitingFinal;

  factory PurchaseOrder.fromMap(Map<String, dynamic> m) {
    final v = m['vendors'] as Map<String, dynamic>?;
    final p = m['projects'] as Map<String, dynamic>?;
    final lines = m['po_lines'];
    return PurchaseOrder(
      id: m['id'] as String,
      poNumber: m['po_number'] as String? ?? '',
      status: m['status'] as String? ?? 'ordered',
      approvalStatus: m['approval_status'] as String? ?? 'approved',
      vendorName: v?['name'] as String?,
      vendorId: m['vendor_id'] as String?,
      projectCode: p?['code'] as String?,
      pmId: m['pm_id'] as String?,
      shipTo: m['ship_to'] as String?,
      paymentTerms: m['payment_terms'] as String?,
      notes: m['notes'] as String?,
      rejectionReason: m['rejection_reason'] as String?,
      itemCount: lines is List ? lines.length : 0,
      amount: toMoney(m['amount']),
      subtotal: toMoney(m['subtotal']),
      taxTotal: toMoney(m['tax_total']),
      orderDate: parseDate(m['order_date']),
      expectedDate: parseDate(m['expected_date']),
      deliveryDate: parseDate(m['delivery_date']),
      neededBy: parseDate(m['needed_by']),
      submittedAt: parseDate(m['submitted_at']),
      pmSignedAt: parseDate(m['pm_signed_at']),
      finalSignedAt: parseDate(m['final_signed_at']),
      rejectedAt: parseDate(m['rejected_at']),
    );
  }
}

/// A single line in a purchase order (now with rate + GST for a proper PO).
class PoLineItem {
  final String name;
  final String? itemCatalogId, hsnCode, description;
  final int qty, receivedQty;
  final double unitPrice, taxRate; // taxRate = GST %
  PoLineItem({required this.name, required this.qty, required this.receivedQty,
    this.itemCatalogId, this.hsnCode, this.description, this.unitPrice = 0, this.taxRate = 0});
  double get lineTotal => qty * unitPrice;
  double get taxAmount => lineTotal * taxRate / 100.0;
  factory PoLineItem.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return PoLineItem(
      name: ic?['name'] as String? ?? 'Item',
      itemCatalogId: m['item_catalog_id'] as String?,
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      receivedQty: (m['received_qty'] as num?)?.toInt() ?? 0,
      unitPrice: toMoney(m['unit_price']),
      taxRate: toMoney(m['tax_rate']),
      hsnCode: m['hsn_code'] as String?,
      description: m['description'] as String?,
    );
  }
}

/// One entry in a PO's approval trail (the delay log for approvals).
class PoApprovalEvent {
  final String event;            // created | pm_signed | final_signed | rejected
  final String? note, actorName;
  final DateTime? at;
  PoApprovalEvent({required this.event, this.note, this.actorName, this.at});
  factory PoApprovalEvent.fromMap(Map<String, dynamic> m) {
    final actor = m['profiles'] as Map<String, dynamic>?;
    return PoApprovalEvent(
      event: m['event'] as String? ?? '',
      note: m['note'] as String?,
      actorName: actor?['full_name'] as String?,
      at: parseDate(m['created_at']),
    );
  }
}

/// A PO awaiting a signature (row of v_po_pending_approvals) — the approvals
/// inbox for PMs and the final approver, with how long it has been waiting.
class PoApproval {
  final String id, poNumber, approvalStatus;
  final String? vendorName, projectCode, pmId;
  final double amount, waitingHours;
  final bool overdue;
  final DateTime? neededBy;
  final String priority;      // critical | high | medium | low
  final int priorityRank;     // 0=critical … 3=low (for sorting)
  PoApproval({required this.id, required this.poNumber, required this.approvalStatus,
    this.vendorName, this.projectCode, this.pmId,
    this.amount = 0, this.waitingHours = 0, this.overdue = false, this.neededBy,
    this.priority = 'medium', this.priorityRank = 2});
  bool get awaitingPm => approvalStatus == 'pending_pm';
  bool get awaitingFinal => approvalStatus == 'pending_final';
  factory PoApproval.fromMap(Map<String, dynamic> m) => PoApproval(
    id: m['id'] as String,
    poNumber: m['po_number'] as String? ?? '',
    approvalStatus: m['approval_status'] as String? ?? '',
    vendorName: m['vendor_name'] as String?,
    projectCode: m['project_code'] as String?,
    pmId: m['pm_id'] as String?,
    amount: toMoney(m['amount']),
    waitingHours: toMoney(m['waiting_hours']),
    overdue: m['overdue'] == true,
    neededBy: parseDate(m['needed_by']),
    priority: m['priority'] as String? ?? 'medium',
    priorityRank: (m['priority_rank'] as num?)?.toInt() ?? 2,
  );
}

/// PO header + its line items + the approval trail.
class PoDetail {
  final PurchaseOrder po;
  final List<PoLineItem> items;
  final List<PoApprovalEvent> events;
  PoDetail(this.po, this.items, {this.events = const []});
}

/// A vendor row with reliability + lead time, plus the tax identity a proper
/// purchase-order document needs (GSTIN, address, state for CGST/SGST vs IGST).
class VendorRow {
  final String id, name;
  final String? category, gstin, address, state, email;
  final int avgLead, reliability;
  VendorRow({required this.id, required this.name, this.category,
    this.gstin, this.address, this.state, this.email,
    this.avgLead = 0, this.reliability = 100});
  factory VendorRow.fromMap(Map<String, dynamic> m) => VendorRow(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    category: m['category'] as String?,
    gstin: m['gstin'] as String?,
    address: m['address'] as String?,
    state: m['state'] as String?,
    email: m['email'] as String?,
    avgLead: (m['avg_lead_time_days'] as num?)?.toInt() ?? 0,
    reliability: (m['reliability_score'] as num?)?.toInt() ?? 100,
  );
}

/// The buyer's identity for the top of a PO document (single-row settings).
class CompanySettings {
  final String name;
  final String? address, gstin, state, phone, email, logoUrl;
  CompanySettings({required this.name, this.address, this.gstin, this.state,
    this.phone, this.email, this.logoUrl});
  factory CompanySettings.fromMap(Map<String, dynamic> m) => CompanySettings(
    name: m['name'] as String? ?? 'Azimuth Business on Wheels',
    address: m['address'] as String?,
    gstin: m['gstin'] as String?,
    state: m['state'] as String?,
    phone: m['phone'] as String?,
    email: m['email'] as String?,
    logoUrl: m['logo_url'] as String?,
  );
}

/// Everything needed to render a purchase-order document.
class PoDocData {
  final CompanySettings company;
  final VendorRow? vendor;
  final PoDetail detail;
  PoDocData({required this.company, required this.vendor, required this.detail});
}


/// A procurement requirement for a project (drives Hero #1 order-by).
/// Editable per project: qty, needed_by; order_by is auto-computed by the backend.
class Requirement {
  final String id, itemCatalogId, itemName, status; // status: pending | ordered | received
  final int qty;
  final DateTime? neededBy, orderBy;
  Requirement({required this.id, required this.itemCatalogId, required this.itemName,
    required this.status, required this.qty, this.neededBy, this.orderBy});
  factory Requirement.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return Requirement(
      id: m['id'] as String,
      itemCatalogId: m['item_catalog_id'] as String? ?? '',
      itemName: ic?['name'] as String? ?? 'Item',
      status: m['status'] as String? ?? 'pending',
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      neededBy: parseDate(m['needed_by_date']),
      orderBy: parseDate(m['order_by_date']),
    );
  }
}


/// One open stage on the PM's schedule (Schedule tab).
///
/// Replaces the old bay board, which read the `bays` table — nothing in the app
/// or the database ever put a stage in a bay, so that screen could only ever be
/// empty. This is built from data that genuinely exists: the date the PM
/// committed to when assigning the stage, falling back to the backward-scheduled
/// planned end date.
class ScheduleEntry {
  final String stageId, stageName, status;
  final String projectId, projectCode, projectName;
  final String? assigneeId, assigneeName, discipline;
  final DateTime? start, due;

  /// True when [due] came from backward scheduling rather than the PM's own
  /// commitment — worth showing differently, it is a plan and not a promise.
  final bool dueIsPlanned;

  ScheduleEntry({
    required this.stageId, required this.stageName, required this.status,
    required this.projectId, required this.projectCode, required this.projectName,
    this.assigneeId, this.assigneeName, this.discipline,
    this.start, this.due, this.dueIsPlanned = false,
  });

  /// Whole calendar days from today until [due]. Negative = overdue.
  ///
  /// Both sides are normalised to UTC midnight on purpose. Subtracting two
  /// *local* midnights across a daylight-saving boundary gives 23 or 25 hours,
  /// and `inDays` truncates — so a stage due tomorrow can report 0 days left and
  /// show up as "Today". India has no DST so this would not bite here, but the
  /// arithmetic is meant to be calendar arithmetic, and this makes it so
  /// everywhere.
  int? get daysLeft {
    if (due == null) return null;
    final today = DateTime.now();
    return DateTime.utc(due!.year, due!.month, due!.day)
        .difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }

  bool get isOverdue => (daysLeft ?? 1) < 0;
  bool get isDueToday => daysLeft == 0;
  bool get isUnassigned => assigneeId == null;
  bool get hasNoDate => due == null;
}

/// A PM "today" in-progress stage (project code + stage name).
class ActiveStage {
  final String id, name, projectCode;
  final String projectId;
  ActiveStage({required this.id, required this.name, required this.projectCode, this.projectId = ''});
}


/// A tracked component instance (Store — traceability, Hero #2).
class ComponentRow {
  final String id, itemCatalogId, name, model, serial, status;
  final String? projectCode, vendorName, billUrl;
  final DateTime? warrantyEnd, installDate;
  ComponentRow({required this.id, required this.itemCatalogId, required this.name, required this.model,
    required this.serial, required this.status, this.projectCode, this.vendorName, this.billUrl,
    this.warrantyEnd, this.installDate});
  factory ComponentRow.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    final pr = m['projects'] as Map<String, dynamic>?;
    final vn = m['vendors'] as Map<String, dynamic>?;
    return ComponentRow(
      id: m['id'] as String,
      itemCatalogId: m['item_catalog_id'] as String? ?? '',
      name: ic?['name'] as String? ?? 'Component',
      model: ic?['model'] as String? ?? '',
      serial: m['serial_number'] as String? ?? '—',
      status: m['status'] as String? ?? 'in_stock',
      projectCode: pr?['code'] as String?,
      vendorName: vn?['name'] as String?,
      billUrl: (m['bill_url'] as String?)?.trim().isEmpty ?? true ? null : (m['bill_url'] as String?),
      warrantyEnd: parseDate(m['warranty_end']),
      installDate: parseDate(m['install_date']),
    );
  }
  /// none | active | expiring | expired — the same [warrantyStateFor] every
  /// other screen uses.
  ///
  /// This was the **third** copy of the warranty comparison, and it still had
  /// the bug 0026 fixed in the other two: `warrantyEnd.isAfter(DateTime.now())`
  /// on a date-only column is false all through the warranty's own last day, so
  /// a part whose cover ends today read "Expired" in Workshop's Parts tab,
  /// Store's Parts list and the component record.
  String get warrantyState => warrantyStateFor(warrantyEnd);
  bool get warrantyActive => warrantyState == 'active' || warrantyState == 'expiring';
  bool get hasBill => billUrl != null;

  /// Store logged this part against a build but nobody has fitted it yet.
  ///
  /// 0026 made intake an **earmark**, not an installation: the part stays on
  /// the shelf (`in_stock`) while naming the build it was bought for. Lists
  /// that filter on the build alone therefore show reserved and fitted parts
  /// together, which reads as if the truck already has them.
  bool get isReserved => status == 'in_stock' && projectCode != null;
  bool get isFitted => status == 'installed';
}

/// One component on a truck's complete record (row of v_truck_components):
/// what it is, its serial + vendor + bill, its warranty, and where/by whom it
/// was fitted.
class TruckComponent {
  final String id, itemName, serial, status;
  final String? model, vendorName, billUrl, stageName, stageDiscipline, installedByName;
  final DateTime? warrantyStart, warrantyEnd, installDate;
  TruckComponent({required this.id, required this.itemName, required this.serial, required this.status,
    this.model, this.vendorName, this.billUrl, this.stageName, this.stageDiscipline,
    this.installedByName, this.warrantyStart, this.warrantyEnd, this.installDate});
  bool get hasBill => billUrl != null && billUrl!.isNotEmpty;
  /// none | active | expiring | expired — see [warrantyStateFor].
  String get warrantyState => warrantyStateFor(warrantyEnd);
  factory TruckComponent.fromMap(Map<String, dynamic> m) => TruckComponent(
    id: m['id'] as String,
    itemName: m['item_name'] as String? ?? 'Component',
    serial: m['serial_number'] as String? ?? '—',
    status: m['status'] as String? ?? 'installed',
    model: m['model'] as String?,
    vendorName: m['vendor_name'] as String?,
    billUrl: (m['bill_url'] as String?)?.trim().isEmpty ?? true ? null : (m['bill_url'] as String?),
    stageName: m['stage_name'] as String?,
    stageDiscipline: m['stage_discipline'] as String?,
    installedByName: m['installed_by_name'] as String?,
    warrantyStart: parseDate(m['warranty_start']),
    warrantyEnd: parseDate(m['warranty_end']),
    installDate: parseDate(m['install_date']),
  );
}

/// A stock line (Store inventory).
class StockRow {
  final String name, unit;
  final String? itemCatalogId, category;
  final num quantity;
  final int threshold;

  /// Whether the **Store** reorders this item, or a build's PM does.
  ///
  /// `0019` draws the line: essentials (sheet, wheels, wire) are general stock
  /// the Store keeps regardless of any one build, and the Store reorders them.
  /// A project part — an LED panel, a truck's BOM items — is ordered by
  /// procurement against that build's requirement. The Store never reorders it.
  final bool isEssential;

  StockRow({required this.name, required this.unit, this.itemCatalogId, this.category,
    required this.quantity, required this.threshold, this.isEssential = false});

  /// Composed in [StoreRepo.stock] rather than mapped from one row: on-hand for
  /// a serialized item is a count over the component ledger, not a column.
  ///
  /// **Essentials only**, and that is the whole point. `low_stock_threshold`
  /// defaults to 0, so `quantity <= threshold` is true for every project part
  /// with nothing on the shelf — which is its *normal* state: you order what a
  /// build needs, log it, fit it, and keep no spares. Reading that as "low"
  /// put a permanent red flag on items the Store cannot reorder anyway, and
  /// buried the sheet and wire that genuinely had run out.
  bool get low => isEssential && quantity <= threshold;

  /// True when this line is nobody's restocking job — a project part. The
  /// quantity still matters (it is what Workshop can install today), it just
  /// is not a reorder signal.
  bool get isProjectPart => !isEssential;
}

/// A Store → Procurement reorder request for a general essential (not tied to a
/// project). Store raises it; Procurement fulfils it with a general PO.
class StockRequest {
  final String id, itemName;
  final String? itemCatalogId, note, status;
  final int qty;
  final DateTime? createdAt;
  StockRequest({
    required this.id, required this.itemName, required this.qty,
    this.itemCatalogId, this.note, this.status, this.createdAt,
  });
  factory StockRequest.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return StockRequest(
      id: m['id'] as String,
      itemCatalogId: m['item_catalog_id'] as String?,
      itemName: ic?['name'] as String? ?? 'Item',
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      note: m['note'] as String?,
      status: m['status'] as String?,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? ''),
    );
  }
}

/// A truck affected by a recall (Hero #2).
class RecallRow {
  final String? projectCode, serial, status;
  RecallRow({this.projectCode, this.serial, this.status});
  factory RecallRow.fromMap(Map<String, dynamic> m) => RecallRow(
    projectCode: m['project_code'] as String?,
    serial: m['serial'] as String?,
    status: m['status'] as String?,
  );
}


/// A stage assigned to the signed-in workshop member (their task).
class WorkshopTask {
  final String stageId, stageName, status, projectId, projectCode, projectName;
  /// What the PM asked for when handing this over.
  final DateTime? assignedDue;
  /// True while a submission of this stage is sitting with the PM.
  final bool awaitingApproval;
  /// Why the PM sent it back (set when status == 'rework').
  final String? reworkNote;
  /// The build's own status. A build can be marked delivered with stages still
  /// open (`fn_mark_delivered(p_force => true)`, which deliberately does not
  /// close them — that would rewrite history). Those stages stayed in the
  /// assignee's list forever, offering Start work on a truck the customer
  /// already has, so the list needs to know.
  final String projectStatus;
  /// Something in an earlier **step** of this build is still open, so this
  /// stage cannot be started yet (0031). Read from `v_stage_gate`, the same
  /// definition `fn_start_stage` enforces, so a screen can never offer a
  /// Start that the server would refuse.
  final bool isLocked;
  /// The stage it is waiting for — named, because "locked" on its own tells
  /// the person nothing they can act on.
  final String? blockedBy;
  /// How many earlier stages are still open, when it is more than one.
  final int blockedByCount;
  WorkshopTask({required this.stageId, required this.stageName, required this.status,
    required this.projectId, required this.projectCode, required this.projectName,
    this.assignedDue, this.awaitingApproval = false, this.reworkNote,
    this.projectStatus = 'on_track',
    this.isLocked = false, this.blockedBy, this.blockedByCount = 0});
  factory WorkshopTask.fromMap(Map<String, dynamic> m) {
    final pr = m['projects'] as Map<String, dynamic>?;
    return WorkshopTask(
      stageId: m['id'] as String,
      stageName: m['name'] as String? ?? '',
      status: m['status'] as String? ?? 'todo',
      projectId: m['project_id'] as String? ?? '',
      projectCode: pr?['code'] as String? ?? '',
      projectName: pr?['name'] as String? ?? '',
      assignedDue: parseDate(m['assigned_due']),
      projectStatus: pr?['status'] as String? ?? 'on_track',
    );
  }

  WorkshopTask copyWith({bool? awaitingApproval, String? reworkNote,
    bool? isLocked, String? blockedBy, int? blockedByCount}) => WorkshopTask(
    stageId: stageId, stageName: stageName, status: status, projectId: projectId,
    projectCode: projectCode, projectName: projectName, assignedDue: assignedDue,
    projectStatus: projectStatus,
    awaitingApproval: awaitingApproval ?? this.awaitingApproval,
    reworkNote: reworkNote ?? this.reworkNote,
    isLocked: isLocked ?? this.isLocked,
    blockedBy: blockedBy ?? this.blockedBy,
    blockedByCount: blockedByCount ?? this.blockedByCount,
  );

  /// Nothing has started yet and it is not waiting on the PM — **and** its
  /// turn has come. Offering Start on a locked stage would be offering
  /// something `fn_start_stage` refuses.
  bool get canStart => !isLocked && (status == 'todo' || status == 'rework');
  /// Not started, and cannot be: it is waiting on an earlier step.
  bool get isWaitingOnEarlierWork => isLocked && status != 'done' && !isDelivered;
  /// "Waiting on Chassis" / "Waiting on 3 earlier stages".
  String get waitingLabel => blockedByCount > 1
      ? 'Waiting on $blockedByCount earlier stages'
      : 'Waiting on ${blockedBy ?? 'earlier work'}';
  /// The stage is finished, or the truck has gone out with it still open.
  bool get isClosed => status == 'done' || isDelivered;
  /// The truck has been handed over. Nothing on it is work any more.
  bool get isDelivered => projectStatus == 'delivered';

  /// Calendar days, not a timestamp comparison.
  ///
  /// `assigned_due` is a Postgres `date`, so it parses to midnight — and
  /// `isBefore(DateTime.now())` is therefore **true for a stage due today**.
  /// Every workshop stage due today read "Overdue", in a red pill, all day.
  /// Same trap as the warranty that expired on its own last day, fixed in
  /// 0026; [daysUntil] is the one definition both now use.
  bool get isOverdue => !isClosed && assignedDue != null && daysUntil(assignedDue!) < 0;
  bool get isDueToday => assignedDue != null && daysUntil(assignedDue!) == 0;
  int? get daysLeft => assignedDue == null ? null : daysUntil(assignedDue!);

  /// Worst first, for every list that shows these: someone is already waiting
  /// on rework, then a missed date, then the soonest due. Undated sorts last —
  /// nobody committed to a date, so it cannot be the most urgent thing.
  int get urgencyRank {
    if (isDelivered) return 6;
    // Locked work is real but not actionable today, so it sorts below
    // everything the person can actually pick up — above only a delivered
    // truck, which is not work at all.
    if (isWaitingOnEarlierWork) return 5;
    if (awaitingApproval) return 4;      // with the PM; not yours to move
    if (status == 'rework') return 0;
    if (isOverdue) return 1;
    if (isDueToday) return 2;
    return 3;
  }

  /// Orders a mixed list of stages across builds. `ord` alone — which is what
  /// this list used — is the stage's order *within its own build*, so two
  /// builds interleave meaninglessly and an overdue stage can sort last.
  static int compare(WorkshopTask a, WorkshopTask b) {
    final r = a.urgencyRank.compareTo(b.urgencyRank);
    if (r != 0) return r;
    final ad = a.daysLeft, bd = b.daysLeft;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    final c = a.projectCode.compareTo(b.projectCode);
    return c != 0 ? c : a.stageName.compareTo(b.stageName);
  }
}


/// One segment of a build's pipeline, for the PM's schedule strip.
///
/// Unlike [ScheduleEntry] this includes **finished** stages: the point of the
/// strip is the shape of the whole build, and a build that is four stages in
/// looks nothing like one that has not started.
class StageTick {
  final String id, name, status;   // todo | in_progress | done | rework
  final int ord;
  /// Parallel group (0031). See [Stage.step].
  final int step;
  final String? assigneeName, discipline;
  final DateTime? due;
  /// A submission of this stage is sitting with the PM. Worth its own flag:
  /// it is the one kind of blockage the PM is causing themselves.
  final bool awaitingApproval;

  StageTick({required this.id, required this.name, required this.status, required this.ord,
    this.step = 1,
    this.assigneeName, this.discipline, this.due, this.awaitingApproval = false});

  bool get isDone => status == 'done';
  bool get isActive => status == 'in_progress' || status == 'rework';
  bool get isRework => status == 'rework';
  bool get isUnassigned => !isDone && assigneeName == null;
  bool get isOverdue => !isDone && due != null && daysUntil(due!) < 0;
  int? get daysLeft => due == null ? null : daysUntil(due!);
}

/// Which stages of a build cannot start yet, worked out from the whole list.
///
/// The same rule `fn_start_stage` enforces and `v_stage_gate` reports: a stage
/// is locked while any stage in an **earlier step** is not approved. Computed
/// here rather than fetched, because the screens that show a whole build (the
/// PM's pipeline, the build screen) already hold every stage — asking the
/// server again for something they can already see would be a round trip to
/// learn what they know.
Set<String> lockedStageIds(List<StageTick> stages) {
  // The earliest step that still has unfinished work in it. Everything in a
  // later step is waiting; everything in this step or before is open.
  int? openFrom;
  for (final s in stages) {
    if (s.isDone) continue;
    if (openFrom == null || s.step < openFrom) openFrom = s.step;
  }
  if (openFrom == null) return const {};
  return {for (final s in stages) if (!s.isDone && s.step > openFrom) s.id};
}

/// What a locked stage is waiting for: the first unfinished stage in an
/// earlier step, which is the one that has to move before anything else can.
StageTick? blockerFor(StageTick stage, List<StageTick> all) {
  StageTick? best;
  for (final s in all) {
    if (s.isDone || s.step >= stage.step) continue;
    if (best == null || s.step < best.step || (s.step == best.step && s.ord < best.ord)) {
      best = s;
    }
  }
  return best;
}

/// A build as the PM's schedule sees it: the whole pipeline, and what is
/// actually holding it up.
///
/// The schedule used to be a flat list of open stages sorted by date. Across a
/// handful of builds that reads fine; across ten it interleaves — `AZ-101
/// Fabrication`, `AZ-107 Design`, `AZ-103 Paint` — and the build, which is the
/// thing a PM actually manages, disappears. This keeps the build whole.
class BuildSchedule {
  final Project project;
  final DateTime? targetDelivery;
  /// Every stage, in `ord` order, finished ones included.
  final List<StageTick> stages;

  BuildSchedule({required this.project, required this.stages, this.targetDelivery});

  int get total => stages.length;
  int get doneCount => stages.where((s) => s.isDone).length;
  int get overdueCount => stages.where((s) => s.isOverdue).length;
  int get unassignedCount => stages.where((s) => s.isUnassigned).length;
  int get awaitingCount => stages.where((s) => s.awaitingApproval).length;
  int get reworkCount => stages.where((s) => s.isRework).length;

  /// Where the build is now: what is being worked, else the next thing up.
  StageTick? get current {
    for (final s in stages) { if (s.isActive) return s; }
    for (final s in stages) { if (!s.isDone) return s; }
    return stages.isEmpty ? null : stages.last;
  }

  /// 1-based position of [current] in the pipeline, for "Stage 4 of 7".
  int get currentIndex {
    final c = current;
    if (c == null) return 0;
    return stages.indexOf(c) + 1;
  }

  int? get daysToDelivery => targetDelivery == null ? null : daysUntil(targetDelivery!);
  bool get isDelivered => project.status == 'delivered';

  /// Handed over without a workflow, so it has no stages at all (0031). This
  /// is the PM's to fix and nothing else about the build can happen until they
  /// do — no stage can be assigned, worked or approved.
  bool get needsPlan => !isDelivered && stages.isEmpty;

  /// Which of this build's stages cannot start yet. Computed from the whole
  /// list rather than fetched — this screen already holds every stage.
  Set<String> get lockedIds => lockedStageIds(stages);

  /// The one line that says what to do about this build. Ordered by who is
  /// holding it up: the PM first, because that is the one they can clear
  /// without asking anyone.
  String get blockedLabel {
    if (isDelivered) return 'Delivered';
    // Nothing else is true of this build yet, and nothing can be.
    if (needsPlan) return 'Needs a plan';
    final bits = <String>[];
    if (awaitingCount > 0) bits.add('$awaitingCount waiting on you');
    if (overdueCount > 0) bits.add('$overdueCount overdue');
    if (reworkCount > 0) bits.add('$reworkCount in rework');
    if (unassignedCount > 0) bits.add('$unassignedCount unassigned');
    if (bits.isEmpty) return doneCount == total ? 'All stages done' : 'On track';
    return bits.join(' · ');
  }

  /// True when nothing needs the PM and nothing has slipped.
  bool get isClear =>
      !needsPlan &&
      awaitingCount == 0 && overdueCount == 0 && reworkCount == 0 && unassignedCount == 0;

  /// Worst first. A build with no plan leads — nothing about it can start at
  /// all. Then one waiting on the PM, because it is the one they can unblock
  /// right now; after that it is how late it is, then how close delivery is.
  List<int> get severity => [
        isDelivered ? 1 : 0,
        // A build with no plan outranks everything live: until the PM chooses
        // a workflow, not one stage of it can be assigned, worked or approved.
        needsPlan ? 0 : 1,
        awaitingCount > 0 ? 0 : 1,
        -overdueCount,
        -reworkCount,
        -unassignedCount,
        daysToDelivery ?? 1 << 20,
      ];

  static int compare(BuildSchedule a, BuildSchedule b) {
    final x = a.severity, y = b.severity;
    for (var i = 0; i < x.length; i++) {
      final c = x[i].compareTo(y[i]);
      if (c != 0) return c;
    }
    return a.project.code.compareTo(b.project.code);
  }
}

/// One thing a designer should do next, and why.
///
/// The Design Studio asked the same question twice — "my design stages" and
/// "needs your attention" — and answered it twice, differently: the stage
/// section showed an overdue stage while the attention panel showed a green
/// tick, because the panel read `design_artifacts` alone and the designer had
/// no designs at all. The most blocking fact on their plate was the one thing
/// the screen could not see.
///
/// Since 0028 a design stage cannot be submitted until the client approves a
/// design, so a stage and its designs are one piece of work and have to be
/// read together. This does that, and names the next action rather than
/// leaving it to be worked out.
enum DesignTodoKind {
  /// The PM sent the stage back.
  rework,
  /// An approved design exists and the stage has not been submitted. One tap.
  readyToSubmit,
  /// The client asked for changes; a new version has to go round.
  changesRequested,
  /// The stage is late and no design has been started at all.
  overdueNoDesign,
  /// A design is sitting in draft, doing nothing until it is sent.
  unsentDraft,
  /// Assigned, not late, nothing started yet.
  notStarted,
  /// The build has not reached this stage yet (0031). Nothing to do but know.
  waitingOnEarlierWork,
}

class DesignTodo {
  final DesignTodoKind kind;
  final String title, detail, action;
  /// The stage to open, when this is about one.
  final WorkshopTask? task;
  /// The design to open, when this is about one.
  final DesignItem? design;

  const DesignTodo(this.kind, {required this.title, required this.detail,
    required this.action, this.task, this.design});

  /// Lower sorts first. Rework leads because someone is already waiting on it;
  /// "ready to submit" comes next because it is the cheapest thing on the list
  /// and it unblocks the build.
  int get rank => switch (kind) {
    DesignTodoKind.rework            => 0,
    DesignTodoKind.readyToSubmit     => 1,
    DesignTodoKind.changesRequested  => 2,
    DesignTodoKind.overdueNoDesign   => 3,
    DesignTodoKind.unsentDraft       => 4,
    DesignTodoKind.notStarted        => 5,
    DesignTodoKind.waitingOnEarlierWork => 6,
  };
}

/// What this designer should do next, worst first.
///
/// Deliberately **excludes** designs sitting with the client. A designer can do
/// nothing about those, and a to-do list that includes things you cannot act on
/// stops being a to-do list. [designsWithClient] carries that count separately,
/// so the screen can say it without putting it in the queue.
({List<DesignTodo> todos, int designsWithClient}) designTodos({
  required List<WorkshopTask> tasks,
  required List<DesignItem> designs,
}) {
  final out = <DesignTodo>[];
  final claimed = <String>{};   // design ids already spoken for by a stage
  // Designs sitting with the client, counted once over the whole set. Counting
  // them per-stage instead would both miss the ones no stage reads and
  // double-count the ones two stages on a build both see.
  final withClient = designs.where((d) => d.status == 'pending_approval').length;

  List<DesignItem> forStage(WorkshopTask t) {
    final linked = designs.where((d) => d.stageId == t.stageId).toList();
    if (linked.isNotEmpty) return linked;
    return designs.where((d) => d.projectId == t.projectId).toList();
  }

  for (final t in tasks.where((t) => !t.isClosed)) {
    final mine = forStage(t);
    // The stage speaks for *every* design on its build, not just the ones it
    // read. A stage linked to one design still covers the older loose designs
    // on the same truck — otherwise the loop below would raise a second card
    // for the same build and the same person.
    for (final d in designs) {
      if (d.projectId == t.projectId || d.stageId == t.stageId) claimed.add(d.id);
    }
    final where = '${t.projectCode} · ${t.stageName}';

    // Already with the PM: nothing for the designer to do until they decide.
    if (t.awaitingApproval) continue;

    // The build has not reached this stage. Still listed — it is theirs and
    // they should know it is coming — but last, and saying what it waits for
    // rather than pretending there is something to start.
    if (t.isWaitingOnEarlierWork) {
      out.add(DesignTodo(DesignTodoKind.waitingOnEarlierWork, task: t,
        title: where,
        detail: t.blockedByCount > 1
            ? 'Opens once the earlier stages on this build are approved.'
            : 'Opens once "${t.blockedBy}" is approved.',
        action: 'Open stage'));
      continue;
    }

    if (t.status == 'rework') {
      out.add(DesignTodo(DesignTodoKind.rework, task: t,
        title: where,
        detail: t.reworkNote ?? 'Your project manager sent this stage back.',
        action: 'Open stage'));
      continue;
    }

    if (mine.any((d) => d.status == 'approved')) {
      out.add(DesignTodo(DesignTodoKind.readyToSubmit, task: t,
        title: where,
        detail: 'The client approved a design. Submit this stage to your project manager.',
        action: 'Submit stage'));
      continue;
    }

    // With the client: theirs to decide, not yours to chase. Already counted
    // in withClient above.
    if (mine.any((d) => d.status == 'pending_approval')) continue;

    final revision = mine.where((d) => d.status == 'revision').toList();
    if (revision.isNotEmpty) {
      out.add(DesignTodo(DesignTodoKind.changesRequested, design: revision.first, task: t,
        title: where,
        detail: revision.first.clientFeedback?.trim().isNotEmpty == true
            ? revision.first.clientFeedback!.trim()
            : 'The client asked for changes. Upload a revised version.',
        action: 'Upload revision'));
      continue;
    }

    final draft = mine.where((d) => d.status == 'draft').toList();
    if (draft.isNotEmpty) {
      out.add(DesignTodo(DesignTodoKind.unsentDraft, design: draft.first, task: t,
        title: where,
        detail: 'A design is still a draft. It does nothing until the client sees it.',
        action: 'Send for approval'));
      continue;
    }

    out.add(DesignTodo(
      t.isOverdue ? DesignTodoKind.overdueNoDesign : DesignTodoKind.notStarted,
      task: t,
      title: where,
      detail: t.isOverdue
          ? 'Overdue, and no design has been started. This stage finishes when the client approves one.'
          : 'No design yet. This stage finishes when the client approves one.',
      action: 'Start a design'));
  }

  // Designs on builds this designer holds no open stage on — made ahead of an
  // assignment, or left behind when a stage was reassigned. Still theirs.
  for (final d in designs) {
    if (claimed.contains(d.id)) continue;
    final where = '${d.projectCode ?? 'Build'} · ${d.type}';
    if (d.status == 'revision') {
      out.add(DesignTodo(DesignTodoKind.changesRequested, design: d,
        title: where,
        detail: d.clientFeedback?.trim().isNotEmpty == true
            ? d.clientFeedback!.trim()
            : 'The client asked for changes. Upload a revised version.',
        action: 'Upload revision'));
    } else if (d.status == 'draft') {
      out.add(DesignTodo(DesignTodoKind.unsentDraft, design: d,
        title: where,
        detail: 'A design is still a draft. It does nothing until the client sees it.',
        action: 'Send for approval'));
    }
  }

  out.sort((a, b) => a.rank.compareTo(b.rank));
  return (todos: out, designsWithClient: withClient);
}

/// A client-visible document (contract/invoice/warranty/handover).
class ClientDoc {
  final String id, type;
  final String? fileUrl;
  final bool available;
  ClientDoc({required this.id, required this.type, this.fileUrl, this.available = false});
  factory ClientDoc.fromMap(Map<String, dynamic> m) => ClientDoc(
    id: m['id'] as String,
    type: m['type'] as String? ?? 'document',
    fileUrl: m['file_url'] as String?,
    available: m['available'] as bool? ?? false,
  );
}

/// A support request / ticket raised by the client.
class TicketRow {
  final String id, number, category, status;
  final String? description, resolutionNote, resolutionType;
  final DateTime? createdAt, resolvedAt;
  TicketRow({required this.id, required this.number, required this.category,
    required this.status, this.description, this.createdAt,
    this.resolutionNote, this.resolutionType, this.resolvedAt});
  factory TicketRow.fromMap(Map<String, dynamic> m) => TicketRow(
    id: m['id'] as String,
    number: m['ticket_number'] as String? ?? '',
    category: m['category'] as String? ?? 'other',
    status: m['status'] as String? ?? 'open',
    description: m['description'] as String?,
    createdAt: parseDate(m['created_at']),
    resolutionNote: m['resolution_note'] as String?,
    resolutionType: m['resolution_type'] as String?,
    resolvedAt: parseDate(m['resolved_at']),
  );

  bool get isResolved => status == 'resolved' || status == 'closed';
  /// The client can say "still not fixed" while it is resolved but not closed.
  bool get canReopen => status == 'resolved';
}

/// A design artifact the client can view / approve.
/// modelUrl/imageUrl/changeNote come from the artifact's current version.
class DesignRow {
  final String id, type, status;
  final String? modelUrl, imageUrl, changeNote, clientFeedback;
  DesignRow({required this.id, required this.type, required this.status,
    this.modelUrl, this.imageUrl, this.changeNote, this.clientFeedback});
  factory DesignRow.fromMap(Map<String, dynamic> m) => DesignRow(
    id: m['id'] as String,
    type: m['type'] as String? ?? 'layout',
    status: m['status'] as String? ?? 'draft',
    clientFeedback: m['client_feedback'] as String?,
  );
}

/// A design artifact from the Designer's perspective (adds project context +
/// the current version's model/image/note + version number).
class DesignItem {
  final String id, type, status, projectId;
  final String? projectCode, projectName, modelUrl, imageUrl, changeNote, clientFeedback;
  /// The build stage this design is the deliverable for (0028). Null for
  /// designs made before the link existed, or on a build with no design stage.
  final String? stageId;
  final int versionNo;
  DesignItem({required this.id, required this.type, required this.status, required this.projectId,
    this.projectCode, this.projectName, this.modelUrl, this.imageUrl, this.changeNote,
    this.clientFeedback, this.stageId, this.versionNo = 1});
}

/// One version of a design (history on the design detail screen).
class DesignVersionRow {
  final String id;
  final int versionNo;
  final String? modelUrl, imageUrl, changeNote;
  final DateTime? createdAt;
  DesignVersionRow({required this.id, required this.versionNo,
    this.modelUrl, this.imageUrl, this.changeNote, this.createdAt});
  factory DesignVersionRow.fromMap(Map<String, dynamic> m) => DesignVersionRow(
    id: m['id'] as String,
    versionNo: (m['version_no'] as num?)?.toInt() ?? 1,
    modelUrl: m['model_url'] as String?,
    imageUrl: m['file_url'] as String?,
    changeNote: m['change_note'] as String?,
    createdAt: parseDate(m['created_at']),
  );
}

/// A design artifact + its full version history (Designer detail screen).
class DesignDetailData {
  final DesignItem design;
  final List<DesignVersionRow> versions;
  DesignDetailData(this.design, this.versions);
}


// ═══════════════════════════════════════════════════════════════════════════
// Service role — after-sales support on delivered trucks
// ═══════════════════════════════════════════════════════════════════════════

/// A support ticket as the Service team sees it (the client's view is [TicketRow]).
class ServiceTicket {
  final String id, number, category, status, priority;
  final String? description, projectId, projectCode, projectName, clientName;
  final String? assignedTo, resolutionType, resolutionNote, linkedComponentId;
  final DateTime? slaDue, createdAt, resolvedAt;

  ServiceTicket({
    required this.id, required this.number, required this.category,
    required this.status, required this.priority,
    this.description, this.projectId, this.projectCode, this.projectName, this.clientName,
    this.assignedTo, this.resolutionType, this.resolutionNote, this.linkedComponentId,
    this.slaDue, this.createdAt, this.resolvedAt,
  });

  factory ServiceTicket.fromMap(Map<String, dynamic> m) {
    final p = m['projects'] as Map<String, dynamic>?;
    final ca = p?['client_accounts'] as Map<String, dynamic>?;
    return ServiceTicket(
      id: m['id'] as String,
      number: m['ticket_number'] as String? ?? '—',
      category: m['category'] as String? ?? 'other',
      status: m['status'] as String? ?? 'open',
      priority: m['priority'] as String? ?? 'medium',
      description: m['description'] as String?,
      projectId: m['project_id'] as String?,
      projectCode: p?['code'] as String?,
      projectName: p?['name'] as String?,
      clientName: ca?['business_name'] as String?,
      assignedTo: m['assigned_to'] as String?,
      resolutionType: m['resolution_type'] as String?,
      resolutionNote: m['resolution_note'] as String?,
      linkedComponentId: m['linked_component_id'] as String?,
      slaDue: parseDate(m['sla_due']),
      createdAt: parseDate(m['created_at']),
      resolvedAt: parseDate(m['resolved_at']),
    );
  }

  bool get isOpen     => status == 'open' || status == 'in_progress';
  bool get isResolved => status == 'resolved' || status == 'closed';

  /// Time left on the SLA. Negative once breached.
  Duration? get slaRemaining =>
      slaDue == null ? null : slaDue!.difference(DateTime.now());

  bool get isOverdue => isOpen && slaDue != null && slaDue!.isBefore(DateTime.now());

  /// "1h left" · "3d left" · "2h overdue" — the countdown the queue is sorted by.
  String get slaLabel {
    final r = slaRemaining;
    if (r == null) return '—';
    if (isResolved) return 'Done';
    final overdue = r.isNegative;
    final d = r.abs();
    final text = d.inDays >= 1
        ? '${d.inDays}d'
        : d.inHours >= 1
            ? '${d.inHours}h'
            : '${d.inMinutes}m';
    return overdue ? '$text overdue' : '$text left';
  }
}

/// A booked technician visit against a ticket.
class ServiceVisitRow {
  final String id, ticketId, status;
  final String? technicianId, note;
  final DateTime? scheduledDate;
  ServiceVisitRow({required this.id, required this.ticketId, required this.status,
    this.technicianId, this.note, this.scheduledDate});
  factory ServiceVisitRow.fromMap(Map<String, dynamic> m) => ServiceVisitRow(
    id: m['id'] as String,
    ticketId: m['ticket_id'] as String? ?? '',
    status: m['status'] as String? ?? 'scheduled',
    technicianId: m['technician_id'] as String?,
    note: m['note'] as String?,
    scheduledDate: parseDate(m['scheduled_date']),
  );
}

/// A warranty-lookup result row (from fn_warranty_search).
class WarrantyRow {
  final String componentId, itemName, model, serial, projectCode, vendorName, compStatus;
  final String? projectId;
  final DateTime? warrantyEnd;
  final int? daysLeft;
  WarrantyRow({required this.componentId, required this.itemName, required this.model,
    required this.serial, required this.projectCode, required this.vendorName,
    required this.compStatus, this.projectId, this.warrantyEnd, this.daysLeft});
  factory WarrantyRow.fromMap(Map<String, dynamic> m) => WarrantyRow(
    componentId: m['component_id'] as String,
    itemName: m['item_name'] as String? ?? 'Component',
    model: m['model'] as String? ?? '',
    serial: m['serial'] as String? ?? '—',
    projectId: m['project_id'] as String?,
    projectCode: m['project_code'] as String? ?? '',
    vendorName: m['vendor_name'] as String? ?? '',
    compStatus: m['comp_status'] as String? ?? '',
    warrantyEnd: parseDate(m['warranty_end']),
    daysLeft: (m['days_left'] as num?)?.toInt(),
  );

  /// none · expired · expiring · active — see [warrantyStateFor].
  String get state => warrantyStateFor(warrantyEnd, daysLeft: daysLeft);

  /// "2 yr left" · "45d left" · "Expired"
  String get label {
    if (warrantyEnd == null) return 'No warranty';
    final d = daysLeft ?? daysUntil(warrantyEnd!);
    if (d < 0) return 'Expired';
    if (d >= 365) return '${(d / 365).floor()} yr left';
    if (d >= 60) return '${(d / 30).floor()} mo left';
    return '${d}d left';
  }
}

/// A delivered truck in after-sales, with its open-ticket / warranty health.
class DeliveredTruck {
  final Project project;
  final DateTime? deliveredOn;
  final int openTickets, expiringParts;
  DeliveredTruck({required this.project, this.deliveredOn,
    this.openTickets = 0, this.expiringParts = 0});

  bool get healthy => openTickets == 0 && expiringParts == 0;
}

/// Everything the Truck history screen shows for one delivered truck.
class TruckHistory {
  final Project project;
  final DateTime? deliveredOn;
  final String? clientName;
  final int componentCount;
  final DateTime? earliestWarrantyEnd;
  final List<ServiceTicket> tickets;
  TruckHistory({required this.project, this.deliveredOn, this.clientName,
    this.componentCount = 0, this.earliestWarrantyEnd, required this.tickets});

  int? get daysInService =>
      deliveredOn == null ? null : DateTime.now().difference(deliveredOn!).inDays;
}
