import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../state/gallery_controller.dart';
import 'photo_view_page.dart';
import 'widgets/asset_thumbnail.dart';

/// The recycle bin: items moved here can be restored to their original album or
/// permanently deleted. Items older than the retention window are auto-purged.
class BinPage extends StatefulWidget {
  const BinPage({super.key});

  @override
  State<BinPage> createState() => _BinPageState();
}

class _BinPageState extends State<BinPage> {
  List<AssetEntity>? _assets;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<GalleryController>();
    // Remove anything past the auto-delete window (no-op when set to "never").
    await controller.purgeExpiredBin();
    final assets = await controller.loadBin();
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _selected.retainWhere((id) => assets.any((a) => a.id == id));
    });
  }

  Future<void> _preview(AssetEntity asset) async {
    final index = _assets!.indexWhere((a) => a.id == asset.id);
    if (index < 0) return;
    await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => PhotoViewPage(
          assets: List.of(_assets!),
          initialIndex: index,
          albumName: 'Bin',
        ),
      ),
    );
    if (mounted) await _load();
  }

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  List<AssetEntity> get _selectedAssets =>
      _assets!.where((a) => _selected.contains(a.id)).toList();

  Future<void> _restore() async {
    if (_selected.isEmpty || _busy) return;
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;
    setState(() => _busy = true);
    bool ok;
    try {
      ok = await controller.restoreFromBin(_selectedAssets);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text('Restore failed: $e'),
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Restored $count item${count == 1 ? '' : 's'}'
          : 'Could not restore'),
    ));
    if (ok) {
      _selected.clear();
      await _load();
    }
  }

  Future<void> _deleteForever() async {
    if (_selected.isEmpty || _busy) return;
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Permanently delete $count item${count == 1 ? '' : 's'}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final removed =
        await controller.deleteForever(_selectedAssets.map((a) => a.id).toList());
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content:
          Text('Deleted ${removed.length} item${removed.length == 1 ? '' : 's'}'),
    ));
    _selected.clear();
    await _load();
  }

  void _toggleSelectAll() {
    final assets = _assets;
    if (assets == null) return;
    setState(() {
      if (_selected.length == assets.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(assets.map((a) => a.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final assets = _assets;
    final count = _selected.length;
    final allSelected =
        assets != null && assets.isNotEmpty && count == assets.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(count == 0 ? 'Bin' : '$count selected'),
        actions: [
          if (assets != null && assets.isNotEmpty)
            IconButton(
              tooltip: allSelected ? 'Clear selection' : 'Select all',
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
              onPressed: _busy ? null : _toggleSelectAll,
            ),
          IconButton(
            tooltip: 'Restore',
            icon: const Icon(Icons.restore_from_trash_outlined),
            onPressed: count == 0 || _busy ? null : _restore,
          ),
          IconButton(
            tooltip: 'Delete forever',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: count == 0 || _busy ? null : _deleteForever,
          ),
        ],
      ),
      body: assets == null
          ? const Center(child: CircularProgressIndicator())
          : assets.isEmpty
              ? const Center(child: Text('Bin is empty'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        context.read<GalleryController>().binRetentionDays <= 0
                            ? 'Items here stay until you restore or permanently '
                                'delete them.'
                            : 'Items are automatically deleted '
                                '${context.read<GalleryController>().binRetentionDays}'
                                ' days after they were removed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(2),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              (MediaQuery.sizeOf(context).width ~/ 120)
                                  .clamp(3, 6),
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: assets.length,
                        itemBuilder: (context, index) {
                          final asset = assets[index];
                          final selected = _selected.contains(asset.id);
                          final daysLeft = context
                              .read<GalleryController>()
                              .binDaysLeftFor(asset.id);
                          return GestureDetector(
                            onTap: () => _toggle(asset.id),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Padding(
                                  padding: EdgeInsets.all(selected ? 6 : 0),
                                  child: AssetThumbnail(asset: asset, size: 300),
                                ),
                                if (daysLeft != null)
                                  Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: _DaysLeftBadge(daysLeft: daysLeft),
                                  ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white,
                                    shadows: const [Shadow(blurRadius: 4)],
                                    size: 22,
                                  ),
                                ),
                                // Preview button — opens full screen without
                                // changing the selection.
                                Positioned(
                                  right: 2,
                                  bottom: 2,
                                  child: GestureDetector(
                                    onTap: () => _preview(asset),
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      margin: const EdgeInsets.all(2),
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black45,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.fullscreen,
                                          color: Colors.white, size: 18),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Small badge showing how long until an item is auto-deleted.
class _DaysLeftBadge extends StatelessWidget {
  const _DaysLeftBadge({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final urgent = daysLeft <= 3;
    final label = daysLeft <= 0
        ? 'Deleting…'
        : daysLeft == 1
            ? '1 day left'
            : '$daysLeft days left';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: urgent ? Colors.red.withValues(alpha: 0.85) : Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}
