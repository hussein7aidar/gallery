import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/album_stats.dart';
import '../state/gallery_controller.dart';

/// Shows an info sheet for the currently selected albums.
///
/// For a single album it shows the full details (name, folder, date range,
/// counts, size). For several albums it shows only the aggregatable figures
/// (album count, item count, photos/videos, total size).
Future<void> showAlbumStats(BuildContext context, List<Album> albums) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AlbumStatsSheet(albums: albums),
  );
}

class _AlbumStatsSheet extends StatefulWidget {
  const _AlbumStatsSheet({required this.albums});
  final List<Album> albums;

  @override
  State<_AlbumStatsSheet> createState() => _AlbumStatsSheetState();
}

class _AlbumStatsSheetState extends State<_AlbumStatsSheet> {
  AlbumStats? _stats;

  bool get _isSingle => widget.albums.length == 1;

  /// Item total is known up-front from the cached album counts.
  int get _quickItemTotal =>
      widget.albums.fold(0, (sum, a) => sum + a.assetCount);

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    final stats =
        await context.read<GalleryController>().computeAlbumStats(widget.albums);
    if (mounted) setState(() => _stats = stats);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _dateRange(AlbumStats stats) {
    final fmt = DateFormat('MMM d, yyyy');
    if (stats.oldest == null || stats.newest == null) return '—';
    final a = fmt.format(stats.oldest!);
    final b = fmt.format(stats.newest!);
    return a == b ? a : '$a – $b';
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final title = _isSingle
        ? widget.albums.first.displayName
        : '${widget.albums.length} albums';

    final pending = stats == null;

    final rows = <Widget>[
      if (!_isSingle)
        _StatRow(
          icon: Icons.photo_album_outlined,
          label: 'Albums',
          value: '${widget.albums.length}',
        ),
      _StatRow(
        icon: Icons.collections_outlined,
        label: 'Photos & videos',
        value: '${stats?.totalItems ?? _quickItemTotal}',
      ),
      _StatRow(
        icon: Icons.image_outlined,
        label: 'Photos',
        value: pending ? null : '${stats.photoCount}',
      ),
      _StatRow(
        icon: Icons.videocam_outlined,
        label: 'Videos',
        value: pending ? null : '${stats.videoCount}',
      ),
      _StatRow(
        icon: Icons.sd_storage_outlined,
        label: 'Total size',
        value: pending ? null : _formatBytes(stats.totalBytes),
      ),
      if (_isSingle) ...[
        _StatRow(
          icon: Icons.date_range_outlined,
          label: 'Date range',
          value: pending ? null : _dateRange(stats),
        ),
        _StatRow(
          icon: Icons.folder_outlined,
          label: 'Folder',
          value: widget.albums.first.originalName,
        ),
      ],
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pending)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Calculating…',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.label, this.value});
  final IconData icon;
  final String label;

  /// Null renders a small spinner (value still being computed).
  final String? value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      trailing: value == null
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(value!,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}
