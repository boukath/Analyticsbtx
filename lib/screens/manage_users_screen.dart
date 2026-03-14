// lib/screens/manage_users_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_user_screen.dart';

class ManageUsersScreen extends StatelessWidget {
  final bool isFrench;

  const ManageUsersScreen({Key? key, required this.isFrench}) : super(key: key);

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  // Function to send a password reset email
  Future<void> _sendPasswordReset(BuildContext context, String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFrench ? "Email de réinitialisation envoyé à $email" : "Reset email sent to $email"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        title: Text(
          isFrench ? 'Gestion des Utilisateurs' : 'Manage Users',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFrench ? 'Comptes Clients' : 'Client Accounts',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              isFrench
                  ? 'Consultez tous vos clients enregistrés. Pour des raisons de sécurité, les mots de passe sont cryptés et invisibles.'
                  : 'View all your registered clients. For security, passwords are encrypted and cannot be viewed.',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                // StreamBuilder listens to Firestore in real-time!
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').orderBy('created_at', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final users = snapshot.data!.docs;

                    if (users.isEmpty) {
                      return Center(
                        child: Text(
                          isFrench ? "Aucun utilisateur trouvé." : "No users found.",
                          style: const TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    // Build a neat list of users
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: users.length,
                      separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
                      itemBuilder: (context, index) {
                        var userData = users[index].data() as Map<String, dynamic>;
                        String fullName = userData['full_name'] ?? 'No Name';
                        String email = userData['email'] ?? 'No Email';

                        // 🚀 CHANGED: Now looking for 'client_id', but keeping 'client_brand' as a fallback for older test accounts.
                        String clientId = userData['client_id'] ?? userData['client_brand'] ?? 'No Client Assigned';

                        String role = userData['role'] ?? 'client';

                        return ListTile(
                          // 🚀 NEW: Make the list item clickable to navigate to the Edit Screen
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditUserScreen(
                                  isFrench: isFrench,
                                  userId: users[index].id, // Passes the specific Firestore document ID
                                  currentData: userData,   // Passes the user's data to pre-fill the form
                                ),
                              ),
                            );
                          },

                          // Make it look great when hovered over or clicked
                          hoverColor: Colors.white.withOpacity(0.05),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),

                          leading: CircleAvatar(
                            backgroundColor: _accentCyan.withOpacity(0.2),
                            child: Icon(Icons.person, color: _accentCyan),
                          ),
                          title: Text(fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text("$clientId  •  $email", style: const TextStyle(color: Colors.white54)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: role == 'admin' ? Colors.redAccent.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(role.toUpperCase(), style: TextStyle(color: role == 'admin' ? Colors.redAccent : Colors.green, fontSize: 12)),
                              ),
                              const SizedBox(width: 16),
                              // Button to trigger password reset email
                              IconButton(
                                icon: const Icon(Icons.lock_reset, color: Colors.amberAccent),
                                tooltip: isFrench ? 'Envoyer réinitialisation mot de passe' : 'Send Password Reset',
                                onPressed: () => _sendPasswordReset(context, email),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}