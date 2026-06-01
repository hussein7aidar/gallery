import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../state/gallery_controller.dart';
import 'widgets/name_input_dialog.dart';

/// Rename dialog. The text field accepts any characters including emoji; an
/// empty value clears the override and restores the original folder name.
Future<void> showRenameDialog(BuildContext context, Album album) async {
  final controller = context.read<GalleryController>();
  final messenger = ScaffoldMessenger.of(context);

  final newName = await showNameInputDialog(
    context,
    title: 'Rename album',
    initialValue: album.displayName,
    confirmLabel: 'Save',
  );

  if (newName == null) return;
  await controller.renameAlbum(album, newName);
  messenger.showSnackBar(
    const SnackBar(content: Text('Album renamed')),
  );
}
