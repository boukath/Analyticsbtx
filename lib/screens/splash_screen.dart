// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import '../services/b2_cloud_service.dart';
import '../services/ftp_service.dart';
import '../main.dart'; // To access the globalNavigatorKey

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Set up a simple fade-in animation for your logo
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _animationController.forward();

    // Start the heavy lifting!
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. WAKE UP BACKGROUND SERVICES GLOBALLY
      await B2CloudService.initialize();
      await FtpService.autoStart();

      // 2. Start the background IP security monitor
      FtpService.startIpMonitor(globalNavigatorKey);

      // Add a tiny artificial delay just so the user can admire your logo 😉
      await Future.delayed(const Duration(seconds: 1));

    } catch (e) {
      debugPrint("Error during initialization: $e");
      // You could handle errors here, but for now we'll just proceed to the dashboard
    }

    // 3. Navigate to the Dashboard and remove the Splash Screen from the stack
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Matches your _bgDark
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Display the new app icon you uploaded!
              Image.asset(
                'assets/app_icon.png',
                width: 150,
                height: 150,
              ),
              const SizedBox(height: 32),

              // App Title
              const Text(
                'BoitexInfo',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const Text(
                'ANALYTICS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF06B6D4), // Cyan accent
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 48),

              // Loading indicator
              const CircularProgressIndicator(
                color: Color(0xFF06B6D4), // Cyan accent
              ),
              const SizedBox(height: 16),
              const Text(
                'Starting server...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              )
            ],
          ),
        ),
      ),
    );
  }
}