import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sort_method.dart';
import '../state/gallery_controller.dart';

/// Central settings screen. Intentionally collects every app setting in one
/// place, even ones reachable elsewhere (e.g. theme, also on the home bar).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static String _retentionLabel(int days) =>
      days <= 0 ? 'Never' : '$days days';

  static String _smallMediaLabel(int kb) => kb <= 0 ? 'Off' : '$kb KB';

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryController>(
      builder: (context, c, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              const _SectionHeader('Appearance'),
              _ChoiceTile<ThemeMode>(
                icon: Icons.brightness_6_outlined,
                title: 'Theme',
                value: c.themeMode,
                options: const {
                  ThemeMode.system: 'System',
                  ThemeMode.light: 'Light',
                  ThemeMode.dark: 'Dark',
                },
                onSelected: c.setThemeMode,
              ),

              const _SectionHeader('Albums'),
              _ChoiceTile<AlbumViewMode>(
                icon: Icons.grid_view_rounded,
                title: 'Default view',
                value: c.viewMode,
                options: const {
                  AlbumViewMode.grid: 'Grid',
                  AlbumViewMode.list: 'List',
                },
                onSelected: c.setViewMode,
              ),
              _ChoiceTile<AlbumSort>(
                icon: Icons.sort_rounded,
                title: 'Sort albums by',
                value: c.sort,
                options: {for (final s in AlbumSort.values) s: s.label},
                onSelected: c.setSort,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('Show hidden albums'),
                value: c.showHidden,
                onChanged: c.hasHiddenAlbums || c.showHidden
                    ? c.setShowHidden
                    : null,
              ),

              const _SectionHeader('Recycle bin'),
              _ChoiceTile<int>(
                icon: Icons.auto_delete_outlined,
                title: 'Auto-delete after',
                subtitle: 'How long items stay in the Bin before being removed',
                value: c.binRetentionDays,
                options: {
                  for (final d in GalleryController.retentionChoices)
                    d: _retentionLabel(d),
                },
                onSelected: c.setBinRetentionDays,
              ),

              const _SectionHeader('Media'),
              _ChoiceTile<int>(
                icon: Icons.hide_image_outlined,
                title: 'Hide small media',
                subtitle:
                    'Hide tiny images (usually third-party junk) below this size',
                value: c.hideSmallMediaKb,
                options: {
                  for (final kb in GalleryController.smallMediaChoices)
                    kb: _smallMediaLabel(kb),
                },
                onSelected: c.setHideSmallMediaKb,
              ),

              const _SectionHeader('Photo stacks'),
              SwitchListTile(
                secondary: const Icon(Icons.layers_outlined),
                title: const Text('Auto-group burst & original photos'),
                subtitle: const Text(
                    'Groups variants by filename (e.g. Pixel BURST/.original) '
                    'into one tile; the enhanced version is the cover'),
                value: c.autoStackByName,
                onChanged: c.setAutoStackByName,
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A settings row that shows the current value and opens a radio picker.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            options[value] ?? '',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () async {
        final selected = await showModalBottomSheet<T>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                for (final entry in options.entries)
                  ListTile(
                    title: Text(entry.value),
                    trailing: entry.key == value
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, entry.key),
                  ),
              ],
            ),
          ),
        );
        if (selected != null) onSelected(selected);
      },
    );
  }
}
