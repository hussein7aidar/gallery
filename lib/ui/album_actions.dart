import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../state/gallery_controller.dart';

/// Bottom sheet of actions for a long-pressed album. The locked "All Photos"
/// album never reaches here (it has no actions).
Future<void> showAlbumActions(BuildContext context, Album album) async {
  final controller = context.read<GalleryController>();
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                album.displayName,
                style: Theme.of(sheetContext).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              subtitle: const Text('Emoji allowed 🙂'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showRenameDialog(context, album);
              },
            ),
            ListTile(
              leading:
                  Icon(album.hidden ? Icons.visibility : Icons.visibility_off),
              title: Text(album.hidden ? 'Unhide' : 'Hide'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await controller.setAlbumHidden(album, !album.hidden);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await confirmDeleteAlbum(context, album);
              },
            ),
          ],
        ),
      );
    },
  );
}

/// Rename dialog. The text field accepts any characters including emoji; an
/// empty value clears the override and restores the original folder name.
Future<void> showRenameDialog(BuildContext context, Album album) async {
  final controller = context.read<GalleryController>();
  final field = TextEditingController(text: album.displayName);
  final messenger = ScaffoldMessenger.of(context);

  final newName = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Rename album'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(
            hintText: album.originalName,
            helperText: 'Leave empty to restore "${album.originalName}"',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, field.text),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  field.dispose();
  if (newName == null) return;
  await controller.renameAlbum(album, newName);
  messenger.showSnackBar(
    const SnackBar(content: Text('Album renamed')),
  );
}

/// Delete confirmation. Deleting an album removes all of its photos and videos
/// from the device, so we warn clearly before doing it.
Future<void> confirmDeleteAlbum(BuildContext context, Album album) async {
  final controller = context.read<GalleryController>();
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: Text('Delete "${album.displayName}"?'),
        content: Text(
          'This permanently deletes all ${album.assetCount} '
          'photo${album.assetCount == 1 ? '' : 's'} and videos in this album '
          'from your device. This cannot be undone.',
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
      );
    },
  );

  if (confirmed != true) return;
  final removed = await controller.deleteAlbum(album);
  messenger.showSnackBar(
    SnackBar(
      content: Text(removed > 0
          ? 'Deleted $removed item${removed == 1 ? '' : 's'}'
          : 'Nothing was deleted'),
    ),
  );
}
