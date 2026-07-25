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
class OptRef {
  final String id, label;
  OptRef(this.id, this.label);
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
