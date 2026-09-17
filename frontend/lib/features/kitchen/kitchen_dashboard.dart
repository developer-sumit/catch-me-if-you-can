import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'add_food_screen.dart';

final kitchenDataProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiProvider);
  final values = await Future.wait([
    api.get('/dashboard/kitchen/stats'),
    api.get('/waste/my-logs'),
    api.get('/dashboard/predictions?days=7'),
  ]);
  return {
    'stats': Map<String, dynamic>.from(values[0]),
    'logs': List<Map<String, dynamic>>.from(
        (values[1] as List).map((e) => Map<String, dynamic>.from(e))),
    'forecast': Map<String, dynamic>.from(values[2]),
  };
});

class KitchenDashboard extends ConsumerWidget {
  const KitchenDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(kitchenDataProvider);
    return PageBody(
      eyebrow: 'Kitchen',
      title: _greeting(),
      subtitle: 'Log surplus, follow pickups, and plan tomorrow with less waste.',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(kitchenDataProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(kitchenDataProvider);
        await ref.read(kitchenDataProvider.future);
      },
      child: data.when(
        loading: () => const _KitchenSkeleton(),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () => ref.invalidate(kitchenDataProvider),
        ),
        data: (value) => _Content(data: value),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _Content extends ConsumerWidget {
  const _Content({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = data['stats'] as Map<String, dynamic>;
    final logs = data['logs'] as List<Map<String, dynamic>>;
    final forecast = data['forecast'] as Map<String, dynamic>;
    final tokens = context.tokens;

    final total = _number(stats['totalQuantity']);
    final redistributed = _number(stats['redistributedQuantity']);
    final rescueRate = total == 0 ? 0.0 : (redistributed / total).clamp(0, 1);

    final sections = <Widget>[
      ResponsiveGrid(
        children: [
          MetricCard(
            label: 'Logged overall',
            value: _format(total),
            unit: 'kg',
            icon: Icons.inventory_2_outlined,
          ),
          MetricCard(
            label: 'Redistributed',
            value: _format(redistributed),
            unit: 'kg',
            icon: Icons.recycling_rounded,
            tint: tokens.positive,
            footnote: total == 0
                ? null
                : '${(rescueRate * 100).round()}% of total logged',
          ),
          MetricCard(
            label: 'Awaiting pickup',
            value: '${_number(stats['totalPending']).round()}',
            icon: Icons.schedule_rounded,
            tint: tokens.caution,
          ),
          MetricCard(
            label: 'Forecast accuracy',
            value: '${(_number(forecast['accuracy']) * 100).round()}',
            unit: '%',
            icon: Icons.auto_graph_rounded,
            tint: tokens.info,
          ),
        ],
      ),
      _PrepSheet(forecast: forecast),
      _RecentLogs(logs: logs),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in stagger(sections)) ...[
          section,
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// The forecast, expressed as a single decision rather than a paragraph of
/// numbers: which dish to scale back, and by how much.
class _PrepSheet extends StatelessWidget {
  const _PrepSheet({required this.forecast});
  final Map<String, dynamic> forecast;

  @override
  Widget build(BuildContext context) {
    final predictions = forecast['predictions'] as List?;
    final tomorrow = predictions != null && predictions.isNotEmpty
        ? Map<String, dynamic>.from(predictions.first as Map)
        : null;
    final tokens = context.tokens;

    if (tomorrow == null) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_outlined, color: tokens.inkSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Log a few more days of surplus and a prep forecast will appear here.',
                style: context.text.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final byFood = Map<String, dynamic>.from(tomorrow['predictions'] as Map);
    final ranked = byFood.entries
        .map((e) => MapEntry(e.key, (e.value as num).toDouble()))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final peak = ranked.first.value;

    return AppCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 20, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Prep sheet for ${tomorrow['dayOfWeek']}',
                    style: context.text.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Expected surplus if you cook the same volume as usual.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 18),
          for (final entry in ranked.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(foodEmoji(entry.key),
                      style: const TextStyle(fontSize: 17)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 84,
                    child: Text(
                      foodLabel(entry.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: peak == 0 ? 0 : entry.value / peak,
                        minHeight: 8,
                        backgroundColor: tokens.hairline,
                        color: entry == ranked.first
                            ? context.colors.primary
                            : context.colors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_format(entry.value)} kg',
                    style: context.text.labelMedium,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Trimming ${foodLabel(ranked.first.key).toLowerCase()} is the single '
            'biggest lever for ${tomorrow['dayOfWeek']}.',
            style: context.text.bodySmall?.copyWith(color: tokens.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _RecentLogs extends ConsumerWidget {
  const _RecentLogs({required this.logs});
  final List<Map<String, dynamic>> logs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = logs.take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Recent logs',
          subtitle: logs.isEmpty
              ? null
              : '${logs.length} entr${logs.length == 1 ? 'y' : 'ies'} on record',
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: logs.isEmpty
              ? AppEmptyState(
                  icon: Icons.restaurant_rounded,
                  title: 'Nothing logged yet',
                  message:
                      'Publish your first surplus batch and nearby NGOs can '
                      'claim it within minutes.',
                  action: FilledButton.icon(
                    onPressed: () async {
                      final created = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const AddFoodScreen()),
                      );
                      if (created == true) {
                        ref.invalidate(kitchenDataProvider);
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Log surplus'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 74,
                    color: context.tokens.hairline,
                  ),
                  itemBuilder: (context, index) {
                    final log = shown[index];
                    return ListTile(
                      leading: FoodGlyph(log['foodType']),
                      title: Text(foodLabel(log['foodType'])),
                      subtitle: Text(
                        '${_format(_number(log['quantity']))} ${log['unit']} · '
                        '${_relativeDate(log['logDate'])}',
                      ),
                      trailing: StatusBadge('${log['status']}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _KitchenSkeleton extends StatelessWidget {
  const _KitchenSkeleton();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveGrid(
            children: List.generate(
                4, (_) => const SkeletonCard(lines: 2, height: 128)),
          ),
          const SizedBox(height: 20),
          const SkeletonCard(lines: 5),
          const SizedBox(height: 20),
          const SkeletonCard(lines: 6),
        ],
      );
}

double _number(Object? value) => switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

/// Whole numbers stay whole; fractions keep one decimal. `12.0 kg` reads as
/// machine output, `12 kg` reads as a measurement.
String _format(double value) =>
    value == value.roundToDouble() ? value.round().toString()
        : value.toStringAsFixed(1);

String _relativeDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '');
  if (date == null) return 'Date unknown';
  final today = DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Yesterday',
    < 7 => '$days days ago',
    _ => DateFormat.MMMd().format(date),
  };
}
