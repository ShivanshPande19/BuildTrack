import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'animations.dart';

/// Reusable Equora-style components: the building blocks for all role screens.

/// The standard surface: cream card, hairline border, soft warm shadow.
///
/// Give it [onTap] and it becomes a pressable card. It sinks slightly under the
/// finger and springs back, which is how every tappable card in the app should
/// feel. That's preferable to wrapping a card in a bare `GestureDetector`, which
/// gives no feedback at all.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
    this.radius = BT.radiusCard,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? BT.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: BT.line),
        boxShadow: const [BoxShadow(color: Color(0x11695228), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return PressableScale(onTap: onTap, pressedScale: 0.98, child: card);
  }
}

/// Candy status pill with a leading dot (e.g. On-track / At-risk / Delayed).
/// Colour and label changes cross-fade instead of snapping.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color; // background tint
  final bool dark;
  const StatusPill(this.label, {super.key, this.color = BT.lime, this.dark = false});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.move,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? BT.ink : color,
          borderRadius: BorderRadius.circular(BT.radiusPill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: dark ? BT.lime : BT.ink, shape: BoxShape.circle)),
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? Colors.white : BT.ink)),
        ]),
      );
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: BT.mut)),
      );
}

/// The small-caps "eyebrow" line above a page title (e.g. OWNER · ADMIN).
class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600));
}

Widget _buttonFace({
  required String label,
  required IconData? icon,
  required Color bg,
  required Color fg,
  required bool busy,
  required bool enabled,
  required double height,
}) =>
    AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.move,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: enabled ? bg : Color.alphaBlend(BT.bg.withValues(alpha: 0.55), bg),
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedSwitcher(
        duration: Motion.fast,
        switchInCurve: Motion.curve,
        switchOutCurve: Motion.exit,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: c),
        ),
        child: busy
            ? SizedBox(
                key: const ValueKey('busy'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation<Color>(fg)))
            : Row(key: const ValueKey('label'), mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
                Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg))),
              ]),
      ),
    );

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color bg;
  final Color fg;
  final double height;

  /// While true the label morphs into a spinner in place (the button keeps its
  /// size, so the form doesn't jump) and taps are ignored. Use it when the
  /// screen owns its own "saving" flag; otherwise prefer [AsyncPrimaryButton].
  final bool busy;
  const PrimaryButton(this.label,
      {super.key,
      this.onTap,
      this.icon,
      this.bg = BT.lime,
      this.fg = BT.ink,
      this.height = 54,
      this.busy = false});
  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: busy ? null : onTap,
        haptic: true,
        child: _buttonFace(
            label: label, icon: icon, bg: bg, fg: fg, busy: busy, enabled: onTap != null, height: height),
      );
}

/// A [PrimaryButton] that guards a mutating async action against double-taps.
///
/// While its [onTap] future runs, the label morphs into a spinner and further
/// taps are ignored, so a fast double-tap can never fire the same call twice
/// (duplicate PO, double approval, duplicate recall notifications, …). On
/// success it gives a light confirmation haptic. Use this instead of
/// [PrimaryButton] anywhere the tap writes to the backend.
class AsyncPrimaryButton extends StatefulWidget {
  final String label;
  final Future<void> Function()? onTap;
  final IconData? icon;
  final Color bg;
  final Color fg;
  final double height;
  const AsyncPrimaryButton(this.label,
      {super.key, this.onTap, this.icon, this.bg = BT.lime, this.fg = BT.ink, this.height = 54});
  @override
  State<AsyncPrimaryButton> createState() => _AsyncPrimaryButtonState();
}

class _AsyncPrimaryButtonState extends State<AsyncPrimaryButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onTap == null) return;
    setState(() => _busy = true);
    try {
      await widget.onTap!();
      Haptic.confirm();
    } finally {
      // The action may have popped this screen, so only touch state if we're still mounted.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: (_busy || widget.onTap == null) ? null : _run,
        haptic: true,
        child: _buttonFace(
            label: widget.label,
            icon: widget.icon,
            bg: widget.bg,
            fg: widget.fg,
            busy: _busy,
            enabled: widget.onTap != null,
            height: widget.height),
      );
}

/// The quieter partner of [PrimaryButton] (cream card with a hairline border),
/// for the second choice in a pair: "Save as draft", "Request changes",
/// "Cancel". It springs and gives haptics like the primary one, and can morph
/// into a spinner when it is the action in flight.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool busy;
  const SecondaryButton(this.label, {super.key, this.onTap, this.icon, this.height = 54, this.busy = false});
  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: busy ? null : onTap,
        haptic: true,
        child: AnimatedOpacity(
          duration: Motion.fast,
          opacity: onTap == null && !busy ? 0.5 : 1,
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
            child: AnimatedSwitcher(
              duration: Motion.fast,
              switchInCurve: Motion.curve,
              switchOutCurve: Motion.exit,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: c),
              ),
              child: busy
                  ? const SizedBox(
                      key: ValueKey('busy'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: BT.ink))
                  : Row(key: const ValueKey('label'), mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, size: 18, color: BT.ink), const SizedBox(width: 8)],
                      Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink))),
                    ]),
            ),
          ),
        ),
      );
}

/// A compact secondary action (icon + label in a soft pill). Use for in-section
/// actions such as "Add member" or "Add vendor" next to a section title, where
/// a full-width primary button would be too loud.
class PillAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;
  const PillAction(this.label, {super.key, required this.icon, this.onTap, this.dark = true});
  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        haptic: true,
        pressedScale: 0.94,
        child: Container(
          height: 40,
          padding: const EdgeInsets.fromLTRB(12, 0, 15, 0),
          decoration: BoxDecoration(
            color: dark ? BT.ink : BT.card,
            borderRadius: BorderRadius.circular(BT.radiusPill),
            border: dark ? null : Border.all(color: BT.line),
            boxShadow: dark
                ? const [BoxShadow(color: Color(0x261D1C18), blurRadius: 14, offset: Offset(0, 6))]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: dark ? BT.lime : BT.card2, shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: BT.ink),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: dark ? Colors.white : BT.ink)),
          ]),
        ),
      );
}

/// A filter chip whose fill, border and label colour glide between states.
/// The optional [count] sits in a small bubble that animates with it.
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final int? count;
  final Color? tint; // resting tint (e.g. coral for a warning filter)
  final Color selectedColor;
  final Color selectedFg;
  const AppChip(
    this.label, {
    super.key,
    required this.selected,
    this.onTap,
    this.icon,
    this.count,
    this.tint,
    this.selectedColor = BT.ink,
    this.selectedFg = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? selectedFg : (tint != null ? BT.ink : BT.mut);
    return PressableScale(
      onTap: onTap,
      haptic: true,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.move,
        padding: EdgeInsets.fromLTRB(icon != null ? 12 : 15, 9, count != null ? 9 : 15, 9),
        decoration: BoxDecoration(
          color: selected ? selectedColor : (tint ?? BT.card),
          borderRadius: BorderRadius.circular(BT.radiusPill),
          border: Border.all(color: selected ? selectedColor : (tint ?? BT.line)),
          boxShadow: selected
              ? [BoxShadow(color: selectedColor.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 5))]
              : const [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg, fontFamily: DefaultTextStyle.of(context).style.fontFamily),
            child: Text(label),
          ),
          if (count != null) ...[
            const SizedBox(width: 7),
            AnimatedContainer(
              duration: Motion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.16) : BT.card2,
                borderRadius: BorderRadius.circular(BT.radiusPill),
              ),
              child: Text('$count',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? selectedFg : BT.mut)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A horizontally scrolling row of [AppChip]s with consistent spacing and edge
/// padding, so chips can scroll under the screen edge instead of being clipped.
class ChipBar extends StatelessWidget {
  final List<Widget> chips;
  final double height;
  const ChipBar({super.key, required this.chips, this.height = 40});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      );
}

/// In-screen tabs (e.g. a build's Overview · Pipeline · Materials · Record).
///
/// Tabs are sized to their labels, and one ink pill **slides** under the
/// active label instead of every tab cross-fading its own fill. A tap gives a
/// selection haptic. If the row is wider than the screen it scrolls, and the
/// active tab is kept in view.
class SegmentTabs extends StatefulWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final EdgeInsets padding;
  const SegmentTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });
  @override
  State<SegmentTabs> createState() => _SegmentTabsState();
}

class _SegmentTabsState extends State<SegmentTabs> {
  final _scroll = ScrollController();
  static const _gap = 8.0, _hPad = 16.0, _h = 40.0;
  static const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  List<double> _widths(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return [
      for (final l in widget.labels)
        (TextPainter(text: TextSpan(text: l, style: _style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
              ..layout())
            .width +
            _hPad * 2,
    ];
  }

  @override
  void didUpdateWidget(SegmentTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final w = _widths(context);
    final left = w.take(widget.index).fold<double>(0, (s, x) => s + x + _gap);
    final right = left + w[widget.index] + widget.padding.horizontal;
    final pos = _scroll.position;
    double? to;
    if (left < pos.pixels) to = left;
    if (right > pos.pixels + pos.viewportDimension) to = right - pos.viewportDimension;
    if (to != null) {
      _scroll.animateTo(to.clamp(0, pos.maxScrollExtent), duration: Motion.base, curve: Motion.move);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = _widths(context);
    final left = w.take(widget.index).fold<double>(0, (s, x) => s + x + _gap);
    final total = w.fold<double>(0, (s, x) => s + x) + _gap * (w.length - 1);
    final dur = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 380);
    return SizedBox(
      height: _h,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: SizedBox(
          width: total,
          child: Stack(children: [
            // Resting pills (cream), one per tab.
            for (var i = 0; i < w.length; i++)
              Positioned(
                left: w.take(i).fold<double>(0, (s, x) => s + x + _gap),
                top: 0,
                bottom: 0,
                width: w[i],
                child: Container(
                  decoration: BoxDecoration(
                    color: BT.card,
                    borderRadius: BorderRadius.circular(BT.radiusPill),
                    border: Border.all(color: BT.line),
                  ),
                ),
              ),
            // The ink indicator glides between them.
            AnimatedPositioned(
              duration: dur,
              curve: Motion.move,
              left: left,
              top: 0,
              bottom: 0,
              width: w[widget.index],
              child: Container(
                decoration: BoxDecoration(
                  color: BT.ink,
                  borderRadius: BorderRadius.circular(BT.radiusPill),
                  boxShadow: const [BoxShadow(color: Color(0x331D1C18), blurRadius: 12, offset: Offset(0, 4))],
                ),
              ),
            ),
            for (var i = 0; i < w.length; i++)
              Positioned(
                left: w.take(i).fold<double>(0, (s, x) => s + x + _gap),
                top: 0,
                bottom: 0,
                width: w[i],
                child: Semantics(
                  button: true,
                  selected: i == widget.index,
                  child: PressableScale(
                    pressedScale: 0.94,
                    onTap: () {
                      if (i != widget.index) Haptic.tap();
                      widget.onChanged(i);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: Motion.base,
                        curve: Motion.move,
                        style: DefaultTextStyle.of(context).style.merge(_style).copyWith(
                              color: i == widget.index ? Colors.white : BT.mut,
                            ),
                        child: Text(widget.labels[i], maxLines: 1, softWrap: false),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Signature floating pill nav + circular action button.
///
/// The active tab is marked by an ink "bubble" that **slides** between tabs,
/// rather than each tab separately fading its own background. The icon tints
/// and the label unfolds beside it as the bubble arrives. Tabs give a selection
/// haptic, and the lime action button springs on press.
class PillNav extends StatelessWidget {
  final List<IconData> icons;
  final int active;
  final String activeLabel;
  final IconData actionIcon;
  final ValueChanged<int>? onTap;
  final VoidCallback? onAction;
  const PillNav(
      {super.key,
      required this.icons,
      required this.active,
      required this.activeLabel,
      this.actionIcon = Icons.add,
      this.onTap,
      this.onAction});

  @override
  Widget build(BuildContext context) {
    // Floating pill: no border, because an outline reads as flat and attached.
    // Instead a soft, layered drop shadow, so the white pill and lime button
    // clearly hover above the warm background. main.dart zeroes the bottom
    // inset app-wide, so read the real one from the view.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom > 0
        ? MediaQuery.viewPaddingOf(context).bottom
        : View.of(context).viewPadding.bottom / View.of(context).devicePixelRatio;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, bottomInset > 0 ? bottomInset : 14),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BT.card,
              borderRadius: BorderRadius.circular(BT.radiusPill),
              boxShadow: const [
                BoxShadow(color: Color(0x33695228), blurRadius: 34, spreadRadius: -4, offset: Offset(0, 16)),
                BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: _NavTrack(icons: icons, active: active, label: activeLabel, onTap: onTap),
          ),
        ),
        const SizedBox(width: 12),
        PressableScale(
          onTap: onAction,
          haptic: true,
          pressedScale: 0.88,
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: BT.lime,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x80AAB43C), blurRadius: 26, offset: Offset(0, 14))],
            ),
            child: Icon(actionIcon, color: BT.ink, size: 26),
          ),
        ),
      ]),
    );
  }
}

/// Lays out the tabs so the active one is wider (icon + label) and the rest
/// share the remaining space equally. Behind them, a single ink bubble glides to
/// the active slot. Widths come from measured constraints, so the bubble's
/// travel always lines up exactly with its tab.
class _NavTrack extends StatelessWidget {
  final List<IconData> icons;
  final int active;
  final String label;
  final ValueChanged<int>? onTap;
  const _NavTrack({required this.icons, required this.active, required this.label, this.onTap});

  static const _labelStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final n = icons.length;
        final scale = MediaQuery.textScalerOf(context);
        final tp = TextPainter(
          text: TextSpan(text: label, style: _labelStyle),
          textDirection: TextDirection.ltr,
          textScaler: scale,
          maxLines: 1,
        )..layout();
        // Active slot = icon (22) + gap (6) + label + side padding (2×14).
        const minIdle = 44.0;
        final maxActive = c.maxWidth - minIdle * (n - 1);
        final activeW = (22 + 6 + tp.width + 28).clamp(48.0, maxActive > 48 ? maxActive : 48.0);
        final idleW = n > 1 ? (c.maxWidth - activeW) / (n - 1) : 0.0;
        double leftOf(int i) => i <= active ? i * idleW : activeW + (i - 1) * idleW;
        final still = reduceMotion(context);
        final dur = still ? Duration.zero : const Duration(milliseconds: 420);

        return Stack(children: [
          AnimatedPositioned(
            duration: dur,
            curve: Motion.move,
            left: leftOf(active),
            top: 0,
            bottom: 0,
            width: activeW,
            child: Container(
              decoration: BoxDecoration(
                color: BT.ink,
                borderRadius: BorderRadius.circular(BT.radiusPill),
                boxShadow: const [BoxShadow(color: Color(0x331D1C18), blurRadius: 12, offset: Offset(0, 4))],
              ),
            ),
          ),
          for (var i = 0; i < n; i++)
            AnimatedPositioned(
              duration: dur,
              curve: Motion.move,
              left: leftOf(i),
              top: 0,
              bottom: 0,
              width: i == active ? activeW : idleW,
              child: Semantics(
                button: true,
                selected: i == active,
                label: i == active ? label : null,
                child: PressableScale(
                  pressedScale: 0.9,
                  onTap: () {
                    if (i != active) Haptic.tap();
                    onTap?.call(i);
                  },
                  child: _NavItem(icon: icons[i], on: i == active, label: label, style: _labelStyle),
                ),
              ),
            ),
        ]);
      });
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool on;
  final String label;
  final TextStyle style;
  const _NavItem({required this.icon, required this.on, required this.label, required this.style});

  @override
  Widget build(BuildContext context) => Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: on ? Colors.white : BT.mut),
            duration: Motion.base,
            curve: Motion.move,
            builder: (_, c, __) => AnimatedScale(
              scale: on ? 1.0 : 0.94,
              duration: Motion.base,
              curve: Curves.easeOutBack,
              child: Icon(icon, size: 22, color: c),
            ),
          ),
          // The label unfolds as the bubble arrives and folds away as it leaves.
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 380),
              curve: Motion.move,
              alignment: Alignment.centerLeft,
              child: on
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FadeSlideIn(
                        key: ValueKey(label),
                        offsetY: 0,
                        scale: false,
                        delay: const Duration(milliseconds: 90),
                        duration: Motion.fast,
                        child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: style),
                      ),
                    )
                  : const SizedBox(height: 0, width: 0),
            ),
          ),
        ]),
      );
}

/// One option in an [AppSelectField].
class SelectOption<T> {
  final T value;
  final String label;
  final String? sublabel; // optional secondary line
  final IconData? icon; // optional leading icon
  const SelectOption(this.value, this.label, {this.sublabel, this.icon});
}

/// A modern selector field. Tapping it opens a rounded bottom sheet that lists
/// the options properly (drag handle, title, a check + tint on the current
/// choice). It replaces Material's dated little dropdown menu everywhere.
///
/// Optionally shows a "＋ add" row at the top of the sheet (for inline-create
/// flows like "Add new item / vendor") via [addLabel] + [onAdd].
class AppSelectField<T> extends StatelessWidget {
  final String? label; // small caps label above the field
  final String hint; // placeholder when nothing is selected
  final T? value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? title; // sheet heading (defaults to label/hint)
  final bool dense;
  final IconData? leadingIcon;
  final String? addLabel; // if set, a create-new row appears
  final VoidCallback? onAdd;
  final bool enabled;
  const AppSelectField({
    super.key,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.title,
    this.dense = false,
    this.leadingIcon,
    this.addLabel,
    this.onAdd,
    this.enabled = true,
  });

  SelectOption<T>? get _selected {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final field = PressableScale(
      onTap: enabled ? () => _open(context) : null,
      pressedScale: 0.985,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: dense ? 48 : 54,
        padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 16),
        decoration: BoxDecoration(
          color: enabled ? BT.card : BT.card2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BT.line),
        ),
        child: Row(children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 18, color: BT.mut),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.fast,
              switchInCurve: Motion.curve,
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, if (cur != null) cur]),
              child: Text(
                sel?.label ?? hint,
                key: ValueKey(sel?.label ?? hint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: sel == null ? BT.mut2 : BT.ink),
              ),
            ),
          ),
          Icon(Icons.expand_more_rounded, size: 22, color: enabled ? BT.mut : BT.mut2),
        ]),
      ),
    );
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label!.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600))),
      field,
    ]);
  }

  void _open(BuildContext context) {
    showAppSheet<void>(
      context: context,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(title ?? label ?? hint, style: display(19, w: FontWeight.w600))),
          const SizedBox(height: 12),
          if (addLabel != null) ...[
            _AddRow(
                label: addLabel!,
                onTap: () {
                  Navigator.pop(ctx);
                  onAdd?.call();
                }),
            const SizedBox(height: 6),
          ],
          Flexible(
              child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final o = options[i];
              final on = o.value == value;
              return FadeSlideIn(
                delay: Motion.stagger(i, stepMs: 25, maxMs: 200),
                offsetY: 8,
                scale: false,
                child: PressableScale(
                  pressedScale: 0.98,
                  haptic: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    onChanged(o.value);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                    decoration: BoxDecoration(
                        color: on ? BT.lime : BT.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: on ? Colors.transparent : BT.line)),
                    child: Row(children: [
                      if (o.icon != null) ...[
                        Icon(o.icon, size: 19, color: BT.ink),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.ink)),
                        if (o.sublabel != null) ...[
                          const SizedBox(height: 2),
                          Text(o.sublabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: BT.mut)),
                        ],
                      ])),
                      if (on) const Icon(Icons.check_rounded, size: 19, color: BT.ink),
                    ]),
                  ),
                ),
              );
            },
          )),
        ]),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddRow({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        haptic: true,
        pressedScale: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add_rounded, size: 17, color: BT.ink)),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BT.ink)),
          ]),
        ),
      );
}

/// The app's bottom sheet: warm surface, drag handle, rounded top, an
/// emphasized rise-in, and padding that lifts with the keyboard. Use it instead of
/// raw `showModalBottomSheet`, so every sheet moves and looks the same.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool handle = true,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 12, 16, 20),
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: BT.bg,
      sheetAnimationStyle: sheetMotion,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Padding(
          padding: padding,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (handle)
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
            Flexible(child: builder(ctx)),
          ]),
        ),
      ),
    );

/// Friendly empty-state placeholder: a candy icon badge + title + hint.
/// Used wherever a section has no data yet (photos, parts, checklist, lists…).
/// The badge floats in with a soft spring so an empty screen still feels alive.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color tint; // colour of the icon badge
  final EdgeInsets padding;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tint = BT.card2,
    this.padding = const EdgeInsets.symmetric(vertical: 30, horizontal: 22),
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: BT.card,
          borderRadius: BorderRadius.circular(BT.radiusCard),
          border: Border.all(color: BT.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion(context) ? 1 : 0.6, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.35), shape: BoxShape.circle),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 21, color: BT.ink),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BT.ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(subtitle!,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: BT.mut, height: 1.4)),
          ],
        ]),
      );
}

/// A soft inline error card (coral text on cream), with an optional retry.
class ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorCard(this.message, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => FadeSlideIn(
        child: AppCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFFFBE4E0), shape: BoxShape.circle),
              child: const Icon(Icons.wifi_off_rounded, size: 17, color: BT.coral),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: BT.coral, fontSize: 13, height: 1.35))),
            if (onRetry != null)
              PressableScale(
                onTap: onRetry,
                haptic: true,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8, top: 6),
                  child: Text('Retry', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
          ]),
        ),
      );
}

/// The ⓧ / back chip used at the top of pushed screens. It springs on press
/// and gives a selection haptic.
class BackChip extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  const BackChip({super.key, this.onTap, this.icon = Icons.chevron_left_rounded});
  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        haptic: true,
        pressedScale: 0.88,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
          child: Icon(icon, size: 24, color: BT.ink),
        ),
      );
}
