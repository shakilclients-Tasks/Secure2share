import 'package:flutter/material.dart';

import 'recent_file_store.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController(this._store);

  static const String _settingKey = 'appThemeMode';

  final RecentFileStore _store;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> init() async {
    final savedMode = await _store.getSetting(_settingKey);
    _themeMode = _themeModeFromValue(savedMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _store.setSetting(_settingKey, _valueFromThemeMode(mode));
  }

  ThemeMode _themeModeFromValue(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _valueFromThemeMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
