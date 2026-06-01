import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/album.dart';
import '../models/album_customization.dart';
import '../models/album_stats.dart';
import '../models/media_stack.dart';
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

  /// Days before binned items auto-delete (0 = never).
  int _binRetentionDays = 30;
  int get binRetentionDays => _binRetentionDays;

  /// Allowed retention choices shown in settings (0 = never).
  static const List<int> retentionChoices = [10, 15, 30, 60, 90, 0];

  /// Hide media smaller than this many KB from the gallery (0 = off).
  int _hideSmallMediaKb = 0;
  int get hideSmallMediaKb => _hideSmallMediaKb;

  /// Allowed small-media thresholds shown in settings (0 = off).
  static const List<int> smallMediaChoices = [0, 2, 4, 6, 8];

  /// Raw albums as loaded from the device, keyed insertion-independent by id.
  List<Album> _albums = [];

  /// Per-album overrides (rename / hide), keyed by album id.
  Map<String, AlbumCustomization> _customizations = {};

  /// The user's manual album order (album ids). Locked album is excluded.
  List<String> _manualOrder = [];

  /// Soft recycle bin: asset id → time it was binned (epoch ms). Binned items
  /// are hidden from albums but not actually moved or deleted until the user
  /// empties the bin.
  Map<String, int> _binnedAt = {};

  /// Soft recycle bin: asset id → the folder it was binned from, so each album's
  /// count stays accurate and fully-binned albums disappear.
  Map<String, String> _binnedPath = {};

  /// Media stacks (groups of related photos), keyed by stack id.
  Map<String, MediaStack> _stacks = {};

  /// Reverse index: member asset id → its stack id.
  final Map<String, String> _memberToStack = {};

  /// Whether burst/original variants are auto-grouped by filename.
  bool _autoStackByName = true;
  bool get autoStackByName => _autoStackByName;

  bool get hasHiddenAlbums => _albums.any((a) => a.hidden);

  /// The recycle bin is always available (it doesn't rely on MediaStore moves).
  bool get binSupported => true;

  /// Whether an asset is currently in the recycle bin.
  bool isBinned(String id) => _binnedAt.containsKey(id);

  /// Ids currently in the recycle bin.
  Set<String> get binnedIds => _binnedAt.keys.toSet();

  /// Whole days left before [id] auto-deletes, or null when retention is
  /// "never" or the item isn't binned.
  int? binDaysLeftFor(String id) {
    if (_binRetentionDays <= 0) return null;
    final at = _binnedAt[id];
    if (at == null) return null;
    final elapsedDays =
        (DateTime.now().millisecondsSinceEpoch - at) ~/ (24 * 60 * 60 * 1000);
    final left = _binRetentionDays - elapsedDays;
    return left < 0 ? 0 : left;
  }

  /// Binned ids whose retention window has elapsed (empty when "never").
  List<String> get expiredBinIds {
    if (_binRetentionDays <= 0) return const [];
    final cutoff = DateTime.now().millisecondsSinceEpoch -
        _binRetentionDays * 24 * 60 * 60 * 1000;
    return _binnedAt.entries
        .where((e) => e.value < cutoff)
        .map((e) => e.key)
        .toList();
  }

  /// Permanently deletes any binned items past the retention window.
  Future<int> purgeExpiredBin() async {
    final expired = expiredBinIds;
    if (expired.isEmpty) return 0;
    final removed = await deleteForever(expired);
    return removed.length;
  }

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
    _binnedAt = await _settings.loadBinnedAt();
    _binnedPath = await _settings.loadBinnedPaths();
    _binRetentionDays = await _settings.loadBinRetentionDays();
    _hideSmallMediaKb = await _settings.loadHideSmallMediaKb();
    _stacks = await _settings.loadStacks();
    _autoStackByName = await _settings.loadAutoStackByName();
    _rebuildStackIndex();
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

      final loaded = await _media.loadAlbums(
        excludeIds: _binnedAt.keys.toSet(),
        binnedByFolder: _binnedByFolder(),
        minSizeBytes: _hideSmallMediaKb * 1024,
      );
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

  /// Albums to display on the home page: locked "All Photos" pinned first, then
  /// the user's own folders (auto-generated ones are grouped under "Others"),
  /// filtered by hidden state and ordered by the current sort method.
  List<Album> get visibleAlbums {
    final locked = _albums.where((a) => a.isLocked).toList();
    var rest =
        _albums.where((a) => !a.isLocked && !a.isAutoGenerated).toList();

    if (!_showHidden) {
      rest = rest.where((a) => !a.hidden).toList();
    }

    rest.sort(_comparator);
    return [...locked, ...rest];
  }

  /// Auto-generated app/system albums (WhatsApp, Telegram, Screenshots, …),
  /// always sorted A–Z. These live behind the "Others" tile.
  List<Album> get otherAlbums {
    var list = _albums.where((a) => a.isAutoGenerated).toList();
    if (!_showHidden) {
      list = list.where((a) => !a.hidden).toList();
    }
    list.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  /// True when there is at least one auto-generated album to show under Others.
  bool get hasOthers => otherAlbums.isNotEmpty;

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

  Future<void> setViewMode(AlbumViewMode mode) async {
    if (_viewMode == mode) return;
    _viewMode = mode;
    await _settings.saveViewMode(mode);
    notifyListeners();
  }

  Future<void> setBinRetentionDays(int days) async {
    _binRetentionDays = days;
    await _settings.saveBinRetentionDays(days);
    notifyListeners();
  }

  /// Sets the small-media threshold (KB) and reloads albums so the filter takes
  /// effect immediately.
  Future<void> setHideSmallMediaKb(int kb) async {
    if (_hideSmallMediaKb == kb) return;
    _hideSmallMediaKb = kb;
    await _settings.saveHideSmallMediaKb(kb);
    await loadAlbums();
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

  /// Deletes an album by moving all of its media to the recycle bin. The caller
  /// is responsible for showing the warning first. No-op on the locked album.
  /// Returns the number of items moved to the bin.
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
    final ok = await trashAssets(assets); // records metadata + reloads
    _customizations.remove(album.id);
    _manualOrder.remove(album.id);
    await _settings.saveCustomizations(_customizations);
    await _settings.saveOrder(_manualOrder);
    return ok ? assets.length : 0;
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
  // Recycle bin (soft — no file moves)
  // ---------------------------------------------------------------------------

  /// Binned counts per normalized folder, for accurate album counts.
  Map<String, int> _binnedByFolder() {
    final map = <String, int>{};
    for (final path in _binnedPath.values) {
      final key = MediaService.normalizeFolder(path);
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  /// Marks the given assets as binned. They're hidden from albums everywhere but
  /// stay on disk until restored or permanently deleted. Always succeeds.
  Future<bool> trashAssets(List<AssetEntity> assets) async {
    if (assets.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final asset in assets) {
      _binnedAt[asset.id] = now;
      _binnedPath[asset.id] = asset.relativePath ?? '';
      _detachFromStack(asset.id); // a binned item leaves its stack
    }
    _rebuildStackIndex();
    await _settings.saveBinnedAt(_binnedAt);
    await _settings.saveBinnedPaths(_binnedPath);
    await _settings.saveStacks(_stacks);
    await loadAlbums(); // refresh covers/counts; empty albums disappear
    return true;
  }

  /// Loads the recycle bin contents (newest-binned first). Drops ids whose
  /// underlying asset no longer exists.
  Future<List<AssetEntity>> loadBin() async {
    final entries = _binnedAt.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final assets = <AssetEntity>[];
    var changed = false;
    for (final entry in entries) {
      final asset = await AssetEntity.fromId(entry.key);
      if (asset != null) {
        assets.add(asset);
      } else {
        _binnedAt.remove(entry.key);
        _binnedPath.remove(entry.key);
        changed = true;
      }
    }
    if (changed) {
      await _settings.saveBinnedAt(_binnedAt);
      await _settings.saveBinnedPaths(_binnedPath);
    }
    return assets;
  }

  /// Restores items from the bin (un-marks them). Because the soft bin never
  /// moved the files, each item simply reappears in its original album — and if
  /// that album had become empty and disappeared, it comes back automatically.
  /// Always succeeds.
  Future<bool> restoreFromBin(List<AssetEntity> assets) async {
    if (assets.isEmpty) return true;
    for (final asset in assets) {
      _binnedAt.remove(asset.id);
      _binnedPath.remove(asset.id);
    }
    await _settings.saveBinnedAt(_binnedAt);
    await _settings.saveBinnedPaths(_binnedPath);
    await loadAlbums();
    return true;
  }

  /// Permanently deletes the given items (from the bin). Returns removed ids.
  Future<List<String>> deleteForever(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final removed = await _media.deleteAssets(ids);
    // Only items actually deleted leave the bin (the system delete dialog may be
    // cancelled, in which case they stay).
    for (final id in removed) {
      _binnedAt.remove(id);
      _binnedPath.remove(id);
    }
    await _settings.saveBinnedAt(_binnedAt);
    await _settings.saveBinnedPaths(_binnedPath);
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Media stacks (group related photos under one tile)
  // ---------------------------------------------------------------------------

  void _rebuildStackIndex() {
    _memberToStack.clear();
    for (final stack in _stacks.values) {
      for (final id in stack.memberIds) {
        _memberToStack[id] = stack.id;
      }
    }
  }

  /// The stack an asset belongs to, or null.
  MediaStack? stackForAsset(String id) {
    final stackId = _memberToStack[id];
    return stackId == null ? null : _stacks[stackId];
  }

  /// True when an asset is part of a stack.
  bool isStacked(String id) => _memberToStack.containsKey(id);

  /// True when an asset is the visible cover of its stack.
  bool isStackCover(String id) => stackForAsset(id)?.coverId == id;

  /// True when an asset is a hidden (non-cover) stack member — collapsed out of
  /// the grid.
  bool isHiddenStackMember(String id) {
    final stack = stackForAsset(id);
    return stack != null && stack.coverId != id;
  }

  void _detachFromStack(String id) {
    final stackId = _memberToStack[id];
    if (stackId == null) return;
    final stack = _stacks[stackId];
    if (stack == null) return;
    final members = stack.memberIds.where((m) => m != id).toList();
    if (members.length < 2) {
      _stacks.remove(stackId); // a stack needs at least two members
    } else {
      final cover = stack.coverId == id ? members.first : stack.coverId;
      _stacks[stackId] = stack.copyWith(memberIds: members, coverId: cover);
    }
  }

  Future<void> setAutoStackByName(bool value) async {
    _autoStackByName = value;
    await _settings.saveAutoStackByName(value);
    notifyListeners();
  }

  /// Grouping key derived from a filename, or null if it isn't a burst/variant.
  ///
  /// Pixel names like `PXL_20260526_134523420.BURST-02.original.jpg` and
  /// `PXL_20260526_134523420.BURST-01.jpg` share the key
  /// `pxl_20260526_134523420.burst`.
  static String? autoStackKey(String? title) {
    if (title == null || title.isEmpty) return null;
    var name = title;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot); // drop extension
    final lower = name.toLowerCase();
    const marker = '.burst';
    final i = lower.indexOf(marker);
    if (i < 0) return null;
    return lower.substring(0, i + marker.length);
  }

  /// The `-NN` sequence number after BURST (lower = earlier; used to order).
  static int _burstSeq(String? title) {
    final m = RegExp(r'burst-(\d+)', caseSensitive: false)
        .firstMatch(title ?? '');
    return m != null ? (int.tryParse(m.group(1)!) ?? 9999) : 9999;
  }

  /// The default cover for a name group: the **enhanced** version (the one
  /// without `.original`), preferring the lowest sequence number.
  static AssetEntity _pickCover(List<AssetEntity> members) {
    bool isOriginal(AssetEntity a) =>
        (a.title ?? '').toLowerCase().contains('.original');
    final enhanced = members.where((a) => !isOriginal(a)).toList();
    final pool = enhanced.isNotEmpty ? enhanced : List.of(members);
    pool.sort((a, b) => _burstSeq(a.title).compareTo(_burstSeq(b.title)));
    return pool.first;
  }

  /// Auto-groups the given assets by filename (burst/original variants) into
  /// stacks, skipping anything already stacked. Returns true if it created any.
  /// No-op when the setting is off.
  Future<bool> autoGroupAssets(List<AssetEntity> assets) async {
    if (!_autoStackByName) return false;
    final groups = <String, List<AssetEntity>>{};
    for (final asset in assets) {
      if (_memberToStack.containsKey(asset.id)) continue; // already grouped
      final key = autoStackKey(asset.title);
      if (key == null) continue;
      (groups[key] ??= []).add(asset);
    }

    var created = false;
    for (final entry in groups.entries) {
      if (entry.value.length < 2) continue;
      final cover = _pickCover(entry.value);
      final ids = [
        cover.id,
        ...entry.value.where((a) => a.id != cover.id).map((a) => a.id),
      ];
      final stackId =
          'stk_${DateTime.now().microsecondsSinceEpoch}_${entry.key.hashCode}';
      _stacks[stackId] =
          MediaStack(id: stackId, memberIds: ids, coverId: cover.id);
      created = true;
    }
    if (created) {
      _rebuildStackIndex();
      await _settings.saveStacks(_stacks);
      notifyListeners();
    }
    return created;
  }

  /// Disbands a stack so its members show individually again.
  Future<void> ungroupStack(String stackId) async {
    if (_stacks.remove(stackId) == null) return;
    _rebuildStackIndex();
    await _settings.saveStacks(_stacks);
    notifyListeners();
  }

  /// Chooses which version of a stack the gallery shows.
  Future<void> setStackCover(String stackId, String coverId) async {
    final stack = _stacks[stackId];
    if (stack == null || !stack.memberIds.contains(coverId)) return;
    _stacks[stackId] = stack.copyWith(coverId: coverId);
    await _settings.saveStacks(_stacks);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Album creation
  // ---------------------------------------------------------------------------

  /// Creates a new album from [assets] (which must be non-empty — an album can't
  /// exist without media). Marks it as user-created so it isn't grouped under
  /// "Others". Returns true on success.
  Future<bool> createAlbum(String name, List<AssetEntity> assets) async {
    if (assets.isEmpty) return false;
    final folder = await _media.createAlbumWithAssets(name, assets);
    if (folder == null) return false;
    await loadAlbums();
    final matches =
        _albums.where((a) => a.canEdit && a.originalName == folder);
    if (matches.isNotEmpty) {
      final album = matches.first;
      final current = _customizations[album.id] ?? const AlbumCustomization();
      await _updateCustomization(album.id, current.copyWith(userCreated: true));
    }
    return true;
  }

  /// Whether the Google Photos hand-off is available (Android only).
  bool get canOpenInGooglePhotos => _intent.isSupported;

  /// Opens the asset in Google Photos (or the system chooser as a fallback).
  Future<bool> openInGooglePhotos(AssetEntity asset) =>
      _intent.openInGooglePhotos(asset);

  /// Launches the Google Photos app (to reach its trash). Returns true if open.
  Future<bool> openGooglePhotosApp() => _intent.openGooglePhotosApp();

  /// Refreshes album counts/covers after assets were deleted in the viewer.
  void onAssetsDeleted() => loadAlbums();
}
