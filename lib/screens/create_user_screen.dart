// lib/screens/create_user_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateUserScreen extends StatefulWidget {
  final bool isFrench;

  const CreateUserScreen({Key? key, required this.isFrench}) : super(key: key);

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 🚀 Step 1: Store the selected client ID from the dropdown
  String? _selectedClientId;

  bool _isLoading = false;

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  // 🚀 Step 2: Include the Client ID when creating the user
  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Create the user in Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Save their profile data in the 'users' collection
      if (userCredential.user != null) {
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'full_name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'client_id': _selectedClientId, // Links them to the specific client!
          'role': 'client', // Assigning the specific role
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench ? 'Utilisateur créé avec succès !' : 'User created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back after success
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? (widget.isFrench ? "Erreur de création" : "Creation error")),
              backgroundColor: Colors.redAccent
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🚀 Step 3: Helper method to build the Client Dropdown
  Widget _buildClientDropdown() {
    return StreamBuilder<QuerySnapshot>(
      // Assuming your clients are stored in a 'clients' collection
      stream: FirebaseFirestore.instance.collection('clients').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Text(
            widget.isFrench ? "Aucun client trouvé. Connectez d'abord un magasin." : "No clients found. Sync a store first.",
            style: const TextStyle(color: Colors.redAccent),
          );
        }

        List<DropdownMenuItem<String>> clientItems = snapshot.data!.docs.map((doc) {
          return DropdownMenuItem<String>(
            value: doc.id, // The document ID of the client (e.g. zara_algeria)
            child: Text(doc.id, style: const TextStyle(color: Colors.white)),
          );
        }).toList();

        return DropdownButtonFormField<String>(
          value: _selectedClientId,
          items: clientItems,
          dropdownColor: _cardDark,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            labelText: widget.isFrench ? 'Associer au Client' : 'Link to Client',
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: _bgDark,
            prefixIcon: Icon(Icons.business, color: _accentCyan),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _selectedClientId = value;
            });
          },
          validator: (value) => value == null
              ? (widget.isFrench ? 'Veuillez sélectionner un client' : 'Please select a client')
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        title: Text(
          widget.isFrench ? 'Créer un Utilisateur Client' : 'Create Client User',
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
                    widget.isFrench ? 'Nouveau Compte' : 'New Account',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 24),

                  _buildTextField(
                    controller: _nameController,
                    label: widget.isFrench ? 'Nom Complet' : 'Full Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),

                  // 🚀 Inserting the newly extracted Client Dropdown
                  _buildClientDropdown(),

                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email,
                    isEmail: true,
                  ),
                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _passwordController,
                    label: widget.isFrench ? 'Mot de passe' : 'Password',
                    icon: Icons.lock,
                    isPassword: true,
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
                      onPressed: _isLoading ? null : _createUser,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : Text(
                        widget.isFrench ? 'CRÉER COMPTE' : 'CREATE ACCOUNT',
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isEmail = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: _bgDark,
        prefixIcon: Icon(icon, color: _accentCyan),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return widget.isFrench ? 'Ce champ est requis' : 'This field is required';
        }
        if (isPassword && value.length < 6) {
          return widget.isFrench ? 'Le mot de passe doit contenir au moins 6 caractères' : 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }
}