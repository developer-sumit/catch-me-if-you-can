import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A restrained page background: one soft bloom behind the header area instead
/// of a full-bleed gradient, so cards keep their edge against the canvas.
class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        gradient: RadialGradient(
          center: const Alignment(-0.8, -1.1),
          radius: 1.5,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.09),
              tokens.canvas,
            ),
            tokens.canvas,
          ],
          stops: const [0, 0.72],
        ),
      ),
      child: child,
    );
  }
}

class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420) + delay,
      curve: Interval(
        delay.inMilliseconds / (420 + delay.inMilliseconds),
        1,
        curve: Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: child,
        ),
      ),
    );
  }
}

/// Staggers [FadeSlideIn] over a list so sections arrive in reading order.
List<Widget> stagger(List<Widget> children, {int stepMs = 55, int cap = 6}) => [
      for (var i = 0; i < children.length; i++)
        FadeSlideIn(
          delay: Duration(milliseconds: math.min(i, cap) * stepMs),
          child: children[i],
        ),
    ];

class Brand extends StatelessWidget {
  const Brand({this.compact = false, super.key});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.eco_rounded, size: 19, color: scheme.onPrimary),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Text(
            'Soul Serve',
            style: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ],
    );
  }
}

class MaxWidth extends StatelessWidget {
  const MaxWidth({required this.child, this.width = 1140, super.key});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: child,
        ),
      );
}

/// A card with consistent inner padding, and ink feedback when tappable.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding,
    this.onTap,
    this.highlight = false,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Draws a tinted border, for the one card on a page that should lead.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final body = Padding(
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlight
              ? context.colors.primary.withValues(alpha: 0.35)
              : tokens.hairline,
        ),
      ),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: body,
            ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.subtitle, this.action, super.key});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleLarge),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: context.text.bodySmall),
                    ),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

/// A number-first metric tile: the value leads, the label supports it, and the
/// icon is a quiet tinted square rather than a competing circular avatar.
class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.unit,
    this.tint,
    this.footnote,
    super.key,
  });
  final String label, value;
  final String? unit, footnote;
  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? context.colors.primary;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          // The label sits on its own line: beside the icon, a single long
          // word such as "REDISTRIBUTED" breaks mid-word in a narrow tile.
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: context.text.titleSmall
                      ?.copyWith(color: context.tokens.inkSoft),
                ),
              ],
            ],
          ),
          // Reserved whether or not a footnote exists, so tiles sharing a row
          // end up the same height.
          SizedBox(
            height: 18,
            child: footnote == null
                ? null
                : Text(
                    footnote!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Maps the API's raw status strings to a human label and a semantic color, so
/// no screen renders `pending` verbatim.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {this.dense = false, super.key});
  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Every badge pairs an icon and a word with its colour, so the delivery
    // stages that share a hue stay distinguishable.
    final (label, color, icon) = switch (status.toLowerCase()) {
      'pending' => ('Awaiting pickup', tokens.caution, Icons.schedule_rounded),
      'claimed' => ('Reserved', tokens.info, Icons.bookmark_added_rounded),
      'picked_up' => ('Picked up', tokens.info, Icons.inventory_2_rounded),
      'out_for_delivery' =>
        ('Out for delivery', tokens.caution, Icons.local_shipping_rounded),
      'completed' => ('Delivered', tokens.positive, Icons.task_alt_rounded),
      'expired' => ('Expired', context.colors.error, Icons.timer_off_rounded),
      'cancelled' => ('Cancelled', tokens.inkSoft, Icons.cancel_rounded),
      _ => (_sentence(status.replaceAll('_', ' ')), tokens.inkSoft,
          Icons.circle),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
    super.key,
  });
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 26, color: context.colors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// Shows a readable headline and keeps the raw exception behind a disclosure,
/// rather than printing `Exception: ...` as the page content.
class AppErrorState extends StatelessWidget {
  const AppErrorState({required this.error, this.onRetry, super.key});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final detail = error.toString().replaceFirst('Exception: ', '');
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 30, color: context.colors.error),
          const SizedBox(height: 14),
          Text('We could not load this', style: context.text.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A shimmering placeholder block. Loading a dashboard behind a single centred
/// spinner hides the page shape; these keep the layout stable.
class Skeleton extends StatefulWidget {
  const Skeleton({
    this.height = 16,
    this.width,
    this.radius = 8,
    super.key,
  });
  final double height, radius;
  final double? width;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.tokens.hairline;
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(
            alpha: still ? 0.7 : 0.45 + _controller.value * 0.4,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({this.lines = 3, this.height, super.key});
  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Skeleton(height: 12, width: 90),
              const SizedBox(height: 14),
              const Skeleton(height: 26, width: 140, radius: 10),
              for (var i = 0; i < lines - 1; i++) ...[
                const SizedBox(height: 10),
                Skeleton(height: 12, width: i.isEven ? 220 : 160),
              ],
            ],
          ),
        ),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.icon, required this.text, this.maxLines = 1,
      super.key});
  final IconData icon;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 15, color: context.tokens.inkSoft),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ),
          ],
        ),
      );
}

/// Emoji plate for a food type, sized for a leading slot.
class FoodGlyph extends StatelessWidget {
  const FoodGlyph(this.foodType, {this.size = 44, super.key});
  final Object? foodType;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(
          foodEmoji(foodType),
          style: TextStyle(fontSize: size * 0.46),
        ),
      );
}

String foodEmoji(Object? type) =>
    const {
      'rice': '🍚',
      'dal': '🥣',
      'roti': '🫓',
      'vegetables': '🥗',
      'curry': '🍛',
      'biryani': '🍛',
      'bread': '🍞',
      'fruits': '🍎',
      'dairy': '🥛',
    }[type?.toString()] ??
    '🍽️';

String foodLabel(Object? value) => _sentence(value?.toString() ?? 'food');

String _sentence(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';

void showError(BuildContext context, Object error) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error.toString().replaceFirst('Exception: ', ''),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
        backgroundColor: scheme.errorContainer,
      ),
    );
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
