// lib/screens/developer_screen.dart

import 'package:flutter/material.dart';
import 'camera_ftp_setup_screen.dart';
import 'ftp_server_screen.dart';
import 'cloud_sync_screen.dart';
import 'create_user_screen.dart';
import 'manage_users_screen.dart';
import 'store_profile_screen.dart';

class DeveloperScreen extends StatelessWidget {
  final bool isFrench;
  final VoidCallback onSelectDataSource;
  final VoidCallback onForceSync; // 🚀 NEW: Accept the sync function from the Dashboard

  const DeveloperScreen({
    Key? key,
    required this.isFrench,
    required this.onSelectDataSource,
    required this.onForceSync, // 🚀 NEW
  }) : super(key: key);

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        title: Text(
            isFrench ? 'Espace Développeur' : 'Developer Zone',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFrench ? 'Paramètres Avancés' : 'Advanced Settings',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 8),
            Text(
              isFrench
                  ? 'Gérez vos configurations système, caméras, FTP et synchronisation cloud.'
                  : 'Manage your system configurations, cameras, FTP, and cloud sync.',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 40),

            // Grid of Settings
            Expanded(
              child: GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 800 ? 2 : 1,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                childAspectRatio: 3.0,
                children: [
                  // 🚀 NEW CARD: Create User
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Créer un utilisateur' : 'Create User',
                    subtitle: isFrench ? 'Ajouter un compte client' : 'Add client account',
                    icon: Icons.person_add,
                    color: Colors.tealAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CreateUserScreen(isFrench: isFrench))),
                  ),

                  // 🚀 NEW CARD: Manage Users
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Gérer les utilisateurs' : 'Manage Users',
                    subtitle: isFrench ? 'Voir la liste des clients' : 'View client list',
                    icon: Icons.people_alt,
                    color: Colors.pinkAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ManageUsersScreen(isFrench: isFrench))),
                  ),

                  // 🚀 NEW CARD: Store Profile
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Profil du Magasin' : 'Store Profile',
                    subtitle: isFrench ? 'Nom, emplacement et logo' : 'Name, location, and logo',
                    icon: Icons.storefront,
                    color: Colors.lightBlueAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StoreProfileScreen(isFrench: isFrench))),
                  ),

                  // (Your existing cards follow below...)
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Source de données' : 'Data Source',
                    subtitle: isFrench ? 'Changer le dossier .scb local' : 'Change local .scb folder',
                    icon: Icons.source,
                    color: Colors.amberAccent,
                    onTap: onSelectDataSource,
                  ),
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Config. Caméras' : 'Camera Setup',
                    subtitle: isFrench ? 'Lier les adresses IP' : 'Link IP addresses',
                    icon: Icons.videocam,
                    color: Colors.blueAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CameraFtpSetupScreen())),
                  ),
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Serveur FTP' : 'FTP Server',
                    subtitle: isFrench ? 'Gérer la réception réseau' : 'Manage network reception',
                    icon: Icons.wifi_tethering,
                    color: Colors.greenAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen())),
                  ),
                  // 🚀 FIXED: Call the passed function instead of the missing method
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Sync Firestore' : 'Force Cloud Sync',
                    subtitle: isFrench ? 'Envoyer vers Firebase Database' : 'Push data to Firebase Database',
                    icon: Icons.sync_problem,
                    color: Colors.orangeAccent,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isFrench ? "Synchronisation Firestore en cours..." : "Starting Firestore sync..."), backgroundColor: Colors.orangeAccent),
                      );
                      onForceSync();
                    },
                  ),
                  _buildDevCard(
                    context,
                    title: isFrench ? 'Synchronisation Cloud' : 'Cloud Sync (B2)',
                    subtitle: isFrench ? 'Sauvegarde vers Backblaze B2' : 'Backup to Backblaze B2',
                    icon: Icons.cloud_upload,
                    color: Colors.purpleAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CloudSyncScreen())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
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