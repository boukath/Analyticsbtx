// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

// --- ADDED: Import your new splash screen ---
import 'screens/splash_screen.dart';

// A global navigator key so background services can show emergency popups anywhere!
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 The heavy initialization (FTP and Cloud sync) has been moved
  // into splash_screen.dart so the UI paints instantly!

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalNavigatorKey, // Attach the global key here!
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

      // 🚀 Changed from DashboardScreen() to SplashScreen()
      home: const SplashScreen(),
    );
  }
}