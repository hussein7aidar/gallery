import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/media_stack.dart';
import '../state/gallery_controller.dart';
import 'photo_view_page.dart';
import 'widgets/asset_thumbnail.dart';
import 'widgets/name_input_dialog.dart';
import 'widgets/pressable.dart';

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

  // --- drag-to-select state ---
  /// True while a long-press-and-drag selection is in progress.
  bool _dragSelecting = false;

  /// Index in [_assets] where the current drag began.
  int? _dragAnchorIndex;

  /// Last cell index the finger was over, to avoid redundant rebuilds.
  int? _dragLastIndex;

  /// Whether the drag adds (true) or removes (false) items from the selection.
  bool _dragSelectValue = true;

  /// Selection snapshot at drag start, so dragging back unselects correctly.
  Set<String> _dragBaseSelection = {};

  /// Wraps the scrollable so we can hit-test cells under the moving finger.
  final GlobalKey _gridKey = GlobalKey();

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
    final controller = context.read<GalleryController>();
    final batch =
        await widget.album.path.getAssetListPaged(page: _page, size: _pageSize);
    if (!mounted) return;
    // Binned items physically remain on disk; hide them while browsing.
    final visible = batch.where((a) => !controller.isBinned(a.id)).toList();
    setState(() {
      _assets.addAll(visible);
      _page++;
      _hasMore = batch.length == _pageSize;
      _loading = false;
    });
    // Auto-group burst/original variants now loaded; collapse them if any.
    final grouped = await controller.autoGroupAssets(_assets);
    if (grouped && mounted) setState(() {});
  }

  // --- grouping ---

  List<_DaySection> get _sections {
    final controller = context.read<GalleryController>();
    final sections = <_DaySection>[];
    for (final asset in _assets) {
      // Non-cover members of a stack are collapsed into their cover tile —
      // except in selection mode, where the stack expands so each version can
      // be selected, deleted, or moved individually.
      if (!_selecting && controller.isHiddenStackMember(asset.id)) continue;
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

  /// Confirms before throwing away an in-progress selection.
  Future<void> _confirmExitSelection() async {
    if (_selected.isEmpty) {
      _exitSelection();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel selection?'),
        content: Text('You\'ll lose the ${_selected.length} '
            'item${_selected.length == 1 ? '' : 's'} you selected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep selecting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) _exitSelection();
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

  // --- drag-to-select (long-press a thumbnail, then slide) ---

  /// Starts a drag selection anchored on the long-pressed cell. Turns on
  /// selection mode if needed. If the anchor was already selected, the drag
  /// removes items instead of adding them.
  void _startDragSelect(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _dragSelecting = true;
      _dragAnchorIndex = index;
      _dragLastIndex = index;
      _dragBaseSelection = {..._selected};
      _dragSelectValue = !_selected.contains(_assets[index].id);
      _applyDragRange(index);
    });
  }

  /// Re-applies the selection for the inclusive range between the anchor and
  /// [current], starting from the snapshot taken at drag start.
  void _applyDragRange(int current) {
    final anchor = _dragAnchorIndex;
    if (anchor == null) return;
    final lo = math.min(anchor, current);
    final hi = math.max(anchor, current);
    final next = {..._dragBaseSelection};
    for (var i = lo; i <= hi && i < _assets.length; i++) {
      final id = _assets[i].id;
      if (_dragSelectValue) {
        next.add(id);
      } else {
        next.remove(id);
      }
    }
    _selected
      ..clear()
      ..addAll(next);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_dragSelecting) return;
    final index = _cellIndexAt(event.position);
    if (index == null || index == _dragLastIndex) return;
    setState(() {
      _dragLastIndex = index;
      _applyDragRange(index);
    });
  }

  void _endDragSelect() {
    if (!_dragSelecting) return;
    setState(() {
      _dragSelecting = false;
      _dragAnchorIndex = null;
      _dragLastIndex = null;
    });
  }

  /// Hit-tests the grid at a global position and returns the [_assets] index of
  /// the cell under it (cells carry their index via a [MetaData] widget).
  int? _cellIndexAt(Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(globalPosition));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is int) {
        return target.metaData as int;
      }
    }
    return null;
  }

  Future<void> _openViewer(AssetEntity asset) async {
    final controller = context.read<GalleryController>();
    // Swipe only through visible tiles (stack covers, not hidden members).
    final display = _assets
        .where((a) => !controller.isHiddenStackMember(a.id))
        .toList();
    final index = display.indexWhere((a) => a.id == asset.id);
    if (index < 0) return;
    final deletedIds = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => PhotoViewPage(
          assets: display,
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
      _popIfEmpty();
    }
  }

  /// Opens a stack's versions full-screen (cover first), where the user can
  /// switch versions, pick the cover, or ungroup.
  Future<void> _openStack(MediaStack stack) async {
    final members = <AssetEntity>[];
    for (final id in stack.memberIds) {
      AssetEntity? asset;
      for (final a in _assets) {
        if (a.id == id) {
          asset = a;
          break;
        }
      }
      asset ??= await AssetEntity.fromId(id);
      if (asset != null) members.add(asset);
    }
    if (members.isEmpty || !mounted) return;
    var coverIndex = members.indexWhere((a) => a.id == stack.coverId);
    if (coverIndex < 0) coverIndex = 0;

    final deletedIds = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => PhotoViewPage(
          assets: members,
          initialIndex: coverIndex,
          albumName: '${members.length} versions',
          stackId: stack.id,
        ),
      ),
    );
    if (deletedIds != null && deletedIds.isNotEmpty && mounted) {
      setState(() {
        _assets.removeWhere((a) => deletedIds.contains(a.id));
        _selected.removeAll(deletedIds);
      });
      _popIfEmpty();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;

    final toBin = controller.binSupported;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(toBin
            ? 'Move $count item${count == 1 ? '' : 's'} to Bin?'
            : 'Delete $count item${count == 1 ? '' : 's'}?'),
        content: Text(toBin
            ? 'You can restore them from the Bin.'
            : 'They will be permanently removed from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(toBin ? 'Move to Bin' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final assets = _assets.where((a) => _selected.contains(a.id)).toList();
    final movedIds = assets.map((a) => a.id).toSet();
    bool ok;
    try {
      ok = await controller.trashAssets(assets);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Delete failed: $e'),
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete the selected items')),
      );
      return;
    }
    setState(() {
      _assets.removeWhere((a) => movedIds.contains(a.id));
      _selecting = false;
      _selected.clear();
    });
    messenger.showSnackBar(
      SnackBar(content: Text(toBin
          ? 'Moved ${movedIds.length} item${movedIds.length == 1 ? '' : 's'} to Bin'
          : 'Deleted ${movedIds.length} '
              'item${movedIds.length == 1 ? '' : 's'}')),
    );
    _popIfEmpty();
  }

  /// Leaves the album once it has no media left (it no longer exists on the
  /// device, so there's nothing to show). If more pages remain, loads the next
  /// one instead so the grid doesn't look empty prematurely.
  void _popIfEmpty() {
    if (_assets.isNotEmpty) return;
    if (_hasMore) {
      _loadMore();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _moveSelected() async {
    if (_selected.isEmpty) return;
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final assets =
        _assets.where((a) => _selected.contains(a.id)).toList();

    // The picker returns an existing Album, or a String for a new album name.
    final target = await _pickDestination(controller);
    if (target == null || !mounted) return;

    final bool ok;
    final String destName;
    try {
      if (target is Album) {
        ok = await controller.moveAssets(assets, target);
        destName = target.displayName;
      } else {
        final name = target as String;
        ok = await controller.createAlbum(name, assets);
        destName = name;
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Move failed: $e'),
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not move the selected items')),
      );
      return;
    }
    final movedIds = assets.map((a) => a.id).toSet();
    setState(() {
      _assets.removeWhere((a) => movedIds.contains(a.id));
      _selecting = false;
      _selected.clear();
    });
    messenger.showSnackBar(
      SnackBar(content: Text('Moved ${movedIds.length} '
          'item${movedIds.length == 1 ? '' : 's'} to $destName')),
    );
    _popIfEmpty();
  }

  /// Creates a new album directly from the current selection.
  Future<void> _createAlbumFromSelection() async {
    if (_selected.isEmpty) return;
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final assets = _assets.where((a) => _selected.contains(a.id)).toList();

    final name = await _promptAlbumName();
    if (name == null || name.trim().isEmpty || !mounted) return;

    final movedIds = assets.map((a) => a.id).toSet();
    final ok = await controller.createAlbum(name.trim(), assets);
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create the album')),
      );
      return;
    }
    setState(() {
      _assets.removeWhere((a) => movedIds.contains(a.id));
      _selecting = false;
      _selected.clear();
    });
    messenger.showSnackBar(
      SnackBar(content: Text('Created "${name.trim()}" with '
          '${movedIds.length} item${movedIds.length == 1 ? '' : 's'}')),
    );
    _popIfEmpty();
  }

  /// Prompts for a new album name. Returns null if cancelled.
  Future<String?> _promptAlbumName() => showNameInputDialog(
        context,
        title: 'New album',
        confirmLabel: 'Create',
      );

  /// Bottom-sheet picker of destination albums (excludes this album and the
  /// locked "All Photos"). Returns an [Album], or a [String] when the user
  /// chooses to create a new album.
  Future<Object?> _pickDestination(GalleryController controller) {
    final destinations = controller.moveDestinations(widget.album.id);
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Move to album',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Create new album'),
                onTap: () async {
                  final name = await _promptAlbumName();
                  if (name != null && name.trim().isNotEmpty) {
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext, name.trim());
                    }
                  }
                },
              ),
              const Divider(height: 1),
              if (destinations.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No other albums to move into.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: destinations.length,
                    itemBuilder: (context, i) {
                      final album = destinations[i];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: album.coverAsset == null
                                ? const ColoredBox(color: Colors.black12)
                                : AssetThumbnail(
                                    asset: album.coverAsset!,
                                    size: 200,
                                    showVideoBadge: false,
                                  ),
                          ),
                        ),
                        title: Text(album.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${album.assetCount} '
                            'item${album.assetCount == 1 ? '' : 's'}'),
                        onTap: () => Navigator.pop(sheetContext, album),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width ~/ 120).clamp(3, 6);
    final sections = _sections;

    return PopScope(
      // While selecting, the back gesture cancels the selection (with a
      // confirmation) instead of leaving the album.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExitSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionAppBar() : _normalAppBar(),
        body: _assets.isEmpty && !_loading
            ? const Center(child: Text('This album is empty'))
            : Listener(
                onPointerMove: _onPointerMove,
                onPointerUp: (_) => _endDragSelect(),
                onPointerCancel: (_) => _endDragSelect(),
                child: KeyedSubtree(
                  key: _gridKey,
                  child: CustomScrollView(
                    controller: _scroll,
                    // Freeze scrolling while a drag-selection is in progress.
                    physics: _dragSelecting
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    slivers: _buildSlivers(sections, columns),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildSlivers(List<_DaySection> sections, int columns) {
    final slivers = <Widget>[];
    // True index of each asset within _assets, so drag-select stays correct
    // regardless of whether stacks are collapsed or expanded.
    final assetIndex = <String, int>{
      for (var k = 0; k < _assets.length; k++) _assets[k].id: k,
    };
    for (final section in sections) {
      slivers.add(
        SliverToBoxAdapter(
          child: _DayHeader(
            label: _dayLabel(section.day),
            count: section.items.length,
            selecting: _selecting,
            selected: _dayFullySelected(section),
            onToggleDay: () => _toggleDay(section),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final asset = section.items[i];
                final globalIndex = assetIndex[asset.id] ?? 0;
                final stack =
                    context.read<GalleryController>().stackForAsset(asset.id);
                final stackCount =
                    stack != null && stack.coverId == asset.id
                        ? stack.count
                        : null;
                // MetaData carries the index so a moving finger can be
                // hit-tested to the cell underneath it during drag-select.
                return MetaData(
                  metaData: globalIndex,
                  behavior: HitTestBehavior.opaque,
                  child: _AssetCell(
                    asset: asset,
                    selecting: _selecting,
                    isSelected: _selected.contains(asset.id),
                    stackCount: stackCount,
                    onTap: () {
                      if (_selecting) {
                        _toggleAsset(asset);
                      } else if (stack != null) {
                        _openStack(stack);
                      } else {
                        _openViewer(asset);
                      }
                    },
                    // Long-press anchors a drag-select; sliding selects more.
                    onLongPress: () => _startDragSelect(globalIndex),
                    // Preview opens full screen without changing the selection.
                    onPreview: () =>
                        stack != null ? _openStack(stack) : _openViewer(asset),
                  ),
                );
              },
              childCount: section.items.length,
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
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
    final controller = context.read<GalleryController>();
    final count = _selected.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _confirmExitSelection,
      ),
      title: Text(count == 0 ? 'Select items' : '$count selected'),
      actions: [
        if (controller.binSupported)
          IconButton(
            tooltip: 'Create new album',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: count == 0 ? null : _createAlbumFromSelection,
          ),
        if (controller.canMoveBetweenAlbums)
          IconButton(
            tooltip: 'Move to album',
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: count == 0 ? null : _moveSelected,
          ),
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
    this.stackCount,
  });

  final AssetEntity asset;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Opens the full-screen preview without affecting selection.
  final VoidCallback onPreview;

  /// When non-null, this tile is a stack cover; shows a "layers ×N" badge.
  final int? stackCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(isSelected ? 6 : 0),
            child: AssetThumbnail(asset: asset, size: 300),
          ),
          if (stackCount != null && !selecting)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers, color: Colors.white, size: 13),
                    const SizedBox(width: 2),
                    Text('$stackCount',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
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
