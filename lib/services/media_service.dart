import 'package:photo_manager/photo_manager.dart';

import '../models/album.dart';
import '../models/album_stats.dart';

/// Thin wrapper around photo_manager for permissions, album and asset loading,
/// and deletion. Keeps all plugin-specific calls in one place.
class MediaService {
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
  Future<List<Album>> loadAlbums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common, // images + videos
      hasAll: true,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    final albums = <Album>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      AssetEntity? cover;
      if (count > 0) {
        final first = await path.getAssetListRange(start: 0, end: 1);
        if (first.isNotEmpty) cover = first.first;
      }
      albums.add(Album(path: path, assetCount: count, coverAsset: cover));
    }
    return albums;
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
