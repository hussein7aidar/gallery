/// Aggregated statistics for one or more selected albums, shown in the album
/// info sheet. For a single album every field is meaningful; for several
/// albums only the aggregatable fields (counts, size) are surfaced.
class AlbumStats {
  const AlbumStats({
    required this.albumCount,
    required this.totalItems,
    required this.photoCount,
    required this.videoCount,
    required this.totalBytes,
    this.oldest,
    this.newest,
  });

  final int albumCount;
  final int totalItems;
  final int photoCount;
  final int videoCount;
  final int totalBytes;

  /// Capture date of the oldest / newest item across the albums.
  final DateTime? oldest;
  final DateTime? newest;
}
