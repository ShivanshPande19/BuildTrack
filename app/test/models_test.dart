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
}
