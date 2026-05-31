import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/album_customization.dart';
import '../models/sort_method.dart';

/// Persists everything the user can customize: the album view mode, the sort
/// method, the manual album order, and per-album overrides (rename/hide).
class SettingsService {
  static const _kViewMode = 'view_mode';
  static const _kSort = 'album_sort';
  static const _kOrder = 'album_order';
  static const _kCustomizations = 'album_customizations';
  static const _kShowHidden = 'show_hidden';
  static const _kThemeMode = 'theme_mode';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<AlbumViewMode> loadViewMode() async =>
      AlbumViewMode.fromName((await _p).getString(_kViewMode));

  Future<void> saveViewMode(AlbumViewMode mode) async =>
      (await _p).setString(_kViewMode, mode.name);

  Future<AlbumSort> loadSort() async =>
      AlbumSort.fromName((await _p).getString(_kSort));

  Future<void> saveSort(AlbumSort sort) async =>
      (await _p).setString(_kSort, sort.name);

  Future<bool> loadShowHidden() async =>
      (await _p).getBool(_kShowHidden) ?? false;

  Future<void> saveShowHidden(bool value) async =>
      (await _p).setBool(_kShowHidden, value);

  Future<ThemeMode> loadThemeMode() async {
    final name = (await _p).getString(_kThemeMode);
    return ThemeMode.values.firstWhere((m) => m.name == name,
        orElse: () => ThemeMode.system);
  }

  Future<void> saveThemeMode(ThemeMode mode) async =>
      (await _p).setString(_kThemeMode, mode.name);

  /// The user's manual album order, as a list of album ids.
  Future<List<String>> loadOrder() async =>
      (await _p).getStringList(_kOrder) ?? const [];

  Future<void> saveOrder(List<String> ids) async =>
      (await _p).setStringList(_kOrder, ids);

  Future<Map<String, AlbumCustomization>> loadCustomizations() async {
    final raw = (await _p).getString(_kCustomizations);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(
        key, AlbumCustomization.fromJson(value as Map<String, dynamic>)));
  }

  Future<void> saveCustomizations(
      Map<String, AlbumCustomization> customizations) async {
    final encoded = jsonEncode(customizations.map(
        (key, value) => MapEntry(key, value.toJson())));
    await (await _p).setString(_kCustomizations, encoded);
  }
}
