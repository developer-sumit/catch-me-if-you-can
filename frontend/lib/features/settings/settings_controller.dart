import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CameraPreference { capture, realtime }

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.cameraPreference = CameraPreference.capture,
  });

  final ThemeMode themeMode;
  final CameraPreference cameraPreference;

  AppSettings copyWith({
    ThemeMode? themeMode,
    CameraPreference? cameraPreference,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        cameraPreference: cameraPreference ?? this.cameraPreference,
      );
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
    SettingsController.new);

class SettingsController extends AsyncNotifier<AppSettings> {
  static const _themeKey = 'appearance_theme';
  static const _cameraKey = 'camera_default_mode';

  @override
  Future<AppSettings> build() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _themeFromName(preferences.getString(_themeKey)),
      cameraPreference: preferences.getString(_cameraKey) == 'realtime'
          ? CameraPreference.realtime
          : CameraPreference.capture,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = AsyncData(
        (state.valueOrNull ?? const AppSettings()).copyWith(themeMode: mode));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, mode.name);
  }

  Future<void> setCameraPreference(CameraPreference preference) async {
    state = AsyncData(
      (state.valueOrNull ?? const AppSettings())
          .copyWith(cameraPreference: preference),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_cameraKey, preference.name);
  }

  static ThemeMode _themeFromName(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
