import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../admin/build_screen.dart';
import '../client/truck_detail.dart';
import '../procurement/po_detail.dart';
import '../service/ticket_detail.dart';
import '../workshop/task_detail.dart';

/// Open whatever a notification is about.
///
/// Every `fn_notify` call in the migrations already records an `entity_type` and
/// `entity_id` — the build, the stage, the purchase order, the ticket. The feed
/// simply never used them, so being told "AZ-118 · Electrical work needs
/// approval" left you to go and find it by hand. This resolves the entity to the
/// screen **that role** is allowed to see:
///
///   • a PM or admin goes to the build screen (or the PO detail);
///   • a workshop / design / service member goes to their own stage, if it is
///     still theirs;
///   • a client goes to their truck;
///   • service goes to the ticket.
///
/// When a role has no screen for that entity — procurement has no build screen,
/// a stage reassigned away is no longer yours — it returns false and the caller
/// leaves the row alone rather than showing a dead end.
Future<bool> openNotificationTarget(
  BuildContext context,
  WidgetRef ref,
  AppNotification n,
) async {
  final id = n.entityId;
  if (id == null) return false;
  final role = await ref.read(myRoleProvider.future);
  if (!context.mounted) return false;

  Future<void> push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  switch (n.entityType) {
    case 'purchase_order':
      // Everyone in the approval chain can read a PO; the shop floor cannot.
      if (role == 'admin' || role == 'pm' || role == 'procurement' || role == 'store') {
        await push(PoDetailScreen(poId: id));
        return true;
      }
      return false;

    case 'ticket':
      if (role == 'admin' || role == 'service') {
        await push(TicketDetailScreen(ticketId: id));
        return true;
      }
      return false;

    case 'project':
      return _openProject(context, ref, role, id, push);

    case 'stage':
      // Resolve the stage to its build first: a PM wants the build, the
      // assignee wants their own task screen.
      if (role == 'admin' || role == 'pm') {
        final projectId = await ref.read(projectsRepoProvider).projectIdForStage(id);
        if (projectId == null || !context.mounted) return false;
        return _openProject(context, ref, role, projectId, push);
      }
      final tasks = await ref.read(workshopRepoProvider).myTasks();
      if (!context.mounted) return false;
      for (final t in tasks) {
        if (t.stageId == id) {
          // A designer's stage finishes on the client's approval (0028), so it
          // opens with the same "waiting on the client" gate as the Studio's.
          await push(TaskDetailScreen(task: t, showInstallPart: role == 'workshop',
            designGate: role == 'design'));
          return true;
        }
      }
      // Assigned to someone else now, or already approved.
      return false;

    default:
      return false;
  }
}

Future<bool> _openProject(
  BuildContext context,
  WidgetRef ref,
  String? role,
  String projectId,
  Future<void> Function(Widget) push,
) async {
  if (role == 'client') {
    // The client's screen needs the Project itself, and they can only see their
    // own — so take it from the list they already have.
    final mine = await ref.read(myTrucksProvider.future);
    if (!context.mounted) return false;
    for (final p in mine) {
      if (p.id == projectId) {
        await push(ClientTruckDetail(project: p));
        return true;
      }
    }
    return false;
  }
  if (role == 'admin') {
    // Oversight: the PM can be assigned or changed, nothing else is editable.
    await push(BuildScreen(projectId: projectId, canAssignPm: true));
    return true;
  }
  if (role == 'pm') {
    await push(BuildScreen(projectId: projectId,
      materialsEditable: true, canAssign: true, canEditTimeline: true));
    return true;
  }
  return false;
}

/// Shown when a notification has nowhere to go for this role, so a tap is still
/// answered rather than silently ignored.
void sayNoTarget(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      backgroundColor: BT.ink,
      content: Text('Nothing to open for this one — it is just an update.')));
