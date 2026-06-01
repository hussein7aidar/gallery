import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/sort_method.dart';
import '../state/gallery_controller.dart';
import '../theme.dart';
import 'album_actions.dart';
import 'album_detail_page.dart';
import 'album_stats_sheet.dart';
import 'widgets/asset_thumbnail.dart';
import 'widgets/pressable.dart';

/// The albums screen — the home of the gallery.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Whether the album multi-select mode is active.
  bool _selecting = false;

  /// Ids of selected albums (never contains the locked album).
  final Set<String> _selected = {};

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggle(Album album) {
    if (!album.canEdit) return; // All Photos can't be selected
    setState(() {
      if (!_selected.remove(album.id)) _selected.add(album.id);
    });
  }

  /// Long-pressing an album turns on multi-select and selects it. (The locked
  /// "All Photos" album can't be selected, so it's a no-op there.)
  void _onAlbumLongPress(Album album) {
    if (!album.canEdit) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selected.add(album.id);
    });
  }

  Future<void> _renameSelected(GalleryController c) async {
    final albums = _selectedAlbums(c);
    if (albums.length != 1) return;
    await showRenameDialog(context, albums.first);
  }

  List<Album> _selectedAlbums(GalleryController c) =>
      c.visibleAlbums.where((a) => a.canEdit && _selected.contains(a.id)).toList();

  Future<void> _setSelectedHidden(GalleryController c, bool hidden) async {
    final albums = _selectedAlbums(c);
    if (albums.isEmpty) return;
    await c.setAlbumsHidden(albums, hidden);
    _exitSelection();
  }

  Future<void> _deleteSelected(GalleryController c) async {
    final albums = _selectedAlbums(c);
    if (albums.isEmpty) return;
    final totalItems = albums.fold<int>(0, (sum, a) => sum + a.assetCount);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${albums.length} '
            'album${albums.length == 1 ? '' : 's'}?'),
        content: Text(
          'This permanently deletes all $totalItems photos and videos in the '
          'selected albums from your device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await c.deleteAlbums(albums);
    _exitSelection();
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted $removed item${removed == 1 ? '' : 's'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryController>(
      builder: (context, controller, _) {
        // Drop ids that are no longer visible (e.g. after hide/delete).
        _selected.retainWhere(
            (id) => controller.visibleAlbums.any((a) => a.id == id));

        return Scaffold(
          appBar: _selecting
              ? _selectionAppBar(controller)
              : _normalAppBar(controller),
          body: _Body(
            controller: controller,
            selecting: _selecting,
            selected: _selected,
            onToggle: _toggle,
            onLongPress: _onAlbumLongPress,
          ),
        );
      },
    );
  }

  AppBar _normalAppBar(GalleryController controller) {
    return AppBar(
      title: _ThemeIndicator(controller: controller),
      actions: [
        IconButton(
          tooltip: controller.viewMode == AlbumViewMode.grid
              ? 'List view'
              : 'Grid view',
          icon: Icon(controller.viewMode == AlbumViewMode.grid
              ? Icons.view_list_rounded
              : Icons.grid_view_rounded),
          onPressed: controller.toggleViewMode,
        ),
        _SortMenu(controller: controller),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (value) {
            if (value == 'hidden') {
              controller.setShowHidden(!controller.showHidden);
            }
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: 'hidden',
              checked: controller.showHidden,
              enabled: controller.hasHiddenAlbums || controller.showHidden,
              child: const Text('Show hidden albums'),
            ),
          ],
        ),
      ],
    );
  }

  AppBar _selectionAppBar(GalleryController controller) {
    final count = _selected.length;
    final selectedAlbums = _selectedAlbums(controller);
    // When every selected album is already hidden, the action unhides instead.
    final allHidden =
        selectedAlbums.isNotEmpty && selectedAlbums.every((a) => a.hidden);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text(count == 0 ? 'Select albums' : '$count selected'),
      actions: [
        IconButton(
          tooltip: 'Info',
          icon: const Icon(Icons.info_outline),
          onPressed: count == 0
              ? null
              : () => showAlbumStats(context, _selectedAlbums(controller)),
        ),
        IconButton(
          tooltip: 'Rename',
          icon: const Icon(Icons.drive_file_rename_outline),
          // Renaming only makes sense for a single album.
          onPressed: count == 1 ? () => _renameSelected(controller) : null,
        ),
        IconButton(
          tooltip: allHidden ? 'Unhide' : 'Hide',
          icon: Icon(allHidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          onPressed: count == 0
              ? null
              : () => _setSelectedHidden(controller, !allHidden),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: count == 0 ? null : () => _deleteSelected(controller),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final GalleryController controller;
  final bool selecting;
  final Set<String> selected;
  final void Function(Album) onToggle;
  final void Function(Album) onLongPress;

  @override
  Widget build(BuildContext context) {
    switch (controller.status) {
      case GalleryStatus.initial:
      case GalleryStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case GalleryStatus.permissionDenied:
        return _PermissionDenied(controller: controller);
      case GalleryStatus.error:
        return _ErrorState(controller: controller);
      case GalleryStatus.ready:
        return _AlbumsView(
          controller: controller,
          selecting: selecting,
          selected: selected,
          onToggle: onToggle,
          onLongPress: onLongPress,
        );
    }
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView({
    required this.controller,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final GalleryController controller;
  final bool selecting;
  final Set<String> selected;
  final void Function(Album) onToggle;
  final void Function(Album) onLongPress;

  @override
  Widget build(BuildContext context) {
    final albums = controller.visibleAlbums;
    final locked = albums.where((a) => a.isLocked).toList();
    final editable = albums.where((a) => a.canEdit).toList();

    return RefreshIndicator(
      onRefresh: controller.loadAlbums,
      child: Column(
        children: [
          if (controller.isLimited) _LimitedBanner(controller: controller),
          Expanded(
            child: controller.viewMode == AlbumViewMode.grid
                ? _GridAlbums(
                    albums: albums,
                    selecting: selecting,
                    selected: selected,
                    onToggle: onToggle,
                    onLongPress: onLongPress,
                  )
                : _ListAlbums(
                    locked: locked,
                    editable: editable,
                    selecting: selecting,
                    selected: selected,
                    onToggle: onToggle,
                    onLongPress: onLongPress,
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Grid view
// -----------------------------------------------------------------------------

class _GridAlbums extends StatelessWidget {
  const _GridAlbums({
    required this.albums,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final List<Album> albums;
  final bool selecting;
  final Set<String> selected;
  final void Function(Album) onToggle;
  final void Function(Album) onLongPress;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width ~/ 180 < 2 ? 2 : width ~/ 180;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _AlbumGridCell(
          album: album,
          selecting: selecting,
          isSelected: selected.contains(album.id),
          onToggle: onToggle,
          onLongPress: onLongPress,
        );
      },
    );
  }
}

class _AlbumGridCell extends StatelessWidget {
  const _AlbumGridCell({
    required this.album,
    required this.selecting,
    required this.isSelected,
    required this.onToggle,
    required this.onLongPress,
  });

  final Album album;
  final bool selecting;
  final bool isSelected;
  final void Function(Album) onToggle;
  final void Function(Album) onLongPress;

  @override
  Widget build(BuildContext context) {
    final disabled = selecting && !album.canEdit;

    return Pressable(
      onTap: () {
        if (selecting) {
          onToggle(album);
        } else {
          _openAlbum(context, album);
        }
      },
      onLongPress:
          (!selecting && album.canEdit) ? () => onLongPress(album) : null,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Cover(album: album),
                    if (selecting)
                      _SelectionOverlay(
                        selectable: album.canEdit,
                        isSelected: isSelected,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (album.isLocked)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.photo_library_rounded, size: 15),
                  ),
                if (album.hidden)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.visibility_off, size: 15),
                  ),
                Expanded(
                  child: Text(
                    album.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Text(
              '${album.assetCount}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// List view (supports drag-to-reorder for editable albums when not selecting)
// -----------------------------------------------------------------------------

class _ListAlbums extends StatelessWidget {
  const _ListAlbums({
    required this.locked,
    required this.editable,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final List<Album> locked;
  final List<Album> editable;
  final bool selecting;
  final Set<String> selected;
  final void Function(Album) onToggle;
  final void Function(Album) onLongPress;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<GalleryController>();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverList.list(
          children: [
            for (final album in locked)
              _AlbumListRow(
                album: album,
                selecting: selecting,
                isSelected: false,
                onToggle: onToggle,
                onLongPress: onLongPress,
              ),
          ],
        ),
        SliverReorderableList(
          itemCount: editable.length,
          onReorder: controller.reorderAlbums,
          itemBuilder: (context, index) {
            final album = editable[index];
            return _AlbumListRow(
              key: ValueKey(album.id),
              album: album,
              selecting: selecting,
              isSelected: selected.contains(album.id),
              onToggle: onToggle,
              onLongPress: onLongPress,
              reorderIndex: selecting ? null : index,
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _AlbumListRow extends StatelessWidget {
  const _AlbumListRow({
    super.key,
    required this.album,
    required this.selecting,
    required this.isSelected,
    required this.onToggle,
    required this.onLongPress,
    this.reorderIndex,
  });

  final Album album;
  final bool selecting;
  final bool isSelected;
  final void Function(Album) onToggle;
  final void Function(Album) onLongPress;
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${album.assetCount} item${album.assetCount == 1 ? '' : 's'}';
    final disabled = selecting && !album.canEdit;

    Widget? trailing;
    if (selecting) {
      trailing = album.canEdit
          ? Icon(
              isSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : const Icon(Icons.lock_outline, size: 18);
    } else if (reorderIndex != null) {
      trailing = ReorderableDragStartListener(
        index: reorderIndex!,
        child: const Icon(Icons.drag_handle),
      );
    } else if (!album.isLocked) {
      trailing = const Icon(Icons.chevron_right);
    }

    return Pressable(
      pressedScale: 0.97,
      onTap: () {
        if (selecting) {
          onToggle(album);
        } else {
          _openAlbum(context, album);
        }
      },
      onLongPress:
          (!selecting && album.canEdit) ? () => onLongPress(album) : null,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: ListTile(
          leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 56,
            height: 56,
            child: _Cover(album: album),
          ),
        ),
        title: Row(
          children: [
            if (album.isLocked)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.photo_library_rounded, size: 16),
              ),
            Flexible(
              child: Text(
                album.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (album.hidden)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.visibility_off, size: 15),
              ),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: trailing,
        ),
      ),
    );
  }
}

/// Dim + checkmark overlay shown on an album cover during multi-select.
class _SelectionOverlay extends StatelessWidget {
  const _SelectionOverlay({
    required this.selectable,
    required this.isSelected,
  });

  final bool selectable;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        if (isSelected)
          Container(color: scheme.primary.withValues(alpha: 0.25)),
        Positioned(
          top: 6,
          right: 6,
          child: selectable
              ? Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected ? scheme.primary : Colors.white,
                  shadows: const [Shadow(blurRadius: 4)],
                )
              : const Icon(Icons.lock_outline,
                  color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Shared cover
// -----------------------------------------------------------------------------

class _Cover extends StatelessWidget {
  const _Cover({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    final cover = album.coverAsset;
    if (cover == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.photo_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return AssetThumbnail(asset: cover, size: 400, showVideoBadge: false);
  }
}

void _openAlbum(BuildContext context, Album album) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AlbumDetailPage(album: album)),
  );
}

// -----------------------------------------------------------------------------
// App bar theme indicator (replaces the title) + sort menu
// -----------------------------------------------------------------------------

/// Shown where the title would be. Displays the current theme mode and lets the
/// user switch between System / Light / Dark.
class _ThemeIndicator extends StatelessWidget {
  const _ThemeIndicator({required this.controller});
  final GalleryController controller;

  static IconData _iconFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };

  static String _labelFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme',
      initialValue: controller.themeMode,
      onSelected: controller.setThemeMode,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final mode in ThemeMode.values)
          CheckedPopupMenuItem(
            value: mode,
            checked: controller.themeMode == mode,
            child: Row(
              children: [
                Icon(_iconFor(mode), size: 20),
                const SizedBox(width: 12),
                Text(_labelFor(mode)),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(controller.themeMode),
              color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            _labelFor(controller.themeMode),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.controller});
  final GalleryController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AlbumSort>(
      tooltip: 'Sort albums',
      icon: const Icon(Icons.sort_rounded),
      initialValue: controller.sort,
      onSelected: controller.setSort,
      itemBuilder: (context) => [
        for (final sort in AlbumSort.values)
          CheckedPopupMenuItem(
            value: sort,
            checked: controller.sort == sort,
            child: Text(sort.label),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Banners / states
// -----------------------------------------------------------------------------

class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.controller});
  final GalleryController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: const Text(
          'You\'ve granted access to only some photos. Manage selection to '
          'show more.'),
      leading: const Icon(Icons.info_outline),
      actions: [
        TextButton(
          onPressed: controller.presentLimitedPicker,
          child: const Text('Manage'),
        ),
      ],
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.controller});
  final GalleryController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            Text(
              'Photo access is needed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Allow access to your photos and videos so the gallery can show '
              'your albums.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: controller.loadAlbums,
              child: const Text('Grant access'),
            ),
            TextButton(
              onPressed: controller.openSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.controller});
  final GalleryController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 16),
            Text(controller.errorMessage ?? 'Something went wrong',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: controller.loadAlbums,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
