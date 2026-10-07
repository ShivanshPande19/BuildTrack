import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

/// The app's motion language: one place for durations and curves so every
/// screen moves with the same rhythm. Pure Flutter, no animation packages.
///
/// Durations and curves follow the Material 3 motion tokens. Entrances
/// *decelerate* (fast start, soft landing). Exits *accelerate* and are shorter,
/// so the UI never feels like it is waiting on itself. Every primitive here
/// honours the OS "reduce motion" setting.
class Motion {
  static const fast = Duration(milliseconds: 200); // M3 short4: chips, pills, presses
  static const base = Duration(milliseconds: 350); // M3 medium3: entrances, swaps
  static const slow = Duration(milliseconds: 600); // M3 long4-ish: counters, bars

  /// Entrances: fast start, long gentle settle.
  static const curve = Easing.emphasizedDecelerate;
  /// Exits: start slow, leave quickly.
  static const exit = Easing.emphasizedAccelerate;
  /// Things that move on screen from A to B (indicators, layout shifts).
  static const move = Curves.easeInOutCubicEmphasized;

  /// Stagger step for list reveals, capped so long lists never feel sluggish.
  static Duration stagger(int index, {int stepMs = 45, int maxMs = 360}) =>
      Duration(milliseconds: (index * stepMs).clamp(0, maxMs));
}

/// Whether the platform asked us to reduce motion (accessibility).
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Light, consistent haptics. Selection for toggles and tab switches, light
/// impact for confirmations. On devices without haptics these are no-ops.
class Haptic {
  static void tap() => HapticFeedback.selectionClick();
  static void confirm() => HapticFeedback.lightImpact();
}

// ───────────────────────────────────────────────────────────── entrances

/// Fade + rise + a whisper of scale. Give successive items an increasing
/// [delay] (see [Motion.stagger]) for a staggered reveal.
///
/// Uses [FadeTransition] / [SlideTransition] / [ScaleTransition], which animate
/// at the paint/composite level, so the child is never rebuilt per frame.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final bool scale;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.base,
    this.offsetY = 14,
    this.scale = true,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final CurvedAnimation _t = CurvedAnimation(parent: _c, curve: Motion.curve);
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget out = widget.child;
    if (widget.scale) {
      out = ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(_t), child: out);
    }
    return FadeTransition(
      opacity: _t,
      child: _PixelSlide(animation: _t, dy: widget.offsetY, child: out),
    );
  }
}

/// Slides by a fixed number of logical pixels (SlideTransition works in
/// fractions of the child's size, so a tall card and a chip would travel
/// different distances; a fixed distance reads as one consistent motion).
class _PixelSlide extends AnimatedWidget {
  final double dy;
  final Widget child;
  const _PixelSlide({required Animation<double> animation, required this.dy, required this.child})
      : super(listenable: animation);
  @override
  Widget build(BuildContext context) {
    final v = (listenable as Animation<double>).value;
    return Transform.translate(offset: Offset(0, dy * (1 - v)), child: child);
  }
}

/// Wrap each top-level item of a scrolling page so the page cascades in, top
/// to bottom, the first time it appears. Pull-to-refresh and data updates
/// rebuild the same element, so items don't re-animate (no flicker).
List<Widget> staggered(List<Widget> children, {int stepMs = 40, int maxMs = 320, double offsetY = 14}) => [
      for (var i = 0; i < children.length; i++)
        FadeSlideIn(
          delay: Motion.stagger(i, stepMs: stepMs, maxMs: maxMs),
          offsetY: offsetY,
          child: children[i],
        ),
    ];

// ───────────────────────────────────────────────────────────── feedback

/// Tactile press feedback: the child scales down slightly while held and
/// springs back on release. Use on cards, tiles and action buttons.
///
/// The tap fires on release, like native buttons, and a selection haptic plays
/// when [haptic] is on. Scrolling a list that is full of pressables never
/// triggers taps or stuck "pressed" states, because a drag cancels the press.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final HitTestBehavior behavior;
  final bool haptic;
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.behavior = HitTestBehavior.opaque,
    this.haptic = false,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled
          ? (_) {
              _set(false);
              if (widget.haptic) Haptic.tap();
              widget.onTap!();
            }
          : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        // Press in quickly; release with a slightly longer, springier settle.
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// A number that counts up to [value] the first time it appears, then glides
/// from the old value to the new one whenever data changes. It never snaps
/// back to zero on refresh.
class CountUp extends StatefulWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;
  final String Function(num v)? format;
  const CountUp(this.value, {super.key, this.style, this.duration = Motion.slow, this.format});

  @override
  State<CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<CountUp> {
  double _from = 0;

  @override
  void didUpdateWidget(CountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _from = old.value.toDouble();
  }

  String _fmt(num v) => widget.format?.call(v) ?? v.round().toString();

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return Text(_fmt(widget.value), style: widget.style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _from, end: widget.value.toDouble()),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(_fmt(v), style: widget.style),
    );
  }
}

/// A rounded progress / distribution bar. It grows in the first time it
/// appears, then animates smoothly between values.
class AnimatedBar extends StatelessWidget {
  final double fraction; // 0..1
  final Color color;
  final Color track;
  final double height;
  final Duration duration;
  const AnimatedBar({
    super.key,
    required this.fraction,
    required this.color,
    this.track = BT.track,
    this.height = 8,
    this.duration = Motion.slow,
  });

  @override
  Widget build(BuildContext context) {
    final target = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final still = reduceMotion(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: height,
        color: track,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? target : 0, end: target),
          duration: still ? Duration.zero : duration,
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small badge (a count on a bell, a dot) that pops in with a springy scale
/// when it appears and pulses briefly when its value changes.
class BadgePop extends StatelessWidget {
  final Widget child;
  final bool visible;
  final Object? valueKey;
  const BadgePop({super.key, required this.child, required this.visible, this.valueKey});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Motion.exit,
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: visible
            ? KeyedSubtree(key: ValueKey(valueKey ?? 'on'), child: child)
            : const SizedBox.shrink(key: ValueKey('off')),
      );
}

/// Cross-fades between two states of the same slot (a label and a spinner,
/// "Assign" and "Change", an icon and a check). Sizes animate too, so
/// surrounding layout glides instead of jumping.
class AnimatedSwap extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const AnimatedSwap({super.key, required this.child, this.duration = Motion.fast});

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: duration,
        curve: Motion.move,
        alignment: Alignment.centerLeft,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Motion.curve,
          switchOutCurve: Motion.exit,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c),
          ),
          child: child,
        ),
      );
}

/// The slot that shows a screen's async state (skeleton → content, or → error).
///
/// When the *kind* of widget changes (e.g. [SkeletonList] → the content
/// column), the old one fades out quickly and then the new one fades up into
/// place, while the slot's height glides to the new size, so content
/// "settles in" instead of cutting in. A data refresh that returns the same kind
/// of widget updates in place with no animation, so pull-to-refresh never
/// flashes.
class ContentReveal extends StatelessWidget {
  final Widget child;
  const ContentReveal({super.key, required this.child});

  // Incoming waits for the first 30% of its 350ms (~105ms), and the leaving
  // layer runs the same curve backwards over 150ms, so it is fully gone at
  // 0.7 × 150 = 105ms, exactly when the new one starts. That gives a clean
  // fade-through with no ghosting. One curve for both directions also means the
  // transition never depends on rebuild timing.
  static const _curve = Interval(0.3, 1, curve: Easing.emphasizedDecelerate);

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.move,
      alignment: Alignment.topCenter,
      // Cards cast shadows past their bounds; clipping here would shave them.
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: Motion.base,
        reverseDuration: const Duration(milliseconds: 150),
        switchInCurve: _curve,
        switchOutCurve: _curve,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: _PixelSlide(animation: a, dy: 10, child: c),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [...previous, if (current != null) current],
        ),
        child: child,
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── loading

/// One shimmer clock for everything under it. All [SkeletonBox]es share a
/// single animation, so a screen full of placeholders sweeps in sync. The
/// highlight is painted with a gradient on each box, so there is no
/// `ShaderMask` and no extra compositing layer.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ShimmerScope(animation: _c, child: widget.child);
}

class _ShimmerScope extends InheritedWidget {
  final Animation<double> animation;
  const _ShimmerScope({required this.animation, required super.child});
  @override
  bool updateShouldNotify(_ShimmerScope old) => old.animation != animation;
}

/// A rounded placeholder block that shimmers while content loads.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  static const _base = Color(0xFFEDEADF);
  static const _hi = Color(0xFFF8F6EE);

  @override
  Widget build(BuildContext context) {
    final anim = Shimmer.of(context);
    final box = BorderRadius.circular(radius);
    if (anim == null) {
      return Container(width: width, height: height, decoration: BoxDecoration(color: _base, borderRadius: box));
    }
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        // Sweep a soft highlight band from left (-1) to right (+2).
        final x = -1.0 + 3.0 * anim.value;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: box,
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: const [_base, _hi, _base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A card-shaped skeleton (avatar or icon tile, two text lines, an optional pill)
/// that mirrors the app's list rows, so the layout "lands" before the data does.
class SkeletonCard extends StatelessWidget {
  final bool leading;
  final bool trailingPill;
  final double height;
  const SkeletonCard({super.key, this.leading = true, this.trailingPill = true, this.height = 74});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: BT.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BT.line),
        ),
        child: Row(children: [
          if (leading) ...[
            const SkeletonBox(width: 42, height: 42, radius: 21),
            const SizedBox(width: 13),
          ],
          const Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              FractionallySizedBox(widthFactor: 0.62, child: SkeletonBox(height: 13)),
              SizedBox(height: 9),
              FractionallySizedBox(widthFactor: 0.38, child: SkeletonBox(height: 10)),
            ]),
          ),
          if (trailingPill) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 62, height: 24, radius: 12),
          ],
        ]),
      );
}

/// Drop-in loading state for list screens: a column of shimmering cards,
/// cascading in. Replaces bare spinners so the screen keeps its shape while
/// data loads.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool leading;
  final bool trailingPill;
  final EdgeInsets padding;
  const SkeletonList(
      {super.key, this.count = 5, this.leading = true, this.trailingPill = true, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Padding(
          padding: padding,
          child: Column(children: [
            for (var i = 0; i < count; i++)
              FadeSlideIn(
                delay: Motion.stagger(i, stepMs: 60),
                offsetY: 8,
                scale: false,
                child: SkeletonCard(leading: leading, trailingPill: trailingPill),
              ),
          ]),
        ),
      );
}

// ───────────────────────────────────────────────────────────── switching

/// Cross-fades and gently lifts between switchable tab bodies, so changing tabs
/// feels fluid instead of an instant cut. The outgoing tab fades out quickly
/// and the incoming one rises in, so the two never fight for attention.
class TabSwitcher extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration duration;
  const TabSwitcher({super.key, required this.index, required this.child, this.duration = Motion.base});

  // Material "fade through". The outgoing tab is fully gone in the first ~35%
  // of the switch, and only then does the incoming tab fade and scale up. Two
  // overlapping cross-fades read as ghosting (old title showing through the
  // new one) and that is the jerky feel.
  static const _outEnd = 0.35;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return KeyedSubtree(key: ValueKey(index), child: child);
    return AnimatedSwitcher(
      duration: duration,
      // Same length both ways so the two halves stay in step.
      reverseDuration: duration,
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      transitionBuilder: (child, anim) {
        // AnimatedSwitcher re-runs this builder when the current tab becomes the
        // outgoing one, so the widget shape must be identical in both branches
        // (Fade → Scale → child). If it changed, Flutter would rebuild the
        // outgoing tab from scratch mid-fade and its entrance motion would
        // restart, which shows as a flicker.
        final incoming = child.key == ValueKey(index);
        final Animation<double> opacity;
        final Animation<double> scale;
        if (incoming) {
          final t = CurvedAnimation(parent: anim, curve: const Interval(_outEnd, 1, curve: Easing.emphasizedDecelerate));
          opacity = t;
          scale = Tween(begin: 0.97, end: 1.0).animate(t);
        } else {
          // Outgoing: anim runs 1 → 0, so it has finished fading by 1 - _outEnd.
          opacity = CurvedAnimation(parent: anim, curve: const Interval(1 - _outEnd, 1, curve: Curves.easeOut));
          scale = const AlwaysStoppedAnimation(1.0);
        }
        return FadeTransition(opacity: opacity, child: ScaleTransition(scale: scale, child: child));
      },
      // Every layer keeps the same shape (keyed Positioned → IgnorePointer →
      // child) whether it is current or leaving. Then the tab that just lost
      // focus keeps its element and state while it fades, and doesn't get
      // rebuilt and replay its entrance. Taps only reach the current tab.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        children: <Widget>[
          for (final c in previousChildren)
            Positioned.fill(key: c.key, child: IgnorePointer(child: c)),
          if (currentChild != null)
            Positioned.fill(key: currentChild.key, child: IgnorePointer(ignoring: false, child: currentChild)),
        ],
      ),
      child: KeyedSubtree(key: ValueKey(index), child: child),
    );
  }
}

// ───────────────────────────────────────────────────────────── routes

/// The app-wide route transition.
///
/// * **iOS / macOS:** the native Cupertino slide, which keeps the
///   **edge-swipe-back gesture**. A custom fade there would silently break it,
///   and that is the gesture iPhone users rely on most.
/// * **Android and others:** Material 3's fade-forwards transition. The new
///   page slides in from the right while fading up, and the old page drifts left
///   and dims, with Android's predictive back on supported versions.
PageTransitionsTheme appPageTransitions() => const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(backgroundColor: BT.bg),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(backgroundColor: BT.bg),
      TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(backgroundColor: BT.bg),
    });

/// Bottom sheets rise with an emphasized decelerate and leave quickly.
const sheetMotion = AnimationStyle(
  duration: Duration(milliseconds: 420),
  reverseDuration: Duration(milliseconds: 240),
  curve: Easing.emphasizedDecelerate,
  reverseCurve: Easing.emphasizedAccelerate,
);
