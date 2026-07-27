import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Reusable Equora-style components — the building blocks for all role screens.

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? BT.card,
      borderRadius: BorderRadius.circular(BT.radiusCard),
      border: Border.all(color: BT.line),
      boxShadow: const [BoxShadow(color: Color(0x11695228), blurRadius: 24, offset: Offset(0, 12))],
    ),
    child: child,
  );
}

/// Candy status pill with a leading dot (e.g. On-track / At-risk / Delayed).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;      // background tint
  final bool dark;
  const StatusPill(this.label, {super.key, this.color = BT.lime, this.dark = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: dark ? BT.ink : color,
      borderRadius: BorderRadius.circular(BT.radiusPill),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(color: dark ? BT.lime : BT.ink, shape: BoxShape.circle)),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? Colors.white : BT.ink)),
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

class PrimaryButton extends StatelessWidget {
  final String label; final VoidCallback? onTap; final IconData? icon; final Color bg; final Color fg;
  const PrimaryButton(this.label, {super.key, this.onTap, this.icon, this.bg = BT.lime, this.fg = BT.ink});
  @override
  Widget build(BuildContext context) => Material(
    color: bg, borderRadius: BorderRadius.circular(16),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
      child: Container(height: 54, alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
        ]))),
  );
}

/// Signature floating pill nav + circular action button (matches the UI).
class PillNav extends StatelessWidget {
  final List<IconData> icons;
  final int active;
  final String activeLabel;
  final IconData actionIcon;
  final ValueChanged<int>? onTap;
  final VoidCallback? onAction;
  const PillNav({super.key, required this.icons, required this.active,
    required this.activeLabel, this.actionIcon = Icons.add, this.onTap, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
    child: Row(children: [
      Expanded(child: Container(
        height: 64, padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(BT.radiusPill),
          border: Border.all(color: BT.line),
          boxShadow: const [BoxShadow(color: Color(0x1F695228), blurRadius: 30, offset: Offset(0, 14))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(icons.length, (i) {
            final on = i == active;
            final item = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap?.call(i),
              child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                height: 48, padding: EdgeInsets.symmetric(horizontal: on ? 14 : 12),
                decoration: BoxDecoration(color: on ? BT.ink : Colors.transparent, borderRadius: BorderRadius.circular(BT.radiusPill)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icons[i], size: 22, color: on ? Colors.white : BT.mut),
                  if (on) ...[
                    const SizedBox(width: 6),
                    Flexible(child: Text(activeLabel, maxLines: 1, softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                  ],
                ])));
            // Only the active pill may shrink (loose) if space is tight — never overflows.
            return on ? Flexible(fit: FlexFit.loose, child: item) : item;
          }))),
      ),
      const SizedBox(width: 12),
      GestureDetector(onTap: onAction, child: Container(width: 60, height: 60,
        decoration: BoxDecoration(color: BT.lime, shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x80AAB43C), blurRadius: 26, offset: Offset(0, 14))]),
        child: const Icon(Icons.add, color: BT.ink, size: 26))),
    ]),
  );
}


/// Friendly empty-state placeholder: a candy icon badge + title + hint.
/// Used wherever a section has no data yet (photos, parts, checklist, lists…).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color tint;     // colour of the icon badge
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
      Container(
        width: 58, height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(color: tint.withOpacity(0.35), shape: BoxShape.circle),
        child: Container(
          width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: 21, color: BT.ink),
        ),
      ),
      const SizedBox(height: 13),
      Text(title, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BT.ink)),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(subtitle!, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: BT.mut, height: 1.4)),
      ],
    ]),
  );
}
