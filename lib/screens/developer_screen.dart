// lib/screens/developer_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🚀 ADDED for wiping data
import 'camera_ftp_setup_screen.dart';
import 'ftp_server_screen.dart';
import 'cloud_sync_screen.dart';
import 'create_user_screen.dart';
import 'manage_users_screen.dart';
import 'store_profile_screen.dart';
import '../services/firebase_sync_service.dart';
import 'firestore_sync_settings_screen.dart';
import 'polaris_test_screen.dart';

class DeveloperScreen extends StatefulWidget {
  final bool isFrench;
  final VoidCallback onSelectDataSource;
  final VoidCallback onForceSync;
  final String? currentFolderPath;

  const DeveloperScreen({
    Key? key,
    required this.isFrench,
    required this.onSelectDataSource,
    required this.onForceSync,
    this.currentFolderPath,
  }) : super(key: key);

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  // --- Auth State ---
  bool _isAuthenticated = false;
  bool _isSuperAdmin = false; // true = Super Admin, false = Technician

  final TextEditingController _passwordController = TextEditingController();
  String? _errorMessage;

  void _verifyPassword() {
    setState(() {
      _errorMessage = null;
    });

    final enteredPassword = _passwordController.text.trim();

    if (enteredPassword == 'boitexinfodev') {
      // Super Admin Tier
      setState(() {
        _isAuthenticated = true;
        _isSuperAdmin = true;
      });
    } else if (enteredPassword == 'bi2026') {
      // Technician Tier
      setState(() {
        _isAuthenticated = true;
        _isSuperAdmin = false;
      });
    } else {
      // Wrong Password
      setState(() {
        _errorMessage = widget.isFrench ? 'Mot de passe incorrect' : 'Incorrect password';
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  // 🚀 NEW: Factory Reset Warning Dialog
  void _showWipeDataConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 2)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
            const SizedBox(width: 12),
            Text(
              widget.isFrench ? "ATTENTION : DANGER CRITIQUE" : "WARNING: CRITICAL DANGER",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          widget.isFrench
              ? "Êtes-vous absolument sûr de vouloir tout effacer ? Cette action supprimera :\n\n• Toutes les configurations\n• Les profils de magasin\n• Les adresses IP des caméras\n• La base de données locale des caisses (POS)\n\nL'application se fermera automatiquement après la suppression. Au prochain lancement, elle sera comme neuve."
              : "Are you absolutely sure you want to wipe everything? This action will delete:\n\n• All configurations\n• Store profiles\n• Camera IP addresses\n• Local POS database\n\nThe application will close automatically after deletion. Upon the next launch, it will be completely empty.",
          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.isFrench ? "ANNULER" : "CANCEL", style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context); // Close the dialog
              _performFactoryReset();
            },
            child: Text(widget.isFrench ? "OUI, TOUT EFFACER" : "YES, WIPE ALL DATA", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🚀 NEW: The Wipe Logic
  Future<void> _performFactoryReset() async {
    final prefs = await SharedPreferences.getInstance();

    // This clears ALL saved data, IPs, passwords, paths, and databases
    await prefs.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isFrench
                ? "Toutes les données ont été effacées avec succès. Fermeture de l'application..."
                : "All data wiped successfully. Closing application...",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Wait 2 seconds so the user can read the success message
    await Future.delayed(const Duration(seconds: 2));

    // Forcefully exit the application to ensure clean memory for the next launch
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        title: Text(
            widget.isFrench ? 'Espace Développeur' : 'Developer Zone',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isAuthenticated ? _buildDashboard() : _buildLoginScreen(),
    );
  }

  // =======================================================================
  // 1. LOGIN SCREEN (Auth Gateway)
  // =======================================================================
  Widget _buildLoginScreen() {
    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings, color: Colors.blueAccent, size: 64),
            const SizedBox(height: 24),
            Text(
              widget.isFrench ? 'Accès Restreint' : 'Restricted Access',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isFrench
                  ? 'Veuillez entrer le mot de passe pour continuer.'
                  : 'Please enter the password to continue.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _verifyPassword(),
              decoration: InputDecoration(
                filled: true,
                fillColor: _bgDark,
                hintText: widget.isFrench ? 'Mot de passe' : 'Password',
                hintStyle: const TextStyle(color: Colors.white24),
                errorText: _errorMessage,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.lock, color: Colors.white54),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentCyan,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verifyPassword,
                child: Text(
                  widget.isFrench ? 'Se Connecter' : 'Login',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // =======================================================================
  // 2. MAIN DASHBOARD (Filtered by Access Tier)
  // =======================================================================
  Widget _buildDashboard() {
    List<Widget> allCards = [];

    // --- TECHNICIAN & ADMIN TIER (Available to both) ---
    allCards.addAll([
      // Store Profile
      _buildDevCard(
        title: widget.isFrench ? 'Profil du Magasin' : 'Store Profile',
        subtitle: widget.isFrench ? 'Nom, emplacement et logo' : 'Name, location, and logo',
        icon: Icons.storefront,
        color: Colors.lightBlueAccent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StoreProfileScreen(isFrench: widget.isFrench))),
      ),
      // Data Source
      _buildDevCard(
        title: widget.isFrench ? 'Source de données' : 'Data Source',
        subtitle: widget.isFrench ? 'Changer le dossier .scb local' : 'Change local .scb folder',
        icon: Icons.source,
        color: Colors.amberAccent,
        onTap: widget.onSelectDataSource,
      ),
      // Camera Setup
      _buildDevCard(
        title: widget.isFrench ? 'Config. Caméras' : 'Camera Setup',
        subtitle: widget.isFrench ? 'Lier les adresses IP' : 'Link IP addresses',
        icon: Icons.videocam,
        color: Colors.blueAccent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CameraFtpSetupScreen())),
      ),
      // FTP Server
      _buildDevCard(
        title: widget.isFrench ? 'Serveur FTP' : 'FTP Server',
        subtitle: widget.isFrench ? 'Gérer la réception réseau' : 'Manage network reception',
        icon: Icons.wifi_tethering,
        color: Colors.greenAccent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen())),
      ),
    ]);

    // --- SUPER ADMIN TIER (Only visible if _isSuperAdmin == true) ---
    if (_isSuperAdmin) {
      allCards.addAll([
        // Create User
        _buildDevCard(
          title: widget.isFrench ? 'Créer un utilisateur' : 'Create User',
          subtitle: widget.isFrench ? 'Ajouter un compte client' : 'Add client account',
          icon: Icons.person_add,
          color: Colors.tealAccent,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CreateUserScreen(isFrench: widget.isFrench))),
        ),
        // Manage Users
        _buildDevCard(
          title: widget.isFrench ? 'Gérer les utilisateurs' : 'Manage Users',
          subtitle: widget.isFrench ? 'Voir la liste des clients' : 'View client list',
          icon: Icons.people_alt,
          color: Colors.pinkAccent,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ManageUsersScreen(isFrench: widget.isFrench))),
        ),
        // Polaris Parser Test
        _buildDevCard(
          title: widget.isFrench ? 'Testeur Polaris' : 'Polaris Parser Test',
          subtitle: widget.isFrench ? 'Tester l\'extraction de données' : 'Test extracting data from .sav',
          icon: Icons.receipt_long,
          color: Colors.deepPurpleAccent,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PolarisTestScreen())),
        ),
        // Sync Firestore
        _buildDevCard(
          title: widget.isFrench ? 'Sync Firestore' : 'Sync Firestore',
          subtitle: widget.isFrench ? 'Horaires & Synchro forcée' : 'Schedules & Force Sync',
          icon: Icons.sync,
          color: Colors.orangeAccent,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FirestoreSyncSettingsScreen(
                  isFrench: widget.isFrench,
                  currentFolderPath: widget.currentFolderPath,
                  onForceSync: widget.onForceSync,
                ),
              ),
            );
          },
        ),
        // Cloud Sync (B2)
        _buildDevCard(
          title: widget.isFrench ? 'Synchronisation Cloud' : 'Cloud Sync (B2)',
          subtitle: widget.isFrench ? 'Sauvegarde vers Backblaze B2' : 'Backup to Backblaze B2',
          icon: Icons.cloud_upload,
          color: Colors.purpleAccent,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CloudSyncScreen())),
        ),

        // 🚀 NEW: WIPE ALL DATA (FACTORY RESET)
        _buildDevCard(
          title: widget.isFrench ? 'Réinitialisation d\'Usine' : 'Factory Reset',
          subtitle: widget.isFrench ? 'Effacer toutes les données locales' : 'Wipe all local app data',
          icon: Icons.delete_forever,
          color: Colors.redAccent,
          onTap: _showWipeDataConfirmation, // Call the warning dialog
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.isFrench ? 'Paramètres Avancés' : 'Advanced Settings',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
              ),
              const Spacer(),
              // Badge showing the current tier level
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isSuperAdmin ? Colors.purpleAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _isSuperAdmin ? Colors.purpleAccent : Colors.greenAccent),
                ),
                child: Row(
                  children: [
                    Icon(_isSuperAdmin ? Icons.shield : Icons.build,
                        color: _isSuperAdmin ? Colors.purpleAccent : Colors.greenAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _isSuperAdmin ? 'SUPER ADMIN' : 'TECHNICIAN',
                      style: TextStyle(
                        color: _isSuperAdmin ? Colors.purpleAccent : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.isFrench
                ? 'Gérez vos configurations système, caméras, FTP et synchronisation cloud.'
                : 'Manage your system configurations, cameras, FTP, and cloud sync.',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 40),

          // Grid of Settings populated dynamically
          Expanded(
            child: GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 800 ? 2 : 1,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              childAspectRatio: 3.0,
              children: allCards,
            ),
          ),
        ],
      ),
    );
  }

  // =======================================================================
  // 3. CARD WIDGET BUILDER
  // =======================================================================
  Widget _buildDevCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 20)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white54)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}