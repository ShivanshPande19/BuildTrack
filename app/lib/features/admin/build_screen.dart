import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import 'project_detail.dart';
import 'project_dossier.dart';
import 'project_requirements.dart';
import 'truck_record.dart';

/// The one canonical screen for a build.
///
/// It replaces the old Detail-vs-Dossier fork (a build opened to a *different*
/// screen depending on whether you came from the Projects tab or the Command
/// Center) with a single tabbed home: **Overview · Pipeline · Materials ·
/// Record**. Every entry point opens THIS, so "open a build" always lands in
/// the same place, and the four areas are tabs rather than scattered pushes.
///
/// The role flags are passed straight through to the Overview tab
/// (ProjectDetailScreen), which shows the mode banner and decides what is
/// editable — Admin opens it read-only (oversight, `canAssignPm`), the build's
/// PM opens it editable. Materials editability follows `materialsEditable`.
/// (See docs/UX_NAVIGATION_AUDIT.md.)
class BuildScreen extends StatefulWidget {
  final String projectId;
  final Project? initial; // instant header while the detail loads
  final bool materialsEditable, canAssign, canEditTimeline, canAssignPm;
  const BuildScreen({
    super.key,
    required this.projectId,
    this.initial,
    this.materialsEditable = false,
    this.canAssign = false,
    this.canEditTimeline = false,
    this.canAssignPm = false,
  });

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  int _tab = 0;
  static const _tabs = ['Overview', 'Pipeline', 'Materials', 'Record'];

  @override
  Widget build(BuildContext context) {
    final code = widget.initial?.code;
    final name = widget.initial?.name;
    final pages = <Widget>[
      ProjectDetailScreen(
        projectId: widget.projectId,
        initial: widget.initial,
        materialsEditable: widget.materialsEditable,
        canAssign: widget.canAssign,
        canEditTimeline: widget.canEditTimeline,
        canAssignPm: widget.canAssignPm,
        embedded: true,
      ),
      ProjectDossierScreen(projectId: widget.projectId, code: code, embedded: true),
      ProjectRequirementsScreen(
        projectId: widget.projectId, projectCode: code,
        editable: widget.materialsEditable, embedded: true),
      TruckRecordScreen(projectId: widget.projectId, code: code, name: name, embedded: true),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // header: back + code + name (once, for the whole build)
          FadeSlideIn(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(children: [
              const BackChip(),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((code ?? 'BUILD').toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(name ?? 'Build', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: display(21, w: FontWeight.w600)),
              ])),
            ]),
          )),
          // Tabs with a sliding indicator, in the app's chip language (no raw Material TabBar).
          FadeSlideIn(delay: Motion.stagger(1), child: SegmentTabs(
            labels: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i))),
          const SizedBox(height: 6),
          Expanded(child: TabSwitcher(index: _tab, child: pages[_tab])),
        ]),
      ),
    );
  }
}
