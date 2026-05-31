/// The ways the album list can be ordered on the home page.
///
/// [manual] means the user has dragged albums into a custom order; the other
/// values are the "built-in methods" that sort automatically.
enum AlbumSort {
  manual,
  nameAsc,
  nameDesc,
  countDesc,
  countAsc;

  /// Human-readable label shown in the sort menu.
  String get label => switch (this) {
        AlbumSort.manual => 'Custom order',
        AlbumSort.nameAsc => 'Name (A–Z)',
        AlbumSort.nameDesc => 'Name (Z–A)',
        AlbumSort.countDesc => 'Most items',
        AlbumSort.countAsc => 'Fewest items',
      };

  static AlbumSort fromName(String? name) =>
      AlbumSort.values.firstWhere((e) => e.name == name,
          orElse: () => AlbumSort.countDesc);
}

/// Whether the home page shows albums as a vertical list or a grid.
enum AlbumViewMode {
  grid,
  list;

  AlbumViewMode get toggled =>
      this == AlbumViewMode.grid ? AlbumViewMode.list : AlbumViewMode.grid;

  static AlbumViewMode fromName(String? name) => AlbumViewMode.values
      .firstWhere((e) => e.name == name, orElse: () => AlbumViewMode.grid);
}
