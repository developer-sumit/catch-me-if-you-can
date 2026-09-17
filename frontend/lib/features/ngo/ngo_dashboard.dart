import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'claim_stage.dart';
import 'delivery_tracker.dart';

final ngoDataProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiProvider);
  final values = await Future.wait([
    api.get('/waste/available'),
    api.get('/dashboard/ngo/stats'),
    api.get('/claims/my-claims'),
  ]);
  return {
    'available': List<Map<String, dynamic>>.from(
        (values[0] as List).map((e) => Map<String, dynamic>.from(e))),
    'stats': Map<String, dynamic>.from(values[1]),
    'claims': List<Map<String, dynamic>>.from(
        (values[2] as List).map((e) => Map<String, dynamic>.from(e))),
  };
});

class NgoDashboard extends ConsumerWidget {
  const NgoDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(ngoDataProvider);
    return PageBody(
      eyebrow: 'NGO partner',
      title: 'Food available now',
      subtitle:
          'Reserve surplus from kitchens near you, then confirm the pickup '
          'once it is collected.',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(ngoDataProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(ngoDataProvider);
        await ref.read(ngoDataProvider.future);
      },
      child: data.when(
        loading: () => const _NgoSkeleton(),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () => ref.invalidate(ngoDataProvider),
        ),
        data: (value) => _NgoContent(data: value),
      ),
    );
  }
}

class _NgoContent extends StatelessWidget {
  const _NgoContent({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final items = data['available'] as List<Map<String, dynamic>>;
    final claims = data['claims'] as List<Map<String, dynamic>>;
    final stats = data['stats'] as Map<String, dynamic>;
    final tokens = context.tokens;
    final open = claims
        .where((claim) => !ClaimStage.isSettled(claim['status']))
        .length;

    final sections = <Widget>[
      ResponsiveGrid(
        children: [
          MetricCard(
            label: 'Available now',
            value: '${items.length}',
            icon: Icons.restaurant_rounded,
            footnote: items.isEmpty ? 'Nothing listed nearby' : 'Ready to claim',
          ),
          MetricCard(
            label: 'In progress',
            value: '$open',
            icon: Icons.local_shipping_outlined,
            tint: tokens.caution,
            footnote: open == 0 ? 'Nothing outstanding' : 'Being delivered',
          ),
          MetricCard(
            label: 'Pickups complete',
            value: '${_number(stats['totalCompleted']).round()}',
            icon: Icons.task_alt_rounded,
            tint: tokens.positive,
          ),
          MetricCard(
            label: 'Food rescued',
            value: _format(_number(stats['totalQuantitySaved'])),
            unit: 'kg',
            icon: Icons.volunteer_activism_rounded,
            tint: tokens.info,
          ),
        ],
      ),
      _NearbyFood(items: items),
      _ClaimsList(claims: claims),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in stagger(sections)) ...[
          section,
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _NearbyFood extends StatefulWidget {
  const _NearbyFood({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<_NearbyFood> createState() => _NearbyFoodState();
}

class _NearbyFoodState extends State<_NearbyFood> {
  String? _kitchenId;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Nearby surplus'),
          const AppCard(
            padding: EdgeInsets.zero,
            child: AppEmptyState(
              icon: Icons.location_searching_rounded,
              title: 'Nothing available right now',
              message:
                  'New surplus appears here as soon as a nearby kitchen '
                  'publishes it. Pull down to check again.',
            ),
          ),
        ],
      );
    }

    // Nearest first, so the most actionable pickup is the one you see.
    final sorted = [...widget.items]..sort((a, b) {
        final da = _number(a['distance']);
        final db = _number(b['distance']);
        if (a['distance'] == null || b['distance'] == null) return 0;
        return da.compareTo(db);
      });
    final filtered = _kitchenId == null
        ? sorted
        : sorted.where((item) => item['kitchenId'] == _kitchenId).toList();

    final selectedName = _kitchenId == null
        ? null
        : _kitchenName(sorted.firstWhere(
            (item) => item['kitchenId'] == _kitchenId,
            orElse: () => sorted.first,
          )['kitchen']);

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_kitchenId != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: const Icon(Icons.filter_alt_rounded, size: 16),
              label: Text('Filtered to $selectedName'),
              onDeleted: () => setState(() => _kitchenId = null),
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final item in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FoodCard(item: item),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Nearby surplus',
          subtitle: '${filtered.length} listing'
              '${filtered.length == 1 ? '' : 's'}, nearest first',
        ),
        SplitLayout(
          secondaryHeight: 520,
          primary: list,
          secondary: _FoodMap(
            items: widget.items,
            selectedKitchenId: _kitchenId,
            onKitchenSelected: (id) => setState(
              () => _kitchenId = _kitchenId == id ? null : id,
            ),
          ),
        ),
      ],
    );
  }
}

class _FoodMap extends ConsumerWidget {
  const _FoodMap({
    required this.items,
    required this.selectedKitchenId,
    required this.onKitchenSelected,
  });
  final List<Map<String, dynamic>> items;
  final String? selectedKitchenId;
  final ValueChanged<String> onKitchenSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitchens = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final kitchen = Map<String, dynamic>.from(item['kitchen']);
      if (kitchen['latitude'] != null && kitchen['longitude'] != null) {
        kitchens['${kitchen['id']}'] = kitchen;
      }
    }
    final user = ref.watch(authProvider).valueOrNull;
    final fallback = user?.latitude != null && user?.longitude != null
        ? LatLng(user!.latitude!, user.longitude!)
        : const LatLng(28.6139, 77.2090);
    final center = kitchens.isEmpty
        ? fallback
        : LatLng(
            _number(kitchens.values.first['latitude']),
            _number(kitchens.values.first['longitude']),
          );
    final scheme = context.colors;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tokens.hairline),
      ),
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 12,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.soulserve.app',
              ),
              MarkerLayer(
                markers: [
                  if (user?.latitude != null && user?.longitude != null)
                    Marker(
                      point: LatLng(user!.latitude!, user.longitude!),
                      width: 22,
                      height: 22,
                      child: Tooltip(
                        message: 'Your location',
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.tertiary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final entry in kitchens.entries)
                    Marker(
                      point: LatLng(
                        _number(entry.value['latitude']),
                        _number(entry.value['longitude']),
                      ),
                      width: 116,
                      height: 44,
                      child: _MapPin(
                        label: _kitchenName(entry.value),
                        selected: entry.key == selectedKitchenId,
                        onTap: () => onKitchenSelected(entry.key),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: context.tokens.raised.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '© OpenStreetMap',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.tokens.raised.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.tokens.hairline),
              ),
              child: Text(
                'Tap a kitchen to filter',
                style: context.text.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled pin. A bare icon gives no clue which kitchen it belongs to until
/// it is hovered, which does not exist on touch.
class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final background = selected ? scheme.primary : context.tokens.raised;
    final foreground = selected ? scheme.onPrimary : context.tokens.ink;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? scheme.primary : context.tokens.hairline,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_rounded, size: 13, color: foreground),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: selected ? scheme.primary : context.tokens.ink,
          ),
        ],
      ),
    );
  }
}

class _FoodCard extends ConsumerStatefulWidget {
  const _FoodCard({required this.item});
  final Map<String, dynamic> item;

  @override
  ConsumerState<_FoodCard> createState() => _FoodCardState();
}

class _FoodCardState extends ConsumerState<_FoodCard> {
  bool _claiming = false;

  Future<void> _claim() async {
    setState(() => _claiming = true);
    try {
      await ref.read(apiProvider).post('/claims/${widget.item['id']}/claim');
      ref.invalidate(ngoDataProvider);
      if (mounted) {
        showSuccess(context, 'Reserved. Confirm the pickup once collected.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final kitchen = Map<String, dynamic>.from(item['kitchen']);
    final created = DateTime.tryParse(item['createdAt']?.toString() ?? '');
    final age = created == null ? null : DateTime.now().difference(created);
    final tokens = context.tokens;

    // Freshness drives the decision to claim, so it gets colour and position
    // rather than being buried as one more grey detail line.
    final (freshLabel, freshColor) = switch (age?.inMinutes) {
      null => ('Age unknown', tokens.inkSoft),
      final minutes when minutes < 60 =>
        ('${minutes.clamp(1, 59)} min old', tokens.positive),
      final minutes when minutes < 240 =>
        ('${(minutes / 60).floor()}h old', tokens.positive),
      final minutes when minutes < 480 =>
        ('${(minutes / 60).floor()}h old', tokens.caution),
      final minutes => ('${(minutes / 60).floor()}h old', context.colors.error),
    };

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodGlyph(item['foodType'], size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _format(_number(item['quantity'])),
                          style: context.text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text('${item['unit']}',
                            style: context.text.titleSmall
                                ?.copyWith(color: tokens.inkSoft)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            foodLabel(item['foodType']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _kitchenName(kitchen),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: tokens.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: freshColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  freshLabel,
                  style: context.text.labelSmall?.copyWith(
                    color: freshColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InfoRow(
            icon: Icons.location_on_outlined,
            text: '${kitchen['address'] ?? 'Address unavailable'}'
                '${item['distance'] == null ? '' : '  ·  ${_format(_number(item['distance']))} km away'}',
            maxLines: 2,
          ),
          if ((item['notes'] ?? '').toString().isNotEmpty)
            InfoRow(
              icon: Icons.sticky_note_2_outlined,
              text: item['notes'].toString(),
              maxLines: 2,
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if ((kitchen['phone'] ?? '').toString().isNotEmpty)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.call_outlined,
                          size: 15, color: tokens.inkSoft),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${kitchen['phone']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _claiming ? null : _claim,
                icon: _claiming
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(_claiming ? 'Claiming…' : 'Claim'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClaimsList extends StatelessWidget {
  const _ClaimsList({required this.claims});
  final List<Map<String, dynamic>> claims;

  @override
  Widget build(BuildContext context) {
    // Deliveries still in motion come first: they are the ones with an action
    // attached. Finished ones fall to the bottom, newest first.
    final sorted = [...claims]..sort((a, b) {
        final byDone = (ClaimStage.isSettled(a['status']) ? 1 : 0)
            .compareTo(ClaimStage.isSettled(b['status']) ? 1 : 0);
        if (byDone != 0) return byDone;
        return '${b['claimedAt']}'.compareTo('${a['claimedAt']}');
      });
    final active =
        sorted.where((c) => !ClaimStage.isSettled(c['status'])).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Your deliveries',
          subtitle: sorted.isEmpty
              ? null
              : active.isEmpty
                  ? 'All caught up'
                  : '${active.length} in progress',
        ),
        if (sorted.isEmpty)
          const AppCard(
            padding: EdgeInsets.zero,
            child: AppEmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No deliveries yet',
              message:
                  'Claim a listing above and you can track it here from '
                  'pickup through to hand-over.',
            ),
          )
        else
          for (final claim in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ClaimCard(claim: claim),
            ),
      ],
    );
  }
}

class _ClaimCard extends ConsumerStatefulWidget {
  const _ClaimCard({required this.claim});
  final Map<String, dynamic> claim;

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  bool _advancing = false;

  Future<void> _advance(ClaimStage to) async {
    setState(() => _advancing = true);
    try {
      await ref.read(apiProvider).patch(
        '/claims/${widget.claim['id']}/status',
        {'status': to.api},
      );
      ref.invalidate(ngoDataProvider);
      if (mounted) showSuccess(context, '${to.label} recorded.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final waste = Map<String, dynamic>.from(claim['wasteLog']);
    final kitchen = Map<String, dynamic>.from(claim['kitchen']);
    final cancelled = ClaimStage.isCancelled(claim['status']);
    final stage = ClaimStage.fromApi(claim['status']);
    final next = cancelled ? null : stage.next;
    final tokens = context.tokens;

    final timestamps = {
      for (final value in ClaimStage.values)
        value: DateTime.tryParse('${claim[value.timestampKey]}'),
    };

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodGlyph(waste['foodType']),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${foodLabel(waste['foodType'])} · '
                      '${_format(_number(waste['quantity']))} ${waste['unit']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    Text(
                      'from ${_kitchenName(kitchen)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge('${claim['status']}'),
            ],
          ),
          if (!cancelled) ...[
            const SizedBox(height: 20),
            DeliveryTracker(current: stage, timestamps: timestamps),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: tokens.hairline),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  cancelled
                      ? 'This claim was cancelled. The food was returned to '
                          'the available list.'
                      : stage.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              if (next != null)
                FilledButton.icon(
                  onPressed: _advancing ? null : () => _advance(next),
                  icon: _advancing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(next.icon, size: 17),
                  label: Text(
                    context.isCompact ? next.short : next.action!,
                  ),
                )
              else if (!cancelled)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 17, color: tokens.positive),
                    const SizedBox(width: 6),
                    Text(
                      'Complete',
                      style: context.text.labelMedium
                          ?.copyWith(color: tokens.positive),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NgoSkeleton extends StatelessWidget {
  const _NgoSkeleton();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveGrid(
            children: List.generate(
                4, (_) => const SkeletonCard(lines: 2, height: 128)),
          ),
          const SizedBox(height: 24),
          const SkeletonCard(lines: 4),
          const SizedBox(height: 12),
          const SkeletonCard(lines: 4),
        ],
      );
}

String _kitchenName(Object? raw) {
  final kitchen = Map<String, dynamic>.from(raw as Map);
  final organization = '${kitchen['organization'] ?? ''}'.trim();
  return organization.isEmpty ? '${kitchen['name'] ?? 'Kitchen'}' : organization;
}

double _number(Object? value) => switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

String _format(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);
