import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// A square thumbnail for an [AssetEntity], with a video duration badge.
class AssetThumbnail extends StatelessWidget {
  const AssetThumbnail({
    super.key,
    required this.asset,
    this.size = 300,
    this.showVideoBadge = true,
  });

  final AssetEntity asset;
  final int size;
  final bool showVideoBadge;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        AssetEntityImage(
          asset,
          isOriginal: false,
          thumbnailSize: ThumbnailSize.square(size),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : placeholder,
          errorBuilder: (context, error, stack) => placeholder,
        ),
        if (showVideoBadge && asset.type == AssetType.video)
          Positioned(
            right: 6,
            bottom: 6,
            child: _DurationBadge(duration: asset.videoDuration),
          ),
      ],
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});
  final Duration duration;

  String get _formatted {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 2),
          Text(_formatted,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
