# Gallery

A clean, Honor-style photo & video gallery for Android, built with Flutter. It
reads the real media on your device, organizes it into albums, and adds the
conveniences you expect from a modern gallery: a recycle bin, bulk selection,
album customization, a configurable settings screen, automatic photo stacking,
and a full-screen pinch-to-zoom viewer.

> Built and tested against a physical **Pixel 10 Pro** (Android, `arm64-v8a`).

---

## Features

### Albums
- **All Photos** — a locked, always-present album showing every photo and video
  on the device. It can't be renamed, hidden, reordered, deleted, or selected.
- **Device folders as albums** — Camera, Screenshots, Downloads, and your own
  folders appear as albums.
- **Customization (stored locally as an overlay):**
  - **Rename** albums — names may contain **emoji**. Clearing the name restores
    the original folder name.
  - **Hide / unhide** albums (single or in bulk). Hidden albums are revealed via
    _Show hidden albums_.
  - **Reorder** manually (drag in list view) or automatically with built-in
    sorts: **Name A–Z / Z–A**, **Most / Fewest items**, or **Custom order**.
  - **Create** a new album from selected media.
- **List ↔ grid** view toggle (persisted).
- **"Others"** — auto-generated app/system folders (WhatsApp, Telegram,
  Instagram, screen recordings, …) are grouped behind a single **Others** tile
  to keep the main list clean. **Screenshots is intentionally excluded** and
  shown as a normal album. You can enter Others and multi-select albums there.
- **Auto-cleanup** — an album that becomes empty disappears automatically; its
  stale settings are pruned.

### Selection (bulk actions)
- **Albums** — long-press to enter selection. Bulk **Hide / Unhide**, **Delete**
  (to Bin), and **Info** (aggregate stats: single album shows full details,
  multiple shows totals — item count, size, photos/videos). During selection,
  All Photos and the Bin tile are **disabled**; Others can still be entered.
- **Media** — long-press a thumbnail (or the toolbar select action) to enter
  selection, then **drag your finger to sweep-select** with edge auto-scroll.
  Each day header has a **Select day** toggle. Bulk **Delete**, **Move to
  album**, and a per-cell **full-screen preview** that doesn't change the
  selection. (No app-wide "select all" — except inside the **Bin**.)

### Photo / video viewer
- Swipeable, full-screen, pinch-to-zoom.
- Bottom actions: **Info** (name, resolution, size, dates, GPS, path, duration),
  **Open in Google Photos** (Android view intent), and **Delete** (to Bin).
- Videos show a play button that hands off to an external player.

### Media stacks (auto-group related photos)
Related shots — e.g. a Pixel original and its enhanced variant — are grouped
into a **single tile**, similar to how Pixel/Google Photos "stacks" show as one
card.
- **Automatic, by filename.** Variants that share a burst key are grouped, e.g.
  `PXL_20260526_134523420.BURST-02.original.jpg` and
  `PXL_20260526_134523420.BURST-01.jpg` → one stack. The **enhanced** version
  (the one *without* `.original`) becomes the cover by default. Grouping happens
  as you browse an album; toggle it in **Settings → Photo stacks**.
- The grid shows the stack as **one tile** with a **layers ×N** badge; the other
  versions are collapsed out of view.
- Tapping the stack opens a **version viewer**: swipe between versions, **Set as
  cover** to choose which one the gallery shows, or **Ungroup**.
- Stacks are stored locally and keep counts/covers accurate; binning a member
  detaches it from the stack.

> **Note:** grouping is the app's *own*, derived from filenames. Google Photos'
> private stacks and the Pixel camera's on-device "duplicate + processing" model
> aren't exposed to third-party apps, so the variants are matched by name rather
> than read from the system.

### Recycle bin
- A **soft bin**: deleting media hides it from albums but leaves the file in
  place, so restoring is instant and re-populates the original album (recreating
  it if it had emptied). Album counts and covers correctly exclude binned items.
- The Bin is **browsable**: preview, **Restore**, **Delete forever**, and
  **Select all** (only here).
- **Configurable auto-delete** from Settings: **10 / 15 / 30 / 60 / 90 days** or
  **Never**. When enabled, items show a "days left" badge and expired items are
  purged when the Bin is opened.

### Settings
A single Settings screen (home **⋮** menu) collecting every option:
- **Theme** — System / Light / Dark (also available from the home app-bar title).
- **Default view** — Grid / List.
- **Sort albums by**.
- **Show hidden albums**.
- **Bin auto-delete** window.
- **Hide small media** — Off / 2 / 4 / 6 / 8 KB. Filters out tiny images (usually
  third-party junk like icons, stickers, and cached thumbnails) at the MediaStore
  query level, so it applies to counts, album grids, and All Photos.

### Other touches
- **Haptic feedback** and a **press-in animation** on long-press (albums & media).
- Light/dark theming with a seeded Material 3 color scheme.

---

## Architecture

The app uses a simple, layered structure with `provider` (a single
`ChangeNotifier`) for state.

```
lib/
├─ main.dart                      App entry; ChangeNotifierProvider + MaterialApp
├─ theme.dart                     Material 3 light/dark themes
├─ models/
│  ├─ album.dart                  Album = device folder + customization overlay;
│  │                              isAutoGenerated classification ("Others")
│  ├─ album_customization.dart    Rename / hidden / userCreated overlay (JSON)
│  ├─ album_stats.dart            Aggregated stats for the info sheet
│  ├─ media_stack.dart            A group of related photos (one shown as cover)
│  └─ sort_method.dart            AlbumSort + AlbumViewMode enums
├─ services/
│  ├─ media_service.dart          photo_manager wrapper: permission, load albums
│  │                              (with size filter + binned-count exclusion),
│  │                              paging, delete, move, create-album, stats
│  ├─ settings_service.dart       shared_preferences persistence for everything
│  └─ intent_service.dart         Android view intents (Google Photos hand-off)
├─ state/
│  └─ gallery_controller.dart     The brain: owns albums, selection-independent
│                                 state, customizations, soft bin, settings
└─ ui/
   ├─ home_page.dart              Albums screen (grid/list, selection, footer)
   ├─ album_detail_page.dart      Day-grouped media grid + drag-select + move
   ├─ photo_view_page.dart        Full-screen viewer (pinch-zoom, info, delete)
   ├─ bin_page.dart               Recycle bin (restore / delete forever / select all)
   ├─ others_page.dart            Auto-generated albums + multi-select
   ├─ settings_page.dart          All settings
   ├─ album_actions.dart          Rename dialog
   ├─ album_stats_sheet.dart      Album info bottom sheet
   ├─ photo_info_sheet.dart       Single-asset metadata sheet
   └─ widgets/
      ├─ asset_thumbnail.dart     Thumbnail + video duration badge
      ├─ name_input_dialog.dart   Safe dialog that owns its TextEditingController
      └─ pressable.dart           Press-in scale + tap/long-press wrapper
```

### Key design notes
- **Albums are device folders** plus a local customization overlay keyed by
  album id. The on-disk folder name is never changed.
- **Soft recycle bin** — binned ids (and their source folder) are stored in
  `shared_preferences`. Items are *hidden*, not moved, so restore is instant and
  album counts stay accurate (each album's binned items are subtracted; fully
  binned albums disappear).
- **Size filter** is applied as a `photo_manager` `AdvancedCustomFilter` on the
  MediaStore `_size` column and baked into each `AssetPathEntity`, so counts and
  paged loads honor it automatically.

---

## Tech stack

| Package | Purpose |
| --- | --- |
| [`photo_manager`](https://pub.dev/packages/photo_manager) | Read device albums, photos & videos; delete/move; permissions |
| [`photo_manager_image_provider`](https://pub.dev/packages/photo_manager_image_provider) | `AssetEntityImage` / image provider for thumbnails |
| [`photo_view`](https://pub.dev/packages/photo_view) | Full-screen pan / pinch-to-zoom viewer |
| [`shared_preferences`](https://pub.dev/packages/shared_preferences) | Persist settings, customizations, bin state |
| [`android_intent_plus`](https://pub.dev/packages/android_intent_plus) | Open media in Google Photos via an Android intent |
| [`provider`](https://pub.dev/packages/provider) | State management |
| [`intl`](https://pub.dev/packages/intl) | Date / size formatting |

- **Flutter:** 3.38+ (Dart 3.10+)
- **Min Android SDK:** 23 (`photo_manager` requirement)

---

## Permissions

Declared in `android/app/src/main/AndroidManifest.xml`:

- `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` (Android 13+)
- `READ_MEDIA_VISUAL_USER_SELECTED` (Android 14 partial access)
- `READ_EXTERNAL_STORAGE` (≤ Android 12), `WRITE_EXTERNAL_STORAGE` (≤ Android 10)
- `ACCESS_MEDIA_LOCATION` (read EXIF GPS)
- A `<queries>` entry for Google Photos so the hand-off resolves on Android 11+.

On first launch the app requests media access. On Android 14 "selected photos"
mode, a banner lets you manage the selection.

---

## Getting started

### Prerequisites
- Flutter SDK 3.38+
- An Android device or emulator (with some photos/videos on it)

### Run (debug)
```bash
flutter pub get
flutter run
```

### Build a release APK
The smallest installable build ships only your device's CPU architecture:
```bash
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-<abi>-release.apk
```
Most modern phones are `arm64-v8a`. Install it over USB:
```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```
A single universal APK (all ABIs, larger) is `flutter build apk --release`.

### App icon
The launcher icon is generated from `gallery.png` with
[`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons):
```bash
dart run flutter_launcher_icons
```

---

## Known limitations
- **Move / Create album** rely on Android `MediaStore` moves, which require a
  per-batch system permission dialog for files the app doesn't own and can fail
  if it's dismissed (scoped-storage behavior). They're Android-only.
- The recycle bin is **app-managed**: deleted files remain on disk (and may
  still appear to other apps) until you **Delete forever**.
- **Open in Google Photos** is Android-only.
- iOS targets are scaffolded but the move/Google-Photos features are Android-only.

---

## License
This is a personal project; feel free to fork it.
