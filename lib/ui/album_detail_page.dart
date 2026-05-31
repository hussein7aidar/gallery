import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../state/gallery_controller.dart';
import 'photo_view_page.dart';
import 'widgets/asset_thumbnail.dart';

/// A paginated, day-grouped grid of the photos/videos inside an [Album].
///
/// Supports a multi-select mode: long-press (or the select action) enters it,
/// each day header carries a checkbox that selects/deselects that whole day,
/// and selected items can be deleted in bulk. There is intentionally no
/// "select all".
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.album});
  final Album album;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

/// One day's worth of assets.
class _DaySection {
  _DaySection(this.day, this.items);
  final DateTime day;
  final List<AssetEntity> items;
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  static const _pageSize = 90;

  final List<AssetEntity> _assets = [];
  final ScrollController _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;

  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final batch =
        await widget.album.path.getAssetListPaged(page: _page, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets.addAll(batch);
      _page++;
      _hasMore = batch.length == _pageSize;
      _loading = false;
    });
  }

  // --- grouping ---

  List<_DaySection> get _sections {
    final sections = <_DaySection>[];
    for (final asset in _assets) {
      final d = asset.createDateTime;
      final day = DateTime(d.year, d.month, d.day);
      if (sections.isEmpty || sections.last.day != day) {
        sections.add(_DaySection(day, [asset]));
      } else {
        sections.last.items.add(asset);
      }
    }
    return sections;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, MMM d, yyyy').format(day);
  }

  // --- selection ---

  void _enterSelection([AssetEntity? first]) {
    setState(() {
      _selecting = true;
      if (first != null) _selected.add(first.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleAsset(AssetEntity asset) {
    setState(() {
      if (!_selected.remove(asset.id)) _selected.add(asset.id);
    });
  }

  bool _dayFullySelected(_DaySection section) =>
      section.items.every((a) => _selected.contains(a.id));

  void _toggleDay(_DaySection section) {
    final allSelected = _dayFullySelected(section);
    setState(() {
      for (final asset in section.items) {
        if (allSelected) {
          _selected.remove(asset.id);
        } else {
          _selected.add(asset.id);
        }
      }
    });
  }

  Future<void> _openViewer(AssetEntity asset) async {
    final index = _assets.indexWhere((a) => a.id == asset.id);
    if (index < 0) return;
    final deletedIds = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => PhotoViewPage(
          assets: List.of(_assets),
          initialIndex: index,
          albumName: widget.album.displayName,
        ),
      ),
    );
    if (deletedIds != null && deletedIds.isNotEmpty && mounted) {
      setState(() {
        _assets.removeWhere((a) => deletedIds.contains(a.id));
        _selected.removeAll(deletedIds);
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        title: Text('Delete $count item${count == 1 ? '' : 's'}?'),
        content: const Text(
            'They will be permanently removed from your device.'),
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

    final removed = await controller.deleteAssets(_selected.toList());
    if (removed.isNotEmpty) controller.onAssetsDeleted();
    if (!mounted) return;
    setState(() {
      _assets.removeWhere((a) => removed.contains(a.id));
      _selecting = false;
      _selected.clear();
    });
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${removed.length} '
          'item${removed.length == 1 ? '' : 's'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width ~/ 120).clamp(3, 6);
    final sections = _sections;

    return Scaffold(
      appBar: _selecting ? _selectionAppBar() : _normalAppBar(),
      body: _assets.isEmpty && !_loading
          ? const Center(child: Text('This album is empty'))
          : CustomScrollView(
              controller: _scroll,
              slivers: [
                for (final section in sections) ...[
                  SliverToBoxAdapter(
                    child: _DayHeader(
                      label: _dayLabel(section.day),
                      count: section.items.length,
                      selecting: _selecting,
                      selected: _dayFullySelected(section),
                      onToggleDay: () => _toggleDay(section),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    sliver: SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final asset = section.items[i];
                          return _AssetCell(
                            asset: asset,
                            selecting: _selecting,
                            isSelected: _selected.contains(asset.id),
                            onTap: () => _selecting
                                ? _toggleAsset(asset)
                                : _openViewer(asset),
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              if (_selecting) {
                                _toggleAsset(asset);
                              } else {
                                _enterSelection(asset);
                              }
                            },
                            // Preview opens full screen without changing the
                            // current selection.
                            onPreview: () => _openViewer(asset),
                          );
                        },
                        childCount: section.items.length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }

  AppBar _normalAppBar() {
    return AppBar(
      title: Text(widget.album.displayName),
      actions: [
        if (_assets.isNotEmpty)
          IconButton(
            tooltip: 'Select',
            icon: const Icon(Icons.checklist_rounded),
            onPressed: () => _enterSelection(),
          ),
      ],
    );
  }

  AppBar _selectionAppBar() {
    final count = _selected.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text(count == 0 ? 'Select items' : '$count selected'),
      actions: [
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: count == 0 ? null : _deleteSelected,
        ),
      ],
    );
  }
}

/// A date section header. In selection mode it carries a checkbox that selects
/// or deselects the whole day's photos and videos.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.count,
    required this.selecting,
    required this.selected,
    required this.onToggleDay,
  });

  final String label;
  final int count;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleDay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (selecting)
            TextButton.icon(
              onPressed: onToggleDay,
              icon: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
              ),
              label: Text(selected ? 'Deselect day' : 'Select day'),
            )
          else
            Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }
}

class _AssetCell extends StatelessWidget {
  const _AssetCell({
    required this.asset,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onPreview,
  });

  final AssetEntity asset;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Opens the full-screen preview without affecting selection.
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(isSelected ? 6 : 0),
            child: AssetThumbnail(asset: asset, size: 300),
          ),
          if (selecting) ...[
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: isSelected ? scheme.primary : Colors.white,
                shadows: const [Shadow(blurRadius: 4)],
                size: 22,
              ),
            ),
            // Bottom-right preview button. Its own gesture handler swallows the
            // tap so it doesn't toggle selection.
            Positioned(
              bottom: 2,
              right: 2,
              child: GestureDetector(
                onTap: onPreview,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
