import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../state/gallery_controller.dart';

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
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
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
