import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui/home_screen.dart';
import 'config/app_config.dart';
import 'headless_runner.dart'; // Import HeadlessRunner
import 'utils/windows_task_manager.dart';
import 'utils/macos_task_manager.dart';

import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check for headless mode
  if (args.contains('--headless')) {
    await HeadlessRunner.run(args);
    return; // Exit after headless run
  }

  // Check for task registration/removal
  if (args.contains('--install-task')) {
    await WindowsTaskManager.registerTaskFromArgs(args);
    return;
  }

  if (args.contains('--remove-task')) {
    await WindowsTaskManager.removeTask();
    return;
  }

  // Check for macOS daemon registration/removal
  if (args.contains('--install-daemon')) {
    await MacOSTaskManager.registerFromArgs(args);
    return;
  }

  if (args.contains('--remove-daemon')) {
    await MacOSTaskManager.remove();
    return;
  }

  await windowManager.ensureInitialized();
  await AppConfig().init(); // Initialize configuration

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
