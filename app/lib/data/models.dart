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

/// One BOM item on a template stage (item + qty).
class StageItemDraft {
  final String itemId, label;
  int qty;
  StageItemDraft(this.itemId, this.label, this.qty);
}

/// One stage while building a custom workflow template (+ its BOM items).
class StageDraft {
  String name;
  int days;
  final List<StageItemDraft> items;
  StageDraft(this.name, this.days, {List<StageItemDraft>? items}) : items = items ?? [];
}

/// A pending stage-completion approval (PM approves work submitted by workshop).
class ApprovalItem {
  final String id, stageId, stageName, projectCode;
  ApprovalItem({required this.id, required this.stageId, required this.stageName, required this.projectCode});
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
  final String? assigneeId;
  final DateTime? plannedStart, plannedEnd, actualStart, actualEnd;
  Stage({required this.id, required this.name, required this.status, required this.ord,
    this.assigneeId, this.plannedStart, this.plannedEnd, this.actualStart, this.actualEnd});
  factory Stage.fromMap(Map<String, dynamic> m) => Stage(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'todo',
    ord: (m['ord'] as num?)?.toInt() ?? 0,
    assigneeId: m['assignee_id'] as String?,
    plannedStart: parseDate(m['planned_start']),
    plannedEnd: parseDate(m['planned_end']),
    actualStart: parseDate(m['actual_start']),
    actualEnd: parseDate(m['actual_end']),
  );
}

/// A checklist row under a stage.
class ChecklistItem {
  final String id, label;
  final bool done;
  ChecklistItem({required this.id, required this.label, required this.done});
  factory ChecklistItem.fromMap(Map<String, dynamic> m) => ChecklistItem(
    id: m['id'] as String, label: m['label'] as String? ?? '', done: m['done'] as bool? ?? false);
}

/// A photo / image attached to a stage (attachments where owner_type='stage').
class StagePhoto {
  final String url;
  final String? caption;
  StagePhoto(this.url, this.caption);
  factory StagePhoto.fromMap(Map<String, dynamic> m) =>
    StagePhoto(m['file_url'] as String? ?? '', m['caption'] as String?);
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

/// Everything the Stage detail screen shows for one stage.
class StageBundle {
  final String? assignee;
  final List<ChecklistItem> checklist;
  final List<StagePhoto> photos;
  final List<StagePart> parts;
  final List<StageDelay> delays;
  StageBundle({this.assignee, required this.checklist, required this.photos,
    required this.parts, required this.delays});
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
  final bool read;
  final DateTime? createdAt;
  AppNotification({required this.id, required this.title, this.body, this.type,
    this.read = false, this.createdAt});
  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    body: m['body'] as String?,
    type: m['type'] as String?,
    read: m['read'] as bool? ?? false,
    createdAt: parseDate(m['created_at']),
  );
}


/// A purchase order row (list + detail header).
class PurchaseOrder {
  final String id, poNumber, status; // status: ordered | dispatched | received | partial
  final String? vendorName, projectCode;
  final int itemCount;
  final DateTime? orderDate, expectedDate;
  PurchaseOrder({required this.id, required this.poNumber, required this.status,
    this.vendorName, this.projectCode, this.itemCount = 0, this.orderDate, this.expectedDate});
  factory PurchaseOrder.fromMap(Map<String, dynamic> m) {
    final v = m['vendors'] as Map<String, dynamic>?;
    final p = m['projects'] as Map<String, dynamic>?;
    final lines = m['po_lines'];
    return PurchaseOrder(
      id: m['id'] as String,
      poNumber: m['po_number'] as String? ?? '',
      status: m['status'] as String? ?? 'ordered',
      vendorName: v?['name'] as String?,
      projectCode: p?['code'] as String?,
      itemCount: lines is List ? lines.length : 0,
      orderDate: parseDate(m['order_date']),
      expectedDate: parseDate(m['expected_date']),
    );
  }
}

/// A single line in a purchase order.
class PoLineItem {
  final String name;
  final int qty, receivedQty;
  PoLineItem({required this.name, required this.qty, required this.receivedQty});
  factory PoLineItem.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return PoLineItem(
      name: ic?['name'] as String? ?? 'Item',
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      receivedQty: (m['received_qty'] as num?)?.toInt() ?? 0,
    );
  }
}

/// PO header + its line items.
class PoDetail {
  final PurchaseOrder po;
  final List<PoLineItem> items;
  PoDetail(this.po, this.items);
}

/// A vendor row with reliability + lead time.
class VendorRow {
  final String id, name;
  final String? category;
  final int avgLead, reliability;
  VendorRow({required this.id, required this.name, this.category,
    this.avgLead = 0, this.reliability = 100});
  factory VendorRow.fromMap(Map<String, dynamic> m) => VendorRow(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    category: m['category'] as String?,
    avgLead: (m['avg_lead_time_days'] as num?)?.toInt() ?? 0,
    reliability: (m['reliability_score'] as num?)?.toInt() ?? 100,
  );
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


/// A workshop bay (Schedule screen) — busy if it holds a current stage.
class BayRow {
  final String id, name;
  final bool busy;
  BayRow({required this.id, required this.name, required this.busy});
  factory BayRow.fromMap(Map<String, dynamic> m) => BayRow(
    id: m['id'] as String,
    name: m['name'] as String? ?? 'Bay',
    busy: m['current_stage_id'] != null,
  );
}

/// A PM "today" in-progress stage (project code + stage name).
class ActiveStage {
  final String id, name, projectCode;
  ActiveStage({required this.id, required this.name, required this.projectCode});
}


/// A tracked component instance (Store — traceability, Hero #2).
class ComponentRow {
  final String id, itemCatalogId, name, model, serial, status;
  final String? projectCode, vendorName;
  final DateTime? warrantyEnd, installDate;
  ComponentRow({required this.id, required this.itemCatalogId, required this.name, required this.model,
    required this.serial, required this.status, this.projectCode, this.vendorName, this.warrantyEnd, this.installDate});
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
      warrantyEnd: parseDate(m['warranty_end']),
      installDate: parseDate(m['install_date']),
    );
  }
  bool get warrantyActive => warrantyEnd != null && warrantyEnd!.isAfter(DateTime.now());
}

/// A stock line (Store inventory).
class StockRow {
  final String name, unit;
  final String? category;
  final num quantity;
  final int threshold;
  StockRow({required this.name, required this.unit, this.category, required this.quantity, required this.threshold});
  factory StockRow.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return StockRow(
      name: ic?['name'] as String? ?? 'Item',
      category: ic?['category'] as String?,
      unit: m['unit'] as String? ?? 'pcs',
      quantity: (m['quantity'] as num?) ?? 0,
      threshold: (ic?['low_stock_threshold'] as num?)?.toInt() ?? 0,
    );
  }
  bool get low => quantity <= threshold;
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
