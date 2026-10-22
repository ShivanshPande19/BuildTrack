// Tests for the pure domain logic in lib/data/models.dart.
//
// `models.dart` deliberately imports nothing — no Flutter, no Supabase — so
// these run in milliseconds with no network, no credentials and no emulator.
// That is the point: this is the layer that decides whether a stage is overdue,
// whether a part is still in warranty and whether work still needs handing out,
// and those decisions are worth pinning down.
//
// This file replaced the stock `widget_test.dart` that `flutter create` leaves
// behind. That test asserts on a tap-counter screen which does not exist in this
// app, so it fails the moment anyone runs `flutter test` — which is how a repo
// ends up with a test suite nobody trusts.

import 'package:flutter_test/flutter_test.dart';
import 'package:buildtrack/data/models.dart';

/// A [ScheduleEntry] whose due date is [dayOffset] days from today.
/// Everything else is filler — these tests only care about the dates.
ScheduleEntry entry({int? dayOffset, String? assigneeId, bool dueIsPlanned = false}) {
  final now = DateTime.now();
  // DateTime(y, m, d + n) normalises across month and year ends, and unlike
  // add(Duration(days: n)) it is calendar arithmetic rather than 24-hour
  // arithmetic — so these tests do not drift in a timezone with daylight saving.
  final due = dayOffset == null ? null : DateTime(now.year, now.month, now.day + dayOffset);
  return ScheduleEntry(
    stageId: 's1',
    stageName: 'Electrical work',
    status: 'todo',
    projectId: 'p1',
    projectCode: 'AZ-101',
    projectName: 'Chai Point',
    assigneeId: assigneeId,
    discipline: 'workshop',
    due: due,
    dueIsPlanned: dueIsPlanned,
  );
}

void main() {
  mainExtra();
  scheduleTests();
  stockTests();
  designTodoTests();
  workshopTests();
  stageStepTests();
  pmSetupTests();
  designationTests();
  subStageTests();
  workflowBuilderTests();
  phaseDWalkTests();
  group('parseDate', () {
    test('returns null for null rather than throwing', () {
      // Every nullable date column in the schema arrives here as null at some
      // point (a stage that has not started, a part with no warranty on record).
      expect(parseDate(null), isNull);
    });

    test('parses the date-only strings Postgres sends for a `date` column', () {
      expect(parseDate('2026-03-14'), DateTime(2026, 3, 14));
    });

    test('parses the timestamptz strings Postgres sends', () {
      final d = parseDate('2026-03-14T09:30:00Z');
      expect(d, isNotNull);
      expect(d!.toUtc().hour, 9);
    });

    test('returns null for an unparseable value instead of throwing', () {
      // A malformed value should leave a field empty, not take down the screen.
      expect(parseDate('not a date'), isNull);
      expect(parseDate(''), isNull);
    });
  });

  group('ScheduleEntry.daysLeft', () {
    test('is 0 for something due today', () {
      expect(entry(dayOffset: 0).daysLeft, 0);
    });

    test('counts whole days forward', () {
      expect(entry(dayOffset: 1).daysLeft, 1);
      expect(entry(dayOffset: 7).daysLeft, 7);
    });

    test('goes negative once the date has passed', () {
      expect(entry(dayOffset: -1).daysLeft, -1);
      expect(entry(dayOffset: -12).daysLeft, -12);
    });

    test('is null when no date is set at all', () {
      expect(entry().daysLeft, isNull);
    });
  });

  group('ScheduleEntry buckets', () {
    test('yesterday is overdue, today is not', () {
      expect(entry(dayOffset: -1).isOverdue, isTrue);
      expect(entry(dayOffset: 0).isOverdue, isFalse);
      expect(entry(dayOffset: 1).isOverdue, isFalse);
    });

    test('a stage with no date is never overdue', () {
      // Nobody committed to a date, so it cannot have been missed. It belongs in
      // the "No date yet" bucket, which is the PM's cue to set one.
      final e = entry();
      expect(e.isOverdue, isFalse);
      expect(e.hasNoDate, isTrue);
    });

    test('isDueToday is exactly today', () {
      expect(entry(dayOffset: 0).isDueToday, isTrue);
      expect(entry(dayOffset: -1).isDueToday, isFalse);
      expect(entry(dayOffset: 1).isDueToday, isFalse);
      expect(entry().isDueToday, isFalse);
    });

    test('every entry lands in exactly one Schedule bucket', () {
      // The Schedule tab filters into overdue / today / next 7 days / later /
      // no date. If those five predicates ever overlap or leave a gap, a stage
      // is either shown twice or silently disappears.
      for (final offset in [-30, -1, 0, 1, 7, 8, 400, null]) {
        final e = entry(dayOffset: offset);
        final d = e.daysLeft;
        final buckets = [
          e.isOverdue,
          e.isDueToday,
          d != null && d > 0 && d <= 7,
          d != null && d > 7,
          e.hasNoDate,
        ].where((inIt) => inIt).length;
        expect(buckets, 1, reason: 'offset $offset landed in $buckets buckets, not 1');
      }
    });

    test('isUnassigned tracks the assignee, which is what the PM must fix', () {
      expect(entry(dayOffset: 1).isUnassigned, isTrue);
      expect(entry(dayOffset: 1, assigneeId: 'u1').isUnassigned, isFalse);
    });

    test('dueIsPlanned separates a backward-scheduled plan from a PM promise', () {
      expect(entry(dayOffset: 3).dueIsPlanned, isFalse);
      expect(entry(dayOffset: 3, dueIsPlanned: true).dueIsPlanned, isTrue);
    });
  });

  group('Stage.needsAssigning', () {
    Stage stage({String? assigneeId, required String status}) =>
        Stage(id: 's', name: 'Fabrication', status: status, ord: 1, assigneeId: assigneeId);

    test('unassigned open work needs assigning', () {
      expect(stage(status: 'todo').needsAssigning, isTrue);
      expect(stage(status: 'in_progress').needsAssigning, isTrue);
      expect(stage(status: 'rework').needsAssigning, isTrue);
    });

    test('finished work does not, even with nobody on it', () {
      // A done stage with no assignee is history, not a gap in the plan.
      expect(stage(status: 'done').needsAssigning, isFalse);
    });

    test('assigned work does not', () {
      expect(stage(assigneeId: 'u1', status: 'todo').needsAssigning, isFalse);
    });

    test('isAssigned is independent of status', () {
      expect(stage(assigneeId: 'u1', status: 'done').isAssigned, isTrue);
      expect(stage(status: 'done').isAssigned, isFalse);
    });
  });

  group('Stage.fromMap', () {
    test('survives a row where every nullable column is null', () {
      // RLS and column-level selects mean a screen can legitimately receive a
      // row with almost nothing filled in. It must not throw.
      final s = Stage.fromMap({'id': 'abc'});
      expect(s.id, 'abc');
      expect(s.name, '');
      expect(s.status, 'todo');
      expect(s.ord, 0);
      expect(s.assigneeId, isNull);
      expect(s.assignedDue, isNull);
    });

    test('reads the assignment dates the PM set', () {
      final s = Stage.fromMap({
        'id': 'abc',
        'name': 'Electrical work',
        'status': 'in_progress',
        'ord': 3,
        'assignee_id': 'u1',
        'discipline': 'workshop',
        'assigned_start': '2026-03-01',
        'assigned_due': '2026-03-10',
      });
      expect(s.discipline, 'workshop');
      expect(s.assignedStart, DateTime(2026, 3, 1));
      expect(s.assignedDue, DateTime(2026, 3, 10));
      expect(s.needsAssigning, isFalse);
    });
  });

  group('ComponentRow.warrantyActive', () {
    ComponentRow part({DateTime? warrantyEnd}) => ComponentRow(
      id: 'c1', itemCatalogId: 'i1', name: 'Griddle', model: 'GX-2',
      serial: 'SN-1', status: 'installed', warrantyEnd: warrantyEnd);

    test('a future end date is in warranty', () {
      expect(part(warrantyEnd: DateTime.now().add(const Duration(days: 30))).warrantyActive, isTrue);
    });

    test('a past end date is not', () {
      expect(part(warrantyEnd: DateTime.now().subtract(const Duration(days: 1))).warrantyActive, isFalse);
    });

    test('no end date on record is not treated as covered', () {
      // Store has not logged a warranty for this part. Service must not be told
      // the client is covered when nobody knows that.
      expect(part().warrantyActive, isFalse);
    });
  });

  group('ComponentRow.fromMap', () {
    test('flattens the joined item_catalog / projects / vendors rows', () {
      final c = ComponentRow.fromMap({
        'id': 'c1',
        'item_catalog_id': 'i1',
        'serial_number': 'SN-9',
        'status': 'in_stock',
        'warranty_end': '2027-01-31',
        'item_catalog': {'name': 'Griddle', 'model': 'GX-2'},
        'projects': {'code': 'AZ-101'},
        'vendors': {'name': 'Kitchen Co'},
      });
      expect(c.name, 'Griddle');
      expect(c.model, 'GX-2');
      expect(c.projectCode, 'AZ-101');
      expect(c.vendorName, 'Kitchen Co');
      expect(c.warrantyEnd, DateTime(2027, 1, 31));
    });

    test('a part still in store has no project and no install date', () {
      final c = ComponentRow.fromMap({
        'id': 'c1', 'serial_number': 'SN-9', 'status': 'in_stock',
        'item_catalog': {'name': 'Griddle'},
      });
      expect(c.projectCode, isNull);
      expect(c.installDate, isNull);
      expect(c.model, '');
    });
  });

  group('Project.fromMap', () {
    test('a build with no PM is visible as such', () {
      // pmId == null means no PM sees the build and none of its stages can be
      // assigned or approved. Admin's "No PM" filter depends on this surviving.
      final p = Project.fromMap({
        'id': 'p1', 'code': 'AZ-101', 'name': 'Chai Point',
        'status': 'on_track', 'progress_pct': 0,
      });
      expect(p.pmId, isNull);
    });
  });

  group('FleetData active vs delivered', () {
    Project p(String status) => Project(id: status, code: 'C', name: 'N', status: status, progressPct: 0);
    test('delivered builds are not active, so the shares sum to 100%', () {
      final f = FleetData([p('on_track'), p('on_track'), p('at_risk'), p('delayed'), p('delivered'), p('delivered')], []);
      expect(f.total, 6);
      expect(f.delivered, 2);
      expect(f.active, 4);
      expect(f.onTrack + f.atRisk + f.delayed, f.active);
    });
    test('an all-delivered fleet has no active builds', () {
      final f = FleetData([p('delivered')], []);
      expect(f.active, 0);
      expect(f.onTrack, 0);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Added with migration 0026 / the pre-demo fix pass. Each group names the bug
// it pins down, so a regression says what broke rather than just where.
// ───────────────────────────────────────────────────────────────────────────

/// A [Project] with just the fields the attention feed reads.
Project proj(String code, String status, {String? pmId = 'pm1', int pct = 40}) =>
    Project(id: 'id-$code', code: code, name: '$code Truck', status: status,
            progressPct: pct, pmId: pmId);

/// An [OrderDue] whose order-by date is [daysLeft] days away, or undated.
OrderDue due({int? daysLeft, String code = 'AZ-101'}) {
  final now = DateTime.now();
  return OrderDue(
    id: 'r-$code-$daysLeft', itemName: 'Inverter 2kW', projectCode: code,
    projectId: 'p-$code', itemCatalogId: 'i1', qty: 2,
    orderByDate: daysLeft == null ? null : DateTime(now.year, now.month, now.day + daysLeft),
    daysLeft: daysLeft,
  );
}

void mainExtra() {
  group("Admin's needs-attention feed", () {
    test('a delayed build is listed even when no material is due', () {
      final f = FleetData([proj('AZ-1', 'delayed')], []);
      expect(f.attention, isNotEmpty,
          reason: 'this read "All caught up" while a build sat in delayed');
      expect(f.attention.first.kind, AttentionKind.delayed);
      expect(f.attention.first.projectId, 'id-AZ-1');
    });

    test('a build with no project manager is listed — nobody can work on it', () {
      final f = FleetData([proj('AZ-2', 'on_track', pmId: null)], []);
      expect(f.attention.single.kind, AttentionKind.noPm);
    });

    test('a delivered build with no PM is not a problem any more', () {
      final f = FleetData([proj('AZ-3', 'delivered', pmId: null)], []);
      expect(f.attention, isEmpty);
    });

    test('worst first: delayed, then no PM, then at risk, then materials', () {
      final f = FleetData([
        proj('AZ-R', 'at_risk'),
        proj('AZ-N', 'on_track', pmId: null),
        proj('AZ-D', 'delayed'),
        proj('AZ-OK', 'on_track'),
      ], [due(daysLeft: 1)]);
      expect(f.attention.map((a) => a.kind).toList(), [
        AttentionKind.delayed,
        AttentionKind.noPm,
        AttentionKind.atRisk,
        AttentionKind.orderBy,
      ]);
    });

    test('everything healthy really is "all caught up"', () {
      final f = FleetData([proj('AZ-4', 'on_track')], [due(daysLeft: 30)]);
      expect(f.attention, isEmpty);
    });

    test('only on-track/at-risk/delayed count towards the active shares', () {
      final f = FleetData([
        proj('AZ-5', 'on_track'), proj('AZ-6', 'delayed'), proj('AZ-7', 'delivered'),
      ], []);
      expect(f.active, 2);
      expect(f.delivered, 1);
      expect(f.onTrack + f.atRisk + f.delayed, f.active);
    });
  });

  group('order-by urgency', () {
    test('an undated requirement is not urgent (it used to shout "Order today")', () {
      final f = FleetData([], [due(daysLeft: null)]);
      expect(f.urgent, isEmpty);
      expect(f.attention, isEmpty);
    });

    test('undated sorts last, so it can never take the hero slot', () {
      final rows = [due(daysLeft: null), due(daysLeft: 5), due(daysLeft: -2)]
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
      expect(rows.map((r) => r.daysLeft).toList(), [-2, 5, null]);
    });

    test('labels read the way a buyer thinks about them', () {
      expect(due(daysLeft: null).urgencyLabel, 'Needs a date');
      expect(due(daysLeft: -3).urgencyLabel, '3d overdue');
      expect(due(daysLeft: 0).urgencyLabel, 'Order today');
      expect(due(daysLeft: 4).urgencyLabel, '4d left');
    });
  });

  group('warranty state', () {
    DateTime inDays(int n) {
      final t = DateTime.now();
      return DateTime(t.year, t.month, t.day + n);
    }

    test('a warranty that ends today is expiring, not expired', () {
      // The truck record compared a date-only value against DateTime.now(), so
      // midnight-this-morning read as "already expired".
      expect(warrantyStateFor(inDays(0)), 'expiring');
      expect(daysUntil(inDays(0)), 0);
    });

    test('one threshold everywhere: the record and the search now agree', () {
      final end = inDays(45);
      final fromDate = warrantyStateFor(end);
      final fromServerDays = warrantyStateFor(end, daysLeft: 45);
      expect(fromDate, 'expiring');
      expect(fromServerDays, fromDate,
          reason: 'the truck record used 30 days while warranty search used 60');
    });

    test('the states cover the whole line', () {
      expect(warrantyStateFor(null), 'none');
      expect(warrantyStateFor(inDays(-1)), 'expired');
      expect(warrantyStateFor(inDays(warrantyExpiringDays)), 'expiring');
      expect(warrantyStateFor(inDays(warrantyExpiringDays + 1)), 'active');
    });
  });

  group('notification targets', () {
    AppNotification n(String? type, String? id) => AppNotification(
      id: 'n1', title: 't', entityType: type, entityId: id);

    test('a build, stage, PO or ticket notification is openable', () {
      for (final t in ['project', 'stage', 'purchase_order', 'ticket']) {
        expect(n(t, 'e1').isOpenable, isTrue, reason: t);
      }
    });

    test('no entity means nothing to open — no dead-end tap', () {
      expect(n('project', null).isOpenable, isFalse);
      expect(n(null, 'e1').isOpenable, isFalse);
      expect(n('design', 'e1').isOpenable, isFalse);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// The PM Schedule, build by build. The flat date-sorted list it replaced could
// not answer "which truck is in trouble" — across ten builds it interleaved
// seventy stage rows and the build stopped being visible. These pin down the
// ordering and the one-line verdict that make the new lens worth having.
// ───────────────────────────────────────────────────────────────────────────

StageTick stageTick(String name, {
  int ord = 1,
  /// Parallel group (0031). Defaults to `ord`, which is what every build
  /// created before 0031 was backfilled to.
  int? step,
  String status = 'todo',
  String? who = 'Vikas',
  int? dueInDays,
  bool awaiting = false,
}) {
  final t = DateTime.now();
  return StageTick(
    id: 'st-$name-$ord', name: name, status: status, ord: ord, step: step ?? ord,
    assigneeName: who,
    due: dueInDays == null ? null : DateTime(t.year, t.month, t.day + dueInDays),
    awaitingApproval: awaiting,
  );
}

BuildSchedule build(String code, List<StageTick> stages, {int? deliveryInDays, String status = 'on_track'}) {
  final t = DateTime.now();
  return BuildSchedule(
    project: Project(id: 'p-$code', code: code, name: '$code Truck',
        status: status, progressPct: 0, pmId: 'pm1'),
    targetDelivery: deliveryInDays == null
        ? null : DateTime(t.year, t.month, t.day + deliveryInDays),
    stages: stages,
  );
}

void scheduleTests() {
  group('BuildSchedule · what is blocking it', () {
    test('a stage sitting with the PM is named first — it is theirs to clear', () {
      final b = build('AZ-1', [
        stageTick('Design', ord: 1, status: 'done'),
        stageTick('Fabrication', ord: 2, status: 'in_progress', awaiting: true, dueInDays: -3),
      ]);
      expect(b.awaitingCount, 1);
      // Overdue too, but the PM's own queue leads.
      expect(b.blockedLabel, startsWith('1 waiting on you'));
      expect(b.blockedLabel, contains('1 overdue'));
    });

    test('an unassigned stage is the PM\'s problem and says so', () {
      final b = build('AZ-2', [stageTick('Paint', who: null)]);
      expect(b.unassignedCount, 1);
      expect(b.blockedLabel, '1 unassigned');
    });

    test('a finished stage is never overdue or unassigned', () {
      final b = build('AZ-3', [stageTick('Design', status: 'done', who: null, dueInDays: -40)]);
      expect(b.overdueCount, 0);
      expect(b.unassignedCount, 0);
      expect(b.blockedLabel, 'All stages done');
    });

    test('nothing wrong reads as on track, not as an empty problem list', () {
      final b = build('AZ-4', [
        stageTick('Design', status: 'done'),
        stageTick('Fabrication', status: 'in_progress', dueInDays: 5),
      ]);
      expect(b.isClear, isTrue);
      expect(b.blockedLabel, 'On track');
    });

    test('rework counts as a blockage of its own', () {
      final b = build('AZ-5', [stageTick('Paint', status: 'rework', dueInDays: 2)]);
      expect(b.blockedLabel, '1 in rework');
    });
  });

  group('BuildSchedule · where the build is', () {
    test('current is what is being worked', () {
      final b = build('AZ-6', [
        stageTick('Design', ord: 1, status: 'done'),
        stageTick('Fabrication', ord: 2, status: 'in_progress'),
        stageTick('Paint', ord: 3),
      ]);
      expect(b.current!.name, 'Fabrication');
      expect(b.currentIndex, 2);
      expect(b.total, 3);
      expect(b.doneCount, 1);
    });

    test('with nothing started, current is the next thing up', () {
      final b = build('AZ-7', [stageTick('Design', ord: 1), stageTick('Fabrication', ord: 2)]);
      expect(b.current!.name, 'Design');
      expect(b.currentIndex, 1);
    });

    test('a build with no stages does not crash the strip', () {
      final b = build('AZ-8', const []);
      expect(b.current, isNull);
      expect(b.currentIndex, 0);
      expect(b.total, 0);
    });
  });

  group('BuildSchedule · worst first', () {
    test('waiting on the PM outranks merely being late', () {
      // The one the PM can unblock right now comes first.
      final waiting = build('AZ-W', [stageTick('A', status: 'in_progress', awaiting: true)], deliveryInDays: 60);
      final late = build('AZ-L', [stageTick('A', status: 'in_progress', dueInDays: -20)], deliveryInDays: 60);
      final sorted = [late, waiting]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-W');
    });

    test('more overdue stages outrank fewer', () {
      final two = build('AZ-2X', [
        stageTick('A', ord: 1, status: 'in_progress', dueInDays: -5),
        stageTick('B', ord: 2, dueInDays: -2),
      ]);
      final one = build('AZ-1X', [stageTick('A', status: 'in_progress', dueInDays: -5)]);
      final sorted = [one, two]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-2X');
    });

    test('all else equal, the nearest delivery comes first', () {
      final soon = build('AZ-SOON', [stageTick('A', status: 'in_progress', dueInDays: 5)], deliveryInDays: 7);
      final far = build('AZ-FAR', [stageTick('A', status: 'in_progress', dueInDays: 5)], deliveryInDays: 90);
      final sorted = [far, soon]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-SOON');
    });

    test('a delivered build sinks below every live one', () {
      final done = build('AZ-DONE', [stageTick('A', status: 'done')],
          deliveryInDays: -2, status: 'delivered');
      final healthy = build('AZ-OK', [stageTick('A', status: 'in_progress', dueInDays: 30)],
          deliveryInDays: 60);
      final sorted = [done, healthy]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-OK');
      expect(done.blockedLabel, 'Delivered');
    });

    test('a build with no delivery date does not jump the queue', () {
      final undated = build('AZ-NODATE', [stageTick('A', status: 'in_progress', dueInDays: 5)]);
      final dated = build('AZ-DATED', [stageTick('A', status: 'in_progress', dueInDays: 5)], deliveryInDays: 30);
      final sorted = [undated, dated]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-DATED');
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Who restocks what. `0019` separates *how* an item is tracked (serialized)
// from *who orders it* (is_essential), and the Store screens were ignoring the
// second half.
// ───────────────────────────────────────────────────────────────────────────

StockRow stock(String name, {
  required num qty,
  int threshold = 0,
  bool essential = false,
}) => StockRow(name: name, unit: 'pcs', itemCatalogId: 'i-$name',
      quantity: qty, threshold: threshold, isEssential: essential);

void stockTests() {
  group('StockRow · low stock is the Store\'s job only', () {
    test('a project part sitting at zero is not "low" — that is its normal state', () {
      // An LED panel is ordered against one build's requirement, fitted, and
      // not kept in spares. low_stock_threshold defaults to 0, so the old
      // `quantity <= threshold` flagged every one of them, permanently.
      final led = stock('LED Panel', qty: 0);
      expect(led.isProjectPart, isTrue);
      expect(led.low, isFalse);
    });

    test('an essential at or below its threshold is low', () {
      expect(stock('Steel sheet', qty: 2, threshold: 5, essential: true).low, isTrue);
      expect(stock('Steel sheet', qty: 5, threshold: 5, essential: true).low, isTrue);
      expect(stock('Steel sheet', qty: 6, threshold: 5, essential: true).low, isFalse);
    });

    test('an essential at zero with no threshold set still reads low', () {
      // Nothing on the shelf of something the Store restocks is the one case
      // the flag exists for.
      expect(stock('Wire', qty: 0, essential: true).low, isTrue);
    });

    test('a project part is never low however the numbers fall', () {
      expect(stock('Inverter', qty: 0, threshold: 10).low, isFalse);
      expect(stock('Inverter', qty: 50, threshold: 10).low, isFalse);
    });

    test('only essentials count towards a low-stock badge', () {
      final rows = [
        stock('LED Panel', qty: 0),                           // project part
        stock('Inverter', qty: 0),                            // project part
        stock('Steel sheet', qty: 1, threshold: 5, essential: true),
        stock('Wire', qty: 80, threshold: 20, essential: true),
      ];
      expect(rows.where((r) => r.low).map((r) => r.name).toList(), ['Steel sheet']);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// The designer's "what needs you". The section it replaced read
// design_artifacts alone, so a designer with an overdue stage and no designs
// was told "All caught up" — on the same screen that showed the stage as
// overdue. These pin down that it reads the stage and its designs together.
// ───────────────────────────────────────────────────────────────────────────

WorkshopTask dtask(String code, {
  String stageId = 'st1',
  String status = 'in_progress',
  int? dueInDays,
  bool awaiting = false,
  String? reworkNote,
}) {
  final t = DateTime.now();
  return WorkshopTask(
    stageId: stageId, stageName: 'Design & Layout', status: status,
    projectId: 'p-$code', projectCode: code, projectName: '$code Truck',
    assignedDue: dueInDays == null ? null : DateTime(t.year, t.month, t.day + dueInDays),
    awaitingApproval: awaiting, reworkNote: reworkNote,
  );
}

DesignItem ditem(String code, String status, {String id = 'd1', String? stageId, String? feedback}) =>
    DesignItem(id: id, type: 'layout', status: status, projectId: 'p-$code',
      projectCode: code, projectName: '$code Truck', stageId: stageId, clientFeedback: feedback);

void designTodoTests() {
  group('designTodos · the bug it was built for', () {
    test('an overdue stage with no designs is NOT "all caught up"', () {
      final r = designTodos(tasks: [dtask('AZ-101', dueInDays: -60)], designs: const []);
      expect(r.todos, isNotEmpty, reason: 'this read as "all caught up" before');
      expect(r.todos.single.kind, DesignTodoKind.overdueNoDesign);
      expect(r.todos.single.action, 'Start a design');
    });

    test('a stage that is not late still appears, just lower', () {
      final r = designTodos(tasks: [dtask('AZ-101', dueInDays: 10)], designs: const []);
      expect(r.todos.single.kind, DesignTodoKind.notStarted);
    });
  });

  group('designTodos · what the designer can actually act on', () {
    test('a design with the client is not a to-do — it is counted', () {
      final r = designTodos(
        tasks: [dtask('AZ-101', dueInDays: -5)],
        designs: [ditem('AZ-101', 'pending_approval', stageId: 'st1')]);
      expect(r.todos, isEmpty, reason: 'the designer cannot move this');
      expect(r.designsWithClient, 1);
    });

    test('a stage sitting with the PM is not a to-do either', () {
      final r = designTodos(
        tasks: [dtask('AZ-101', awaiting: true, dueInDays: -5)], designs: const []);
      expect(r.todos, isEmpty);
    });

    test('an approved design turns the stage into a one-tap submit', () {
      final r = designTodos(
        tasks: [dtask('AZ-101')],
        designs: [ditem('AZ-101', 'approved', stageId: 'st1')]);
      expect(r.todos.single.kind, DesignTodoKind.readyToSubmit);
      expect(r.todos.single.action, 'Submit stage');
      expect(r.todos.single.task, isNotNull);
    });

    test('a change request carries the client\'s own words', () {
      final r = designTodos(
        tasks: [dtask('AZ-101')],
        designs: [ditem('AZ-101', 'revision', stageId: 'st1', feedback: 'Make the counter lower')]);
      expect(r.todos.single.kind, DesignTodoKind.changesRequested);
      expect(r.todos.single.detail, 'Make the counter lower');
    });

    test('a draft is called out as doing nothing', () {
      final r = designTodos(
        tasks: [dtask('AZ-101')],
        designs: [ditem('AZ-101', 'draft', stageId: 'st1')]);
      expect(r.todos.single.kind, DesignTodoKind.unsentDraft);
      expect(r.todos.single.action, 'Send for approval');
    });

    test('a rework note from the PM leads the card', () {
      final r = designTodos(
        tasks: [dtask('AZ-101', status: 'rework', reworkNote: 'Wrong truck dimensions')],
        designs: const []);
      expect(r.todos.single.kind, DesignTodoKind.rework);
      expect(r.todos.single.detail, 'Wrong truck dimensions');
    });

    test('a finished stage is not work', () {
      final r = designTodos(tasks: [dtask('AZ-101', status: 'done')], designs: const []);
      expect(r.todos, isEmpty);
    });
  });

  group('designTodos · ordering', () {
    test('rework first, then the one-tap submit, then the client\'s changes', () {
      final r = designTodos(tasks: [
        dtask('AZ-A', stageId: 'sA', dueInDays: -90),                       // overdue, nothing
        dtask('AZ-B', stageId: 'sB'),                                       // approved
        dtask('AZ-C', stageId: 'sC', status: 'rework'),                     // rework
        dtask('AZ-D', stageId: 'sD'),                                       // revision
      ], designs: [
        ditem('AZ-B', 'approved', id: 'dB', stageId: 'sB'),
        ditem('AZ-D', 'revision', id: 'dD', stageId: 'sD'),
      ]);
      expect(r.todos.map((t) => t.kind).toList(), [
        DesignTodoKind.rework,
        DesignTodoKind.readyToSubmit,
        DesignTodoKind.changesRequested,
        DesignTodoKind.overdueNoDesign,
      ]);
    });
  });

  group('designTodos · designs with no stage of their own', () {
    test('a design on a build the designer holds no stage on is still theirs', () {
      // Made ahead of the assignment, or left behind when a stage moved.
      final r = designTodos(tasks: const [], designs: [ditem('AZ-X', 'revision')]);
      expect(r.todos.single.kind, DesignTodoKind.changesRequested);
    });

    test('a design linked to a stage is not counted twice', () {
      final r = designTodos(
        tasks: [dtask('AZ-101', stageId: 'st1')],
        designs: [ditem('AZ-101', 'draft', stageId: 'st1')]);
      expect(r.todos.length, 1);
    });

    test('a linked design wins over an unlinked one on the same build', () {
      // The stage's own design decides the stage, even if an older unlinked
      // design on the same build says something else — and the loose one does
      // not then come back as a second card for the same build.
      final r = designTodos(
        tasks: [dtask('AZ-101', stageId: 'st1')],
        designs: [
          ditem('AZ-101', 'approved', id: 'linked', stageId: 'st1'),
          ditem('AZ-101', 'draft', id: 'loose'),
        ]);
      expect(r.todos.single.kind, DesignTodoKind.readyToSubmit);
    });

    test('a loose design on a build the designer already holds a stage on '
         'does not raise its own card', () {
      // Two cards saying "AZ-101" with different next steps is the same
      // double-answer this list was built to end.
      final r = designTodos(
        tasks: [dtask('AZ-101', stageId: 'st1', dueInDays: 5)],
        designs: [ditem('AZ-101', 'draft', id: 'loose')]);   // no stage_id
      expect(r.todos.length, 1);
      expect(r.todos.single.kind, DesignTodoKind.unsentDraft,
        reason: 'the stage reads the build\'s designs when none is linked');
    });
  });

  group('designTodos · designs with the client', () {
    test('a design with the client is counted once, not once per stage', () {
      // Two of the designer's stages on one build both read the same design.
      final r = designTodos(
        tasks: [
          dtask('AZ-101', stageId: 'st1'),
          dtask('AZ-101', stageId: 'st2'),
        ],
        designs: [ditem('AZ-101', 'pending_approval', id: 'dP')]);
      expect(r.designsWithClient, 1);
      expect(r.todos, isEmpty);
    });

    test('a design with the client on a build with no stage is still counted', () {
      final r = designTodos(
        tasks: const [], designs: [ditem('AZ-X', 'pending_approval')]);
      expect(r.designsWithClient, 1);
      expect(r.todos, isEmpty);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// The Workshop role, read end to end. Every one of these is a defect that was
// live: a stage due today in a red "Overdue" pill, a delivered truck still
// offering Start work, a list ordered by a number that means nothing across
// builds, and a warranty that expired on its own last day — for the third time.
// ───────────────────────────────────────────────────────────────────────────

WorkshopTask wtask({
  String code = 'AZ-101',
  String stageId = 'st1',
  String status = 'in_progress',
  int? dueInDays,
  bool awaiting = false,
  String projectStatus = 'on_track',
  bool locked = false,
  String? blockedBy,
  int blockedByCount = 0,
}) {
  final n = DateTime.now();
  return WorkshopTask(
    stageId: stageId, stageName: 'Chassis', status: status,
    projectId: 'p-$code', projectCode: code, projectName: '$code Truck',
    assignedDue: dueInDays == null ? null : DateTime(n.year, n.month, n.day + dueInDays),
    awaitingApproval: awaiting, projectStatus: projectStatus,
    isLocked: locked,
    blockedBy: blockedBy ?? (locked ? 'Design & Layout' : null),
    blockedByCount: blockedByCount != 0 ? blockedByCount : (locked ? 1 : 0),
  );
}

void workshopTests() {
  group('WorkshopTask.isOverdue · calendar days, not a timestamp', () {
    test('a stage due TODAY is not overdue', () {
      // This was the bug. `assigned_due` is a Postgres `date`, so it parses to
      // midnight, and `isBefore(DateTime.now())` is true from 00:01 onwards —
      // every stage due today wore a red "Overdue" pill all day, in Workshop's
      // Tasks, Design's to-do list and Service's stages.
      expect(wtask(dueInDays: 0).isOverdue, isFalse);
      expect(wtask(dueInDays: 0).isDueToday, isTrue);
    });

    test('yesterday is overdue, tomorrow is not', () {
      expect(wtask(dueInDays: -1).isOverdue, isTrue);
      expect(wtask(dueInDays: 1).isOverdue, isFalse);
    });

    test('a stage with no date is never overdue', () {
      expect(wtask().isOverdue, isFalse);
      expect(wtask().daysLeft, isNull);
    });

    test('an approved stage is not overdue, however late it was', () {
      expect(wtask(status: 'done', dueInDays: -90).isOverdue, isFalse);
    });

    test('it agrees with StageTick, which the PM screens use', () {
      // Two definitions of "overdue" in one app is how the PM and the fitter
      // end up looking at the same stage and disagreeing about it.
      for (final offset in [-30, -1, 0, 1, 90]) {
        final n = DateTime.now();
        final due = DateTime(n.year, n.month, n.day + offset);
        expect(wtask(dueInDays: offset).isOverdue,
          StageTick(id: 's', name: 'n', status: 'in_progress', ord: 1, due: due).isOverdue,
          reason: 'offset $offset disagrees with StageTick');
      }
    });
  });

  group('WorkshopTask · a delivered truck is not work', () {
    test('a stage left open on a delivered build is closed, not live', () {
      // fn_mark_delivered(p_force => true) leaves open stages open on purpose —
      // closing them would rewrite what happened. But they stayed in the
      // fitter's task list forever, with a live Start work button on a truck
      // the customer already had.
      final t = wtask(status: 'todo', projectStatus: 'delivered', dueInDays: -200);
      expect(t.isDelivered, isTrue);
      expect(t.isClosed, isTrue);
      expect(t.isOverdue, isFalse, reason: 'it cannot be late once the truck has gone');
    });

    test('an open stage on a live build is not closed', () {
      expect(wtask(status: 'todo').isClosed, isFalse);
    });

    test('copyWith keeps the build status', () {
      // The approvals pass rebuilds every row through copyWith; dropping
      // projectStatus there would quietly resurrect the delivered stages.
      final t = wtask(projectStatus: 'delivered').copyWith(awaitingApproval: true);
      expect(t.isDelivered, isTrue);
    });
  });

  group('WorkshopTask.compare · ordering across builds', () {
    test('rework leads, then overdue, then today, then soonest', () {
      final list = [
        wtask(code: 'AZ-E', stageId: 'e', dueInDays: 30),
        wtask(code: 'AZ-C', stageId: 'c', dueInDays: 0),
        wtask(code: 'AZ-A', stageId: 'a', status: 'rework'),
        wtask(code: 'AZ-D', stageId: 'd', dueInDays: 3),
        wtask(code: 'AZ-B', stageId: 'b', dueInDays: -5),
      ]..sort(WorkshopTask.compare);
      expect(list.map((t) => t.projectCode).toList(),
        ['AZ-A', 'AZ-B', 'AZ-C', 'AZ-D', 'AZ-E']);
    });

    test('an undated stage sorts after every dated one', () {
      // Nobody committed to a date, so it cannot be the most urgent thing —
      // the same rule the PM's Schedule uses.
      final list = [
        wtask(code: 'AZ-N', stageId: 'n'),
        wtask(code: 'AZ-F', stageId: 'f', dueInDays: 400),
      ]..sort(WorkshopTask.compare);
      expect(list.first.projectCode, 'AZ-F');
    });

    test('a stage with the PM sorts below live work, and delivered below that', () {
      final list = [
        wtask(code: 'AZ-X', stageId: 'x', projectStatus: 'delivered'),
        wtask(code: 'AZ-W', stageId: 'w', awaiting: true, dueInDays: -9),
        wtask(code: 'AZ-L', stageId: 'l', dueInDays: 60),
      ]..sort(WorkshopTask.compare);
      expect(list.map((t) => t.projectCode).toList(), ['AZ-L', 'AZ-W', 'AZ-X']);
    });

    test('two builds no longer interleave by their own stage order', () {
      // `ord` is a stage's position *inside its own build*, which is what this
      // list used to sort by: AZ-205's overdue third stage sorted below
      // AZ-101's not-yet-started first one.
      final list = [
        wtask(code: 'AZ-101', stageId: 'a1', dueInDays: 20),
        wtask(code: 'AZ-205', stageId: 'b3', dueInDays: -2),
      ]..sort(WorkshopTask.compare);
      expect(list.first.projectCode, 'AZ-205');
    });
  });

  group('ChecklistItem · the tick is a record now', () {
    ChecklistItem item(Map<String, dynamic> m) => ChecklistItem.fromMap({'id': 'c1', ...m});

    test('reads who ticked it and when', () {
      final c = item({
        'label': 'Weld the frame', 'done': true, 'done_at': '2026-10-14T09:30:00Z',
        'done_by_profile': {'full_name': 'Ravi Kumar'},
      });
      expect(c.doneByName, 'Ravi Kumar');
      expect(c.doneAt, isNotNull);
    });

    test('a check ticked before 0029 has no name, and does not invent one', () {
      // The old write stored nothing. Null is the honest answer and the row
      // says "ticked before this was recorded" rather than naming somebody.
      final c = item({'label': 'Weld', 'done': true});
      expect(c.doneByName, isNull);
      expect(c.doneAt, isNull);
    });

    test('a photo-required check carries its proof', () {
      final c = item({
        'label': 'Pressure-test the gas line', 'done': true, 'photo_required': true,
        'proof': {'file_url': 'https://example.test/gas.jpg'},
      });
      expect(c.photoRequired, isTrue);
      expect(c.proofUrl, 'https://example.test/gas.jpg');
      expect(c.proofMissing, isFalse);
    });

    test('ticked, photo-required, no photo is called out', () {
      // Only reachable on a row ticked before the rule was added — the RPC
      // refuses it now. Better said out loud than shown as a tick that quietly
      // means less than the one above it.
      final c = item({'label': 'Gas line', 'done': true, 'photo_required': true});
      expect(c.proofMissing, isTrue);
    });

    test('an un-ticked check is never "missing" proof', () {
      expect(item({'label': 'x', 'done': false, 'photo_required': true}).proofMissing, isFalse);
    });

    test('needsPhotoFirst is about the stage having a photo at all', () {
      final c = item({'label': 'x', 'done': false, 'photo_required': true});
      expect(c.needsPhotoFirst(0), isTrue);
      expect(c.needsPhotoFirst(3), isFalse);
      // An ordinary check never needs one.
      expect(item({'label': 'y', 'done': false}).needsPhotoFirst(0), isFalse);
    });

    test('survives a row where every new column is absent', () {
      // RLS and column-level selects mean a screen can legitimately get a row
      // without them; it must not throw.
      final c = ChecklistItem.fromMap({'id': 'c1', 'label': 'x', 'done': false});
      expect(c.photoRequired, isFalse);
      expect(c.proofUrl, isNull);
    });
  });

  group('StageBundle · the fitter\'s own cues', () {
    StageBundle bundle(List<ChecklistItem> checks) => StageBundle(
      checklist: checks, photos: const [], parts: const [], delays: const []);

    test('counts the checks still wanting a photo', () {
      final b = bundle([
        ChecklistItem(id: 'a', label: 'a', done: false, photoRequired: true),
        ChecklistItem(id: 'b', label: 'b', done: false, photoRequired: true),
        ChecklistItem(id: 'c', label: 'c', done: true, photoRequired: true),
        ChecklistItem(id: 'd', label: 'd', done: false),
      ]);
      expect(b.proofOutstanding, 2);
      expect(b.checksDone, 1);
    });

    test('a stage with no photo rules has nothing outstanding', () {
      expect(bundle([ChecklistItem(id: 'a', label: 'a', done: false)]).proofOutstanding, 0);
    });
  });

  group('ComponentRow · reserved is not installed', () {
    ComponentRow row({required String status, String? code}) => ComponentRow.fromMap({
      'id': 'c1', 'serial_number': 'SN-1', 'status': status,
      'item_catalog': {'name': 'LED Panel'},
      if (code != null) 'projects': {'code': code},
    });

    test('an in-stock part named for a build is reserved, not fitted', () {
      // 0026 made Store's intake an earmark: the part stays on the shelf while
      // naming the truck it was bought for. Workshop's Parts tab filtered on
      // the build alone, so these arrived looking exactly like fitted parts.
      final c = row(status: 'in_stock', code: 'AZ-101');
      expect(c.isReserved, isTrue);
      expect(c.isFitted, isFalse);
    });

    test('free stock is neither', () {
      final c = row(status: 'in_stock');
      expect(c.isReserved, isFalse);
      expect(c.isFitted, isFalse);
    });

    test('an installed part is fitted', () {
      final c = row(status: 'installed', code: 'AZ-101');
      expect(c.isFitted, isTrue);
      expect(c.isReserved, isFalse);
    });
  });

  group('ComponentRow warranty · one definition, app-wide', () {
    ComponentRow part({int? endInDays}) {
      final n = DateTime.now();
      return ComponentRow(id: 'c1', itemCatalogId: 'i1', name: 'Griddle', model: '',
        serial: 'SN-1', status: 'installed',
        warrantyEnd: endInDays == null ? null : DateTime(n.year, n.month, n.day + endInDays));
    }

    test('a warranty ending TODAY is still cover', () {
      // The third copy of the bug 0026 fixed in the other two: comparing a
      // date-only column against DateTime.now() is false all through the
      // warranty's own last day, so the part read "Expired" in Workshop's
      // Parts tab, Store's Parts list and the component record.
      expect(part(endInDays: 0).warrantyState, 'expiring');
      expect(part(endInDays: 0).warrantyActive, isTrue);
    });

    test('yesterday is expired', () {
      expect(part(endInDays: -1).warrantyState, 'expired');
      expect(part(endInDays: -1).warrantyActive, isFalse);
    });

    test('inside the expiring window it is still active cover', () {
      expect(part(endInDays: 10).warrantyState, 'expiring');
      expect(part(endInDays: 10).warrantyActive, isTrue);
    });

    test('well in the future is plainly active', () {
      expect(part(endInDays: 300).warrantyState, 'active');
    });

    test('nothing on record is not treated as covered', () {
      expect(part().warrantyState, 'none');
      expect(part().warrantyActive, isFalse);
    });

    test('it agrees with TruckComponent, which the truck record uses', () {
      for (final d in [-5, 0, 10, 300]) {
        final n = DateTime.now();
        final end = DateTime(n.year, n.month, n.day + d);
        expect(part(endInDays: d).warrantyState, warrantyStateFor(end),
          reason: 'offset $d disagrees with the shared helper');
      }
    });
  });

  group('StageMaterial · what this stage is built from', () {
    test('flattens the joined catalogue row', () {
      final m = StageMaterial.fromMap({
        'qty': 4, 'status': 'received', 'item_catalog': {'name': 'Steel sheet'},
      });
      expect(m.name, 'Steel sheet');
      expect(m.qty, 4);
      expect(m.isReceived, isTrue);
    });

    test('an unordered item is not on the shelf', () {
      expect(StageMaterial.fromMap({'qty': 1, 'status': 'pending'}).isReceived, isFalse);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Stages run in steps (0031). A build is a sequence and the app always half
// knew it — fn_decide_stage pulled the next stage in on approval, the
// scheduler laid the plan out backwards — but nothing stopped a person
// starting Fabrication while the design was still with the client. These pin
// down the reading the screens do, which has to match what fn_start_stage
// enforces or a screen will offer a Start the server refuses.
// ───────────────────────────────────────────────────────────────────────────

void stageStepTests() {
  group('WorkshopTask · a locked stage is not startable', () {
    test('canStart is false while an earlier step is open', () {
      // The whole point: the screen must not offer what the server refuses.
      expect(wtask(status: 'todo', locked: true).canStart, isFalse);
      expect(wtask(status: 'todo').canStart, isTrue);
    });

    test('rework is still not startable while locked', () {
      expect(wtask(status: 'rework', locked: true).canStart, isFalse);
    });

    test('it names what it is waiting for', () {
      expect(wtask(locked: true, blockedBy: 'Chassis').waitingLabel,
        'Waiting on Chassis');
    });

    test('…and counts them when there is more than one', () {
      expect(wtask(locked: true, blockedByCount: 3).waitingLabel,
        'Waiting on 3 earlier stages');
    });

    test('a delivered truck is not "waiting" — it is finished with', () {
      final t = wtask(locked: true, projectStatus: 'delivered');
      expect(t.isWaitingOnEarlierWork, isFalse);
    });

    test('a locked stage sorts below everything actionable', () {
      final list = [
        wtask(code: 'AZ-LOCK', stageId: 'l', locked: true, dueInDays: -40),
        wtask(code: 'AZ-LATE', stageId: 'd', dueInDays: -1),
        wtask(code: 'AZ-SOON', stageId: 's', dueInDays: 30),
      ]..sort(WorkshopTask.compare);
      // Even forty days "late", locked work is not what this person does today.
      expect(list.map((t) => t.projectCode).toList(),
        ['AZ-LATE', 'AZ-SOON', 'AZ-LOCK']);
    });

    test('copyWith carries the gate', () {
      final t = wtask(locked: true, blockedBy: 'Chassis')
          .copyWith(awaitingApproval: false);
      expect(t.isLocked, isTrue);
      expect(t.blockedBy, 'Chassis');
    });
  });

  group('lockedStageIds · the same rule, read off a whole build', () {
    test('everything after the first open step is locked', () {
      final stages = [
        stageTick('Design', ord: 1, status: 'in_progress'),
        stageTick('Chassis', ord: 2),
        stageTick('Paint', ord: 3),
      ];
      expect(lockedStageIds(stages), {'st-Chassis-2', 'st-Paint-3'});
    });

    test('stages sharing a step are open together', () {
      // The case strict ordering got wrong: the countertop and the electricals
      // both wait for the chassis, then run alongside each other.
      final stages = [
        stageTick('Chassis', ord: 1, step: 1, status: 'done'),
        stageTick('Countertop', ord: 2, step: 2),
        stageTick('Electricals', ord: 3, step: 2),
        stageTick('Paint', ord: 4, step: 3),
      ];
      expect(lockedStageIds(stages), {'st-Paint-4'});
    });

    test('half a step does not open the next one', () {
      final stages = [
        stageTick('Countertop', ord: 1, step: 1, status: 'done'),
        stageTick('Electricals', ord: 2, step: 1, status: 'in_progress'),
        stageTick('Paint', ord: 3, step: 2),
      ];
      expect(lockedStageIds(stages), {'st-Paint-3'});
    });

    test('a finished build locks nothing', () {
      final stages = [
        stageTick('Design', ord: 1, status: 'done'),
        stageTick('Chassis', ord: 2, status: 'done'),
      ];
      expect(lockedStageIds(stages), isEmpty);
    });

    test('a done stage in a later step is not reported as locked', () {
      // It cannot be "waiting" — it is finished, however it got there.
      final stages = [
        stageTick('Design', ord: 1, status: 'in_progress'),
        stageTick('Chassis', ord: 2, status: 'done'),
      ];
      expect(lockedStageIds(stages), isEmpty);
    });

    test('a build with no steps set behaves as one stage per step', () {
      // Everything created before 0031 was backfilled step = ord, and
      // StageTick falls back to ord, so old builds run exactly as they did.
      final stages = [
        StageTick(id: 'a', name: 'A', status: 'in_progress', ord: 1, step: 1),
        StageTick(id: 'b', name: 'B', status: 'todo', ord: 2, step: 2),
      ];
      expect(lockedStageIds(stages), {'b'});
    });
  });

  group('blockerFor · what to put in front of the person', () {
    final stages = [
      stageTick('Design', ord: 1, step: 1, status: 'done'),
      stageTick('Chassis', ord: 2, step: 2, status: 'in_progress'),
      stageTick('Wiring', ord: 3, step: 2),
      stageTick('Paint', ord: 4, step: 3),
    ];

    test('names the earliest unfinished stage before it', () {
      expect(blockerFor(stages[3], stages)?.name, 'Chassis');
    });

    test('a stage in the open step has no blocker', () {
      expect(blockerFor(stages[2], stages), isNull);
    });

    test('the first step never has one', () {
      expect(blockerFor(stages[0], stages), isNull);
    });
  });

  group('designTodos · a locked design stage', () {
    test('is listed, last, saying what it waits for', () {
      final r = designTodos(
        tasks: [wtask(code: 'AZ-D', locked: true, blockedBy: 'Teardown')],
        designs: const []);
      expect(r.todos.single.kind, DesignTodoKind.waitingOnEarlierWork);
      expect(r.todos.single.detail, contains('Teardown'));
      expect(r.todos.single.action, 'Open stage');
    });

    test('it sorts below work that can actually be done', () {
      final r = designTodos(tasks: [
        wtask(code: 'AZ-L', stageId: 'l', locked: true),
        wtask(code: 'AZ-R', stageId: 'r', status: 'rework'),
      ], designs: const []);
      expect(r.todos.first.kind, DesignTodoKind.rework);
      expect(r.todos.last.kind, DesignTodoKind.waitingOnEarlierWork);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Part 1: an admin can hand a build over with no plan, and the PM builds it.
// ───────────────────────────────────────────────────────────────────────────

void pmSetupTests() {
  group('stepsFor · "runs alongside the one above"', () {
    StageDraft d(String n, {bool with_ = false}) =>
        StageDraft(n, 1, runsWithPrevious: with_);

    test('plain stages each get their own step', () {
      expect(stepsFor([d('Design'), d('Chassis'), d('Paint')]), [1, 2, 3]);
    });

    test('a stage marked "alongside" shares the step above it', () {
      // The case the owner described: the countertop and the electricals both
      // wait for the chassis, then run together.
      expect(stepsFor([
        d('Chassis'), d('Countertop'), d('Electricals', with_: true), d('Paint'),
      ]), [1, 2, 2, 3]);
    });

    test('three in a row all share one step', () {
      expect(stepsFor([
        d('Chassis'), d('A'), d('B', with_: true), d('C', with_: true), d('Paint'),
      ]), [1, 2, 2, 2, 3]);
    });

    test('the first stage always starts step 1, whatever its flag says', () {
      // Nothing precedes it to run alongside, so the flag is meaningless there
      // — and the UI does not offer it. This is the belt to that braces.
      expect(stepsFor([d('Design', with_: true), d('Chassis')]), [1, 2]);
    });

    test('an empty template produces no steps', () {
      expect(stepsFor([]), isEmpty);
    });
  });

  group('BuildSchedule.needsPlan', () {
    BuildSchedule sched(List<StageTick> stages, {String status = 'on_track'}) =>
        BuildSchedule(
          project: Project(id: 'p', code: 'AZ-1', name: 'T', status: status, progressPct: 0),
          stages: stages);

    test('a build with no stages needs a plan', () {
      expect(sched(const []).needsPlan, isTrue);
      expect(sched(const []).blockedLabel, 'Needs a plan');
    });

    test('…and is never reported as clear', () {
      // It has no overdue, no rework, nothing unassigned — every count is zero,
      // which is exactly why it used to read as "all clear".
      expect(sched(const []).isClear, isFalse);
    });

    test('a build with stages does not', () {
      expect(sched([stageTick('Design', ord: 1)]).needsPlan, isFalse);
    });

    test('a delivered build with no stages is history, not a gap', () {
      expect(sched(const [], status: 'delivered').needsPlan, isFalse);
      expect(sched(const [], status: 'delivered').blockedLabel, 'Delivered');
    });

    test('it outranks every live build in the PM\'s list', () {
      final noPlan = sched(const []);
      final waitingOnPm = BuildSchedule(
        project: Project(id: 'q', code: 'AZ-2', name: 'U', status: 'on_track', progressPct: 0),
        stages: [stageTick('Design', ord: 1, status: 'in_progress', awaiting: true)]);
      final list = [waitingOnPm, noPlan]..sort(BuildSchedule.compare);
      expect(list.first.project.code, 'AZ-1');
    });

    test('lockedIds reads the build it already holds', () {
      final b = sched([
        stageTick('Design', ord: 1, status: 'in_progress'),
        stageTick('Chassis', ord: 2),
      ]);
      expect(b.lockedIds, {'st-Chassis-2'});
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// 0032: a designation beside the role, and which admin brought a build in.
// ───────────────────────────────────────────────────────────────────────────

void designationTests() {
  group('Member · designation and supervisor', () {
    Member m(Map<String, dynamic> extra) => Member.fromMap({
      'id': 'u1', 'full_name': 'Ravi', 'email': 'r@az.co',
      'role': 'workshop', 'status': 'active', ...extra,
    });

    test('a designation is read and shown under the name', () {
      expect(m({'designation': 'Senior fitter'}).subtitle, 'Senior fitter');
    });

    test('blank or whitespace is the same as none', () {
      // The field is free text, so an admin who clears it leaves '' behind.
      expect(m({'designation': '   '}).designation, isNull);
      expect(m({'designation': ''}).designation, isNull);
    });

    test('a supervisor is called one even with no designation typed', () {
      expect(m({'is_supervisor': true}).subtitle, 'Workshop supervisor');
    });

    test('a typed designation wins over the generic label', () {
      expect(m({'designation': 'Night shift lead', 'is_supervisor': true}).subtitle,
        'Night shift lead');
    });

    test('otherwise it falls back to the sub-team', () {
      expect(m({'sub_teams': {'name': 'Welding'}}).subtitle, 'Welding');
    });

    test('and to nothing at all', () {
      expect(m(const {}).subtitle, isNull);
    });

    test('a row without the new columns still reads', () {
      // RLS and column-level selects mean a screen can legitimately get a row
      // without them; it must not throw.
      final x = Member.fromMap({
        'id': 'u1', 'full_name': 'R', 'email': 'r@az.co',
        'role': 'admin', 'status': 'active',
      });
      expect(x.designation, isNull);
      expect(x.isSupervisor, isFalse);
    });
  });

  group('Project · which admin brought it in', () {
    Project p(Map<String, dynamic> extra) => Project.fromMap({
      'id': 'p1', 'code': 'AZ-1', 'name': 'T', 'status': 'on_track',
      'progress_pct': 0, ...extra,
    });

    test('reads the creator and their name', () {
      final x = p({
        'created_by': 'a1',
        'created_by_profile': {'full_name': 'Asha'},
      });
      expect(x.createdById, 'a1');
      expect(x.createdByName, 'Asha');
    });

    test('a build created before this was recorded has neither', () {
      expect(p(const {}).createdById, isNull);
      expect(p(const {}).createdByName, isNull);
    });

    test('an offboarded admin leaves the id but no name', () {
      // projects.created_by is ON DELETE SET NULL, so in practice both go —
      // but a column-level select can legitimately return one without the
      // other, and the filter shows the id's group either way.
      expect(p({'created_by': 'a1'}).createdById, 'a1');
      expect(p({'created_by': 'a1'}).createdByName, isNull);
    });

    test('a blank name is treated as no name', () {
      final x = p({'created_by': 'a1', 'created_by_profile': {'full_name': '  '}});
      expect(x.createdByName, isNull);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// 0033: a workshop stage breaks into sub-stages. Same step rule as 0031, one
// level down — and the supervisor, not the template, decides what runs
// together on this truck.
// ───────────────────────────────────────────────────────────────────────────

StageTask subTask(String title, {
  required int ord, int? step, String status = 'todo', String? who,
}) => StageTask(
  id: 'st-$title', stageId: 'stage-1', title: title, status: status,
  ord: ord, step: step ?? ord,
  assigneeId: who, assigneeName: who == null ? null : 'Worker $who');

void subStageTests() {
  group('StageTask.fromMap', () {
    test('reads the people on both sides by their named foreign keys', () {
      final t = StageTask.fromMap({
        'id': 't1', 'stage_id': 's1', 'title': 'Flooring', 'ord': 3,
        'step': 2, 'status': 'done', 'done_at': '2026-10-16T09:00:00Z',
        'assignee_id': 'u1',
        'assignee': {'full_name': 'Ravi'},
        'done_by_profile': {'full_name': 'Ravi'},
      });
      expect(t.assigneeName, 'Ravi');
      expect(t.doneByName, 'Ravi');
      expect(t.doneAt, isNotNull);
      expect(t.isDone, isTrue);
    });

    test('a null step means its own step, which is ord', () {
      // Matches the column: no default, and every reader coalesces to ord.
      final t = StageTask.fromMap({
        'id': 't1', 'stage_id': 's1', 'title': 'Plumbing', 'ord': 5,
      });
      expect(t.step, 5);
    });

    test('an unassigned item says so rather than inventing a name', () {
      final t = StageTask.fromMap({'id': 't1', 'stage_id': 's1', 'title': 'X', 'ord': 1});
      expect(t.isUnassigned, isTrue);
      expect(t.assigneeName, isNull);
    });

    test('a blank note is no note', () {
      final t = StageTask.fromMap({
        'id': 't1', 'stage_id': 's1', 'title': 'X', 'ord': 1, 'note': '   '});
      expect(t.note, isNull);
    });
  });

  group('lockedTaskIds · the step rule, one level down', () {
    test('everything after the first open sub-step waits', () {
      final tasks = [
        subTask('Framework', ord: 1, status: 'in_progress'),
        subTask('Cladding', ord: 2),
        subTask('Paint', ord: 3),
      ];
      expect(lockedTaskIds(tasks), {'st-Cladding', 'st-Paint'});
    });

    test('items sharing a step are open together', () {
      // The owner's own example: after the cladding, the paint and the
      // branding run at the same time.
      final tasks = [
        subTask('Cladding', ord: 1, step: 1, status: 'done'),
        subTask('Paint', ord: 2, step: 2),
        subTask('Branding', ord: 3, step: 2),
        subTask('Plumbing', ord: 4, step: 3),
      ];
      expect(lockedTaskIds(tasks), {'st-Plumbing'});
    });

    test('half a step does not open the next one', () {
      final tasks = [
        subTask('Paint', ord: 1, step: 1, status: 'done'),
        subTask('Branding', ord: 2, step: 1, status: 'in_progress'),
        subTask('Plumbing', ord: 3, step: 2),
      ];
      expect(lockedTaskIds(tasks), {'st-Plumbing'});
    });

    test('a finished breakdown locks nothing', () {
      final tasks = [
        subTask('A', ord: 1, status: 'done'),
        subTask('B', ord: 2, status: 'done'),
      ];
      expect(lockedTaskIds(tasks), isEmpty);
    });

    test('an empty breakdown locks nothing', () {
      expect(lockedTaskIds(const []), isEmpty);
    });
  });

  group('taskBlockerFor · what to name on the card', () {
    final tasks = [
      subTask('Framework', ord: 1, step: 1, status: 'done'),
      subTask('Cladding', ord: 2, step: 2, status: 'in_progress'),
      subTask('Drilling', ord: 3, step: 2),
      subTask('Paint', ord: 4, step: 3),
    ];

    test('names the earliest unfinished item before it', () {
      expect(taskBlockerFor(tasks[3], tasks)?.title, 'Cladding');
    });

    test('an item in the open step has no blocker', () {
      expect(taskBlockerFor(tasks[2], tasks), isNull);
    });
  });

  group('MyStageTask · the worker\'s own list', () {
    MyStageTask item(StageTask t, {bool locked = false}) => MyStageTask(
      task: t, projectCode: 'AZ-1', projectName: 'Truck', stageName: 'Workshop',
      isLocked: locked);

    test('started work leads, then what can be picked up, then what waits', () {
      final list = [
        item(subTask('C', ord: 3), locked: true),
        item(subTask('A', ord: 1, status: 'in_progress')),
        item(subTask('B', ord: 2)),
      ]..sort(MyStageTask.compare);
      expect(list.map((i) => i.task.title).toList(), ['A', 'B', 'C']);
    });

    test('finished work sorts last of all', () {
      final list = [
        item(subTask('Done', ord: 1, status: 'done')),
        item(subTask('Waiting', ord: 2), locked: true),
      ]..sort(MyStageTask.compare);
      expect(list.first.task.title, 'Waiting');
    });
  });
}

void workflowBuilderTests() {
  StageDraft d(String n, int days, {bool with_ = false}) =>
      StageDraft(n, days, runsWithPrevious: with_);

  group('estimatedDaysFor · a step is as long as its longest stage', () {
    test('stages one after another add up', () {
      expect(estimatedDaysFor([d('Design', 3), d('Chassis', 5), d('Paint', 2)]), 10);
    });

    test('stages running alongside cost only the longer of them', () {
      // Countertop (4) and electricals (6) together: 6, not 10.
      expect(estimatedDaysFor([
        d('Chassis', 5), d('Countertop', 4), d('Electricals', 6, with_: true), d('Paint', 2),
      ]), 5 + 6 + 2);
    });

    test('grouping two stages shortens the estimate — what the builder shows', () {
      final apart = [d('Paint', 3), d('Branding', 2)];
      final together = [d('Paint', 3), d('Branding', 2, with_: true)];
      expect(estimatedDaysFor(apart), 5);
      expect(estimatedDaysFor(together), 3);
    });

    test('a stage of zero days still takes a day', () {
      expect(estimatedDaysFor([d('Handover', 0)]), 1);
    });

    test('no stages, no days', () {
      expect(estimatedDaysFor([]), 0);
    });
  });

  group('stepCountFor', () {
    test('counts the waits, not the stages', () {
      expect(stepCountFor([
        d('Chassis', 1), d('Countertop', 1), d('Electricals', 1, with_: true),
      ]), 2);
    });

    test('an empty plan has no steps', () {
      expect(stepCountFor([]), 0);
    });
  });

  group('standardWorkshopFlow · the workshop as the owner described it', () {
    test('framework first, dispatch last, fifteen jobs', () {
      expect(standardWorkshopFlow.length, 15);
      expect(standardWorkshopFlow.first.$1, 'Structural framework');
      expect(standardWorkshopFlow.last.$1, 'Dispatch');
    });

    test('branding runs alongside paint, and nothing else runs alongside', () {
      final together = [for (final (t, w) in standardWorkshopFlow) if (w) t];
      expect(together, ['Branding signage / vinyl']);
      final i = standardWorkshopFlow.indexWhere((e) => e.$1 == 'Branding signage / vinyl');
      expect(standardWorkshopFlow[i - 1].$1, 'Surface preparation and paint');
    });

    test('so fifteen jobs make fourteen steps', () {
      final steps = stepsFromFlags([for (final (_, w) in standardWorkshopFlow) w]);
      expect(steps.last, 14);
    });
  });

  group('WorkflowSummary.fromMap · the list card', () {
    Map<String, dynamic> stage(int ord, int? step, int days) =>
        {'id': 's$ord', 'ord': ord, 'step': step, 'default_duration_days': days};

    test('reads the shape back from the stored steps, in ord order', () {
      final w = WorkflowSummary.fromMap({
        'id': 'w1', 'name': 'Food truck', 'truck_type': 'Food truck',
        'created_at': '2026-10-01T09:00:00Z',
        'creator': {'full_name': 'Priya Nair'},
        // Out of order on purpose: the embed does not promise an order.
        'template_stages': [stage(3, 2, 3), stage(1, 1, 2), stage(4, 3, 1), stage(2, 2, 5)],
      });
      expect(w.stageCount, 4);
      expect(w.stepCount, 3);
      expect(w.estimatedDays, 2 + 5 + 1);
      expect(w.createdByName, 'Priya Nair');
      expect(w.createdAt, DateTime.utc(2026, 10, 1, 9));
    });

    test('a workflow saved before steps existed runs one stage at a time', () {
      final w = WorkflowSummary.fromMap({
        'id': 'w2', 'name': 'Old',
        'template_stages': [stage(1, null, 2), stage(2, null, 3)],
      });
      expect(w.stepCount, 2);
      expect(w.estimatedDays, 5);
    });

    test('blank truck type and creator read as not set', () {
      final w = WorkflowSummary.fromMap({
        'id': 'w3', 'name': 'Bare', 'truck_type': '  ',
        'creator': {'full_name': ' '},
      });
      expect(w.truckType, isNull);
      expect(w.createdByName, isNull);
      expect(w.stageCount, 0);
      expect(w.estimatedDays, 0);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Phase D simulator walk: what the PM is told an approval did, and what the
// approvals card shows as a design stage's evidence.
// ───────────────────────────────────────────────────────────────────────────

void phaseDWalkTests() {
  Stage st(String name, {required int ord, int? step, String status = 'todo'}) =>
      Stage(id: 'id-$name', name: name, status: status, ord: ord, step: step ?? ord);

  group('approvalOutcome · read off the build after fn_decide_stage', () {
    test('a stage on its own in its step opens the next one', () {
      final stages = [
        st('Design', ord: 1, status: 'done'),
        st('Chassis', ord: 2, status: 'in_progress'),
        st('Paint', ord: 3),
      ];
      expect(approvalOutcome(stages, 'id-Design'), 'Chassis started');
    });

    test('a step still half open starts nothing — the bug the toast had', () {
      // It said "next stage started" here, and Paint had not started.
      final stages = [
        st('Chassis', ord: 1, status: 'done'),
        st('Countertop', ord: 2, step: 2, status: 'done'),
        st('Electricals', ord: 3, step: 2, status: 'in_progress'),
        st('Paint', ord: 4, step: 3),
      ];
      expect(approvalOutcome(stages, 'id-Countertop'),
        'Electricals is still open in this step');
    });

    test('several stages still open in the step are counted', () {
      final stages = [
        st('A', ord: 1, step: 1, status: 'done'),
        st('B', ord: 2, step: 1, status: 'in_progress'),
        st('C', ord: 3, step: 1, status: 'rework'),
      ];
      expect(approvalOutcome(stages, 'id-A'), '2 more stages are still open in this step');
    });

    test('a step of several stages opening together is counted', () {
      final stages = [
        st('Chassis', ord: 1, status: 'done'),
        st('Countertop', ord: 2, step: 2, status: 'in_progress'),
        st('Electricals', ord: 3, step: 2, status: 'in_progress'),
      ];
      expect(approvalOutcome(stages, 'id-Chassis'), '2 stages started');
    });

    test('the last stage says the build is done, not that something started', () {
      final stages = [
        st('Design', ord: 1, status: 'done'),
        st('Handover', ord: 2, status: 'done'),
      ];
      expect(approvalOutcome(stages, 'id-Handover'), 'every stage on this build is done');
    });

    test('nothing in progress after it: says nothing rather than guess', () {
      // fn_decide_stage only opens stages still on `todo`; one sent back for
      // rework stays where it is, and the toast must not claim it started.
      final stages = [
        st('Design', ord: 1, status: 'done'),
        st('Chassis', ord: 2, status: 'rework'),
      ];
      expect(approvalOutcome(stages, 'id-Design'), isNull);
    });

    test('a stage that is not on the build reads as nothing to add', () {
      expect(approvalOutcome([st('Design', ord: 1, status: 'done')], 'nope'), isNull);
    });
  });

  group('approvedDesignFor · the same rule as fn_submit_stage (0028)', () {
    DesignRow d(String id, String status, {String? stage}) =>
        DesignRow(id: id, type: 'layout', status: status, stageId: stage);

    test('a design linked to the stage is the one that counts', () {
      final list = [d('loose', 'approved'), d('mine', 'approved', stage: 's1')];
      expect(approvedDesignFor('s1', list)?.id, 'mine');
    });

    test('linked designs that are not approved are not rescued by a loose one', () {
      // If the stage has designs of its own, one of *them* has to be approved.
      final list = [d('loose', 'approved'), d('mine', 'pending_approval', stage: 's1')];
      expect(approvedDesignFor('s1', list), isNull);
    });

    test('with nothing linked, any approved design on the build counts', () {
      final list = [d('draft', 'draft'), d('old', 'approved')];
      expect(approvedDesignFor('s1', list)?.id, 'old');
    });

    test('another stage\'s design counts only while this one has none of its own', () {
      // Nothing linked to s1: the build-wide rule, as on the server.
      expect(approvedDesignFor('s1', [d('other', 'approved', stage: 's2')])?.id, 'other');
      // s1 has its own design, still with changes requested: that is the one.
      expect(approvedDesignFor('s1', [
        d('other', 'approved', stage: 's2'),
        d('mine', 'revision', stage: 's1'),
      ]), isNull);
    });

    test('reads stage_id from the row', () {
      expect(DesignRow.fromMap({'id': 'x', 'stage_id': 's1'}).stageId, 's1');
    });
  });

  group('MyProfile · designation and supervisor', () {
    MyProfile me(Map<String, dynamic> extra) => MyProfile.fromMap({
      'id': 'u1', 'full_name': 'Vikas', 'email': 'v@az.co',
      'role': 'workshop', 'status': 'active', ...extra,
    });

    test('reads both', () {
      final x = me({'designation': 'Floor lead', 'is_supervisor': true});
      expect(x.designation, 'Floor lead');
      expect(x.isSupervisor, isTrue);
    });

    test('blank designation is none, and a missing flag is false', () {
      final x = me({'designation': '  '});
      expect(x.designation, isNull);
      expect(x.isSupervisor, isFalse);
    });
  });
}
