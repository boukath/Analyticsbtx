// lib/screens/dashboard_web.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'export_screen.dart';
import '../models/people_count.dart';
import '../core/data_aggregator.dart';

enum ChartFilter { hourly, daily }

class DashboardWeb extends StatefulWidget {
  const DashboardWeb({Key? key}) : super(key: key);

  @override
  State<DashboardWeb> createState() => _DashboardWebState();
}

class _DashboardWebState extends State<DashboardWeb> {
  List<PeopleCount> _rawData = [];
  List<PeopleCount> _displayedData = [];

  // 🚀 Store separated data for the Matrix Table
  Map<String, List<PeopleCount>> _perDoorData = {};

  bool _isLoading = true;
  ChartFilter _currentFilter = ChartFilter.hourly;
  DateTimeRange? _selectedDateRange;

  bool _isFrench = false;
  int _workingMinuteStart = 0;
  int _workingMinuteEnd = 1439;

  // 🚀 Flag to toggle between Chart Mode and Table Mode
  bool _isTableMode = false;

  // 🚀 Flag to toggle POS (Retail) vs Footfall (Mall) mode
  bool _enablePosFeatures = true;

  // Camera Variables
  List<String> _availableCameras = ['All Doors'];
  String _selectedCamera = 'All Doors';

  int _totalIn = 0;
  int _totalOut = 0;
  int _occupancy = 0;
  String _peakHour = "--:--";

  double _currentCa = 0;
  int _currentClients = 0;
  int _currentArticles = 0;

  Map<String, Map<String, num>> _posDatabase = {};

  // 🚀 FAST LOOKUP DATA FOR MATRIX
  List<Map<String, dynamic>> _matrixRowData = [];
  Map<String, int> _matrixDoorInTotals = {};
  Map<String, int> _matrixDoorOutTotals = {};

  String _loggedInUserName = "Loading...";
  String _loggedInRole = "client";
  String _clientId = "";

  String _storeName = "Loading...";
  String _storeLocation = "CLOUD";
  String _selectedStoreId = "";
  List<Map<String, dynamic>> _userStores = [];

  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);
  final Color _accentMagenta = const Color(0xFFD946EF);

  @override
  void initState() {
    super.initState();
    _loadLanguagePref();
    _loadWorkingHoursPref();

    DateTime today = DateTime.now();
    _selectedDateRange = DateTimeRange(start: today, end: today);

    _verifyUserAndLoadStores();
  }

  Future<void> _loadWorkingHoursPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _workingMinuteStart = prefs.getInt('working_minute_start') ?? 0;
      _workingMinuteEnd = prefs.getInt('working_minute_end') ?? 1439;
    });
  }

  Future<void> _loadLanguagePref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFrench = prefs.getString('app_language') == 'fr';
    });
  }

  Future<void> _toggleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isFrench = !_isFrench);
    await prefs.setString('app_language', _isFrench ? 'fr' : 'en');
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _verifyUserAndLoadStores() async {
    setState(() => _isLoading = true);
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _signOut();
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();

      if (!userDoc.exists || userDoc.data() == null) {
        setState(() {
          _storeName = _isFrench ? "Accès Refusé" : "Access Denied";
          _isLoading = false;
        });
        return;
      }

      var userData = userDoc.data() as Map<String, dynamic>;

      setState(() {
        _loggedInUserName = userData['full_name'] ?? "User";
        _loggedInRole = userData['role'] ?? "client";
        _clientId = userData['client_id'] ?? userData['client_brand'] ?? "";
      });

      if (_clientId.isEmpty) {
        setState(() {
          _storeName = _isFrench ? "Aucun ID Client Assigné" : "No Client ID Assigned";
          _isLoading = false;
        });
        return;
      }

      QuerySnapshot storeSnapshot = await FirebaseFirestore.instance
          .collection('clients')
          .doc(_clientId)
          .collection('stores')
          .get();

      List<Map<String, dynamic>> stores = [];
      for (var doc in storeSnapshot.docs) {
        bool enablePos = true;
        if (doc.data() is Map<String, dynamic>) {
          var data = doc.data() as Map<String, dynamic>;
          if (data.containsKey('enable_pos_features')) {
            enablePos = data['enable_pos_features'];
          }
        }

        stores.add({
          'id': doc.id,
          'brand': doc.data().toString().contains('brand') ? doc.get('brand') : 'Unknown',
          'location': doc.data().toString().contains('location') ? doc.get('location') : doc.id,
          'enable_pos_features': enablePos,
        });
      }

      if (stores.isNotEmpty) {
        setState(() {
          _userStores = stores;
          _selectedStoreId = stores.first['id'];
          _storeName = stores.first['brand'];
          _storeLocation = stores.first['location'];
          _enablePosFeatures = stores.first['enable_pos_features'];
        });
        await _fetchCloudDataForDateRange();
      } else {
        setState(() {
          _storeName = _isFrench ? "Aucun Magasin Synchronisé" : "No Stores Synced Yet";
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error verifying user or fetching stores: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCloudDataForDateRange() async {
    if (_selectedDateRange == null || _selectedStoreId.isEmpty || _clientId.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      DateTime start = _selectedDateRange!.start;
      DateTime end = _selectedDateRange!.end;

      List<PeopleCount> loadedData = [];
      _currentCa = 0; _currentClients = 0; _currentArticles = 0;
      _posDatabase.clear();

      for (DateTime d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        String dateKey = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('clients')
            .doc(_clientId)
            .collection('stores')
            .doc(_selectedStoreId)
            .collection('daily_traffic')
            .doc(dateKey)
            .get();

        if (doc.exists && doc.data() != null) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          if (data.containsKey('cameras')) {
            Map<String, dynamic> cameras = data['cameras'];
            cameras.forEach((cameraName, hourly) {
              if (hourly is Map) {
                hourly.forEach((time, counts) {
                  loadedData.add(PeopleCount(
                    date: "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}",
                    time: time,
                    doorName: cameraName,
                    inCount: counts['in'] ?? 0,
                    outCount: counts['out'] ?? 0,
                    shopId: _selectedStoreId,
                  ));
                });
              }
            });
          }
          else if (data.containsKey('hourly_data')) {
            Map<String, dynamic> hourly = data['hourly_data'];
            hourly.forEach((time, counts) {
              loadedData.add(PeopleCount(
                date: "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}",
                time: time,
                doorName: "All Doors",
                inCount: counts['in'] ?? 0,
                outCount: counts['out'] ?? 0,
                shopId: _selectedStoreId,
              ));
            });
          }

          if (data.containsKey('pos')) {
            double dailyCa = ((data['pos']['ca'] ?? 0) as num).toDouble();
            int dailyClients = ((data['pos']['clients'] ?? 0) as num).toInt();
            int dailyArticles = ((data['pos']['articles'] ?? 0) as num).toInt();

            _currentCa += dailyCa;
            _currentClients += dailyClients;
            _currentArticles += dailyArticles;

            _posDatabase[dateKey] = {
              'ca': dailyCa,
              'clients': dailyClients,
              'articles': dailyArticles,
            };
          }
        }
      }

      setState(() {
        _rawData = loadedData;
        _applyFilter();
        _isLoading = false;
      });

    } catch (e) {
      debugPrint("Error fetching cloud data: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchDataForExport(DateTimeRange range) async {
    List<PeopleCount> loadedData = [];
    Map<String, Map<String, num>> loadedPos = {};

    if (_selectedStoreId.isEmpty || _clientId.isEmpty) return {'rawData': loadedData, 'posDatabase': loadedPos};

    try {
      for (DateTime d = range.start; d.isBefore(range.end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        String dateKey = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('clients').doc(_clientId)
            .collection('stores').doc(_selectedStoreId)
            .collection('daily_traffic').doc(dateKey).get();

        if (doc.exists && doc.data() != null) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          if (data.containsKey('cameras')) {
            data['cameras'].forEach((cameraName, hourly) {
              if (hourly is Map) {
                hourly.forEach((time, counts) {
                  loadedData.add(PeopleCount(
                    date: "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}",
                    time: time, doorName: cameraName, inCount: counts['in'] ?? 0, outCount: counts['out'] ?? 0, shopId: _selectedStoreId,
                  ));
                });
              }
            });
          } else if (data.containsKey('hourly_data')) {
            data['hourly_data'].forEach((time, counts) {
              loadedData.add(PeopleCount(
                date: "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}",
                time: time, doorName: "All Doors", inCount: counts['in'] ?? 0, outCount: counts['out'] ?? 0, shopId: _selectedStoreId,
              ));
            });
          }

          if (data.containsKey('pos')) {
            loadedPos[dateKey] = {
              'ca': ((data['pos']['ca'] ?? 0) as num).toDouble(),
              'clients': ((data['pos']['clients'] ?? 0) as num).toInt(),
              'articles': ((data['pos']['articles'] ?? 0) as num).toInt(),
            };
          }
        }
      }
    } catch (e) {
      debugPrint("Export Fetch Error: $e");
    }
    return {'rawData': loadedData, 'posDatabase': loadedPos};
  }

  void _applyFilter() {
    setState(() {
      if (_selectedDateRange != null && _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays > 0) {
        _currentFilter = ChartFilter.daily;
      } else {
        _currentFilter = ChartFilter.hourly;
      }

      Set<String> cams = {'All Doors'};
      for (var item in _rawData) {
        if (item.doorName != 'All Doors') {
          cams.add(item.doorName);
        }
      }
      _availableCameras = cams.toList()..sort();

      if (!_availableCameras.contains(_selectedCamera)) {
        _selectedCamera = 'All Doors';
      }

      List<PeopleCount> filteredData = _rawData.where((item) {
        if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) {
          return false;
        }

        var timeParts = item.time.split(':');
        int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
        int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        int totalMinutes = (hour * 60) + minute;

        if (totalMinutes < _workingMinuteStart || totalMinutes > _workingMinuteEnd) {
          return false;
        }
        return true;
      }).toList();

      if (_currentFilter == ChartFilter.daily) {
        _displayedData = DataAggregator.aggregateByDay(filteredData);
      } else {
        _displayedData = DataAggregator.aggregateByHour(filteredData);
      }

      _perDoorData.clear();
      if (_selectedCamera == 'All Doors' && _availableCameras.length > 2) {
        for (String door in _availableCameras) {
          if (door == 'All Doors') continue;

          var doorSpecificData = filteredData.where((item) => item.doorName == door).toList();
          if (_currentFilter == ChartFilter.daily) {
            _perDoorData[door] = DataAggregator.aggregateByDay(doorSpecificData);
          } else {
            _perDoorData[door] = DataAggregator.aggregateByHour(doorSpecificData);
          }
        }
      }

      _totalIn = 0; _totalOut = 0; int maxTraffic = 0; _peakHour = "--:--";
      for (var item in _displayedData) {
        _totalIn += item.inCount;
        _totalOut += item.outCount;
        int totalVisitorsForHour = (item.inCount + item.outCount) ~/ 2;
        if (totalVisitorsForHour > maxTraffic) {
          maxTraffic = totalVisitorsForHour;
          _peakHour = item.time;
        }
      }

      _occupancy = _totalIn - _totalOut;
      if (_occupancy < 0) _occupancy = 0;

      // ==========================================================
      // 🚀 NEW OPTIMIZATION: Pre-calculate Matrix Data here instantly!
      // ==========================================================
      _matrixRowData.clear();
      _matrixDoorInTotals.clear();
      _matrixDoorOutTotals.clear();

      if (_selectedCamera == 'All Doors' && _availableCameras.length > 2) {
        List<String> individualDoors = _availableCameras.where((c) => c != 'All Doors').toList();

        // 1. Initialize Totals
        for (String door in individualDoors) {
          _matrixDoorInTotals[door] = 0;
          _matrixDoorOutTotals[door] = 0;
        }

        // 2. Build Fast Lookup HashMaps -> O(1) speed instead of O(N) list searches!
        Map<String, Map<String, PeopleCount>> fastLookup = {};
        for(String door in individualDoors) {
          fastLookup[door] = {};
          if (_perDoorData[door] != null) {
            for(var item in _perDoorData[door]!) {
              String key = _currentFilter == ChartFilter.hourly ? item.time : item.date;
              fastLookup[door]![key] = item;
            }
          }
        }

        // 3. Construct the rows
        for (var globalItem in _displayedData) {
          String timeLabel = _currentFilter == ChartFilter.hourly ? globalItem.time : globalItem.date;
          Map<String, dynamic> row = {
            'time': timeLabel,
            'globalIn': globalItem.inCount,
            'globalOut': globalItem.outCount,
            'doors': <String, Map<String, int>>{}
          };

          for (String door in individualDoors) {
            int dIn = 0;
            int dOut = 0;

            // ⚡ INSTANT LOOKUP (No loops!)
            PeopleCount? match = fastLookup[door]?[timeLabel];
            if (match != null) {
              dIn = match.inCount;
              dOut = match.outCount;
            }

            row['doors'][door] = {'in': dIn, 'out': dOut};
            _matrixDoorInTotals[door] = (_matrixDoorInTotals[door] ?? 0) + dIn;
            _matrixDoorOutTotals[door] = (_matrixDoorOutTotals[door] ?? 0) + dOut;
          }
          _matrixRowData.add(row);
        }
      }
      // ==========================================================
    });
  }

  void _shiftDate(int days) {
    setState(() {
      if (_selectedDateRange == null) {
        DateTime today = DateTime.now();
        _selectedDateRange = DateTimeRange(start: today, end: today);
      } else {
        _selectedDateRange = DateTimeRange(
            start: _selectedDateRange!.start.add(Duration(days: days)),
            end: _selectedDateRange!.end.add(Duration(days: days))
        );
      }
      _fetchCloudDataForDateRange();
    });
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(primary: _accentCyan, onPrimary: Colors.white, surface: _cardDark, onSurface: Colors.white),
            dialogBackgroundColor: _cardDark,
          ),
          child: child!
      ),
    );
    if (pickedRange != null) {
      setState(() => _selectedDateRange = pickedRange);
      _fetchCloudDataForDateRange();
    }
  }

  String _getFormattedDateString() {
    if (_selectedDateRange == null) return _isFrench ? "De tout temps" : "All Time";

    List<String> daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    List<String> daysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    List<String> monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    List<String> monthsFr = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

    List<String> shortDaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    List<String> shortDaysFr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    List<String> shortMonthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    List<String> shortMonthsFr = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];

    List<String> days = _isFrench ? daysFr : daysEn;
    List<String> months = _isFrench ? monthsFr : monthsEn;
    List<String> shortDays = _isFrench ? shortDaysFr : shortDaysEn;
    List<String> shortMonths = _isFrench ? shortMonthsFr : shortMonthsEn;

    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;

    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) {
      return _isFrench
          ? "${days[start.weekday - 1]}, ${start.day} ${months[start.month - 1]} ${start.year}"
          : "${days[start.weekday - 1]}, ${months[start.month - 1]} ${start.day}, ${start.year}";
    }

    return _isFrench
        ? "${shortDays[start.weekday - 1]} ${start.day} ${shortMonths[start.month - 1]} - ${shortDays[end.weekday - 1]} ${end.day} ${shortMonths[end.month - 1]}"
        : "${shortDays[start.weekday - 1]}, ${shortMonths[start.month - 1]} ${start.day} - ${shortDays[end.weekday - 1]}, ${shortMonths[end.month - 1]} ${end.day}";
  }

  void _showStoreSelectorDialog() {
    if (_userStores.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Text(_isFrench ? 'Vos Magasins ($_clientId)' : 'Your Stores ($_clientId)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 300,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _userStores.length,
            separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
            itemBuilder: (context, index) {
              var store = _userStores[index];
              bool isSelected = _selectedStoreId == store['id'];
              return ListTile(
                leading: Icon(Icons.storefront, color: isSelected ? _accentCyan : Colors.white54),
                title: Text(store['brand'], style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
                subtitle: Text(store['location'], style: TextStyle(color: isSelected ? _accentCyan : Colors.white54)),
                trailing: isSelected ? Icon(Icons.check_circle, color: _accentCyan) : null,
                onTap: () {
                  setState(() {
                    _selectedStoreId = store['id'];
                    _storeName = store['brand'];
                    _storeLocation = store['location'];
                    _enablePosFeatures = store['enable_pos_features'];
                  });
                  Navigator.pop(context);
                  _fetchCloudDataForDateRange();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _navigateToExport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExportScreen(
          rawData: _rawData,
          availableCameras: _availableCameras,
          isFrench: _isFrench,
          workingMinuteStart: _workingMinuteStart,
          workingMinuteEnd: _workingMinuteEnd,
          posDatabase: _posDatabase,
          onFetchWebData: _fetchDataForExport,
          storeName: _storeName,
          storeLocation: _storeLocation,
        ),
      ),
    );
  }

  Widget _buildLanguageToggle() {
    return GestureDetector(
      onTap: _toggleLanguage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 100,
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              alignment: _isFrench ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 46,
                height: 36,
                decoration: BoxDecoration(
                  color: _bgDark,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1,
                        color: !_isFrench ? _accentCyan : Colors.white38,
                      ),
                      child: const Text('EN'),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1,
                        color: _isFrench ? _accentCyan : Colors.white38,
                      ),
                      child: const Text('FR'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar() {
    return AppBar(
      backgroundColor: _bgDark,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_storeName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: _buildLanguageToggle(),
        ),
      ],
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(color: _bgDark, border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: Row(
        children: [
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, snapshot) {
              final now = DateTime.now();
              String hour = now.hour.toString().padLeft(2, '0');
              String minute = now.minute.toString().padLeft(2, '0');
              return Text("$hour:$minute", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1));
            },
          ),
          const Spacer(),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentCyan.withOpacity(0.15),
              foregroundColor: _accentCyan,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _accentCyan.withOpacity(0.5))
              ),
            ),
            icon: const Icon(Icons.download, size: 18),
            label: Text(
              _isFrench ? 'EXPORTER' : 'EXPORT',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _navigateToExport,
          ),
          const SizedBox(width: 16),

          _buildLanguageToggle(),
          const SizedBox(width: 32),

          if (_userStores.isNotEmpty)
            Row(
              children: [
                if (_availableCameras.length > 1)
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCamera,
                        dropdownColor: _cardDark,
                        icon: Icon(Icons.videocam, color: _accentCyan, size: 20),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: _availableCameras.map((cam) => DropdownMenuItem(value: cam, child: Padding(padding: const EdgeInsets.only(right: 8), child: Text(cam)))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCamera = val);
                            _applyFilter();
                          }
                        },
                      ),
                    ),
                  ),

                InkWell(
                  onTap: _showStoreSelectorDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                            Text(_storeName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(color: _cardDark, shape: BoxShape.circle, border: Border.all(color: _accentCyan, width: 2)),
                          child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // 🚀 Decides which table layout to show
  Widget _buildTableView() {
    bool showMatrix = _selectedCamera == 'All Doors' && _availableCameras.length > 2;

    if (showMatrix) {
      return _buildMatrixTable();
    } else {
      return _buildStandardTable();
    }
  }

  // 🚀 OPTIMIZED: Horizontal Pivot Matrix for "Vue Globale"
  Widget _buildMatrixTable() {
    List<String> individualDoors = _availableCameras.where((c) => c != 'All Doors').toList();

    const double timeColWidth = 100;
    const double dataColWidth = 70;

    Widget buildCell(String text, double width, {Color? color, bool isTitle = false, bool rightBorder = false}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: rightBorder ? BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withOpacity(0.1)))) : null,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? (isTitle ? Colors.white : Colors.white54),
            fontWeight: isTitle ? FontWeight.w900 : FontWeight.bold,
            fontSize: isTitle ? 13 : 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                child: Row(
                  children: [
                    buildCell('', timeColWidth, rightBorder: true),
                    buildCell(_isFrench ? 'GLOBAL' : 'GLOBAL', dataColWidth * 2, isTitle: true, color: Colors.white, rightBorder: true),
                    ...individualDoors.map((door) => buildCell(door.toUpperCase(), dataColWidth * 2, isTitle: true, color: _accentCyan, rightBorder: true)).toList(),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: Row(
                  children: [
                    buildCell(_isFrench ? 'Période' : 'Time', timeColWidth, isTitle: true, rightBorder: true),
                    buildCell('IN', dataColWidth, color: Colors.greenAccent),
                    buildCell('OUT', dataColWidth, color: Colors.redAccent, rightBorder: true),
                    ...individualDoors.expand((door) => [
                      buildCell('IN', dataColWidth, color: Colors.greenAccent),
                      buildCell('OUT', dataColWidth, color: Colors.redAccent, rightBorder: true),
                    ]).toList(),
                  ],
                ),
              ),
              // ⚡ ListView.builder only renders rows visible on screen
              Expanded(
                child: ListView.builder(
                  itemCount: _matrixRowData.length,
                  itemBuilder: (context, index) {
                    var row = _matrixRowData[index];
                    return Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02)))),
                      child: Row(
                        children: [
                          buildCell(row['time'], timeColWidth, color: Colors.white, isTitle: true, rightBorder: true),
                          buildCell(row['globalIn'].toString(), dataColWidth, color: Colors.greenAccent),
                          buildCell(row['globalOut'].toString(), dataColWidth, color: Colors.redAccent, rightBorder: true),
                          ...individualDoors.expand((door) => [
                            buildCell(row['doors'][door]['in'].toString(), dataColWidth, color: Colors.greenAccent.withOpacity(0.7)),
                            buildCell(row['doors'][door]['out'].toString(), dataColWidth, color: Colors.redAccent.withOpacity(0.7), rightBorder: true),
                          ]).toList(),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    buildCell('TOTAL', timeColWidth, isTitle: true, color: Colors.white, rightBorder: true),
                    buildCell(_totalIn.toString(), dataColWidth, color: Colors.greenAccent, isTitle: true),
                    buildCell(_totalOut.toString(), dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
                    ...individualDoors.expand((door) => [
                      buildCell(_matrixDoorInTotals[door].toString(), dataColWidth, color: Colors.greenAccent, isTitle: true),
                      buildCell(_matrixDoorOutTotals[door].toString(), dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
                    ]).toList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🚀 Standard Table for a Single Camera
  Widget _buildStandardTable() {
    return Container(
      decoration: BoxDecoration(
        color: _bgDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(_isFrench ? 'Période' : 'Time', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
                Expanded(child: Text(_isFrench ? 'Entrées' : 'In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
                Expanded(child: Text(_isFrench ? 'Sorties' : 'Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
                Expanded(child: Text(_isFrench ? 'Total' : 'Total', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _displayedData.length,
              itemBuilder: (context, index) {
                var item = _displayedData[index];
                String timeLabel = _currentFilter == ChartFilter.hourly ? item.time : item.date;
                int total = (item.inCount + item.outCount) ~/ 2;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02)))),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(timeLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      Expanded(child: Text(item.inCount.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent))),
                      Expanded(child: Text(item.outCount.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
                      Expanded(child: Text(total.toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('TOTAL', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
                Expanded(child: Text(_totalIn.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14))),
                Expanded(child: Text(_totalOut.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14))),
                Expanded(child: Text(((_totalIn + _totalOut) ~/ 2).toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChart(bool isMobile) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    List<LineChartBarData> chartLines = [];
    double maxTrafficY = 1.0;

    for (var item in _displayedData) {
      if (item.inCount > maxTrafficY) maxTrafficY = item.inCount.toDouble();
      if (item.outCount > maxTrafficY) maxTrafficY = item.outCount.toDouble();
    }

    chartLines.add(LineChartBarData(
      spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
      isCurved: true, color: const Color(0xFF00C6FF), barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false),
    ));
    chartLines.add(LineChartBarData(
      spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
      isCurved: true, color: const Color(0xFFFF512F), barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false),
    ));

    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      decoration: BoxDecoration(
        color: _cardDark, borderRadius: BorderRadius.circular(isMobile ? 20 : 32), border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40, offset: const Offset(0, 20))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isFrench ? 'TRAFIC GLOBAL' : 'GLOBAL TRAFFIC', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 3.0)),
                  Text(totalVisitors.toString(), style: TextStyle(color: Colors.white, fontSize: isMobile ? 48 : 72, fontWeight: FontWeight.w900, letterSpacing: -2, height: 1.0)),
                ],
              ),
              Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🚀 View Toggle (Chart / Table)
                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.1))
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.show_chart, color: !_isTableMode ? const Color(0xFF00C6FF) : Colors.white54, size: 20),
                            onPressed: () => setState(() => _isTableMode = false),
                            tooltip: _isFrench ? 'Graphique' : 'Chart',
                          ),
                          IconButton(
                            icon: Icon(Icons.table_chart, color: _isTableMode ? const Color(0xFF00C6FF) : Colors.white54, size: 20),
                            onPressed: () => setState(() => _isTableMode = true),
                            tooltip: _isFrench ? 'Tableau' : 'Table',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_isFrench ? "Total Entrées" : "Total In"}: $_totalIn', style: const TextStyle(color: Color(0xFF00C6FF), fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text('${_isFrench ? "Total Sorties" : "Total Out"}: $_totalOut', style: const TextStyle(color: Color(0xFFFF512F), fontSize: 15, fontWeight: FontWeight.w900)),
                      ],
                    )
                  ]
              )
            ],
          ),
          SizedBox(height: isMobile ? 30 : 50),
          SizedBox(
            height: isMobile ? 300 : 380,
            // 🚀 Decide what to render based on the toggle state!
            child: _isTableMode ? _buildTableView() : LineChart(
              LineChartData(
                minY: 0, maxY: maxTrafficY * 1.15,
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [8, 8])),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: isMobile ? 35 : 50, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.white38, fontSize: 12)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) {
                    int index = value.toInt();
                    if (index >= 0 && index < _displayedData.length) {
                      var item = _displayedData[index];
                      String label = _currentFilter == ChartFilter.daily
                          ? item.date.substring(0, 5)
                          : item.time.split(':')[0];

                      return Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))
                      );
                    }
                    return const SizedBox.shrink();
                  })),
                ),
                borderData: FlBorderData(show: false), lineBarsData: chartLines,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoGrid(bool isMobile) {
    List<Widget> cards = [];

    if (!_enablePosFeatures) {
      cards = [
        _buildBentoCard(
            title: _isFrench ? 'TOTAL ENTRÉES' : 'TOTAL IN',
            value: '$_totalIn',
            unit: _isFrench ? 'PERS' : 'PAX',
            icon: Icons.login_rounded,
            color: const Color(0xFF38EF7D),
            isMobile: isMobile
        ),
        _buildBentoCard(
            title: _isFrench ? 'TOTAL SORTIES' : 'TOTAL OUT',
            value: '$_totalOut',
            unit: _isFrench ? 'PERS' : 'PAX',
            icon: Icons.logout_rounded,
            color: const Color(0xFFFF512F),
            isMobile: isMobile
        ),
        _buildBentoCard(
            title: _isFrench ? 'HEURE DE POINTE' : 'PEAK HOUR',
            value: _peakHour,
            unit: 'TIME',
            icon: Icons.access_time_filled_rounded,
            color: const Color(0xFF00C6FF),
            isMobile: isMobile
        ),
        _buildBentoCard(
            title: _isFrench ? 'OCCUPATION' : 'OCCUPANCY',
            value: '$_occupancy',
            unit: _isFrench ? 'ACTUEL' : 'NOW',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF8E2DE2),
            isMobile: isMobile
        ),
      ];
    } else {
      int totalVisitors = (_totalIn + _totalOut) ~/ 2;
      double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
      double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
      double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

      cards = [
        _buildBentoCard(title: _isFrench ? "CHIFFRE D'AFFAIRES" : 'REVENUE', value: _currentCa.toStringAsFixed(0), unit: 'DZD', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF38EF7D), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'TAUX DE CONV.' : 'CONV. RATE', value: conversionRate.toStringAsFixed(1), unit: '%', icon: Icons.track_changes_rounded, color: const Color(0xFFFF512F), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'PANIER MOYEN' : 'AVG BASKET', value: avgBasket.toStringAsFixed(0), unit: 'DZD', icon: Icons.shopping_bag_rounded, color: const Color(0xFF00C6FF), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'INDICE DE VENTE' : 'U.P.T', value: upt.toStringAsFixed(2), unit: 'ART', icon: Icons.layers_rounded, color: const Color(0xFF8E2DE2), isMobile: isMobile),
      ];
    }

    if (isMobile) {
      return Column(
        children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList(),
      );
    } else {
      return Row(
        children: [
          Expanded(flex: 2, child: cards[0]), const SizedBox(width: 24),
          Expanded(flex: 1, child: cards[1]), const SizedBox(width: 24),
          Expanded(flex: 1, child: cards[2]), const SizedBox(width: 24),
          Expanded(flex: 1, child: cards[3]),
        ],
      );
    }
  }

  Widget _buildBentoCard({required String title, required String value, required String unit, required IconData icon, required Color color, required bool isMobile}) {
    return Container(
      height: isMobile ? 180 : 220,
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      width: isMobile ? double.infinity : null,
      decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(isMobile ? 20 : 32), border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: TextStyle(fontSize: isMobile ? 32 : 42, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(width: 6),
                  Text(unit, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar({bool isMobile = false}) {
    return Container(
      width: isMobile ? null : 260,
      color: _cardDark,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            Image.asset(
              'assets/boitex_logo.png',
              width: 180,
              height: 100,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 16),
            const Text('BoitexInfo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            Text(_isFrench ? 'TABLEAU DE BORD CLOUD' : 'CLOUD DASHBOARD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _accentCyan, letterSpacing: 2.0)),
            const SizedBox(height: 40),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _bgDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05))
              ),
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: _accentCyan.withOpacity(0.2), child: Icon(Icons.person, color: _accentCyan, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_loggedInUserName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                        Text(_loggedInRole.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.0)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (isMobile && _userStores.isNotEmpty)
              ListTile(
                leading: Icon(Icons.store, color: _accentCyan),
                title: Text(_isFrench ? 'Changer de Magasin' : 'Switch Store', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _showStoreSelectorDialog();
                },
              ),

            ListTile(leading: Icon(Icons.dashboard, color: _accentCyan), title: Text(_isFrench ? 'Tableau de bord' : 'Dashboard', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),

            ListTile(
              leading: const Icon(Icons.download, color: Colors.white),
              title: Text(_isFrench ? 'Exporter Rapports' : 'Export Reports', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                if (isMobile) Navigator.pop(context);
                _navigateToExport();
              },
            ),

            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: Text(_isFrench ? 'Déconnexion' : 'Sign Out', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: _signOut,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(bool isMobile, double padding) {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: _accentCyan));

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              Text(_isFrench ? "Vue d'Ensemble" : 'Command Center', style: TextStyle(fontSize: isMobile ? 28 : 36, fontWeight: FontWeight.w900, color: Colors.white)),
              Container(
                decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.1))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white54), onPressed: () => _shiftDate(-1)),
                    GestureDetector(onTap: _pickDateRange, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                    IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white54), onPressed: () => _shiftDate(1)),
                  ],
                ),
              ),
            ],
          ),

          if (isMobile && _availableCameras.length > 1)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCamera,
                  dropdownColor: _cardDark,
                  icon: Icon(Icons.videocam, color: _accentCyan, size: 20),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  items: _availableCameras.map((cam) => DropdownMenuItem(value: cam, child: Text(cam))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCamera = val);
                      _applyFilter();
                    }
                  },
                ),
              ),
            ),

          const SizedBox(height: 32),

          if (_rawData.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(80.0), child: Text(_isFrench ? "Aucune donnée trouvée pour ce magasin à cette date." : "No data found for this store on this date.", style: const TextStyle(color: Colors.white54, fontSize: 18), textAlign: TextAlign.center)))
          else ...[
            _buildHeroChart(isMobile),
            const SizedBox(height: 32),

            Container(
              width: double.infinity, padding: EdgeInsets.all(isMobile ? 20 : 32),
              decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(isMobile ? 20 : 24), border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Column(
                children: [
                  const Icon(Icons.videocam_off, color: Colors.white24, size: 48),
                  const SizedBox(height: 16),
                  Text(_isFrench ? 'Flux en direct indisponible à distance' : 'Live Feed Unavailable Remotely', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_isFrench ? 'Pour des raisons de sécurité, les flux des caméras ne peuvent être consultés que sur le PC local du magasin.' : 'For security reasons, live camera streams can only be viewed on the local store PC.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            _buildBentoGrid(isMobile),
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 900;
    double padding = isMobile ? 16.0 : 32.0;

    return Scaffold(
      backgroundColor: _bgDark,
      drawer: isMobile ? Drawer(child: _buildSidebar(isMobile: true)) : null,
      appBar: isMobile ? _buildMobileAppBar() : null,
      body: isMobile
          ? _buildMainContent(isMobile, padding)
          : Row(
        children: [
          _buildSidebar(isMobile: false),
          Expanded(
            child: Column(
              children: [
                _buildTopAppBar(),
                Expanded(child: _buildMainContent(isMobile, padding)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}