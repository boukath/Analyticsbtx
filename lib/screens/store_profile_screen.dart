// lib/screens/store_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🚀 NEW: Import Firestore

class StoreProfileScreen extends StatefulWidget {
  final bool isFrench;

  const StoreProfileScreen({Key? key, required this.isFrench}) : super(key: key);

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locCtrl = TextEditingController();
  final TextEditingController _clientIdCtrl = TextEditingController();

  String? _tempLogoPath;
  bool _isLoading = true;
  bool _syncIndividualCameras = false;
  bool _enablePosFeatures = true; // 🚀 NEW: State for POS Features

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);
  final Color _accentMagenta = const Color(0xFFD946EF);

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('store_name') ?? "My Store";
      _locCtrl.text = prefs.getString('store_location') ?? "MAIN BRANCH";
      _clientIdCtrl.text = prefs.getString('firebase_client_id') ?? '';
      _tempLogoPath = prefs.getString('store_logo_path');
      _syncIndividualCameras = prefs.getBool('sync_individual_cameras') ?? false;
      _enablePosFeatures = prefs.getBool('enable_pos_features') ?? true; // 🚀 Load toggle
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_name', _nameCtrl.text.trim());
    await prefs.setString('store_location', _locCtrl.text.trim());
    await prefs.setString('firebase_client_id', _clientIdCtrl.text.trim());
    await prefs.setBool('sync_individual_cameras', _syncIndividualCameras);
    await prefs.setBool('enable_pos_features', _enablePosFeatures); // 🚀 Save locally

    if (_tempLogoPath != null) {
      await prefs.setString('store_logo_path', _tempLogoPath!);
    }

    // 🚀 NEW: SYNC STORE MODE TO FIREBASE
    String clientId = _clientIdCtrl.text.trim();
    if (clientId.isNotEmpty) {
      try {
        // Generate the exact same Store ID used by your FirebaseSyncService
        String storeId = "${_nameCtrl.text.trim()}_${_locCtrl.text.trim()}".replaceAll(' ', '_').toLowerCase();

        await FirebaseFirestore.instance
            .collection('clients').doc(clientId)
            .collection('stores').doc(storeId)
            .set({
          'brand': _nameCtrl.text.trim(),
          'location': _locCtrl.text.trim(),
          'enable_pos_features': _enablePosFeatures, // Tell the Cloud Dashboard the mode!
          'last_updated_profile': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

      } catch (e) {
        debugPrint("Failed to sync store profile to Firebase: $e");
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isFrench ? 'Paramètres enregistrés !' : 'Profile saved successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(backgroundColor: _bgDark, body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        title: Text(
          widget.isFrench ? 'Profil du Magasin' : 'Store Profile',
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (result != null && result.files.single.path != null) {
                      setState(() => _tempLogoPath = result.files.single.path);
                    }
                  },
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: _bgDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: _accentCyan, width: 2),
                      image: _tempLogoPath != null ? DecorationImage(image: FileImage(File(_tempLogoPath!)), fit: BoxFit.cover) : null,
                    ),
                    child: _tempLogoPath == null ? Icon(Icons.add_a_photo, color: _accentCyan, size: 40) : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                    widget.isFrench ? 'Appuyez pour changer le logo' : 'Tap to change logo',
                    style: const TextStyle(color: Colors.white54, fontSize: 14)
                ),
                const SizedBox(height: 32),

                // Brand Name
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: widget.isFrench ? 'Marque / Magasin (ex: Zara)' : 'Brand / Store (e.g. Zara)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true, fillColor: _bgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.storefront, color: _accentCyan),
                  ),
                ),
                const SizedBox(height: 16),

                // Location
                TextField(
                  controller: _locCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: widget.isFrench ? 'Emplacement (ex: Garden City)' : 'Location (e.g. Garden City)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true, fillColor: _bgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.location_on, color: _accentMagenta),
                  ),
                ),
                const SizedBox(height: 24),

                // Firebase Cloud ID
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.3))
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          widget.isFrench ? "Configuration du Cloud (Client)" : "Cloud Sync Configuration (Client)",
                          style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _clientIdCtrl,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: widget.isFrench ? 'ID du Client (ex: zara_algerie)' : 'Client ID / Name (e.g. zara_algeria)',
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                          filled: true, fillColor: _bgDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          prefixIcon: const Icon(Icons.cloud_sync, color: Colors.orangeAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 🚀 NEW: The Retail/Mall Mode Toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _bgDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _enablePosFeatures ? _accentCyan : Colors.white.withOpacity(0.1)),
                  ),
                  child: SwitchListTile(
                    activeColor: _accentCyan,
                    title: Text(
                      widget.isFrench ? 'Mode Retail (Caisse)' : 'Retail Mode (POS & Sales)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      widget.isFrench
                          ? 'Désactiver pour les centres commerciaux (Trafic uniquement)'
                          : 'Disable for Malls/Buildings (Traffic only)',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _enablePosFeatures,
                    onChanged: (bool value) {
                      setState(() => _enablePosFeatures = value);
                    },
                  ),
                ),

                // The Database Optimization Toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _bgDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _syncIndividualCameras ? _accentCyan : Colors.white.withOpacity(0.1)),
                  ),
                  child: SwitchListTile(
                    activeColor: _accentCyan,
                    title: Text(
                      widget.isFrench ? 'Synchroniser chaque caméra' : 'Sync Individual Cameras',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      widget.isFrench
                          ? 'Désactivez pour fusionner les données et économiser la base de données.'
                          : 'Turn off to merge data and save Firebase database space.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _syncIndividualCameras,
                    onChanged: (bool value) {
                      setState(() => _syncIndividualCameras = value);
                    },
                  ),
                ),
                const SizedBox(height: 40),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saveProfile,
                    child: Text(
                        widget.isFrench ? 'SAUVEGARDER' : 'SAVE PROFILE',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)
                    ),
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