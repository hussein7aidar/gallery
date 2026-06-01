import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../models/album.dart';
import '../models/album_stats.dart';

/// Thin wrapper around photo_manager for permissions, album and asset loading,
/// and deletion. Keeps all plugin-specific calls in one place.
class MediaService {
  /// Filter for normal browsing. When [minSizeBytes] > 0, also excludes media
  /// smaller than that (used to hide tiny third-party junk images). The filter
  /// is baked into each returned [AssetPathEntity], so counts and paged loads
  /// honor it automatically.
  PMFilter _browseFilter(int minSizeBytes) {
    if (minSizeBytes <= 0) {
      return FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );
    }
    return AdvancedCustomFilter(
      where: [
        ColumnWhereCondition(
            column: 'media_type', operator: 'IN', value: '(1,3)',
            needCheck: false),
        ColumnWhereCondition(
            column: '_size',
            operator: '>=',
            value: '$minSizeBytes',
            needCheck: false),
      ],
      orderBy: [const OrderByItem('date_added', false)],
    );
  }

  /// Builds the same browse filter for paged asset loads in album detail.
  PMFilter browseFilter(int minSizeBytes) => _browseFilter(minSizeBytes);

  /// Requests media access. Returns the granted [PermissionState] so the UI can
  /// distinguish full access, limited ("selected photos") access and denial.
  Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend();
  }

  /// Opens the system screen where the user can grant/adjust permission.
  Future<void> openSettings() => PhotoManager.openSetting();

  /// On Android 14+ limited mode, lets the user pick more photos to share.
  Future<void> presentLimitedPicker() => PhotoManager.presentLimited();

  /// Loads every device folder (images + videos). The folder flagged `isAll`
  /// by photo_manager becomes the locked "All Photos" album.
  ///
  /// For each folder we also fetch the item count and the first asset to use as
  /// a cover thumbnail.
  /// [excludeIds] are items in the recycle bin: they're skipped for covers and
  /// subtracted from each album's count. [binnedByFolder] maps a normalized
  /// folder path to how many of its items are binned, so counts stay accurate
  /// and fully-binned albums are dropped entirely.
  Future<List<Album>> loadAlbums({
    Set<String> excludeIds = const {},
    Map<String, int> binnedByFolder = const {},
    int minSizeBytes = 0,
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common, // images + videos
      hasAll: true,
      filterOption: _browseFilter(minSizeBytes),
    );
    final totalBinned = binnedByFolder.values.fold(0, (a, b) => a + b);

    final albums = <Album>[];
    for (final path in paths) {
      final total = await path.assetCountAsync;

      // Look at the head of the folder to learn its path and pick a cover that
      // isn't binned.
      AssetEntity? cover;
      String? folder;
      if (total > 0) {
        final head = await path.getAssetListRange(
            start: 0, end: excludeIds.isEmpty ? 1 : 24);
        for (final asset in head) {
          folder ??= _normalizeFolder(asset.relativePath);
          if (!excludeIds.contains(asset.id)) {
            cover = asset;
            break;
          }
        }
      }

      // Subtract binned items: everything for "All Photos", per-folder otherwise.
      final binnedHere = path.isAll
          ? totalBinned
          : (folder != null ? (binnedByFolder[folder] ?? 0) : 0);
      final effective = total - binnedHere;

      // A non-locked folder with nothing left is gone (its album disappears).
      if (!path.isAll && effective <= 0) continue;

      albums.add(Album(
        path: path,
        assetCount: effective < 0 ? 0 : effective,
        coverAsset: cover,
      ));
    }
    return albums;
  }

  /// Normalizes a MediaStore relative path for use as a folder key (lower-case,
  /// no trailing slash).
  static String _normalizeFolder(String? relativePath) {
    var p = (relativePath ?? '').toLowerCase();
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  /// Exposes the folder normalization so callers build matching keys.
  static String normalizeFolder(String? relativePath) =>
      _normalizeFolder(relativePath);

  /// Creates a new album named [name] by moving [assets] into a new folder under
  /// Pictures. An album can't exist without media, so [assets] must be non-empty.
  /// Returns the sanitized folder name on success, or null on failure.
  Future<String?> createAlbumWithAssets(
      String name, List<AssetEntity> assets) async {
    if (!Platform.isAndroid || assets.isEmpty) return null;
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    if (safe.isEmpty) return null;
    final ok = await PhotoManager.editor.android
        .moveAssetsToPath(entities: assets, targetPath: 'Pictures/$safe');
    return ok ? safe : null;
  }

  /// Loads a page of assets from an album, newest first.
  Future<List<AssetEntity>> loadAssets(
    AssetPathEntity path, {
    required int page,
    int size = 80,
  }) {
    return path.getAssetListPaged(page: page, size: size);
  }

  /// Deletes the given assets from the device. On Android 11+ the system shows
  /// its own confirmation dialog. Returns the ids that were actually removed.
  Future<List<String>> deleteAssets(List<String> ids) {
    return PhotoManager.editor.deleteWithIds(ids);
  }

  /// Whether moving assets between albums is supported on this platform.
  /// Implemented with the Android MediaStore editor only.
  bool get canMoveBetweenAlbums => Platform.isAndroid;

  /// Moves [assets] into the [destination] album (device folder). On Android 11+
  /// the system shows a single permission dialog for the batch. Returns true on
  /// success.
  Future<bool> moveAssetsToAlbum(
      List<AssetEntity> assets, Album destination) async {
    if (!Platform.isAndroid || assets.isEmpty) return false;

    // Prefer the batch API (one permission dialog). It needs the destination's
    // MediaStore RELATIVE_PATH, which we read from the album's cover asset.
    final relative = destination.coverAsset?.relativePath;
    if (relative != null && relative.isNotEmpty) {
      final target =
          relative.endsWith('/') ? relative.substring(0, relative.length - 1) : relative;
      return PhotoManager.editor.android
          .moveAssetsToPath(entities: assets, targetPath: target);
    }

    // Fallback: move one by one to the target path entity.
    var allOk = true;
    for (final asset in assets) {
      final ok = await PhotoManager.editor.android
          .moveAssetToAnother(entity: asset, target: destination.path);
      allOk = allOk && ok;
    }
    return allOk;
  }

  /// Loads every asset in a folder by paging through it.
  Future<List<AssetEntity>> allAssets(AssetPathEntity path) async {
    final all = <AssetEntity>[];
    var page = 0;
    while (true) {
      final batch = await path.getAssetListPaged(page: page, size: 200);
      if (batch.isEmpty) break;
      all.addAll(batch);
      if (batch.length < 200) break;
      page++;
    }
    return all;
  }

  /// Computes combined statistics (counts, total byte size, date range) for the
  /// given albums. Reading byte size requires touching each file, so this can be
  /// slow for very large albums.
  Future<AlbumStats> computeStats(List<Album> albums) async {
    var items = 0, photos = 0, videos = 0, bytes = 0;
    DateTime? oldest, newest;

    for (final album in albums) {
      final assets = await allAssets(album.path);
      items += assets.length;
      for (final asset in assets) {
        if (asset.type == AssetType.video) {
          videos++;
        } else {
          photos++;
        }
        final file = await asset.file;
        if (file != null && file.existsSync()) bytes += file.lengthSync();

        final date = asset.createDateTime;
        if (oldest == null || date.isBefore(oldest)) oldest = date;
        if (newest == null || date.isAfter(newest)) newest = date;
      }
    }

    return AlbumStats(
      albumCount: albums.length,
      totalItems: items,
      photoCount: photos,
      videoCount: videos,
      totalBytes: bytes,
      oldest: oldest,
      newest: newest,
    );
  }
}
