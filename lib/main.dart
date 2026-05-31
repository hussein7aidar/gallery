import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/gallery_controller.dart';
import 'theme.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GalleryApp());
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GalleryController()..init(),
      child: Selector<GalleryController, ThemeMode>(
        selector: (_, controller) => controller.themeMode,
        builder: (context, themeMode, child) => MaterialApp(
          title: 'Gallery',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: const HomePage(),
        ),
      ),
    );
  }
}
