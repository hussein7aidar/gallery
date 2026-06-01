import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';

import '../state/gallery_controller.dart';
import 'photo_info_sheet.dart';

/// Full-screen, swipeable viewer with pinch-to-zoom. The bottom bar exposes
/// Info, Open in Google Photos and Delete. Videos show a play button that hands
/// off to an external player.
///
/// Pops with the set of deleted asset ids so the caller can update its grid.
class PhotoViewPage extends StatefulWidget {
  const PhotoViewPage({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.albumName,
    this.stackId,
  });

  final List<AssetEntity> assets;
  final int initialIndex;
  final String albumName;

  /// When set, the viewer is showing a stack's versions: it offers "Set as
  /// cover" and "Ungroup" actions.
  final String? stackId;

  @override
  State<PhotoViewPage> createState() => _PhotoViewPageState();
}

class _PhotoViewPageState extends State<PhotoViewPage> {
  late final PageController _pageController;
  late final List<AssetEntity> _assets;
  late int _index;
  final Set<String> _deleted = {};
  bool _chromeVisible = true;

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

    final toBin = controller.binSupported;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(toBin ? 'Move this item to Bin?' : 'Delete this item?'),
        content: Text(toBin
            ? 'You can restore it from the Bin.'
            : 'It will be permanently removed from your device.'),
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

    final id = _current.id;
    bool ok;
    try {
      ok = await controller.trashAssets([_current]);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Delete failed: $e'),
          duration: const Duration(seconds: 6),
        ));
      }
      return;
    }
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

  List<Widget> _stackActions() {
    return [
      TextButton.icon(
        onPressed: _setAsCover,
        icon: const Icon(Icons.star_outline, color: Colors.white, size: 18),
        label: const Text('Set as cover',
            style: TextStyle(color: Colors.white)),
      ),
      PopupMenuButton<String>(
        iconColor: Colors.white,
        onSelected: (v) {
          if (v == 'ungroup') _ungroup();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'ungroup', child: Text('Ungroup stack')),
        ],
      ),
    ];
  }

  Future<void> _setAsCover() async {
    final controller = context.read<GalleryController>();
    final messenger = ScaffoldMessenger.of(context);
    await controller.setStackCover(widget.stackId!, _current.id);
    messenger.showSnackBar(
      const SnackBar(content: Text('Stack cover updated')),
    );
  }

  Future<void> _ungroup() async {
    await context.read<GalleryController>().ungroupStack(widget.stackId!);
    if (mounted) _close();
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
                  widget.stackId != null
                      ? 'Version ${_index + 1} / ${_assets.length}'
                      : '${_index + 1} / ${_assets.length}',
                  style: const TextStyle(fontSize: 16),
                ),
                actions: widget.stackId == null ? null : _stackActions(),
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
              scrollPhysics: const BouncingScrollPhysics(),
              builder: (context, index) {
                final asset = _assets[index];
                if (asset.type == AssetType.video) {
                  return _videoPage(asset);
                }
                return PhotoViewGalleryPageOptions(
                  imageProvider:
                      AssetEntityImageProvider(asset, isOriginal: true),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 4,
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
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2,
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
