import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:photo_manager/photo_manager.dart';

/// Hands a photo/video off to an external viewer via an Android view intent.
class IntentService {
  static const _googlePhotosPackage = 'com.google.android.apps.photos';

  /// Whether the Google Photos hand-off is available on this platform. It uses
  /// an Android intent, so it only works on Android.
  bool get isSupported => Platform.isAndroid;

  /// Opens [asset] in Google Photos. Falls back to the system chooser when
  /// Google Photos isn't installed or can't handle the item.
  ///
  /// Returns true if an activity was launched. Always false on non-Android
  /// platforms (the Android intent plugin isn't available there).
  Future<bool> openInGooglePhotos(AssetEntity asset) async {
    if (!Platform.isAndroid) return false;

    final uri = await asset.getMediaUrl();
    if (uri == null) return false;

    final mime = asset.mimeType ??
        (asset.type == AssetType.video ? 'video/*' : 'image/*');

    // Try Google Photos directly first.
    final direct = AndroidIntent(
      action: 'action_view',
      data: uri,
      type: mime,
      package: _googlePhotosPackage,
      flags: <int>[Flag.FLAG_GRANT_READ_URI_PERMISSION],
    );
    if (await direct.canResolveActivity() ?? false) {
      await direct.launch();
      return true;
    }

    // Fall back to whatever the system offers (chooser).
    final any = AndroidIntent(
      action: 'action_view',
      data: uri,
      type: mime,
      flags: <int>[Flag.FLAG_GRANT_READ_URI_PERMISSION],
    );
    if (await any.canResolveActivity() ?? false) {
      await any.launch();
      return true;
    }
    return false;
  }

  /// Launches the Google Photos app (e.g. so the user can reach its trash).
  /// Returns true if it was opened.
  Future<bool> openGooglePhotosApp() async {
    if (!Platform.isAndroid) return false;
    final intent = AndroidIntent(
      action: 'action_main',
      package: _googlePhotosPackage,
      category: 'android.intent.category.LAUNCHER',
    );
    if (await intent.canResolveActivity() ?? false) {
      await intent.launch();
      return true;
    }
    return false;
  }
}
