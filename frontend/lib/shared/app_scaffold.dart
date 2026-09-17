import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/responsive.dart';
import '../core/theme.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/models/user.dart';
import '../features/camera/camera_screen.dart';
import '../features/kitchen/add_food_screen.dart';
import '../features/kitchen/kitchen_dashboard.dart';
import '../features/ngo/ngo_dashboard.dart';
import '../features/settings/settings_screen.dart';
import 'widgets.dart';

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);
  final IconData icon, selectedIcon;
  final String label;
}

const _destinations = [
  _Destination(
      Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
  _Destination(Icons.insights_outlined, Icons.insights_rounded, 'Insights'),
  _Destination(
      Icons.center_focus_weak_outlined, Icons.center_focus_strong_rounded,
      'Scan'),
  _Destination(Icons.tune_outlined, Icons.tune_rounded, 'Settings'),
];

/// The application shell. Tabs switch in place and keep their scroll position
/// instead of pushing routes, so the selected destination always reflects
/// what is on screen and back never unwinds through the tab history.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final isKitchen = user?.role == UserRole.kitchen;

    // The camera tab is built only while selected so the hardware is released
    // as soon as the user moves away from it.
    final body = _index == 2
        ? const CameraScreen(embedded: true)
        : IndexedStack(
            index: _index < 2 ? _index : 2,
            children: [
              isKitchen ? const KitchenDashboard() : const NgoDashboard(),
              const AnalyticsScreen(),
              const SettingsScreen(),
            ],
          );

    final showFab = isKitchen && _index == 0;
    final fab = showFab
        ? FloatingActionButton.extended(
            heroTag: 'primary-action',
            onPressed: () => _logSurplus(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Log surplus'),
          )
        : null;

    if (context.isExpanded) {
      return Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Row(
              children: [
                _Rail(
                  index: _index,
                  onSelect: _select,
                  extended: context.screenWidth >= Breakpoints.expanded,
                  onPrimaryAction:
                      showFab ? () => _logSurplus(context) : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      const _TopBar(),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const _TopBar(),
              Expanded(child: body),
            ],
          ),
        ),
      ),
      floatingActionButton: fab,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.tokens.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final destination in _destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _logSurplus(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddFoodScreen()),
    );
    if (created == true) ref.invalidate(kitchenDataProvider);
  }
}

class _Rail extends ConsumerWidget {
  const _Rail({
    required this.index,
    required this.onSelect,
    required this.extended,
    this.onPrimaryAction,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final bool extended;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: context.tokens.hairline)),
        ),
        child: NavigationRail(
          extended: extended,
          minExtendedWidth: 210,
          selectedIndex: index,
          onDestinationSelected: onSelect,
          labelType:
              extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
          leading: Padding(
            padding: EdgeInsets.fromLTRB(extended ? 16 : 0, 16, 0, 24),
            child: Align(
              alignment:
                  extended ? Alignment.centerLeft : Alignment.center,
              child: Brand(compact: !extended),
            ),
          ),
          destinations: [
            for (final destination in _destinations)
              NavigationRailDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: Text(destination.label),
                padding: const EdgeInsets.symmetric(vertical: 2),
              ),
          ],
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    extended ? 16 : 8, 16, extended ? 16 : 8, 20),
                child: onPrimaryAction == null
                    ? const SizedBox.shrink()
                    : extended
                        ? FilledButton.icon(
                            onPressed: onPrimaryAction,
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Log surplus'),
                          )
                        : IconButton.filled(
                            tooltip: 'Log surplus',
                            onPressed: onPrimaryAction,
                            icon: const Icon(Icons.add_rounded),
                          ),
              ),
            ),
          ),
        ),
      );
}

/// A slim identity bar. On compact widths the brand sits here because the rail
/// that would otherwise carry it is not shown.
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final label = user == null
        ? ''
        : user.organization.isEmpty
            ? user.name
            : user.organization;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.isCompact ? 16 : 28,
        10,
        context.isCompact ? 8 : 20,
        6,
      ),
      child: Row(
        children: [
          if (!context.isExpanded) const Brand(),
          const Spacer(),
          if (user != null)
            _AccountButton(label: label, role: user.role, name: user.name),
        ],
      ),
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton({
    required this.label,
    required this.role,
    required this.name,
  });
  final String label, name;
  final UserRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        if (value == 'signout') ref.read(authProvider.notifier).logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: context.text.titleSmall),
              Text(
                role == UserRole.kitchen ? 'Food provider' : 'NGO partner',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.logout_rounded, size: 20),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!context.isCompact) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium,
                ),
              ),
            ] else
              const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: tokens.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Standard page frame: a scrollable, width-capped column with an editorial
/// header. Pages supply only their content.
class PageBody extends StatelessWidget {
  const PageBody({
    required this.title,
    required this.child,
    this.subtitle,
    this.eyebrow,
    this.actions,
    this.onRefresh,
    this.maxWidth = 1140,
    super.key,
  });

  final String title;
  final String? subtitle, eyebrow;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: MaxWidth(
        width: maxWidth,
        child: Padding(
          padding: context.pagePadding.copyWith(
            bottom: context.isExpanded ? 48 : 110,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: title,
                subtitle: subtitle,
                eyebrow: eyebrow,
                actions: actions,
              ),
              SizedBox(height: context.isCompact ? 20 : 28),
              child,
            ],
          ),
        ),
      ),
    );
    if (onRefresh == null) return content;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      edgeOffset: 8,
      child: content,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    required this.actions,
  });
  final String title;
  final String? subtitle, eyebrow;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: context.text.labelSmall?.copyWith(
              letterSpacing: 1.1,
              color: context.colors.primary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          style: context.isCompact
              ? context.text.headlineMedium
              : context.text.headlineLarge,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              subtitle!,
              style: context.text.bodyMedium?.copyWith(
                color: context.tokens.inkSoft,
              ),
            ),
          ),
        ],
      ],
    );
    if (actions == null || actions!.isEmpty) return heading;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 16),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
        ),
      ],
    );
  }
}
