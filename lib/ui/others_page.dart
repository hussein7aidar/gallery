import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../state/gallery_controller.dart';
import '../theme.dart';
import 'album_detail_page.dart';
import 'album_stats_sheet.dart';
import 'widgets/asset_thumbnail.dart';
import 'widgets/pressable.dart';

/// Lists the auto-generated app/system albums (WhatsApp, Telegram, …) grouped
/// under "Others". Supports the same album multi-select as the home screen, so
/// the user can hide/delete these albums from inside here.
class OthersPage extends StatefulWidget {
  const OthersPage({super.key});

  @override
  State<OthersPage> createState() => _OthersPageState();
}

class _OthersPageState extends State<OthersPage> {
  bool _selecting = false;
  final Set<String> _selected = {};

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _enterSelectionWith(Album album) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selected.add(album.id);
    });
  }

  void _toggle(Album album) => setState(() {
        if (!_selected.remove(album.id)) _selected.add(album.id);
      });

  List<Album> _selectedAlbums(GalleryController c) =>
      c.otherAlbums.where((a) => _selected.contains(a.id)).toList();

  Future<void> _setHidden(GalleryController c, bool hidden) async {
    final albums = _selectedAlbums(c);
    if (albums.isEmpty) return;
    await c.setAlbumsHidden(albums, hidden);
    _exitSelection();
  }

  Future<void> _deleteSelected(GalleryController c) async {
    final albums = _selectedAlbums(c);
    if (albums.isEmpty) return;
    final totalItems = albums.fold<int>(0, (s, a) => s + a.assetCount);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${albums.length} '
            'album${albums.length == 1 ? '' : 's'}?'),
        content: Text('All $totalItems photos and videos in the selected '
            'albums will be moved to the Bin. You can restore them from there.'),
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
    final moved = await c.deleteAlbums(albums);
    _exitSelection();
    messenger.showSnackBar(
      SnackBar(content: Text('Moved $moved item${moved == 1 ? '' : 's'} to Bin')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryController>(
      builder: (context, controller, _) {
        final albums = controller.otherAlbums; // A–Z
        // Drop ids that vanished (e.g. after hide/delete).
        _selected.retainWhere((id) => albums.any((a) => a.id == id));
        final count = _selected.length;
        final allHidden = count > 0 &&
            _selectedAlbums(controller).every((a) => a.hidden);

        return Scaffold(
          appBar: _selecting
              ? AppBar(
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
                          : () => showAlbumStats(
                              context, _selectedAlbums(controller)),
                    ),
                    IconButton(
                      tooltip: allHidden ? 'Unhide' : 'Hide',
                      icon: Icon(allHidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed:
                          count == 0 ? null : () => _setHidden(controller, !allHidden),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed:
                          count == 0 ? null : () => _deleteSelected(controller),
                    ),
                  ],
                )
              : AppBar(title: const Text('Others')),
          body: albums.isEmpty
              ? const Center(child: Text('No other albums'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: (MediaQuery.sizeOf(context).width ~/ 180)
                        .clamp(2, 6),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return _OtherCell(
                      album: album,
                      selecting: _selecting,
                      isSelected: _selected.contains(album.id),
                      onTap: () {
                        if (_selecting) {
                          _toggle(album);
                        } else {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AlbumDetailPage(album: album),
                          ));
                        }
                      },
                      onLongPress: () => _selecting
                          ? _toggle(album)
                          : _enterSelectionWith(album),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _OtherCell extends StatelessWidget {
  const _OtherCell({
    required this.album,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final Album album;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  album.coverAsset == null
                      ? ColoredBox(color: scheme.surfaceContainerHighest)
                      : AssetThumbnail(
                          asset: album.coverAsset!,
                          size: 400,
                          showVideoBadge: false,
                        ),
                  if (selecting)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: isSelected ? scheme.primary : Colors.white,
                        shadows: const [Shadow(blurRadius: 4)],
                      ),
                    ),
                  if (isSelected)
                    Container(color: scheme.primary.withValues(alpha: 0.25)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
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
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
