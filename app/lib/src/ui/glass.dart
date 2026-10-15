// The look since 0.5: a dark page lit from the top by the theme's colour,
// frosted-glass panels with big round corners and a thin light edge, pill
// rows and round glass buttons.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

extension GlassColors on ColorScheme {
  bool get isDark => brightness == Brightness.dark;

  /// A glass panel's fill.
  Color get glass => isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.55);

  /// Its thin edge.
  Color get glassEdge => isDark ? Colors.white.withValues(alpha: 0.13) : Colors.black.withValues(alpha: 0.08);
}

/// Behind every page: the background, with the accent glowing at the top.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glow = scheme.isDark ? 0.34 : 0.16;
    RadialGradient light(Alignment centre, double radius, double alpha) => RadialGradient(
          center: centre,
          radius: radius,
          colors: [scheme.primary.withValues(alpha: alpha), scheme.primary.withValues(alpha: 0)],
        );
    return ColoredBox(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: light(const Alignment(0.75, -1.15), 1.3, glow)),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: light(const Alignment(-1.2, -0.35), 0.9, glow * 0.45)),
          child: child,
        ),
      ),
    );
  }
}

/// Page changes paint the [Backdrop] under each page, so pages can be
/// see-through (the theme's scaffold colour is transparent).
class BackdropTransitions extends FadeForwardsPageTransitionsBuilder {
  const BackdropTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      super.buildTransitions(route, context, animation, secondaryAnimation, Backdrop(child: child));
}

/// A frosted-glass panel. [blur] frosts what's behind it: it costs, so it's
/// for the few panels that float over pictures, not for every row.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = false,
    this.padding = EdgeInsets.zero,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final double radius;
  final bool blur;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final corners = BorderRadius.circular(radius);
    Widget panel = Material(
      color: color ?? scheme.glass,
      shape: RoundedRectangleBorder(borderRadius: corners, side: BorderSide(color: scheme.glassEdge)),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        // A sheen from the top left, as light catches the edge of glass.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: scheme.isDark ? 0.07 : 0.2), Colors.white.withValues(alpha: 0)],
          ),
        ),
        child: onTap == null && onLongPress == null
            ? Padding(padding: padding, child: child)
            : InkWell(onTap: onTap, onLongPress: onLongPress, child: Padding(padding: padding, child: child)),
      ),
    );
    if (blur) {
      panel = ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: panel),
      );
    }
    return panel;
  }
}

/// A few settings or rows on one glass card.
class GlassGroup extends StatelessWidget {
  const GlassGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Glass(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

/// A round glass button with an icon: back, close, more.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.color,
    this.blur = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final bool blur;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: tooltip,
          child: Glass(
            radius: size / 2,
            blur: blur,
            onTap: onPressed,
            child: SizedBox.square(dimension: size, child: Icon(icon, size: size * 0.5, color: color)),
          ),
        ),
      );
}

/// A small label for pictures and bright tiles: "🎧 128 songs".
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: white, fontWeight: FontWeight.w500);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: white), const SizedBox(width: 5)],
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

/// The colours of the big square tiles: the accent, then the highlight.
List<Color> tileColours(ColorScheme scheme, int i) {
  final base = i.isEven ? scheme.primary : scheme.secondary;
  final hsl = HSLColor.fromColor(base);
  return [
    hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 0.85)).toColor(),
    hsl.withLightness((hsl.lightness - 0.06).clamp(0.12, 1.0)).toColor(),
  ];
}
