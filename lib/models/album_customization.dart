/// User-applied overrides for a single device folder ("album").
///
/// Device folders themselves are read-only as far as their on-disk name goes,
/// so renaming, hiding and emoji decoration are stored locally as an overlay
/// keyed by the album id. The locked "All Photos" album never gets one.
class AlbumCustomization {
  const AlbumCustomization({
    this.customName,
    this.hidden = false,
  });

  /// Overrides the displayed album name. May contain emoji. `null` keeps the
  /// original device-folder name.
  final String? customName;

  /// When true the album is hidden from the default home view.
  final bool hidden;

  AlbumCustomization copyWith({
    String? customName,
    bool clearCustomName = false,
    bool? hidden,
  }) {
    return AlbumCustomization(
      customName: clearCustomName ? null : (customName ?? this.customName),
      hidden: hidden ?? this.hidden,
    );
  }

  /// True when this overlay carries no information and can be dropped.
  bool get isEmpty => customName == null && !hidden;

  Map<String, dynamic> toJson() => {
        if (customName != null) 'customName': customName,
        if (hidden) 'hidden': true,
      };

  factory AlbumCustomization.fromJson(Map<String, dynamic> json) {
    return AlbumCustomization(
      customName: json['customName'] as String?,
      hidden: json['hidden'] as bool? ?? false,
    );
  }
}
