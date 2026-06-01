import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/album_customization.dart';
import '../models/media_stack.dart';
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
  static const _kBinMeta = 'bin_meta';
  static const _kBinPaths = 'bin_paths';
  static const _kBinRetention = 'bin_retention_days';
  static const _kHideSmallKb = 'hide_small_media_kb';
  static const _kStacks = 'media_stacks';
  static const _kAutoStack = 'auto_stack_by_name';

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

  /// Soft recycle-bin: asset id → deletion timestamp (epoch ms).
  Future<Map<String, int>> loadBinnedAt() async {
    final raw = (await _p).getString(_kBinMeta);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  Future<void> saveBinnedAt(Map<String, int> binnedAt) async {
    await (await _p).setString(_kBinMeta, jsonEncode(binnedAt));
  }

  /// Soft recycle-bin: asset id → the folder (MediaStore relative path) it was
  /// binned from, used to keep each album's item count accurate.
  Future<Map<String, String>> loadBinnedPaths() async {
    final raw = (await _p).getString(_kBinPaths);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }

  Future<void> saveBinnedPaths(Map<String, String> paths) async {
    await (await _p).setString(_kBinPaths, jsonEncode(paths));
  }

  /// Days before binned items auto-delete; 0 means "never". Default 30.
  Future<int> loadBinRetentionDays() async =>
      (await _p).getInt(_kBinRetention) ?? 30;

  Future<void> saveBinRetentionDays(int days) async =>
      (await _p).setInt(_kBinRetention, days);

  /// Hide media smaller than this many KB from the gallery; 0 means "off".
  Future<int> loadHideSmallMediaKb() async =>
      (await _p).getInt(_kHideSmallKb) ?? 0;

  Future<void> saveHideSmallMediaKb(int kb) async =>
      (await _p).setInt(_kHideSmallKb, kb);

  /// User-defined media stacks (groups of related photos), keyed by stack id.
  Future<Map<String, MediaStack>> loadStacks() async {
    final raw = (await _p).getString(_kStacks);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) =>
        MapEntry(key, MediaStack.fromJson(key, value as Map<String, dynamic>)));
  }

  Future<void> saveStacks(Map<String, MediaStack> stacks) async {
    final encoded = jsonEncode(
        stacks.map((key, value) => MapEntry(key, value.toJson())));
    await (await _p).setString(_kStacks, encoded);
  }

  /// Whether burst/original photos are auto-grouped by filename. Default on.
  Future<bool> loadAutoStackByName() async =>
      (await _p).getBool(_kAutoStack) ?? true;

  Future<void> saveAutoStackByName(bool value) async =>
      (await _p).setBool(_kAutoStack, value);

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
