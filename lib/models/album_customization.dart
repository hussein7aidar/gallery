/// User-applied overrides for a single device folder ("album").
///
/// Device folders themselves are read-only as far as their on-disk name goes,
/// so renaming, hiding and emoji decoration are stored locally as an overlay
/// keyed by the album id. The locked "All Photos" album never gets one.
class AlbumCustomization {
  const AlbumCustomization({
    this.customName,
    this.hidden = false,
    this.userCreated = false,
  });

  /// Overrides the displayed album name. May contain emoji. `null` keeps the
  /// original device-folder name.
  final String? customName;

  /// When true the album is hidden from the default home view.
  final bool hidden;

  /// True when the album was created by the user in this app. Such albums are
  /// never grouped under "Others" (which collects auto-generated folders).
  final bool userCreated;

  AlbumCustomization copyWith({
    String? customName,
    bool clearCustomName = false,
    bool? hidden,
    bool? userCreated,
  }) {
    return AlbumCustomization(
      customName: clearCustomName ? null : (customName ?? this.customName),
      hidden: hidden ?? this.hidden,
      userCreated: userCreated ?? this.userCreated,
    );
  }

  /// True when this overlay carries no information and can be dropped.
  bool get isEmpty => customName == null && !hidden && !userCreated;

  Map<String, dynamic> toJson() => {
        if (customName != null) 'customName': customName,
        if (hidden) 'hidden': true,
        if (userCreated) 'userCreated': true,
      };

  factory AlbumCustomization.fromJson(Map<String, dynamic> json) {
    return AlbumCustomization(
      customName: json['customName'] as String?,
      hidden: json['hidden'] as bool? ?? false,
      userCreated: json['userCreated'] as bool? ?? false,
    );
  }
}
