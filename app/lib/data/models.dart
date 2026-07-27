/// Domain models (map 1:1 to Supabase tables / views).

class Project {
  final String id, code, name, status;
  final int progressPct;
  Project({required this.id, required this.code, required this.name, required this.status, required this.progressPct});
  factory Project.fromMap(Map<String, dynamic> m) => Project(
    id: m['id'] as String,
    code: m['code'] as String? ?? '',
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'on_track',
    progressPct: (m['progress_pct'] as num?)?.toInt() ?? 0,
  );
}

class OrderDue {
  final String id, itemName, projectCode, projectId, itemCatalogId;
  final int qty, daysLeft;
  final DateTime? orderByDate;
  OrderDue({required this.id, required this.itemName, required this.projectCode,
    required this.projectId, required this.itemCatalogId, required this.qty,
    this.orderByDate, required this.daysLeft});
  factory OrderDue.fromMap(Map<String, dynamic> m) => OrderDue(
    id: m['id'] as String,
    projectId: m['project_id'] as String? ?? '',
    itemCatalogId: m['item_catalog_id'] as String? ?? '',
    qty: (m['qty'] as num?)?.toInt() ?? 1,
    itemName: m['item_name'] as String? ?? '',
    projectCode: m['project_code'] as String? ?? '',
    orderByDate: m['order_by_date'] != null ? DateTime.tryParse(m['order_by_date'].toString()) : null,
    daysLeft: (m['days_left'] as num?)?.toInt() ?? 0,
  );
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

/// One stage while building a custom workflow template.
class StageDraft {
  String name;
  int days;
  StageDraft(this.name, this.days);
}

/// A team member (profiles row).
class Member {
  final String id, name, email, role, status;
  Member({required this.id, required this.name, required this.email, required this.role, required this.status});
  factory Member.fromMap(Map<String, dynamic> m) => Member(
    id: m['id'] as String,
    name: m['full_name'] as String? ?? '',
    email: m['email'] as String? ?? '',
    role: m['role'] as String? ?? '',
    status: m['status'] as String? ?? 'active',
  );
}

/// Aggregated data for the Admin fleet dashboard.
class FleetData {
  final List<Project> projects;
  final List<OrderDue> due;
  FleetData(this.projects, this.due);

  int get total   => projects.length;
  int get onTrack => projects.where((p) => p.status == 'on_track').length;
  int get atRisk  => projects.where((p) => p.status == 'at_risk').length;
  int get delayed => projects.where((p) => p.status == 'delayed').length;

  /// Items whose order-by date is near/overdue — the "needs attention" feed.
  List<OrderDue> get urgent => due.where((d) => d.daysLeft <= 3).toList();
}


/// Safe date parser for nullable Supabase date columns.
DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// One build stage (stages row) shown on the project timeline.
class Stage {
  final String id, name, status; // status: todo | in_progress | done | rework
  final int ord;
  final DateTime? plannedStart, plannedEnd, actualStart, actualEnd;
  Stage({required this.id, required this.name, required this.status, required this.ord,
    this.plannedStart, this.plannedEnd, this.actualStart, this.actualEnd});
  factory Stage.fromMap(Map<String, dynamic> m) => Stage(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'todo',
    ord: (m['ord'] as num?)?.toInt() ?? 0,
    plannedStart: parseDate(m['planned_start']),
    plannedEnd: parseDate(m['planned_end']),
    actualStart: parseDate(m['actual_start']),
    actualEnd: parseDate(m['actual_end']),
  );
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
