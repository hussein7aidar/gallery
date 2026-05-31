import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

/// Shows a bottom sheet with metadata for [asset]: name, type, resolution,
/// size, dates, location and (for video) duration.
Future<void> showPhotoInfo(BuildContext context, AssetEntity asset) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PhotoInfoSheet(asset: asset),
  );
}

class _PhotoInfoSheet extends StatefulWidget {
  const _PhotoInfoSheet({required this.asset});
  final AssetEntity asset;

  @override
  State<_PhotoInfoSheet> createState() => _PhotoInfoSheetState();
}

class _PhotoInfoSheetState extends State<_PhotoInfoSheet> {
  int? _fileSize;
  String? _path;
  LatLng? _latLng;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final asset = widget.asset;
    final file = await asset.file;
    final latLng = await asset.latlngAsync();
    if (!mounted) return;
    setState(() {
      if (file != null && file.existsSync()) {
        _fileSize = file.lengthSync();
        _path = file.path;
      }
      if (latLng != null &&
          (latLng.latitude != 0 || latLng.longitude != 0)) {
        _latLng = latLng;
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _formatDate(DateTime date) =>
      DateFormat('MMM d, yyyy · HH:mm').format(date);

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final isVideo = asset.type == AssetType.video;

    final rows = <_InfoRow>[
      _InfoRow(Icons.title, 'Name', asset.title ?? '—'),
      _InfoRow(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        'Type',
        asset.mimeType ?? (isVideo ? 'video' : 'image'),
      ),
      _InfoRow(Icons.aspect_ratio, 'Resolution',
          '${asset.width} × ${asset.height}'),
      if (_fileSize != null)
        _InfoRow(Icons.sd_storage_outlined, 'Size', _formatBytes(_fileSize!)),
      if (isVideo)
        _InfoRow(Icons.timer_outlined, 'Duration',
            _formatDuration(asset.videoDuration)),
      _InfoRow(Icons.event, 'Taken', _formatDate(asset.createDateTime)),
      _InfoRow(Icons.edit_calendar, 'Modified',
          _formatDate(asset.modifiedDateTime)),
      if (_latLng != null)
        _InfoRow(Icons.location_on_outlined, 'Location',
            '${_latLng!.latitude.toStringAsFixed(5)}, '
                '${_latLng!.longitude.toStringAsFixed(5)}'),
      if (_path != null) _InfoRow(Icons.folder_outlined, 'Path', _path!),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('Details',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      subtitle: SelectableText(value),
    );
  }
}
