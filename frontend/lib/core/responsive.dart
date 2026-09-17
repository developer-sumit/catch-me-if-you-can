import 'package:flutter/material.dart';

abstract final class Breakpoints {
  static const compact = 600.0;
  static const medium = 905.0;
  static const expanded = 1240.0;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => screenWidth < Breakpoints.compact;
  bool get isMedium =>
      screenWidth >= Breakpoints.compact && screenWidth < Breakpoints.medium;
  bool get isExpanded => screenWidth >= Breakpoints.medium;

  EdgeInsets get pagePadding => EdgeInsets.symmetric(
        horizontal: isCompact
            ? 16
            : isMedium
                ? 28
                : 40,
        vertical: isCompact ? 16 : 24,
      );
}

/// Lays children out on a column grid that reflows by width. Unlike a fixed
/// [GridView], each row sizes to its tallest child, so cards with different
/// content lengths do not clip or leave dead space.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.children,
    this.compactColumns = 2,
    this.mediumColumns = 2,
    this.expandedColumns = 4,
    this.spacing = 12,
    super.key,
  });

  final List<Widget> children;
  final int compactColumns, mediumColumns, expandedColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < Breakpoints.compact
              ? compactColumns
              : constraints.maxWidth < Breakpoints.medium
                  ? mediumColumns
                  : expandedColumns;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final child in children)
                SizedBox(width: width.floorToDouble(), child: child),
            ],
          );
        },
      );
}

/// Two-column split on wide screens, stacked on narrow ones.
class SplitLayout extends StatelessWidget {
  const SplitLayout({
    required this.primary,
    required this.secondary,
    this.secondaryHeight = 420,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.gap = 20,
    super.key,
  });

  final Widget primary, secondary;
  final double secondaryHeight, gap;
  final int primaryFlex, secondaryFlex;

  @override
  Widget build(BuildContext context) {
    if (!context.isExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: secondaryHeight * 0.75, child: secondary),
          SizedBox(height: gap),
          primary,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: primaryFlex, child: primary),
        SizedBox(width: gap),
        Expanded(
          flex: secondaryFlex,
          child: SizedBox(height: secondaryHeight, child: secondary),
        ),
      ],
    );
  }
}
