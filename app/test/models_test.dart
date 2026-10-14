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

StageTick tick(String name, {
  int ord = 1,
  String status = 'todo',
  String? who = 'Vikas',
  int? dueInDays,
  bool awaiting = false,
}) {
  final t = DateTime.now();
  return StageTick(
    id: 'st-$name-$ord', name: name, status: status, ord: ord,
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
        tick('Design', ord: 1, status: 'done'),
        tick('Fabrication', ord: 2, status: 'in_progress', awaiting: true, dueInDays: -3),
      ]);
      expect(b.awaitingCount, 1);
      // Overdue too, but the PM's own queue leads.
      expect(b.blockedLabel, startsWith('1 waiting on you'));
      expect(b.blockedLabel, contains('1 overdue'));
    });

    test('an unassigned stage is the PM\'s problem and says so', () {
      final b = build('AZ-2', [tick('Paint', who: null)]);
      expect(b.unassignedCount, 1);
      expect(b.blockedLabel, '1 unassigned');
    });

    test('a finished stage is never overdue or unassigned', () {
      final b = build('AZ-3', [tick('Design', status: 'done', who: null, dueInDays: -40)]);
      expect(b.overdueCount, 0);
      expect(b.unassignedCount, 0);
      expect(b.blockedLabel, 'All stages done');
    });

    test('nothing wrong reads as on track, not as an empty problem list', () {
      final b = build('AZ-4', [
        tick('Design', status: 'done'),
        tick('Fabrication', status: 'in_progress', dueInDays: 5),
      ]);
      expect(b.isClear, isTrue);
      expect(b.blockedLabel, 'On track');
    });

    test('rework counts as a blockage of its own', () {
      final b = build('AZ-5', [tick('Paint', status: 'rework', dueInDays: 2)]);
      expect(b.blockedLabel, '1 in rework');
    });
  });

  group('BuildSchedule · where the build is', () {
    test('current is what is being worked', () {
      final b = build('AZ-6', [
        tick('Design', ord: 1, status: 'done'),
        tick('Fabrication', ord: 2, status: 'in_progress'),
        tick('Paint', ord: 3),
      ]);
      expect(b.current!.name, 'Fabrication');
      expect(b.currentIndex, 2);
      expect(b.total, 3);
      expect(b.doneCount, 1);
    });

    test('with nothing started, current is the next thing up', () {
      final b = build('AZ-7', [tick('Design', ord: 1), tick('Fabrication', ord: 2)]);
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
      final waiting = build('AZ-W', [tick('A', status: 'in_progress', awaiting: true)], deliveryInDays: 60);
      final late = build('AZ-L', [tick('A', status: 'in_progress', dueInDays: -20)], deliveryInDays: 60);
      final sorted = [late, waiting]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-W');
    });

    test('more overdue stages outrank fewer', () {
      final two = build('AZ-2X', [
        tick('A', ord: 1, status: 'in_progress', dueInDays: -5),
        tick('B', ord: 2, dueInDays: -2),
      ]);
      final one = build('AZ-1X', [tick('A', status: 'in_progress', dueInDays: -5)]);
      final sorted = [one, two]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-2X');
    });

    test('all else equal, the nearest delivery comes first', () {
      final soon = build('AZ-SOON', [tick('A', status: 'in_progress', dueInDays: 5)], deliveryInDays: 7);
      final far = build('AZ-FAR', [tick('A', status: 'in_progress', dueInDays: 5)], deliveryInDays: 90);
      final sorted = [far, soon]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-SOON');
    });

    test('a delivered build sinks below every live one', () {
      final done = build('AZ-DONE', [tick('A', status: 'done')],
          deliveryInDays: -2, status: 'delivered');
      final healthy = build('AZ-OK', [tick('A', status: 'in_progress', dueInDays: 30)],
          deliveryInDays: 60);
      final sorted = [done, healthy]..sort(BuildSchedule.compare);
      expect(sorted.first.project.code, 'AZ-OK');
      expect(done.blockedLabel, 'Delivered');
    });

    test('a build with no delivery date does not jump the queue', () {
      final undated = build('AZ-NODATE', [tick('A', status: 'in_progress', dueInDays: 5)]);
      final dated = build('AZ-DATED', [tick('A', status: 'in_progress', dueInDays: 5)], deliveryInDays: 30);
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
