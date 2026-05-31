import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:photo_manager/photo_manager.dart';

/// Hands a photo/video off to an external viewer via an Android view intent.
class IntentService {
  static const _googlePhotosPackage = 'com.google.android.apps.photos';

  /// Opens [asset] in Google Photos. Falls back to the system chooser when
  /// Google Photos isn't installed or can't handle the item.
  ///
  /// Returns true if an activity was launched.
  Future<bool> openInGooglePhotos(AssetEntity asset) async {
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
}
