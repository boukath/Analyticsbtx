// lib/screens/store_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // These booleans remain so the rest of your app still works perfectly
  bool _syncIndividualCameras = false;
  bool _enablePosFeatures = true;
  bool _isSingleEntrance = false;

  // 🚀 NEW: State for the currently selected dropdown mode
  String _selectedMode = 'retail_multi';

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

      // Load the booleans
      _syncIndividualCameras = prefs.getBool('sync_individual_cameras') ?? true;
      _enablePosFeatures = prefs.getBool('enable_pos_features') ?? true;
      _isSingleEntrance = prefs.getBool('is_single_entrance') ?? false;

      // 🚀 NEW: Deduce the dropdown mode based on loaded booleans to keep the UI in sync
      if (_enablePosFeatures && !_isSingleEntrance) {
        _selectedMode = 'retail_multi';
      } else if (_enablePosFeatures && _isSingleEntrance) {
        _selectedMode = 'retail_single';
      } else if (!_enablePosFeatures && !_isSingleEntrance) {
        _selectedMode = 'mall_multi';
      } else if (!_enablePosFeatures && _isSingleEntrance) {
        _selectedMode = 'mall_single';
      }

      _isLoading = false;
    });
  }

  // 🚀 NEW: Helper function to apply safe boolean rules when a mode is selected
  void _applyModeSettings(String mode) {
    setState(() {
      _selectedMode = mode;
      if (mode == 'retail_multi') {
        _enablePosFeatures = true;
        _isSingleEntrance = false;
        _syncIndividualCameras = true;
      } else if (mode == 'retail_single') {
        _enablePosFeatures = true;
        _isSingleEntrance = true;
        _syncIndividualCameras = false;
      } else if (mode == 'mall_multi') {
        _enablePosFeatures = false;
        _isSingleEntrance = false;
        _syncIndividualCameras = true;
      } else if (mode == 'mall_single') {
        _enablePosFeatures = false;
        _isSingleEntrance = true;
        _syncIndividualCameras = false;
      }
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_name', _nameCtrl.text.trim());
    await prefs.setString('store_location', _locCtrl.text.trim());
    await prefs.setString('firebase_client_id', _clientIdCtrl.text.trim());

    // Save the booleans based on the selected mode
    await prefs.setBool('sync_individual_cameras', _syncIndividualCameras);
    await prefs.setBool('enable_pos_features', _enablePosFeatures);
    await prefs.setBool('is_single_entrance', _isSingleEntrance);

    if (_tempLogoPath != null) {
      await prefs.setString('store_logo_path', _tempLogoPath!);
    }

    String rawClientId = _clientIdCtrl.text.trim();
    String clientId = rawClientId.replaceAll(' ', '_').toLowerCase();

    if (clientId.isNotEmpty) {
      try {
        String storeId = "${_nameCtrl.text.trim()}_${_locCtrl.text.trim()}".replaceAll(' ', '_').toLowerCase();

        await FirebaseFirestore.instance
            .collection('clients').doc(clientId)
            .collection('stores').doc(storeId)
            .set({
          'brand': _nameCtrl.text.trim(),
          'location': _locCtrl.text.trim(),
          'enable_pos_features': _enablePosFeatures,
          'is_single_entrance': _isSingleEntrance,
          'app_mode': _selectedMode,
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

                // 🚀 The App Mode Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _bgDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accentCyan),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedMode,
                    dropdownColor: _cardDark,
                    iconEnabledColor: _accentCyan,
                    decoration: InputDecoration(
                      labelText: widget.isFrench ? 'Mode de Fonctionnement' : 'Operating Mode',
                      labelStyle: const TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.settings_suggest, color: _accentCyan),
                    ),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    items: [
                      DropdownMenuItem(
                        value: 'retail_multi',
                        child: Text(widget.isFrench ? 'Retail (Caisse) - Multi Caméras' : 'Retail (POS) - Multi Camera'),
                      ),
                      DropdownMenuItem(
                        value: 'retail_single',
                        child: Text(widget.isFrench ? 'Retail (Caisse) - Entrée Unique' : 'Retail (POS) - Single Entrance'),
                      ),
                      DropdownMenuItem(
                        value: 'mall_multi',
                        child: Text(widget.isFrench ? 'Mall (Trafic) - Multi Caméras' : 'Mall (Traffic) - Multi Camera'),
                      ),
                      DropdownMenuItem(
                        value: 'mall_single',
                        child: Text(widget.isFrench ? 'Mall (Trafic) - Entrée Unique' : 'Mall (Traffic) - Single Entrance'),
                      ),
                    ],
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        _applyModeSettings(newValue);
                      }
                    },
                  ),
                ),

                // Hint text explaining the selected mode
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 24),
                  child: Text(
                    _selectedMode.contains('single')
                        ? (widget.isFrench ? "Mode fusionné : Tout le trafic est combiné en une seule entrée." : "Merged Mode: All traffic is combined into one global view.")
                        : (widget.isFrench ? "Mode détaillé : Chaque caméra est synchronisée séparément." : "Detailed Mode: Every camera synchronizes data separately."),
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),

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