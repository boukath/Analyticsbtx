// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_web.dart'; // We will create this next!

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = "";

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        // Navigate to the Web Dashboard upon success!
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardWeb()));
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? "Authentication failed";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 20)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics, color: _accentCyan, size: 80),
                const SizedBox(height: 16),
                const Text(
                  'BoitexInfo',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                Text(
                  'CLOUD DASHBOARD',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _accentCyan, letterSpacing: 2.0),
                ),
                const SizedBox(height: 40),

                if (_errorMessage.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 20),
                ],

                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: _bgDark,
                    prefixIcon: Icon(Icons.email, color: _accentCyan),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: _bgDark,
                    prefixIcon: Icon(Icons.lock, color: _accentCyan),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('SECURE LOGIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}