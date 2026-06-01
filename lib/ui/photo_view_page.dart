import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';

import '../state/gallery_controller.dart';
import 'photo_info_sheet.dart';

/// Full-screen, swipeable viewer.
///
/// Images support two-finger pinch-zoom and **two-finger rotation** (via
/// photo_view's `enableRotation`) — this rotates the image itself, independent
/// of the device's auto-rotate setting. The bottom bar exposes Info, Open in
/// Google Photos and Delete. Videos show a play button that hands off to an
/// external player.
///
/// Pops with the set of deleted asset ids so the caller can update its grid.
class PhotoViewPage extends StatefulWidget {
  const PhotoViewPage({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.albumName,
  });

  final List<AssetEntity> assets;
  final int initialIndex;
  final String albumName;

  @override
  State<PhotoViewPage> createState() => _PhotoViewPageState();
}

class _PhotoViewPageState extends State<PhotoViewPage> {
  late final PageController _pageController;
  late final List<AssetEntity> _assets;
  late int _index;
  final Set<String> _deleted = {};
  bool _chromeVisible = true;

  /// One controller per item, so we can snap rotation to the nearest 90°
  /// (horizontal/vertical) when the two-finger gesture ends — for both photos
  /// and videos.
  final Map<String, PhotoViewController> _controllers = {};

  /// The settled quarter-turn count per item, so we only re-fit on a real
  /// orientation change (and leave plain pinch-zoom alone).
  final Map<String, int> _settledSteps = {};

  PhotoViewController _controllerFor(String id) =>
      _controllers.putIfAbsent(id, PhotoViewController.new);

  /// Called when a two-finger gesture ends. Snaps rotation to the nearest
  /// horizontal/vertical orientation and, when the orientation changed, scales
  /// the item so the whole photo/video fits the screen (even if small).
  void _onGestureEnd(String id, Size content) {
    final controller = _controllers[id];
    if (controller == null) return;
    const quarter = math.pi / 2;
    final steps = (controller.rotation / quarter).round();
    controller.rotation = steps * quarter; // snap to horizontal / vertical

    if (steps != (_settledSteps[id] ?? 0)) {
      final swapped = steps.isOdd; // 90° / 270° → width and height swap
      final viewport = MediaQuery.sizeOf(context);
      final w = content.width, h = content.height;
      final fit = swapped
          ? math.min(viewport.width / h, viewport.height / w)
          : math.min(viewport.width / w, viewport.height / h);
      controller.scale = fit;
      controller.position = Offset.zero;
    }
    _settledSteps[id] = steps;
  }

  AssetEntity get _current => _assets[_index];

  @override
  void initState() {
    super.initState();
    _assets = List.of(widget.assets);
    _index = widget.initialIndex.clamp(0, _assets.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_deleted);

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  Future<void> _openInGooglePhotos() async {
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    final launched = await controller.openInGooglePhotos(_current);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app available to open this item')),
      );
    }
  }

  Future<void> _showInfo() => showPhotoInfo(context, _current);

  Future<void> _delete() async {
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this item?'),
        content: const Text(
            'It will be permanently removed from your device.'),
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

    final id = _current.id;
    final ok = await controller.deleteAsset(id);
    if (!ok || !mounted) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not delete item')),
        );
      }
      return;
    }

    _deleted.add(id);
    controller.onAssetsDeleted();
    setState(() {
      _assets.removeWhere((a) => a.id == id);
      if (_assets.isEmpty) return;
      if (_index >= _assets.length) _index = _assets.length - 1;
    });
    if (_assets.isEmpty) {
      _close();
    } else {
      _pageController.jumpToPage(_index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: _chromeVisible
            ? AppBar(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _close,
                ),
                title: Text(
                  '${_index + 1} / ${_assets.length}',
                  style: const TextStyle(fontSize: 16),
                ),
              )
            : null,
        body: Stack(
          children: [
            PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: _assets.length,
              onPageChanged: (i) => setState(() => _index = i),
              backgroundDecoration:
                  const BoxDecoration(color: Colors.black),
              enableRotation: true, // two-finger rotation of the image itself
              scrollPhysics: const BouncingScrollPhysics(),
              builder: (context, index) {
                final asset = _assets[index];
                if (asset.type == AssetType.video) {
                  return _videoPage(asset);
                }
                return PhotoViewGalleryPageOptions(
                  imageProvider:
                      AssetEntityImageProvider(asset, isOriginal: true),
                  controller: _controllerFor(asset.id),
                  minScale: PhotoViewComputedScale.contained * 0.4,
                  maxScale: PhotoViewComputedScale.covered * 4,
                  onScaleEnd: (context, details, value) => _onGestureEnd(
                    asset.id,
                    Size(asset.width.toDouble(), asset.height.toDouble()),
                  ),
                  onTapUp: (context, details, value) => _toggleChrome(),
                );
              },
              loadingBuilder: (context, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
            if (_chromeVisible) _bottomBar(),
          ],
        ),
      ),
    );
  }

  PhotoViewGalleryPageOptions _videoPage(AssetEntity asset) {
    return PhotoViewGalleryPageOptions.customChild(
      childSize: Size(asset.width.toDouble(), asset.height.toDouble()),
      controller: _controllerFor(asset.id),
      minScale: PhotoViewComputedScale.contained * 0.4,
      maxScale: PhotoViewComputedScale.covered * 2,
      onScaleEnd: (context, details, value) => _onGestureEnd(
        asset.id,
        Size(asset.width.toDouble(), asset.height.toDouble()),
      ),
      onTapUp: (context, details, value) => _toggleChrome(),
      child: GestureDetector(
        onTap: _openInGooglePhotos,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AssetEntityImage(
              asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(800),
              fit: BoxFit.contain,
            ),
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 72),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    // Google Photos hand-off is Android-only; hide it elsewhere (e.g. iOS).
    final canOpenInGooglePhotos =
        context.read<GalleryController>().canOpenInGooglePhotos;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black45,
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BarButton(
              icon: Icons.info_outline,
              label: 'Info',
              onTap: _showInfo,
            ),
            if (canOpenInGooglePhotos)
              _BarButton(
                icon: Icons.photo_library_outlined,
                label: 'Google Photos',
                onTap: _openInGooglePhotos,
              ),
            _BarButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: _delete,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
