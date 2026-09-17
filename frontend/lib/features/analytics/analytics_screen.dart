import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/models/user.dart';

final analyticsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, UserRole>((ref, role) async {
  final api = ref.watch(apiProvider);
  if (role == UserRole.kitchen) {
    final values = await Future.wait([
      api.get('/dashboard/kitchen/stats'),
      api.get('/dashboard/kitchen/history?days=30'),
      api.get('/waste/my-logs'),
    ]);
    return {'stats': values[0], 'history': values[1], 'records': values[2]};
  }
  final values = await Future.wait([
    api.get('/dashboard/ngo/stats'),
    api.get('/claims/my-claims'),
  ]);
  return {'stats': values[0], 'records': values[1]};
});

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();
    final analytics = ref.watch(analyticsProvider(user.role));
    final isKitchen = user.role == UserRole.kitchen;

    return PageBody(
      eyebrow: 'Insights',
      title: isKitchen ? 'Kitchen performance' : 'Community impact',
      subtitle: isKitchen
          ? 'Where your surplus comes from, and how much of it reaches a plate.'
          : 'What you have rescued, and which pickups are still open.',
      onRefresh: () async {
        ref.invalidate(analyticsProvider(user.role));
        await ref.read(analyticsProvider(user.role).future);
      },
      child: analytics.when(
        loading: () => Column(
          children: [
            const SkeletonCard(lines: 6, height: 300),
            const SizedBox(height: 16),
            const SkeletonCard(lines: 6, height: 300),
          ],
        ),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () => ref.invalidate(analyticsProvider(user.role)),
        ),
        data: (data) => isKitchen
            ? _KitchenAnalytics(data: data)
            : _NgoAnalytics(data: data),
      ),
    );
  }
}

class _KitchenAnalytics extends StatelessWidget {
  const _KitchenAnalytics({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final stats = Map<String, dynamic>.from(data['stats']);
    final history = List<Map<String, dynamic>>.from(
      (data['history'] as List).map((item) => Map<String, dynamic>.from(item)),
    );
    final records = List<Map<String, dynamic>>.from(
      (data['records'] as List).map((item) => Map<String, dynamic>.from(item)),
    );
    final byType = <String, double>{
      for (final item in (stats['byType'] as List? ?? const []))
        item['foodType'].toString(): _number(item['total']),
    };
    final daily = <DateTime, double>{};
    for (final item in history) {
      final date = DateTime.tryParse('${item['logDate']}');
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      daily[day] = (daily[day] ?? 0) + _number(item['quantity']);
    }

    return _ChartStack(
      children: [
        _ChartCard(
          title: 'Where the surplus comes from',
          subtitle: 'Total kilograms logged, by food type',
          height: 320,
          child: _BarChart(values: byType, unit: 'kg'),
        ),
        _ChartCard(
          title: 'Redistribution pipeline',
          subtitle: 'Every log you have created, by current state',
          height: 130,
          child: _PipelineMeter(
            counts: _countBy(records, 'status'),
            stages: _wasteStages,
          ),
        ),
        _ChartCard(
          title: 'Daily volume',
          subtitle: 'Kilograms logged over the last 30 days',
          height: 320,
          child: _TrendChart(values: daily, unit: 'kg'),
        ),
      ],
    );
  }
}

class _NgoAnalytics extends StatelessWidget {
  const _NgoAnalytics({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final records = List<Map<String, dynamic>>.from(
      (data['records'] as List).map((item) => Map<String, dynamic>.from(item)),
    );
    final byFood = <String, double>{};
    final daily = <DateTime, double>{};
    for (final claim in records) {
      final waste = Map<String, dynamic>.from(claim['wasteLog']);
      final quantity = _number(waste['quantity']);
      byFood[waste['foodType'].toString()] =
          (byFood[waste['foodType'].toString()] ?? 0) + quantity;
      if (claim['status'] == 'completed') {
        final date = DateTime.tryParse('${claim['claimedAt']}');
        if (date == null) continue;
        final day = DateTime(date.year, date.month, date.day);
        daily[day] = (daily[day] ?? 0) + quantity;
      }
    }

    return _ChartStack(
      children: [
        _ChartCard(
          title: 'What you rescue most',
          subtitle: 'Total claimed kilograms, by food type',
          height: 320,
          child: _BarChart(values: byFood, unit: 'kg'),
        ),
        _ChartCard(
          title: 'Delivery pipeline',
          subtitle: 'Every claim you have made, by where it has reached',
          height: 150,
          child: _PipelineMeter(
            counts: _countBy(records, 'status'),
            stages: _claimStages,
          ),
        ),
        _ChartCard(
          title: 'Delivered over time',
          subtitle: 'Kilograms confirmed as collected, by day',
          height: 320,
          child: _TrendChart(values: daily, unit: 'kg'),
        ),
      ],
    );
  }
}

/// Charts stack full width rather than sitting two-up: a squeezed plot loses
/// its axis labels long before it saves any scrolling.
class _ChartStack extends StatelessWidget {
  const _ChartStack({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in stagger(children)) ...[
            child,
            const SizedBox(height: 16),
          ],
        ],
      );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.height,
  });
  final String title, subtitle;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, style: context.text.bodySmall),
            const SizedBox(height: 20),
            SizedBox(height: height, child: child),
          ],
        ),
      );
}

/// One series, one color. Coloring each bar differently would double-encode
/// the length that the bars already show.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.values, required this.unit});
  final Map<String, double> values;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Nothing to chart yet',
        message: 'Totals appear here once a few records exist.',
      );
    }
    final tokens = context.tokens;
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(7).toList();
    final scale = _niceScale(shown.first.value);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: scale.max,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: scale.interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: tokens.hairline, strokeWidth: 1),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => context.colors.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${foodLabel(shown[group.x].key)}\n',
              context.text.labelSmall!.copyWith(
                color: context.colors.onInverseSurface.withValues(alpha: 0.75),
              ),
              children: [
                TextSpan(
                  text: '${_format(rod.toY)} $unit',
                  style: context.text.labelMedium!.copyWith(
                    color: context.colors.onInverseSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: scale.interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _format(value),
                  textAlign: TextAlign.right,
                  style: context.text.labelSmall,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= shown.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    foodLabel(shown[index].key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < shown.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: shown[i].value,
                  width: 16,
                  color: tokens.series,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
              // Only the leader is labelled; the axis and tooltip carry the rest.
              showingTooltipIndicators: const [],
            ),
        ],
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
    );
  }
}

/// Pending -> claimed -> delivered is an ordered pipeline, not a set of
/// unrelated categories, so it reads as one meter on a single-hue ramp instead
/// of a pie. Counts are labelled directly, so color never carries meaning alone.
typedef _Stage = ({String key, String label});

/// Waste logs move pending -> claimed -> completed.
const _wasteStages = <_Stage>[
  (key: 'pending', label: 'Awaiting pickup'),
  (key: 'claimed', label: 'Claimed'),
  (key: 'completed', label: 'Delivered'),
];

/// Claims carry the full delivery progression.
const _claimStages = <_Stage>[
  (key: 'claimed', label: 'Reserved'),
  (key: 'picked_up', label: 'Picked up'),
  (key: 'out_for_delivery', label: 'Out for delivery'),
  (key: 'completed', label: 'Delivered'),
];

class _PipelineMeter extends StatelessWidget {
  const _PipelineMeter({required this.counts, required this.stages});
  final Map<String, double> counts;
  final List<_Stage> stages;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ramp = tokens.pipelineSteps(stages.length);
    final known = {for (final stage in stages) stage.key};
    // Anything the server reports outside the progression (a cancellation, a
    // status this build predates) still has to be in the denominator, or the
    // percentages quietly stop summing to 100.
    final other = counts.entries
        .where((entry) => !known.contains(entry.key))
        .fold<double>(0, (sum, entry) => sum + entry.value);
    final resolved = [
      for (var i = 0; i < stages.length; i++)
        (
          key: stages[i].key,
          label: stages[i].label,
          value: counts[stages[i].key] ?? 0,
          color: ramp[i],
        ),
      if (other > 0)
        (key: 'other', label: 'Other', value: other, color: tokens.inkSoft),
    ];
    final total = resolved.fold<double>(0, (sum, s) => sum + s.value);

    if (total == 0) {
      return const AppEmptyState(
        icon: Icons.donut_large_rounded,
        title: 'No records yet',
        message: 'The pipeline fills in as records move through it.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final visible = resolved.where((s) => s.value > 0).toList();
            final gaps = (visible.length - 1).clamp(0, 10) * 2.0;
            final usable = constraints.maxWidth - gaps;
            return Row(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Container(
                    width: usable * (visible[i].value / total),
                    height: 30,
                    decoration: BoxDecoration(
                      color: visible[i].color,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(i == 0 ? 8 : 2),
                        right:
                            Radius.circular(i == visible.length - 1 ? 8 : 2),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            for (final stage in resolved)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: stage.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(stage.label, style: context.text.bodySmall),
                  const SizedBox(width: 6),
                  Text(
                    '${stage.value.round()}'
                    '  ·  ${(stage.value / total * 100).round()}%',
                    style: context.text.labelMedium,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values, required this.unit});
  final Map<DateTime, double> values;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const AppEmptyState(
        icon: Icons.show_chart_rounded,
        title: 'No trend yet',
        message: 'A few days of records are needed before a line is useful.',
      );
    }
    final tokens = context.tokens;
    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final scale = _niceScale(
      entries.map((e) => e.value).reduce((a, b) => a > b ? a : b),
    );

    return LineChart(
      LineChartData(
        maxY: scale.max,
        minY: 0,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: scale.interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: tokens.hairline, strokeWidth: 1),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.colors.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${DateFormat.MMMd().format(entries[spot.x.toInt()].key)}\n',
                  context.text.labelSmall!.copyWith(
                    color:
                        context.colors.onInverseSurface.withValues(alpha: 0.75),
                  ),
                  children: [
                    TextSpan(
                      text: '${_format(spot.y)} $unit',
                      style: context.text.labelMedium!.copyWith(
                        color: context.colors.onInverseSurface,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          getTouchedSpotIndicator: (barData, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(color: tokens.inkSoft, strokeWidth: 1),
                FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 5,
                    color: tokens.series,
                    strokeWidth: 2,
                    strokeColor: tokens.raised,
                  ),
                ),
              ),
          ],
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: scale.interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _format(value),
                  textAlign: TextAlign.right,
                  style: context.text.labelSmall,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval:
                  entries.length > 6 ? (entries.length / 5).ceilToDouble() : 1,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat.MMMd().format(entries[index].key),
                    style: context.text.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            curveSmoothness: 0.22,
            preventCurveOverShooting: true,
            color: tokens.series,
            barWidth: 2,
            // A dot on every day is noise; only the latest point is marked.
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, bar) =>
                  spot.x == (entries.length - 1).toDouble(),
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4,
                color: tokens.series,
                strokeWidth: 2,
                strokeColor: tokens.raised,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tokens.series.withValues(alpha: 0.18),
                  tokens.series.withValues(alpha: 0.02),
                ],
              ),
            ),
            spots: [
              for (var i = 0; i < entries.length; i++)
                FlSpot(i.toDouble(), entries[i].value),
            ],
          ),
        ],
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
    );
  }
}

Map<String, double> _countBy(List<Map<String, dynamic>> records, String key) {
  final result = <String, double>{};
  for (final item in records) {
    final value = item[key]?.toString() ?? 'unknown';
    result[value] = (result[value] ?? 0) + 1;
  }
  return result;
}

double _number(Object? value) => switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

String _format(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);

/// Rounds an axis up to a whole-number top gridline. Without it fl_chart
/// labels the raw maximum (73.2) right on top of the nearest tick (70).
({double max, double interval}) _niceScale(double peak) {
  if (peak <= 0) return (max: 1, interval: 1);
  final rough = peak / 4;
  final magnitude =
      math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final normalized = rough / magnitude;
  final step = normalized <= 1
      ? 1.0
      : normalized <= 2
          ? 2.0
          : normalized <= 2.5
              ? 2.5
              : normalized <= 5
                  ? 5.0
                  : 10.0;
  final interval = step * magnitude;
  final top = (peak / interval).ceil() * interval;
  return (max: top <= peak ? top + interval : top, interval: interval);
}
