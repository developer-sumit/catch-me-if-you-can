import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/models/user.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final user = ref.watch(authProvider).valueOrNull;

    return PageBody(
      eyebrow: 'Settings',
      title: 'Preferences',
      subtitle: 'Appearance and capture options apply to this device only.',
      maxWidth: 780,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in stagger([
            if (user != null) _AccountCard(user: user),
            _SettingsSection(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              description: 'System follows your device light and dark setting.',
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded, size: 18),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded, size: 18),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded, size: 18),
                    label: Text('Dark'),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) => ref
                    .read(settingsProvider.notifier)
                    .setThemeMode(selection.first),
              ),
            ),
            _SettingsSection(
              icon: Icons.camera_alt_outlined,
              title: 'Camera',
              description: 'Capture takes one photo. Real-time keeps labelling '
                  'the live view, which uses more battery.',
              child: SegmentedButton<CameraPreference>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: CameraPreference.capture,
                    icon: Icon(Icons.camera_rounded, size: 18),
                    label: Text('Capture'),
                  ),
                  ButtonSegment(
                    value: CameraPreference.realtime,
                    icon: Icon(Icons.motion_photos_on_rounded, size: 18),
                    label: Text('Real-time'),
                  ),
                ],
                selected: {settings.cameraPreference},
                onSelectionChanged: (selection) => ref
                    .read(settingsProvider.notifier)
                    .setCameraPreference(selection.first),
              ),
            ),
            const _SettingsSection(
              icon: Icons.shield_outlined,
              title: 'Privacy',
              description:
                  'Food recognition runs entirely on this device. Photos are '
                  'never uploaded, and the recognition history stores labels '
                  'only.',
            ),
          ])) ...[
            section,
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.user});
  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = user.name.trim().isEmpty
        ? '?'
        : user.name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials,
                  style: context.text.titleMedium?.copyWith(
                    color: context.colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.organization.isEmpty ? user.name : user.organization,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  user.role == UserRole.kitchen ? 'Provider' : 'NGO',
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (user.address.isNotEmpty) ...[
            const SizedBox(height: 16),
            InfoRow(
              icon: Icons.location_on_outlined,
              text: user.address,
              maxLines: 2,
            ),
          ],
          if (user.phone.isNotEmpty)
            InfoRow(icon: Icons.call_outlined, text: user.phone),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need your email and password to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authProvider.notifier).logout();
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.description,
    this.child,
  });

  final IconData icon;
  final String title, description;
  final Widget? child;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: context.tokens.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(description, style: context.text.bodySmall),
            if (child != null) ...[
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: child),
            ],
          ],
        ),
      );
}
