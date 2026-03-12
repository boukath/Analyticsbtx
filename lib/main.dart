// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'screens/dashboard_screen.dart';
import 'services/b2_cloud_service.dart';
import 'services/ftp_service.dart';

// NEW: A global navigator key so background services can show emergency popups anywhere!
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // WAKE UP BACKGROUND SERVICES GLOBALLY
  await B2CloudService.initialize();
  await FtpService.autoStart();

  // Start the background IP security monitor
  FtpService.startIpMonitor(globalNavigatorKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalNavigatorKey, // Attach the global key here!
      title: 'Store Traffic Analytics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),

      // --- NEW: Localization Settings ---
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

      home: const DashboardScreen(),
    );
  }
}