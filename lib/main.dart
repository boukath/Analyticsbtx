// lib/main.dart

import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart'; // This tells main.dart where our new screen is!

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Store Traffic Analytics',
      debugShowCheckedModeBanner: false, // Hides the little "DEBUG" banner
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark, // Gives our dashboard a sleek, modern dark mode!
        useMaterial3: true,
      ),
      // THIS is the magic line. It sets our DashboardScreen as the very first thing you see.
      home: const DashboardScreen(),
    );
  }
}