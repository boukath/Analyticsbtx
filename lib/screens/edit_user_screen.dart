// lib/screens/edit_user_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditUserScreen extends StatefulWidget {
  final bool isFrench;
  final String userId;
  final Map<String, dynamic> currentData;

  const EditUserScreen({
    Key? key,
    required this.isFrench,
    required this.userId,
    required this.currentData,
  }) : super(key: key);

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;

  String? _selectedClientId;
  late String _selectedRole;

  bool _isLoading = false;

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentData['full_name'] ?? '');

    // Fetch old client_id or fallback to client_brand
    _selectedClientId = widget.currentData['client_id'] ?? widget.currentData['client_brand'];

    // 🚀 THE FIX: Safety check for the role
    String fetchedRole = widget.currentData['role'] ?? 'client';
    if (fetchedRole != 'client' && fetchedRole != 'admin') {
      fetchedRole = 'client'; // Defaults to 'client' if it finds 'client_viewer' or anything else!
    }
    _selectedRole = fetchedRole;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
        'full_name': _nameController.text.trim(),
        'client_id': _selectedClientId,
        'role': _selectedRole,
        'last_updated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench ? "Profil mis à jour!" : "Profile updated!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          widget.isFrench ? 'Éditer l\'Utilisateur' : 'Edit User',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.currentData['email'] ?? 'No Email',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isFrench
                        ? "L'email de connexion ne peut pas être modifié pour des raisons de sécurité."
                        : "Login email cannot be changed for security reasons.",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 32),

                  _buildTextField(
                    controller: _nameController,
                    label: widget.isFrench ? 'Nom Complet' : 'Full Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),

                  // 🚀 FETCH CLIENTS FROM FIREBASE DROPDOWN
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('clients').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      List<String> clientIds = [];
                      if (snapshot.hasData) {
                        clientIds = snapshot.data!.docs.map((doc) => doc.id).toList();
                      }

                      // 🚀 ANTI-CRASH FIX: If the user's current client isn't in the DB list, add it so the Dropdown doesn't crash!
                      if (_selectedClientId != null && _selectedClientId!.isNotEmpty && !clientIds.contains(_selectedClientId)) {
                        clientIds.add(_selectedClientId!);
                      }

                      if (clientIds.isEmpty) {
                        return Text(
                          widget.isFrench ? "Aucun client trouvé." : "No clients found.",
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }

                      return DropdownButtonFormField<String>(
                        value: _selectedClientId,
                        dropdownColor: _bgDark,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: widget.isFrench ? 'Client Assigné' : 'Assigned Client',
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: _bgDark,
                          prefixIcon: Icon(Icons.business, color: _accentCyan),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: clientIds.map((clientId) {
                          return DropdownMenuItem<String>(
                            value: clientId,
                            child: Text(clientId),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedClientId = value);
                        },
                        validator: (value) => value == null ? (widget.isFrench ? 'Requis' : 'Required') : null,
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  Text(widget.isFrench ? 'Rôle' : 'Role', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: _bgDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedRole,
                        dropdownColor: _bgDark,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        items: const [
                          DropdownMenuItem(value: 'client', child: Text('Client (Standard)')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin (Full Access)')),
                        ],
                        onChanged: (String? newValue) {
                          if (newValue != null) setState(() => _selectedRole = newValue);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentCyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _updateUser,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : Text(
                        widget.isFrench ? 'SAUVEGARDER' : 'SAVE CHANGES',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: _bgDark,
        prefixIcon: Icon(icon, color: _accentCyan),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (value) => (value == null || value.isEmpty) ? (widget.isFrench ? 'Requis' : 'Required') : null,
    );
  }
}