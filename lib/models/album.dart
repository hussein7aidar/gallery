import 'package:photo_manager/photo_manager.dart';

import 'album_customization.dart';

/// A device folder presented as an album, merged with any local customization.
///
/// Wraps a photo_manager [AssetPathEntity]. The special "All Photos" album
/// (photo_manager's `isAll` path) is locked: it cannot be renamed, hidden,
/// reordered manually or deleted.
class Album {
  Album({
    required this.path,
    required this.assetCount,
    this.coverAsset,
    this.customization = const AlbumCustomization(),
  });

  /// The underlying device folder.
  final AssetPathEntity path;

  /// Number of photos + videos in the folder.
  final int assetCount;

  /// First asset, used as the album cover thumbnail. Null when empty.
  final AssetEntity? coverAsset;

  /// Local overrides (name/hidden). Always empty for the locked album.
  final AlbumCustomization customization;

  /// Stable id used as the key for customizations and ordering.
  String get id => path.id;

  /// True for the locked, always-present "All Photos" album.
  bool get isLocked => path.isAll;

  /// The folder's on-disk name (what the device reports).
  String get originalName => isLocked ? 'All Photos' : path.name;

  /// What to show in the UI: the custom name (which may include emoji) when set,
  /// otherwise the original folder name.
  String get displayName => customization.customName ?? originalName;

  /// Hidden albums are filtered out of the default home view.
  bool get hidden => customization.hidden;

  /// Locked albums can't be renamed / hidden / deleted / manually reordered.
  bool get canEdit => !isLocked;

  Album copyWith({
    int? assetCount,
    AssetEntity? coverAsset,
    AlbumCustomization? customization,
  }) {
    return Album(
      path: path,
      assetCount: assetCount ?? this.assetCount,
      coverAsset: coverAsset ?? this.coverAsset,
      customization: customization ?? this.customization,
    );
  }
}
