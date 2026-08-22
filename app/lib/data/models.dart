/// Domain models (map 1:1 to Supabase tables / views).

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

/// One stage while building a custom workflow template — its BOM items and the
/// checklist the assignee will tick off (copied onto every build's stage on
/// onboarding).
class StageDraft {
  String name;
  int days;
  final List<StageItemDraft> items;
  final List<String> checks;
  StageDraft(this.name, this.days, {List<StageItemDraft>? items, List<String>? checks})
      : items = items ?? [],
        checks = checks ?? [];
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
  /// Which role is meant to do this stage (workshop | design | store | service).
  /// Set from the workflow template, so the PM's assign sheet can recommend the
  /// right people instead of offering every staff member.
  final String? discipline;
  final DateTime? plannedStart, plannedEnd, actualStart, actualEnd;
  /// Dates the PM set when assigning this stage (separate from the backward-
  /// scheduled planned_* dates).
  final DateTime? assignedStart, assignedDue;
  Stage({required this.id, required this.name, required this.status, required this.ord,
    this.assigneeId, this.discipline, this.plannedStart, this.plannedEnd,
    this.actualStart, this.actualEnd, this.assignedStart, this.assignedDue});
  factory Stage.fromMap(Map<String, dynamic> m) => Stage(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'todo',
    ord: (m['ord'] as num?)?.toInt() ?? 0,
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

/// A stage the PM still has to hand out, with its build context — powers the
/// "Assign work" screen.
class AssignableStage {
  final Stage stage;
  final String projectId, projectCode, projectName;
  AssignableStage({required this.stage, required this.projectId,
    required this.projectCode, required this.projectName});
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
  PoApproval({required this.id, required this.poNumber, required this.approvalStatus,
    this.vendorName, this.projectCode, this.pmId,
    this.amount = 0, this.waitingHours = 0, this.overdue = false, this.neededBy});
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
  ActiveStage({required this.id, required this.name, required this.projectCode});
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
  bool get warrantyActive => warrantyEnd != null && warrantyEnd!.isAfter(DateTime.now());
  bool get hasBill => billUrl != null;
}

/// A stock line (Store inventory).
class StockRow {
  final String name, unit;
  final String? itemCatalogId, category;
  final num quantity;
  final int threshold;
  StockRow({required this.name, required this.unit, this.itemCatalogId, this.category, required this.quantity, required this.threshold});
  factory StockRow.fromMap(Map<String, dynamic> m) {
    final ic = m['item_catalog'] as Map<String, dynamic>?;
    return StockRow(
      itemCatalogId: m['item_catalog_id'] as String? ?? ic?['id'] as String?,
      name: ic?['name'] as String? ?? 'Item',
      category: ic?['category'] as String?,
      unit: m['unit'] as String? ?? 'pcs',
      quantity: (m['quantity'] as num?) ?? 0,
      threshold: (ic?['low_stock_threshold'] as num?)?.toInt() ?? 0,
    );
  }
  bool get low => quantity <= threshold;
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
  WorkshopTask({required this.stageId, required this.stageName, required this.status,
    required this.projectId, required this.projectCode, required this.projectName,
    this.assignedDue, this.awaitingApproval = false, this.reworkNote});
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
    );
  }

  WorkshopTask copyWith({bool? awaitingApproval, String? reworkNote}) => WorkshopTask(
    stageId: stageId, stageName: stageName, status: status, projectId: projectId,
    projectCode: projectCode, projectName: projectName, assignedDue: assignedDue,
    awaitingApproval: awaitingApproval ?? this.awaitingApproval,
    reworkNote: reworkNote ?? this.reworkNote,
  );

  /// Nothing has started yet and it is not waiting on the PM.
  bool get canStart => status == 'todo' || status == 'rework';
  bool get isOverdue =>
      assignedDue != null && status != 'done' && assignedDue!.isBefore(DateTime.now());
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
  final int versionNo;
  DesignItem({required this.id, required this.type, required this.status, required this.projectId,
    this.projectCode, this.projectName, this.modelUrl, this.imageUrl, this.changeNote,
    this.clientFeedback, this.versionNo = 1});
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

  /// none · expired · expiring (≤60d) · active
  String get state {
    if (warrantyEnd == null) return 'none';
    final d = daysLeft ?? warrantyEnd!.difference(DateTime.now()).inDays;
    if (d < 0) return 'expired';
    if (d <= 60) return 'expiring';
    return 'active';
  }

  /// "2 yr left" · "45d left" · "Expired"
  String get label {
    if (warrantyEnd == null) return 'No warranty';
    final d = daysLeft ?? warrantyEnd!.difference(DateTime.now()).inDays;
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
