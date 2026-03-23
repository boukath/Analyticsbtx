// lib/main.dart

import 'dart:io'; // 🚀 NEW: Required for Platform.resolvedExecutable
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🚀 Gives us kIsWeb!
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Needed for the background worker
import 'l10n/app_localizations.dart';

// --- Desktop Background & Tray Imports ---
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

// --- Startup Imports ---
import 'package:launch_at_startup/launch_at_startup.dart'; // 🚀 NEW: For running on Windows boot
import 'package:package_info_plus/package_info_plus.dart'; // 🚀 NEW: For getting the app's executable path

// --- Firebase imports ---
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// --- Service imports ---
import 'services/firebase_sync_service.dart'; // Import the sync service

// --- Screen imports ---
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';

// A global navigator key so background services can show emergency popups anywhere!
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter engine is fully bound before making native calls
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase across Windows, Android, and Web automatically
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the window manager and startup behavior for Desktop apps
  if (!kIsWeb) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1024, 768), // Default startup size
      center: true,
      title: 'BoitexInfo Analytics',
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      // Crucial step: tell Windows we want to handle the close event ourselves!
      await windowManager.setPreventClose(true);
    });

    // =======================================================================
    // 🚀 NEW: WINDOWS STARTUP CONFIGURATION
    // Configure the app to start automatically when the user logs into Windows.
    // =======================================================================
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
      );

      // Enable the app to run on startup
      await launchAtStartup.enable();
      debugPrint("✅ App configured to launch at Windows startup.");
    } catch (e) {
      debugPrint("❌ Failed to configure launch at startup: $e");
    }

    // =======================================================================
    // 🚀 FIX: GLOBAL BACKGROUND WORKER
    // Start the scheduled sync here so it runs independently of the UI.
    // =======================================================================
    FirebaseSyncService.startScheduledSync(() async {
      debugPrint("🌍 Global Background Worker: Triggering Scheduled Firebase Sync...");

      try {
        final prefs = await SharedPreferences.getInstance();
        String folderPath = prefs.getString('saved_data_folder') ?? '';

        if (folderPath.isNotEmpty) {
          // Trigger the full folder history sync to catch any data missed while offline/asleep
          await FirebaseSyncService.syncFullFolderHistory(folderPath);
          debugPrint("✅ Global Background Worker: Sync successfully finished.");
        } else {
          debugPrint("⚠️ Global Background Worker: No data folder configured yet. Skipping sync.");
        }
      } catch (e) {
        debugPrint("❌ Global Background Worker Error: $e");
      }
    });
  }

  // 🚀 SMART ROUTING: Decide which screen to show first based on the platform
  Widget firstScreen;
  if (kIsWeb) {
    firstScreen = const LoginScreen(); // Web users must log in to the Cloud Dashboard
  } else {
    firstScreen = const SplashScreen(); // Windows users go to the local worker app
  }

  runApp(MyApp(initialScreen: firstScreen));
}

// 🚀 Changed from StatelessWidget to StatefulWidget to handle Window & Tray events
class MyApp extends StatefulWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener, TrayListener {

  @override
  void initState() {
    super.initState();
    // Add listeners ONLY if we are running on desktop/mobile (Not Web)
    if (!kIsWeb) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initSystemTray();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  // --- Setup the System Tray Icon & Menu ---
  Future<void> _initSystemTray() async {
    // We use the app_icon.ico that already exists in your windows resources!
    await trayManager.setIcon('windows/runner/resources/app_icon.ico');

    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_app',
          label: 'Show Dashboard',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Exit Analytics completely',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  // --- Handle the 'X' Button Click ---
  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      // 🚀 Hide the window instead of killing the app!
      // Your FirebaseSyncService will keep running smoothly in the background.
      await windowManager.hide();
    }
  }

  // --- Handle System Tray Clicks ---
  @override
  void onTrayIconMouseDown() {
    // Left click on the tray icon shows the app again
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_app') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      // If the user deliberately selects exit, we terminate the app completely.
      windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalNavigatorKey,
      title: 'BoitexInfo Analytics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),

      // --- Localization Settings ---
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // English
        Locale('fr', ''), // French
      ],
      // ---------------------------------

      home: widget.initialScreen,
    );
  }
}