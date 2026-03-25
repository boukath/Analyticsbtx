// lib/screens/firestore_sync_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_sync_service.dart';

class FirestoreSyncSettingsScreen extends StatefulWidget {
  final bool isFrench;
  final String? currentFolderPath;
  final VoidCallback onForceSync;

  const FirestoreSyncSettingsScreen({
    Key? key,
    required this.isFrench,
    this.currentFolderPath,
    required this.onForceSync,
  }) : super(key: key);

  @override
  State<FirestoreSyncSettingsScreen> createState() => _FirestoreSyncSettingsScreenState();
}

class _FirestoreSyncSettingsScreenState extends State<FirestoreSyncSettingsScreen> {
  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);
  final Color _accentOrange = Colors.orangeAccent;

  List<String> _syncTimes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSyncTimes();
  }

  Future<void> _loadSyncTimes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _syncTimes = prefs.getStringList('sync_times') ?? ['14:00', '22:00'];
      _isLoading = false;
    });
  }

  Future<void> _saveSyncTimes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sync_times', _syncTimes);
  }

  Future<void> _addNewTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: _accentCyan, surface: _bgDark),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      String formattedTime = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      if (!_syncTimes.contains(formattedTime)) {
        setState(() {
          _syncTimes.add(formattedTime);
          _syncTimes.sort(); // Keep them in chronological order
        });
        await _saveSyncTimes();
      }
    }
  }

  void _removeTime(String time) async {
    setState(() {
      _syncTimes.remove(time);
    });
    await _saveSyncTimes();
  }

  Future<void> _triggerForceSync() async {
    if (widget.currentFolderPath == null || widget.currentFolderPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isFrench ? "Erreur: Aucun dossier source sélectionné." : "Error: No source folder selected."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isFrench ? "Lecture de l'historique en cours..." : "Reading folder history..."),
        backgroundColor: _accentOrange,
      ),
    );

    try {
      // Trigger the massive historical folder sync
      await FirebaseSyncService.syncFullFolderHistory(widget.currentFolderPath!);

      // Tell the dashboard to run a quick update if needed
      widget.onForceSync();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench ? "Synchronisation terminée avec succès!" : "Historical sync complete!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
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
          widget.isFrench ? 'Paramètres Firestore' : 'Firestore Settings',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _accentCyan))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- SECTION 1: SCHEDULED TIMES ---
            Text(
              widget.isFrench ? 'Planification Automatique' : 'Automatic Schedule',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isFrench
                  ? "L'application enverra automatiquement les données au cloud à ces heures."
                  : "The app will automatically push data to the cloud at these times.",
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _accentCyan.withOpacity(0.3), width: 1.5),
              ),
              child: Column(
                children: [
                  ..._syncTimes.map((time) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _bgDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.cloud_upload, color: Colors.greenAccent, size: 24),
                      title: Text(time, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _removeTime(time),
                      ),
                    ),
                  )).toList(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentCyan.withOpacity(0.2),
                      foregroundColor: _accentCyan,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _addNewTime,
                    icon: const Icon(Icons.add),
                    label: Text(
                        widget.isFrench ? "AJOUTER UNE HEURE" : "ADD NEW TIME",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 60),

            // --- SECTION 2: MANUAL FORCE SYNC ---
            Text(
              widget.isFrench ? 'Actions Manuelles' : 'Manual Actions',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isFrench
                  ? "Forcer la synchronisation immédiate de tout l'historique local."
                  : "Force an immediate synchronization of all local history.",
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 24),

            InkWell(
              onTap: _triggerForceSync,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: _cardDark,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _accentOrange.withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(color: _accentOrange.withOpacity(0.1), blurRadius: 20)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: _accentOrange.withOpacity(0.2), shape: BoxShape.circle),
                      child: Icon(Icons.sync_problem, color: _accentOrange, size: 40),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              widget.isFrench ? 'Forcer la Synchro' : 'Force Full Sync',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)
                          ),
                          const SizedBox(height: 8),
                          Text(
                              widget.isFrench ? "Envoyer tout l'historique à Firebase maintenant" : "Push all history to Firebase right now",
                              style: const TextStyle(fontSize: 14, color: Colors.white54)
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}