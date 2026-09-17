import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/settings/settings_controller.dart';
import 'shared/app_scaffold.dart';
import 'shared/widgets.dart';

void main() => runApp(const ProviderScope(child: SoulServeApp()));

class SoulServeApp extends ConsumerWidget {
  const SoulServeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soul Serve',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings?.themeMode ?? ThemeMode.system,
      home: auth.when(
        loading: () => const _Splash(),
        error: (error, _) => AuthScreen(initialError: error.toString()),
        data: (user) => user == null ? const AuthScreen() : const AppShell(),
      ),
    );
  }
}

/// Shown while the stored session is validated. It carries the brand rather
/// than a bare spinner, so a cold start does not flash an empty screen.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackground(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Brand(),
                const SizedBox(height: 28),
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    borderRadius: BorderRadius.circular(999),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
