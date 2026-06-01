/// A group of related media (e.g. an original and a processed/duplicate
/// variant) shown as a single tile. The [coverId] is the version the gallery
/// displays; the viewer lets the user switch between [memberIds] and choose it.
///
/// This is the app's own grouping — it does not read Google Photos' private
/// "stacks". Members are just normal device files.
class MediaStack {
  const MediaStack({
    required this.id,
    required this.memberIds,
    required this.coverId,
  });

  final String id;
  final List<String> memberIds;
  final String coverId;

  int get count => memberIds.length;

  MediaStack copyWith({List<String>? memberIds, String? coverId}) => MediaStack(
        id: id,
        memberIds: memberIds ?? this.memberIds,
        coverId: coverId ?? this.coverId,
      );

  Map<String, dynamic> toJson() => {
        'cover': coverId,
        'members': memberIds,
      };

  factory MediaStack.fromJson(String id, Map<String, dynamic> json) {
    final members = (json['members'] as List).cast<String>();
    final cover = json['cover'] as String?;
    return MediaStack(
      id: id,
      memberIds: members,
      coverId: cover != null && members.contains(cover)
          ? cover
          : (members.isNotEmpty ? members.first : ''),
    );
  }
}
