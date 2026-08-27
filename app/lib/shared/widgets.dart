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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg))),
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
  Widget build(BuildContext context) {
    // Grounded "dock" instead of a floating island: a rounded-top raised panel
    // that runs to the bottom edge, so there's no dead band beneath the pill.
    // The card2 surface fills past the pill to cover the device's safe-area
    // inset, and a soft upward shadow lifts it off the scrolling content.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: BT.card2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: BT.line)),
        boxShadow: [BoxShadow(color: Color(0x14695228), blurRadius: 22, offset: Offset(0, -6))],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
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
        child: Icon(actionIcon, color: BT.ink, size: 26))),
    ]),
    );
  }
}


/// One option in an [AppSelectField].
class SelectOption<T> {
  final T value;
  final String label;
  final String? sublabel;   // optional secondary line
  final IconData? icon;     // optional leading icon
  const SelectOption(this.value, this.label, {this.sublabel, this.icon});
}

/// A modern selector field. Tapping it opens a rounded bottom sheet with the
/// options as a proper list (drag handle, title, a check + tint on the current
/// choice) — replaces Material's dated little dropdown menu everywhere.
///
/// Optionally shows a "＋ add" row at the top of the sheet (for inline-create
/// flows like "Add new item / vendor") via [addLabel] + [onAdd].
class AppSelectField<T> extends StatelessWidget {
  final String? label;                 // small caps label above the field
  final String hint;                   // placeholder when nothing is selected
  final T? value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? title;                 // sheet heading (defaults to label/hint)
  final bool dense;
  final IconData? leadingIcon;
  final String? addLabel;              // if set, a create-new row appears
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
    for (final o in options) { if (o.value == value) return o; }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final field = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _open(context) : null,
      child: Container(
        height: dense ? 48 : 54,
        padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 16),
        decoration: BoxDecoration(
          color: BT.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BT.line),
        ),
        child: Row(children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 18, color: BT.mut),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(
            sel?.label ?? hint,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: sel == null ? BT.mut2 : BT.ink),
          )),
          Icon(Icons.expand_more_rounded, size: 22, color: enabled ? BT.mut : BT.mut2),
        ]),
      ),
    );
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label!.toUpperCase(),
          style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600))),
      field,
    ]);
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
        decoration: const BoxDecoration(color: BT.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(title ?? label ?? hint, style: display(19, w: FontWeight.w600))),
          const SizedBox(height: 12),
          if (addLabel != null) ...[
            _AddRow(label: addLabel!, onTap: () { Navigator.pop(ctx); onAdd?.call(); }),
            const SizedBox(height: 6),
          ],
          Flexible(child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final o = options[i];
              final on = o.value == value;
              return Material(
                color: on ? BT.lime : BT.card,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () { Navigator.pop(ctx); onChanged(o.value); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: on ? Colors.transparent : BT.line)),
                    child: Row(children: [
                      if (o.icon != null) ...[
                        Icon(o.icon, size: 19, color: BT.ink),
                        const SizedBox(width: 12),
                      ],
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.ink)),
                        if (o.sublabel != null) ...[
                          const SizedBox(height: 2),
                          Text(o.sublabel!, maxLines: 1, overflow: TextOverflow.ellipsis,
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
  final String label; final VoidCallback onTap;
  const _AddRow({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: BT.card2, borderRadius: BorderRadius.circular(14),
    child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(children: [
          Container(width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.add_rounded, size: 17, color: BT.ink)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BT.ink)),
        ]),
      )),
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
