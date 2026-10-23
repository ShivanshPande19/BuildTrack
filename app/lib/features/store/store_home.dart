import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/role_header.dart';
import '../../shared/animations.dart';
import '../../shared/my_stages.dart';
import 'component_detail.dart';
import 'log_component.dart';

/// Store / Inventory shell — Inbox · Stock · Parts. Hero #2 lives here (traceability + recall).
class StoreHome extends ConsumerStatefulWidget {
  const StoreHome({super.key});
  @override
  ConsumerState<StoreHome> createState() => _StoreHomeState();
}

class _StoreHomeState extends ConsumerState<StoreHome> {
  int _tab = 0;
  static const _labels = ['Inbox', 'Stock', 'Parts'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: TabSwitcher(index: _tab, child: const <Widget>[
        _InboxTab(), _StockTab(), _PartsTab(),
      ][_tab])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.local_shipping_rounded, Icons.layers_rounded, Icons.inventory_2_rounded],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        actionIcon: Icons.qr_code_scanner_rounded,
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogComponent())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 110); // bottom clears the floating nav (extendBody)

Widget _storeHeader(BuildContext context, String title) =>
    FadeSlideIn(child: RoleHeader(role: 'store', eyebrow: 'Store · Inventory', title: title));

// ───────────────────────────────────────────────────────────── INBOX

/// What has arrived, and what is on its way.
///
/// This tab was called Inbox and showed low stock. Low stock is a standing
/// condition, not an arrival — and the Stock tab already shows it, with an
/// All/Low filter. So Inbox duplicated Stock and left out the one thing only
/// it could show: the goods actually coming in. (`PROJECT_LOG.md` §3 listed
/// the gap as "Store: no incoming-PO / GRN list".)
///
/// Now it is the Store's arrivals queue: what can be received right now, what
/// is still on the road, and — underneath, where it belongs — what is running
/// low. `fn_receive_po` accepts store as well as procurement, so receiving
/// here is the Store doing its own job, not borrowing someone else's screen.
class _InboxTab extends ConsumerWidget {
  const _InboxTab();

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(purchaseOrdersProvider);
    final stock = ref.watch(stockProvider);

    final all = orders.valueOrNull ?? const <PurchaseOrder>[];
    // Only an approved PO is a real order; one still in approval has not been
    // placed with anyone and cannot arrive.
    final approved = all.where((o) => o.isApproved).toList();
    final ready = approved.where((o) => o.status == 'dispatched' || o.status == 'partial').toList();
    final coming = approved.where((o) => o.status == 'ordered').toList();
    final low = (stock.valueOrNull ?? const <StockRow>[]).where((s) => s.low).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(purchaseOrdersProvider);
        ref.invalidate(componentsProvider);
        ref.invalidate(myTasksProvider);
        return ref.refresh(stockProvider.future);
      },
      child: ListView(padding: _pad, children: [
        _storeHeader(context, 'Inbox'),
        const SizedBox(height: 4),
        const FadeSlideIn(child: Text('What has arrived, and what is on its way',
          style: TextStyle(color: BT.mut, fontSize: 12.5))),
        const SizedBox(height: 16),

        // Numbers about arrivals, which is what this tab is for. The old row
        // counted "Tracked" (every component ever logged) and "Stock lines",
        // neither of which tells the Store what to do next.
        AppCard(padding: const EdgeInsets.all(16), child: Row(children: [
          _stat(orders.hasValue ? '${ready.length}' : '—', 'To receive',
            color: ready.isEmpty ? null : BT.lime),
          _divider(),
          _stat(orders.hasValue ? '${coming.length}' : '—', 'On the way'),
          _divider(),
          _stat(stock.hasValue ? '${low.length}' : '—', 'Low stock',
            color: low.isEmpty ? null : BT.coral),
        ])),

        orders.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 18),
            child: SkeletonList(count: 3)),
          error: (e, _) => Padding(padding: const EdgeInsets.only(top: 18),
            child: ErrorCard('Could not load incoming orders.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(purchaseOrdersProvider))),
          data: (_) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
            if (ready.isEmpty && coming.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 18), child: EmptyState(
                icon: Icons.local_shipping_outlined, tint: BT.sky,
                title: 'Nothing incoming',
                subtitle: 'Purchase orders on their way to you show up here, '
                          'ready to receive the moment they land.'))
            else ...[
              CappedSection(
                label: 'Ready to receive', sheetTitle: 'Ready to receive', max: 4,
                items: [for (final o in ready) _arrivalCard(context, ref, o)]),
              CappedSection(
                label: 'On the way', sheetTitle: 'On the way', max: 4,
                items: [for (final o in coming) _comingCard(o)]),
            ],
          ], stepMs: 40)),
        ),

        // Build stages a PM assigned to the Store — material intake, a stock
        // check. Without this a store member could reach one only from its
        // notification, and it sat on 'todo' the way Design's and Service's
        // stages used to (see MyStagesSection).
        const MyStagesSection(
          label: 'My build stages',
          tint: BT.sky,
          emptySubtitle: 'When a project manager assigns you a stage on a build, '
                         'you can start it and submit it here.',
        ),

        // Low stock is a standing condition, so it sits below the things that
        // actually arrived today — and each row now opens the reorder request
        // it has always been telling you to make.
        CappedSection(
          label: 'Running low', sheetTitle: 'Running low', max: 4,
          items: [for (final s in low) _lowCard(context, ref, s)],
          empty: stock.hasValue
            ? const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                title: 'Stock healthy', subtitle: 'Nothing is below its reorder threshold.')
            : const SkeletonList(count: 2),
        ),
      ]),
    );
  }

  /// A dispatched PO: the Store can take it in right here.
  Widget _arrivalCard(BuildContext context, WidgetRef ref, PurchaseOrder o) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.inventory_rounded, size: 20, color: BT.ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o.poNumber} · ${o.vendorName ?? 'Vendor'}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text([
                '${o.itemCount} item${o.itemCount == 1 ? '' : 's'}',
                if (o.projectCode != null) o.projectCode!,
              ].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          if (o.expectedDate != null)
            StatusPill(_fmt.format(o.expectedDate!), color: BT.sky),
        ]),
        const SizedBox(height: 13),
        AsyncPrimaryButton('Receive into stock', icon: Icons.check_rounded,
          onTap: () async {
            try {
              await ref.read(procurementRepoProvider).markReceived(o.id);
              Haptic.confirm();
              // Receiving moves stock and closes requirements, so everything
              // this screen and the next one read has just changed.
              ref.invalidate(purchaseOrdersProvider);
              ref.invalidate(stockProvider);
              ref.invalidate(componentsProvider);
              ref.invalidate(inStockProvider);
              // Workshop picks from a per-build view of the same stock.
              ref.invalidate(inStockForProvider);
              ref.invalidate(reservedForProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: BT.ink,
                  content: Text('${o.poNumber} received — bulk items are in stock. '
                                'Log serials with the scanner.')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: BT.coral, content: Text(friendlyError(e))));
              }
            }
          }),
      ]),
    ),
  );

  /// An approved PO the vendor has not shipped yet. Nothing for the Store to
  /// do but know it is coming, so there is no action on it.
  Widget _comingCard(PurchaseOrder o) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13),
            border: Border.all(color: BT.line)),
          child: const Icon(Icons.local_shipping_outlined, size: 20, color: BT.mut)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${o.poNumber} · ${o.vendorName ?? 'Vendor'}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text(o.deliveryDate == null
              ? 'Awaiting dispatch'
              : 'Promised ${_fmt.format(o.deliveryDate!)}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 12)),
        ])),
        const StatusPill('Ordered', color: BT.mut2),
      ]),
    ),
  );

  /// A low line. Tapping raises the reorder its own subtitle has always been
  /// asking for — it used to say "reorder" and do nothing.
  Widget _lowCard(BuildContext context, WidgetRef ref, StockRow s) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      onTap: () => showRequestStockSheet(context, ref, preselect: s),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.coral, borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFF5A2410))),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text('${s.quantity} ${s.unit} left · tap to request a reorder',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 11.5)),
        ])),
        const StatusPill('Low', color: BT.coral),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ]),
    ),
  );

  Widget _stat(String v, String label, {Color? color}) => Expanded(child: Column(children: [
    Text(v, style: display(24, w: FontWeight.w600, c: color)),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(color: BT.mut, fontSize: 11)),
  ]));
  Widget _divider() => Container(width: 1, height: 34, color: BT.line);
}

// ───────────────────────────────────────────────────────────── STOCK

class _StockTab extends ConsumerStatefulWidget {
  const _StockTab();
  @override
  ConsumerState<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends ConsumerState<_StockTab> {
  /// all · low · essentials · parts
  String _cut = 'all';
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final v = _search.text.trim().toLowerCase();
      if (v != _q) setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stock = ref.watch(stockProvider);
    final all = stock.valueOrNull ?? const <StockRow>[];

    final essentials = all.where((s) => s.isEssential).toList();
    final parts = all.where((s) => s.isProjectPart).toList();
    final low = all.where((s) => s.low).toList();

    final cuts = {'all': all, 'low': low, 'essentials': essentials, 'parts': parts};
    // A cut that empties out quietly falls back to All, so you are never left
    // staring at a blank list with a chip selected that explains nothing.
    if (stock.hasValue && (cuts[_cut] ?? const <StockRow>[]).isEmpty) _cut = 'all';

    var rows = cuts[_cut] ?? const <StockRow>[];
    if (_q.isNotEmpty) {
      rows = rows.where((s) =>
        s.name.toLowerCase().contains(_q) ||
        (s.category ?? '').toLowerCase().contains(_q)).toList();
    }

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(stockProvider.future),
      // A CustomScrollView, not a ListView of children: the rows are built by
      // a SliverList.builder, so only what is on screen exists. The catalogue
      // is the one list here that genuinely grows without bound — every item
      // the company has ever bought — and the old version built all of it on
      // every frame.
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Request from procurement" was a full-width primary button
              // wedged between the filters and the list — the loudest thing on
              // a screen whose job is browsing, sitting above the content it is
              // secondary to. As a pill beside the title it is still one tap
              // and stops shouting. Same shape Admin's Team screen uses for
              // "Add member".
              FadeSlideIn(child: Row(children: [
                Expanded(child: RoleHeader(role: 'store',
                  eyebrow: 'Store · Inventory', title: 'Stock')),
              ])),
              const SizedBox(height: 10),
              FadeSlideIn(delay: Motion.stagger(1), child: Row(children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 10),
                PillAction('Request', icon: Icons.add_shopping_cart_rounded,
                  onTap: () => showRequestStockSheet(context, ref)),
              ])),
              const SizedBox(height: 12),
              FadeSlideIn(delay: Motion.stagger(2), child: ChipBar(chips: [
                _chip('All', 'all', all.length),
                if (low.isNotEmpty) _chip('Low', 'low', low.length, tint: BT.coral),
                if (essentials.isNotEmpty) _chip('Essentials', 'essentials', essentials.length),
                if (parts.isNotEmpty) _chip('Project parts', 'parts', parts.length),
              ])),
              const SizedBox(height: 14),
            ],
          )),
        ),

        if (stock.isLoading && !stock.hasValue)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: SkeletonList(count: 5)))
        else if (stock.hasError)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: ErrorCard(
              'Could not load stock.\n${friendlyError(stock.error!)}',
              onRetry: () => ref.invalidate(stockProvider))))
        else if (rows.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _q.isNotEmpty
              ? EmptyState(icon: Icons.search_off_rounded, tint: BT.mut2,
                  title: 'No match', subtitle: 'Nothing in stock matches "${_search.text.trim()}".')
              : const EmptyState(icon: Icons.layers_rounded, tint: BT.mint,
                  title: 'No stock lines',
                  subtitle: 'Items you keep in stock will show here once goods are received.')))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final row = _row(rows[i]);
                // Only the first screenful cascades in. Staggering by index
                // would make row 60 wait two seconds to appear as you scroll
                // to it, which reads as a stutter, not as polish.
                return i < 8
                  ? FadeSlideIn(delay: Motion.stagger(i, stepMs: 35, maxMs: 280), child: row)
                  : row;
              },
            ),
          ),
      ]),
    );
  }

  Widget _searchField() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: BT.line)),
    child: Row(children: [
      const Icon(Icons.search_rounded, size: 18, color: BT.mut2),
      const SizedBox(width: 9),
      Expanded(child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.ink),
        decoration: const InputDecoration(
          isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
          hintText: 'Search stock',
          hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w500, fontSize: 14.5)),
      )),
      if (_q.isNotEmpty)
        PressableScale(
          pressedScale: 0.88, haptic: true,
          onTap: () => _search.clear(),
          child: const Icon(Icons.close_rounded, size: 17, color: BT.mut2)),
    ]),
  );

  /// Selected chips are ink-on-white by default, like every other filter row
  /// in the app. A chip given a light [tint] (Low is coral) flips its text to
  /// ink, because white on coral is unreadable — the same pairing the Command
  /// Center's department chips use.
  Widget _chip(String label, String value, int count, {Color? tint}) => AppChip(label,
    selected: _cut == value,
    count: count,
    selectedColor: tint ?? BT.ink,
    selectedFg: tint == null ? Colors.white : BT.ink,
    onTap: () => setState(() => _cut = value));

  Widget _row(StockRow s) {
    // A project part is not the Store's to restock, so it gets neither a
    // health badge nor a reorder tap — both would be inviting an action the
    // database refuses and the process does not want. What it gets is the
    // count, which is the real question about it: how many can Workshop fit
    // today. Essentials keep the OK / Fair / Low read-out they always had.
    final color = s.low ? BT.coral : (s.quantity <= s.threshold * 2 ? BT.amber : BT.lime);
    final label = s.low ? 'Low' : (s.quantity <= s.threshold * 2 ? 'Fair' : 'OK');
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: PressableScale(
      pressedScale: s.isProjectPart ? 1 : 0.98,
      haptic: !s.isProjectPart,
      onTap: (s.itemCatalogId == null || s.isProjectPart) ? null : () => _openReorder(s),
      child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.inventory_2_outlined, size: 20, color: BT.ink)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text([
              s.category ?? 'General',
              if (s.isProjectPart) 'ordered per build',
            ].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 11.5)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${s.quantity}${s.unit == 'pcs' ? '' : s.unit}',
            style: display(15, w: FontWeight.w600, c: s.low ? BT.coral : BT.ink)),
          if (!s.isProjectPart) ...[
            const SizedBox(height: 3),
            StatusPill(label, color: color),
          ],
        ]),
        const SizedBox(width: 10),
        Icon(s.isProjectPart ? Icons.lock_outline_rounded : Icons.add_shopping_cart_rounded,
          size: 18, color: BT.mut2),
      ]),
    )));
  }

  Future<void> _openReorder(StockRow s) async {
    final qtyCtl = TextEditingController(text: s.threshold > 0 ? '${s.threshold}' : '1');
    final noteCtl = TextEditingController();
    var sending = false;
    await showModalBottomSheet<void>(
      sheetAnimationStyle: sheetMotion,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(color: BT.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: BT.line, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            const Text('REQUEST REORDER',
              style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(s.name, style: display(22, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${s.quantity} ${s.unit} in stock · procurement will order it',
              style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 18),
            sheetField('QUANTITY NEEDED', qtyCtl, hint: 'e.g. 20', number: true),
            const SizedBox(height: 11),
            sheetField('NOTE (OPTIONAL)', noteCtl, hint: 'Why / for which builds'),
            const SizedBox(height: 20),
            PrimaryButton(sending ? 'Sending…' : 'Send to procurement', icon: Icons.send_rounded,
              onTap: sending ? null : () async {
                final qty = int.tryParse(qtyCtl.text.trim()) ?? 0;
                if (qty <= 0) {
                  ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                    backgroundColor: BT.coral, content: Text('Enter a quantity greater than zero.')));
                  return;
                }
                setSheet(() => sending = true);
                try {
                  await ref.read(storeRepoProvider).requestStock(
                    itemId: s.itemCatalogId!, qty: qty, note: noteCtl.text);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: BT.ink, content: Text('Reorder for ${s.name} sent to procurement.')));
                  }
                } catch (e) {
                  setSheet(() => sending = false);
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                      backgroundColor: BT.coral, content: Text('Failed: ${friendlyError(e)}')));
                  }
                }
              }),
          ]),
        ),
      )),
    );
  }


  // General "raise a request" — Store picks any catalogue item (or adds a new
  // one) and asks procurement to order it. Unlike _openReorder (which starts
  // from an existing stock row), this works with an empty inventory.




}

// ───────────────────────────────────────────────────────────── PARTS

class _PartsTab extends ConsumerStatefulWidget {
  const _PartsTab();
  @override
  ConsumerState<_PartsTab> createState() => _PartsTabState();
}

class _PartsTabState extends ConsumerState<_PartsTab> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final comps = ref.watch(componentsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(componentsProvider.future),
      child: ListView(padding: _pad, children: [
        _storeHeader(context, 'Components'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 20, color: BT.mut),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search serial, model, truck…', border: InputBorder.none,
                hintStyle: TextStyle(color: BT.mut2, fontSize: 14)),
            )),
          ]),
        ),
        const SizedBox(height: 14),
        comps.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load components.\n${friendlyError(e)}'),
          data: (list) {
            final filtered = _q.isEmpty ? list : list.where((c) =>
              c.serial.toLowerCase().contains(_q) || c.name.toLowerCase().contains(_q) ||
              c.model.toLowerCase().contains(_q) || (c.projectCode ?? '').toLowerCase().contains(_q)).toList();
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.inventory_2_outlined, tint: BT.sky,
                title: 'No components yet', subtitle: 'Log components at intake (scan icon) to track them.');
            }
            if (filtered.isEmpty) {
              return const EmptyState(icon: Icons.search_off_rounded, tint: BT.mut2,
                title: 'No matches', subtitle: 'Try a different serial, model or truck.');
            }
            return Column(children: [
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('${list.length} tracked components', style: const TextStyle(color: BT.mut, fontSize: 12))),
              ...filtered.map(_row),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _row(ComponentRow c) => Padding(padding: const EdgeInsets.only(bottom: 11), child: PressableScale(pressedScale: 0.98, haptic: true, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComponentDetailScreen(component: c))),
    child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14), child: Row(children: [
      Container(width: 46, height: 46, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.memory_rounded, size: 21, color: Color(0xFF123040))),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.model.isEmpty ? c.name : '${c.name} · ${c.model}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text('${c.serial}${c.projectCode != null ? ' · ${c.projectCode}' : ''}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
      ])),
      StatusPill(c.warrantyEnd == null ? '—' : (c.warrantyActive ? 'In warranty' : 'Expired'),
        color: c.warrantyEnd == null ? BT.mut2 : (c.warrantyActive ? BT.lime : BT.coral)),
    ])),
  ));
}

/// "Ask procurement to order this." Reached from the Stock tab's button and
/// from a low-stock row in the Inbox, which is where the thought usually
/// starts — so it lives at file scope rather than inside one tab's State.
///
/// [preselect] fills the item in when the caller already knows which one;
/// the picker still opens on it so the quantity and note can be set.
Future<void> showRequestStockSheet(BuildContext context, WidgetRef ref, {StockRow? preselect}) async {
  final base = ref.read(essentialItemsProvider).valueOrNull ?? <OptRef>[];
  // A low line may not be among the essentials; offer it regardless.
  final extra = <OptRef>[
    if (preselect?.itemCatalogId != null)
      OptRef(preselect!.itemCatalogId!, preselect.name),
  ];
  String? itemId = preselect?.itemCatalogId;
  final qtyCtl = TextEditingController(text: '1');
  final noteCtl = TextEditingController();
  var sending = false;
  await showModalBottomSheet<void>(
    sheetAnimationStyle: sheetMotion,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
      final items = {for (final o in [...base, ...extra]) o.id: o}.values.toList();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(color: BT.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: BT.line, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            const Text('REQUEST FROM PROCUREMENT',
              style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Ask procurement to order an item', style: display(21, w: FontWeight.w600)),
            const SizedBox(height: 16),
            sheetLabel('ITEM'),
            AppSelectField<String>(
              value: itemId, hint: 'Select item', title: 'Item',
              options: [for (final o in items) SelectOption(o.id, o.label)],
              addLabel: 'Add new item',
              onAdd: () async {
                final created = await promptNewStockItem(sheetCtx, ref);
                if (created != null) {
                  setSheet(() { extra.add(created); itemId = created.id; });
                  ref.invalidate(essentialItemsProvider);
                }
              },
              onChanged: (v) => setSheet(() => itemId = v),
            ),
            const SizedBox(height: 11),
            sheetField('QUANTITY NEEDED', qtyCtl, hint: 'e.g. 20', number: true),
            const SizedBox(height: 11),
            sheetField('NOTE (OPTIONAL)', noteCtl, hint: 'Why / for which builds'),
            const SizedBox(height: 20),
            PrimaryButton(sending ? 'Sending…' : 'Send to procurement', icon: Icons.send_rounded,
              onTap: sending ? null : () async {
                if (itemId == null) {
                  ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                    backgroundColor: BT.coral, content: Text('Pick an item first.')));
                  return;
                }
                final qty = int.tryParse(qtyCtl.text.trim()) ?? 0;
                if (qty <= 0) {
                  ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                    backgroundColor: BT.coral, content: Text('Enter a quantity greater than zero.')));
                  return;
                }
                setSheet(() => sending = true);
                try {
                  await ref.read(storeRepoProvider).requestStock(
                    itemId: itemId!, qty: qty, note: noteCtl.text);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      backgroundColor: BT.ink, content: Text('Request sent to procurement.')));
                  }
                } catch (e) {
                  setSheet(() => sending = false);
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                      backgroundColor: BT.coral, content: Text('Failed: ${friendlyError(e)}')));
                  }
                }
              }),
          ]),
        ),
      );
    }),
  );
}

/// Create a catalogue item without leaving the request sheet. Store writes
/// to `item_catalog` since 0026, so this no longer fails on RLS.
Future<OptRef?> promptNewStockItem(BuildContext ctx, WidgetRef ref) {
  final nameC = TextEditingController();
  String? e;
  return showDialog<OptRef>(context: ctx, builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
    backgroundColor: BT.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    title: Text('New item', style: display(18, w: FontWeight.w600)),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(controller: nameC, decoration: const InputDecoration(hintText: 'Item name', border: InputBorder.none)),
      ),
      if (e != null) Padding(padding: const EdgeInsets.only(top: 8),
        child: Text(e!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel', style: TextStyle(color: BT.mut))),
      TextButton(onPressed: () async {
        if (nameC.text.trim().isEmpty) { setD(() => e = 'Name required'); return; }
        // A new item added here is a Store essential, and essentials are bulk.
        final created = await ref.read(procurementRepoProvider)
            .createItem(name: nameC.text.trim(), essential: true, serialized: false);
        if (dctx.mounted) Navigator.pop(dctx, created);
      }, child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
    ],
  )));
}

Widget sheetLabel(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
  child: Text(t, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)));

/// Shared by both sheets in this file.
Widget sheetField(String label, TextEditingController c,
    {String? hint, bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: c, keyboardType: number ? TextInputType.number : null,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
        decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
          hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
      ),
    ]),
  );
