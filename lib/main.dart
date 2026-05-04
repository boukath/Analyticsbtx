// lib/main.dart

import 'dart:io'; // Required for Platform.resolvedExecutable and Directory
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Gives us kIsWeb!
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Needed for the background worker
import 'l10n/app_localizations.dart';

// --- Desktop Background & Tray Imports ---
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

// --- Startup Imports ---
import 'package:launch_at_startup/launch_at_startup.dart'; // For running on Windows boot
import 'package:package_info_plus/package_info_plus.dart'; // For getting the app's executable path

// --- Firebase imports ---
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// --- Service imports ---
import 'services/firebase_sync_service.dart'; // Import the sync service
// 🚀 NEW: Import the server services for auto-start capabilities
import 'services/ftp_service.dart';
import 'services/http_server_service.dart';

// --- Screen imports ---
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';

// A global navigator key so background services can show emergency popups anywhere!
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

// =======================================================================
// 🚀 NEW: DIRECTORY INITIALIZATION LOGIC
// Checks for C:\comptage, creates it if missing, and binds it to the app.
// =======================================================================
Future<void> _initializeComptageDirectory() async {
  // Use a raw string (r) so we don't have to escape the backslash in Windows paths
  const String targetPath = r'C:\comptage';
  final directory = Directory(targetPath);

  try {
    // 1. Check if the directory exists. If not, create it.
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      debugPrint("✅ Automatically created directory at $targetPath");
    } else {
      debugPrint("✅ Directory already exists at $targetPath");
    }

    // 2. Save this path to SharedPreferences so the app uses it automatically
    final prefs = await SharedPreferences.getInstance();
    String? currentSavedPath = prefs.getString('saved_data_folder');

    // Only update the preferences if it isn't already set to C:\comptage
    if (currentSavedPath != targetPath) {
      await prefs.setString('saved_data_folder', targetPath);
      debugPrint("✅ Bound default saved_data_folder to $targetPath");
    }
  } catch (e) {
    // If it fails, it is almost certainly due to missing Administrator privileges
    debugPrint("❌ CRITICAL ERROR creating $targetPath. Are you running as Administrator? Details: $e");
  }
}

void main() async {
  // Ensure Flutter engine is fully bound before making native calls
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase across Windows, Android, and Web automatically
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🚀 Execute our new directory logic right here at startup!
  if (!kIsWeb) {
    await _initializeComptageDirectory();
  }

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
    // WINDOWS STARTUP CONFIGURATION
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
    // GLOBAL BACKGROUND WORKER
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

    // =======================================================================
    // 🚀 NEW: SERVER AUTO-START LOGIC
    // Checks if the servers were running before the app was last closed/rebooted
    // =======================================================================
    try {
      final prefs = await SharedPreferences.getInstance();
      bool startFtp = prefs.getBool('ftp_auto_start') ?? false;
      bool startHttp = prefs.getBool('http_auto_start') ?? false;
      String folderPath = prefs.getString('saved_data_folder') ?? '';

      if (folderPath.isNotEmpty) {
        // Auto-start FTP if it was left on
        if (startFtp) {
          int ftpPort = prefs.getInt('ftp_port') ?? 21;
          String ftpUser = prefs.getString('ftp_user') ?? "shopline";
          String ftpPass = prefs.getString('ftp_pass') ?? "shopline";
          await FtpService.startServer(
              rootDirectory: folderPath,
              port: ftpPort,
              username: ftpUser,
              password: ftpPass
          );
          debugPrint("✅ Auto-started FTP Server in background.");
        }

        // Auto-start HTTP if it was left on
        if (startHttp) {
          int httpPort = prefs.getInt('http_port') ?? 8080;
          await HttpServerService.startServer(
              rootDirectory: folderPath,
              port: httpPort
          );
          debugPrint("✅ Auto-started HTTP Server in background.");
        }
      }
    } catch (e) {
      debugPrint("❌ Error during server auto-start: $e");
    }
  }

  // SMART ROUTING: Decide which screen to show first based on the platform
  Widget firstScreen;
  if (kIsWeb) {
    firstScreen = const LoginScreen(); // Web users must log in to the Cloud Dashboard
  } else {
    firstScreen = const SplashScreen(); // Windows users go to the local worker app
  }

  runApp(MyApp(initialScreen: firstScreen));
}

// Changed from StatelessWidget to StatefulWidget to handle Window & Tray events
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
          key: 'restart_app',
          label: 'Restart App', // NEW: Added the restart option
        ),
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
      // Hide the window instead of killing the app!
      // Your FirebaseSyncService will keep running smoothly in the background.
      await windowManager.hide();
    }
  }

  // --- Handle System Tray Clicks ---
  @override
  void onTrayIconMouseDown() {
    // Left-click now forces the context menu to pop up instead of just opening the window!
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_app') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'restart_app') {
      // Start a fresh instance of the app, then kill this one.
      Process.start(Platform.resolvedExecutable, []);
      windowManager.destroy();
      exit(0);
    } else if (menuItem.key == 'exit_app') {
      // If the user deliberately selects exit, we terminate the app completely.
      windowManager.destroy();
      exit(0); // Added exit(0) to ensure background isolates die cleanly
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