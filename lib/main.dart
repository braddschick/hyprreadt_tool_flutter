import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui/home_screen.dart';

import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
  double windowHeight =
      primaryDisplay.visibleSize?.height ?? primaryDisplay.size.height;

  WindowOptions windowOptions = WindowOptions(
    size: Size(500, windowHeight),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const HyprReadinessApp());
}

class HyprReadinessApp extends StatelessWidget {
  const HyprReadinessApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF7553e0);

    return MaterialApp(
      title: 'HYPR Readiness Tool',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system, // Supports both light (default) and dark
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandColor,
          brightness: Brightness.light,
          primary: brandColor,
        ),
        useMaterial3: true,
        fontFamily: GoogleFonts.inter().fontFamily,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandColor,
          brightness: Brightness.dark,
          surface: const Color(0xFF1C1C1E),
          background: const Color(0xFF000000),
          primary: brandColor,
        ),
        useMaterial3: true,
        fontFamily: GoogleFonts.inter().fontFamily,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const HomeScreen(),
    );
  }
}
