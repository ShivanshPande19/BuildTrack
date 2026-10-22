import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';

/// Settings → **Roles & permissions**: who is allowed to do what, and where in
/// the app they do it.
///
/// This is reference, not configuration — the permission matrix lives in
/// Postgres (row-level security + guard triggers), which is the point: it is
/// the same for every client and cannot be talked around in the UI. So the
/// screen states the rules rather than offering switches that would be a lie.
/// Your own role is pulled to the top and marked, because "what am I allowed to
/// do here" is the question people actually open this with.
class RolesReferenceScreen extends ConsumerWidget {
  const RolesReferenceScreen({super.key});

  static const _roles = <_RoleSpec>[
    _RoleSpec('admin', 'Owner · Admin', Icons.workspace_premium_rounded,
      'Runs the company side of every build.',
      can: [
        'Onboard a build: pick the workflow template, set the delivery date, create the client\'s login',
        'Assign or change a build\'s project manager',
        'Add and remove members, set their role and sub-team',
        'Give purchase orders final approval, and override an approval\'s priority',
        'See every build, the live Command Center and the fleet\'s health',
        'Edit the company details printed on every purchase order',
      ],
      cannot: [
        'Assign stages or edit a build\'s materials — a build opens read-only, as oversight',
      ]),
    _RoleSpec('pm', 'Project Manager', Icons.assignment_rounded,
      'Owns the plan for the builds assigned to them.',
      can: [
        'Set up the plan of a build handed over without one: choose its workflow, or make a new one',
        'Assign each stage to the right discipline, with start and due dates',
        'Plan materials: quantities and needed-by dates, which set each order-by date',
        'Approve or send back submitted work, on the photos, checklist and parts as evidence',
        'Sign purchase orders raised on their own builds',
        'Log a delay with its reason, and push the delivery date (which re-plans the build)',
        'Mark the truck delivered and add the client\'s documents',
      ],
      cannot: [
        'Create a build, or change its code or client',
        'Switch a build to another workflow once it has a plan',
        'Touch a build that is not theirs — enforced in the database, not just hidden',
        'Take a build from another PM',
      ]),
    _RoleSpec('procurement', 'Procurement', Icons.shopping_cart_rounded,
      'Turns material needs into orders that arrive on time.',
      can: [
        'Raise a purchase order with rates, GST and HSN, and send it for signature',
        'Fix and resubmit a purchase order that was sent back',
        'Mark an order dispatched, then receive it — which moves the stock',
        'Add vendors with their GSTIN and state',
        'Print or share the GST purchase-order document',
      ],
      cannot: [
        'Approve its own purchase order — the PM signs, then the owner',
        'Dispatch or receive anything before it is fully approved',
      ]),
    _RoleSpec('store', 'Store / Inventory', Icons.inventory_2_rounded,
      'Keeps the part record that makes a truck traceable.',
      can: [
        'Log every part at intake: serial, vendor, warranty dates and a photo of the bill',
        'Keep stock, and ask procurement to reorder a general essential',
        'Look a part up by serial, model or truck, and open its record',
        'Run a recall check on a part model and notify every affected build',
      ],
      cannot: [
        'Raise a purchase order, or approve one',
      ]),
    _RoleSpec('workshop', 'Workshop', Icons.handyman_rounded,
      'Builds the truck and records what went into it.',
      can: [
        'Start an assigned stage, tick its checklist, upload site photos',
        'Scan a part and install it into the stage being worked',
        'Report a hold-up on its own stage, with the reason and days lost',
        'Submit a finished stage for the project manager\'s approval',
      ],
      cannot: [
        'Mark its own stage done — a stage moves only through Start, Submit and the PM\'s approval',
        'Change its own assignment or the schedule',
        'Change what a checklist says, or whether a check needs a photo',
        'Change anything on a stage once the PM has approved it',
      ]),
    _RoleSpec('design', 'Design', Icons.palette_rounded,
      'Gets the truck\'s design approved before it is built.',
      can: [
        'Create a design and upload a 3D model (.glb) with a 2D preview',
        'Submit it for the client\'s approval, and the client is told',
        'Upload a revised version when changes are requested, with a version history',
        'Start and submit a design stage it has been assigned',
      ],
      cannot: [
        'Approve its own design — only the client decides',
      ]),
    _RoleSpec('service', 'Service & Support', Icons.build_circle_rounded,
      'Looks after the truck once it is on the road.',
      can: [
        'Work the ticket queue by SLA, assign a technician, book a visit',
        'Resolve a ticket as a warranty replacement, a repair or a remote fix',
        'Raise a ticket for a client who phoned it in',
        'Look up what is still under warranty, by serial, model or truck',
      ],
      cannot: [
        'Reopen a closed ticket on someone else\'s behalf without the client asking',
      ]),
    _RoleSpec('client', 'Client', Icons.emoji_people_rounded,
      'Sees their own truck, and only their own truck.',
      can: [
        'Watch progress, the current stage and the promised delivery date',
        'View the 3D design and approve it, or ask for changes with feedback',
        'See the stage photos as the build goes on, and their documents',
        'Raise a support request with a photo, and reopen it if it is still broken',
      ],
      cannot: [
        'See any other client\'s build, the team, costs or purchase orders',
      ]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myRoleProvider).valueOrNull;
    // Your own role first; the rest keep their chain-of-command order.
    final ordered = [
      ..._roles.where((r) => r.key == mine),
      ..._roles.where((r) => r.key != mine),
    ];

    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Row(children: [BackChip()]),
          const SizedBox(height: 14),
          Text('Roles & permissions', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('What each role can do, and what the app will refuse. These rules are '
                     'enforced in the database, so they hold even outside this app.',
            style: TextStyle(color: BT.mut, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 20),
          ...staggered([
            for (final r in ordered) Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RoleCard(spec: r, isMine: r.key == mine),
            ),
          ], stepMs: 40, maxMs: 320),
        ],
      )),
    );
  }
}

class _RoleSpec {
  final String key, title, blurb;
  final IconData icon;
  final List<String> can, cannot;
  const _RoleSpec(this.key, this.title, this.icon, this.blurb,
    {required this.can, required this.cannot});
}

/// One role, collapsed to its summary until tapped. Eight roles × ten rules is
/// a wall of text if it all opens at once; your own role starts expanded.
class _RoleCard extends StatefulWidget {
  final _RoleSpec spec;
  final bool isMine;
  const _RoleCard({required this.spec, required this.isMine});
  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  late bool _open = widget.isMine;

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final rc = roleColor(s.key);
    return AppCard(
      onTap: () => setState(() => _open = !_open),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: rc, borderRadius: BorderRadius.circular(12)),
            child: Icon(s.icon, size: 20, color: s.key == 'admin' ? BT.lime : BT.ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              if (widget.isMine) ...[
                const SizedBox(width: 8),
                const StatusPill('You', color: BT.lime),
              ],
            ]),
            const SizedBox(height: 2),
            Text(s.blurb, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          ])),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: _open ? 0.5 : 0, duration: Motion.fast, curve: Motion.curve,
            child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: BT.mut2)),
        ]),
        AnimatedSize(
          duration: Motion.base, curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: !_open ? const SizedBox(width: double.infinity)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 14),
                _bullets('CAN', s.can, BT.lime, Icons.check_rounded),
                if (s.cannot.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _bullets('CANNOT', s.cannot, BT.coral, Icons.block_rounded),
                ],
              ]),
        ),
      ]),
    );
  }

  Widget _bullets(String label, List<String> items, Color tint, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 10, letterSpacing: 1.1,
        fontWeight: FontWeight.w700, color: tint == BT.lime ? BT.mut : BT.coral)),
      const SizedBox(height: 7),
      for (final t in items) Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 17, height: 17, alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(5)),
            child: Icon(icon, size: 11, color: BT.ink)),
          const SizedBox(width: 9),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.35, color: BT.ink))),
        ]),
      ),
    ],
  );
}
