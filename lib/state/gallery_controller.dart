import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/album.dart';
import '../models/album_customization.dart';
import '../models/album_stats.dart';
import '../models/sort_method.dart';
import '../services/intent_service.dart';
import '../services/media_service.dart';
import '../services/settings_service.dart';

/// Loading lifecycle for the album list.
enum GalleryStatus { initial, loading, ready, permissionDenied, error }

/// Owns all gallery state: permission, the loaded albums, the user's view mode,
/// sort method, manual order and per-album customizations. The UI listens to
/// this and calls its mutator methods.
class GalleryController extends ChangeNotifier {
  GalleryController({
    MediaService? mediaService,
    SettingsService? settingsService,
    IntentService? intentService,
  })  : _media = mediaService ?? MediaService(),
        _settings = settingsService ?? SettingsService(),
        _intent = intentService ?? IntentService();

  final MediaService _media;
  final SettingsService _settings;
  final IntentService _intent;

  GalleryStatus _status = GalleryStatus.initial;
  GalleryStatus get status => _status;

  PermissionState? _permission;
  PermissionState? get permission => _permission;

  /// True on Android 14+ "selected photos" partial access.
  bool get isLimited => _permission == PermissionState.limited;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  AlbumViewMode _viewMode = AlbumViewMode.grid;
  AlbumViewMode get viewMode => _viewMode;

  AlbumSort _sort = AlbumSort.countDesc;
  AlbumSort get sort => _sort;

  bool _showHidden = false;
  bool get showHidden => _showHidden;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Raw albums as loaded from the device, keyed insertion-independent by id.
  List<Album> _albums = [];

  /// Per-album overrides (rename / hide), keyed by album id.
  Map<String, AlbumCustomization> _customizations = {};

  /// The user's manual album order (album ids). Locked album is excluded.
  List<String> _manualOrder = [];

  bool get hasHiddenAlbums => _albums.any((a) => a.hidden);

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _themeMode = await _settings.loadThemeMode();
    _viewMode = await _settings.loadViewMode();
    _sort = await _settings.loadSort();
    _showHidden = await _settings.loadShowHidden();
    _manualOrder = await _settings.loadOrder();
    _customizations = await _settings.loadCustomizations();
    await loadAlbums();
  }

  Future<void> loadAlbums() async {
    _status = GalleryStatus.loading;
    notifyListeners();

    try {
      final permission = await _media.requestPermission();
      _permission = permission;

      if (permission == PermissionState.denied ||
          permission == PermissionState.restricted) {
        _status = GalleryStatus.permissionDenied;
        notifyListeners();
        return;
      }

      final loaded = await _media.loadAlbums();
      // Re-attach saved customizations to freshly loaded albums.
      _albums = loaded
          .map((a) => a.isLocked
              ? a
              : a.copyWith(
                  customization:
                      _customizations[a.id] ?? const AlbumCustomization()))
          .toList();
      // Albums that became empty (e.g. all media deleted or moved out) are no
      // longer returned by the device, so drop their stale customization and
      // ordering entries. Skip this in "limited" mode, where many albums are
      // intentionally absent and pruning would lose the user's settings.
      if (permission == PermissionState.authorized) {
        await _pruneOrphans();
      }
      _status = GalleryStatus.ready;
    } catch (e) {
      _errorMessage = e.toString();
      _status = GalleryStatus.error;
    }
    notifyListeners();
  }

  /// Drops customizations and manual-order entries for albums that no longer
  /// exist (e.g. became empty). Persists only if something actually changed.
  Future<void> _pruneOrphans() async {
    final existing = _albums.map((a) => a.id).toSet();
    final removedCustom =
        _customizations.keys.where((id) => !existing.contains(id)).toList();
    final orderHadOrphan =
        _manualOrder.any((id) => !existing.contains(id));

    if (removedCustom.isNotEmpty) {
      for (final id in removedCustom) {
        _customizations.remove(id);
      }
      await _settings.saveCustomizations(_customizations);
    }
    if (orderHadOrphan) {
      _manualOrder.removeWhere((id) => !existing.contains(id));
      await _settings.saveOrder(_manualOrder);
    }
  }

  Future<void> openSettings() => _media.openSettings();

  Future<void> presentLimitedPicker() async {
    await _media.presentLimitedPicker();
    await loadAlbums();
  }

  // ---------------------------------------------------------------------------
  // Derived: the ordered, filtered list the home page renders
  // ---------------------------------------------------------------------------

  /// Albums to display: locked "All Photos" always pinned first, then the rest
  /// filtered by hidden state and ordered by the current sort method.
  List<Album> get visibleAlbums {
    final locked = _albums.where((a) => a.isLocked).toList();
    var rest = _albums.where((a) => !a.isLocked).toList();

    if (!_showHidden) {
      rest = rest.where((a) => !a.hidden).toList();
    }

    rest.sort(_comparator);
    return [...locked, ...rest];
  }

  Comparator<Album> get _comparator {
    switch (_sort) {
      case AlbumSort.manual:
        return (a, b) {
          final ia = _manualOrder.indexOf(a.id);
          final ib = _manualOrder.indexOf(b.id);
          // Unordered albums (newly added) sink to the bottom.
          final ra = ia == -1 ? _manualOrder.length : ia;
          final rb = ib == -1 ? _manualOrder.length : ib;
          return ra.compareTo(rb);
        };
      case AlbumSort.nameAsc:
        return (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      case AlbumSort.nameDesc:
        return (a, b) =>
            b.displayName.toLowerCase().compareTo(a.displayName.toLowerCase());
      case AlbumSort.countDesc:
        return (a, b) => b.assetCount.compareTo(a.assetCount);
      case AlbumSort.countAsc:
        return (a, b) => a.assetCount.compareTo(b.assetCount);
    }
  }

  // ---------------------------------------------------------------------------
  // View mode / sort / hidden toggles
  // ---------------------------------------------------------------------------

  Future<void> toggleViewMode() async {
    _viewMode = _viewMode.toggled;
    await _settings.saveViewMode(_viewMode);
    notifyListeners();
  }

  Future<void> setSort(AlbumSort sort) async {
    _sort = sort;
    await _settings.saveSort(sort);
    notifyListeners();
  }

  Future<void> setShowHidden(bool value) async {
    _showHidden = value;
    await _settings.saveShowHidden(value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _settings.saveThemeMode(mode);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Per-album customization
  // ---------------------------------------------------------------------------

  Future<void> _updateCustomization(
      String id, AlbumCustomization customization) async {
    if (customization.isEmpty) {
      _customizations.remove(id);
    } else {
      _customizations[id] = customization;
    }
    final index = _albums.indexWhere((a) => a.id == id);
    if (index != -1) {
      _albums[index] = _albums[index].copyWith(customization: customization);
    }
    await _settings.saveCustomizations(_customizations);
    notifyListeners();
  }

  /// Renames an album. The name may contain emoji. Empty/blank clears the
  /// override and reverts to the device-folder name. No-op on the locked album.
  Future<void> renameAlbum(Album album, String name) async {
    if (!album.canEdit) return;
    final trimmed = name.trim();
    final current =
        _customizations[album.id] ?? const AlbumCustomization();
    await _updateCustomization(
      album.id,
      trimmed.isEmpty
          ? current.copyWith(clearCustomName: true)
          : current.copyWith(customName: trimmed),
    );
  }

  Future<void> setAlbumHidden(Album album, bool hidden) async {
    if (!album.canEdit) return;
    final current =
        _customizations[album.id] ?? const AlbumCustomization();
    await _updateCustomization(album.id, current.copyWith(hidden: hidden));
  }

  /// Hides or unhides several albums at once. Locked albums are ignored.
  Future<void> setAlbumsHidden(Iterable<Album> albums, bool hidden) async {
    for (final album in albums) {
      if (!album.canEdit) continue;
      final current = _customizations[album.id] ?? const AlbumCustomization();
      final updated = current.copyWith(hidden: hidden);
      if (updated.isEmpty) {
        _customizations.remove(album.id);
      } else {
        _customizations[album.id] = updated;
      }
      final index = _albums.indexWhere((a) => a.id == album.id);
      if (index != -1) {
        _albums[index] = _albums[index].copyWith(customization: updated);
      }
    }
    await _settings.saveCustomizations(_customizations);
    notifyListeners();
  }

  /// Computes combined statistics for the given albums (for the info sheet).
  Future<AlbumStats> computeAlbumStats(List<Album> albums) =>
      _media.computeStats(albums);

  /// Whether moving media between albums is supported (Android only).
  bool get canMoveBetweenAlbums => _media.canMoveBetweenAlbums;

  /// Editable albums that media can be moved into, excluding the source album
  /// (by [excludeId]) and the locked "All Photos". Sorted by name.
  List<Album> moveDestinations(String excludeId) {
    final list = _albums
        .where((a) => a.canEdit && a.id != excludeId)
        .toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  /// Moves the given assets into [destination], then refreshes the album list.
  Future<bool> moveAssets(
      List<AssetEntity> assets, Album destination) async {
    final ok = await _media.moveAssetsToAlbum(assets, destination);
    if (ok) await loadAlbums();
    return ok;
  }

  /// Deletes several albums (and all their assets) at once. Locked albums are
  /// ignored. Returns the total number of assets removed.
  Future<int> deleteAlbums(Iterable<Album> albums) async {
    var total = 0;
    for (final album in albums) {
      if (!album.canEdit) continue;
      total += await deleteAlbum(album);
    }
    return total;
  }

  /// Deletes an album by deleting all of its assets from the device. The caller
  /// is responsible for showing the warning first. No-op on the locked album.
  /// Returns the number of assets removed.
  Future<int> deleteAlbum(Album album) async {
    if (!album.canEdit) return 0;
    final assets = <AssetEntity>[];
    var page = 0;
    while (true) {
      final batch =
          await _media.loadAssets(album.path, page: page, size: 200);
      if (batch.isEmpty) break;
      assets.addAll(batch);
      if (batch.length < 200) break;
      page++;
    }
    final ids = assets.map((a) => a.id).toList();
    final removed = await _media.deleteAssets(ids);
    _customizations.remove(album.id);
    _manualOrder.remove(album.id);
    await _settings.saveCustomizations(_customizations);
    await _settings.saveOrder(_manualOrder);
    await loadAlbums();
    return removed.length;
  }

  // ---------------------------------------------------------------------------
  // Manual reordering
  // ---------------------------------------------------------------------------

  /// Reorders editable albums. [oldIndex]/[newIndex] are positions within the
  /// reorderable list (which excludes the pinned locked album). Switches the
  /// active sort to manual so the new order sticks.
  Future<void> reorderAlbums(int oldIndex, int newIndex) async {
    final editable = visibleAlbums.where((a) => a.canEdit).toList();
    if (oldIndex < 0 || oldIndex >= editable.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = editable.removeAt(oldIndex);
    editable.insert(newIndex.clamp(0, editable.length), moved);

    _manualOrder = editable.map((a) => a.id).toList();
    _sort = AlbumSort.manual;
    await _settings.saveOrder(_manualOrder);
    await _settings.saveSort(_sort);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Single-asset operations (from the photo viewer)
  // ---------------------------------------------------------------------------

  /// Deletes one asset from the device. Returns true if it was removed.
  Future<bool> deleteAsset(String id) async {
    final removed = await _media.deleteAssets([id]);
    return removed.contains(id);
  }

  /// Deletes several assets at once. Returns the ids that were removed.
  Future<List<String>> deleteAssets(List<String> ids) async {
    if (ids.isEmpty) return const [];
    return _media.deleteAssets(ids);
  }

  /// Whether the Google Photos hand-off is available (Android only).
  bool get canOpenInGooglePhotos => _intent.isSupported;

  /// Opens the asset in Google Photos (or the system chooser as a fallback).
  Future<bool> openInGooglePhotos(AssetEntity asset) =>
      _intent.openInGooglePhotos(asset);

  /// Refreshes album counts/covers after assets were deleted in the viewer.
  void onAssetsDeleted() => loadAlbums();
}
