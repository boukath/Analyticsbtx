// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🚀 NEW: This gives us kIsWeb!
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

// --- Firebase imports ---
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// --- Screen imports ---
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart'; // 🚀 NEW: Import the login screen

// A global navigator key so background services can show emergency popups anywhere!
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter engine is fully bound before making native calls
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase across Windows, Android, and Web automatically
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🚀 SMART ROUTING: Decide which screen to show first based on the platform
  Widget firstScreen;
  if (kIsWeb) {
    firstScreen = const LoginScreen(); // Web users must log in to the Cloud Dashboard
  } else {
    firstScreen = const SplashScreen(); // Windows users go to the local worker app
  }

  runApp(MyApp(initialScreen: firstScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen; // 🚀 NEW: Accept the smartly selected screen

  const MyApp({super.key, required this.initialScreen});

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

      // 🚀 Use the smartly selected screen instead of a hardcoded one
      home: initialScreen,
    );
  }
}