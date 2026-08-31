import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The app's motion language — one place for durations & curves so every
/// screen animates with the same rhythm. Kept dependency-free (pure Flutter).
class Motion {
  static const fast = Duration(milliseconds: 200);
  static const base = Duration(milliseconds: 380);
  static const slow = Duration(milliseconds: 620);
  static const curve = Curves.easeOutCubic;

  /// Stagger step for list reveals, capped so long lists never feel sluggish.
  static Duration stagger(int index, {int stepMs = 55, int maxMs = 440}) =>
      Duration(milliseconds: (index * stepMs).clamp(0, maxMs));
}

/// Whether the platform asked us to reduce motion (accessibility).
bool _reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Fade + slide-up entrance. Give successive items an increasing [delay]
/// (see [Motion.stagger]) for a staggered reveal.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.base,
    this.offsetY = 16,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (_reduceMotion(context)) {
      _c.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Motion.curve);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Tactile press feedback: the child scales down slightly while held, then
/// springs back. Use on cards, tiles and action buttons.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final HitTestBehavior behavior;
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.behavior = HitTestBehavior.opaque,
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
              widget.onTap!();
            }
          : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A number that counts up from zero to [value] on first build — for dashboard
/// stats and headline figures. [format] lets you render %, currency, etc.
class CountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;
  final String Function(num v)? format;
  const CountUp(
    this.value, {
    super.key,
    this.style,
    this.duration = Motion.slow,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) {
      return Text(format?.call(value) ?? value.round().toString(), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) =>
          Text(format?.call(v) ?? v.round().toString(), style: style),
    );
  }
}

/// A rounded progress/distribution bar whose fill grows in on first build.
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
    final target = fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(children: [
        Container(height: height, color: track),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _reduceMotion(context) ? target : target),
          duration: _reduceMotion(context) ? Duration.zero : duration,
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => FractionallySizedBox(
            widthFactor: v,
            child: Container(height: height, color: color),
          ),
        ),
      ]),
    );
  }
}

/// Cross-fades + gently slides between switchable tab bodies. Drop-in for the
/// role dashboards so changing tabs feels fluid instead of an instant cut.
class TabSwitcher extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration duration;
  const TabSwitcher({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          children: <Widget>[
            ...previousChildren.map((c) => Positioned.fill(child: c)),
            if (currentChild != null) Positioned.fill(child: currentChild),
          ],
        ),
        child: KeyedSubtree(key: ValueKey(index), child: child),
      );
}

/// Modern route transition: a soft fade combined with a subtle scale-up, used
/// app-wide via [ThemeData.pageTransitionsTheme] so every pushed screen feels
/// smooth rather than doing the dated platform slide.
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final t = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        builder: (_, child) =>
            Transform.scale(scale: 0.98 + 0.02 * t.value, child: child),
        child: child,
      ),
    );
  }
}
