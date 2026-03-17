// lib/screens/dashboard_web.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'export_screen.dart'; // 🚀 NEW: Import the export screen
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

  bool _isLoading = true;
  ChartFilter _currentFilter = ChartFilter.hourly;
  DateTimeRange? _selectedDateRange;

  bool _isFrench = false;
  int _workingMinuteStart = 0;
  int _workingMinuteEnd = 1439;

  // 🚀 Camera Variables
  List<String> _availableCameras = ['All Doors'];
  String _selectedCamera = 'All Doors';

  int _totalIn = 0;
  int _totalOut = 0;
  String _peakHour = "--:--";

  double _currentCa = 0;
  int _currentClients = 0;
  int _currentArticles = 0;

  // 🚀 NEW: A map to hold daily POS data for the Export Screen
  Map<String, Map<String, num>> _posDatabase = {};

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
        stores.add({
          'id': doc.id,
          'brand': doc.data().toString().contains('brand') ? doc.get('brand') : 'Unknown',
          'location': doc.data().toString().contains('location') ? doc.get('location') : doc.id,
        });
      }

      if (stores.isNotEmpty) {
        setState(() {
          _userStores = stores;
          _selectedStoreId = stores.first['id'];
          _storeName = stores.first['brand'];
          _storeLocation = stores.first['location'];
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
      _posDatabase.clear(); // 🚀 NEW: Clear previous POS data

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

          // 🚀 FIXED: Safely cast Firebase numbers to avoid crashes AND map them for ExportScreen
          if (data.containsKey('pos')) {
            double dailyCa = ((data['pos']['ca'] ?? 0) as num).toDouble();
            int dailyClients = ((data['pos']['clients'] ?? 0) as num).toInt();
            int dailyArticles = ((data['pos']['articles'] ?? 0) as num).toInt();

            _currentCa += dailyCa;
            _currentClients += dailyClients;
            _currentArticles += dailyArticles;

            // Save this exact date's POS data into our map
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

  // 🚀 NEW: Helper to fetch data strictly for the Export Screen
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
      // 🚀 FIXED: Auto-switch between Hourly and Daily views depending on selected dates
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

    // Full names for single days
    List<String> daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    List<String> daysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    List<String> monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    List<String> monthsFr = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

    // Short names for date ranges
    List<String> shortDaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    List<String> shortDaysFr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    List<String> shortMonthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    List<String> shortMonthsFr = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];

    List<String> days = _isFrench ? daysFr : daysEn;
    List<String> months = _isFrench ? monthsFr : monthsEn;
    List<String> shortDays = _isFrench ? shortDaysFr : shortDaysEn;
    List<String> shortMonths = _isFrench ? shortMonthsFr : shortMonthsEn;

    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;

    // If it's a single day, show the full day of the week and full month name
    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) {
      return _isFrench
          ? "${days[start.weekday - 1]}, ${start.day} ${months[start.month - 1]} ${start.year}"
          : "${days[start.weekday - 1]}, ${months[start.month - 1]} ${start.day}, ${start.year}";
    }

    // For a range of days, use the shorter format to save space
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
          // 🚀 ADD THESE TWO LINES:
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

  // 🚀 RESPONSIVE: Simplified AppBar just for mobile
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

          // 🚀 NEW: Export Button nicely integrated into Top AppBar for Desktop
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

  // 🚀 RESPONSIVE: Pass isMobile to handle fonts and padding
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
          // 🚀 RESPONSIVE: Wrap instead of Row to prevent overflow on small phones
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_isFrench ? "Total Entrées" : "Total In"}: $_totalIn', style: const TextStyle(color: Color(0xFF00C6FF), fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('${_isFrench ? "Total Sorties" : "Total Out"}: $_totalOut', style: const TextStyle(color: Color(0xFFFF512F), fontSize: 15, fontWeight: FontWeight.w900)),
                ],
              )
            ],
          ),
          SizedBox(height: isMobile ? 30 : 50),
          SizedBox(
            height: isMobile ? 250 : 380,
            child: LineChart(
              LineChartData(
                minY: 0, maxY: maxTrafficY * 1.15,
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [8, 8])),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: isMobile ? 35 : 50, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.white38, fontSize: 12)))),

                  // 🚀 FIXED: Dynamic X-Axis labels! Shows Dates for multi-day views, Hours for single-day views.
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) {
                    int index = value.toInt();
                    if (index >= 0 && index < _displayedData.length) {
                      var item = _displayedData[index];
                      String label = _currentFilter == ChartFilter.daily
                          ? item.date.substring(0, 5) // Display "DD/MM"
                          : item.time.split(':')[0];  // Display "14", "15", etc.

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

  // 🚀 RESPONSIVE: Switch between Column and Row
  Widget _buildBentoGrid(bool isMobile) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
    double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
    double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

    List<Widget> cards = [
      _buildBentoCard(title: _isFrench ? "CHIFFRE D'AFFAIRES" : 'REVENUE', value: _currentCa.toStringAsFixed(0), unit: 'DZD', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF38EF7D), isMobile: isMobile),
      _buildBentoCard(title: _isFrench ? 'TAUX DE CONV.' : 'CONV. RATE', value: conversionRate.toStringAsFixed(1), unit: '%', icon: Icons.track_changes_rounded, color: const Color(0xFFFF512F), isMobile: isMobile),
      _buildBentoCard(title: _isFrench ? 'PANIER MOYEN' : 'AVG BASKET', value: avgBasket.toStringAsFixed(0), unit: 'DZD', icon: Icons.shopping_bag_rounded, color: const Color(0xFF00C6FF), isMobile: isMobile),
      _buildBentoCard(title: _isFrench ? 'INDICE DE VENTE' : 'U.P.T', value: upt.toStringAsFixed(2), unit: 'ART', icon: Icons.layers_rounded, color: const Color(0xFF8E2DE2), isMobile: isMobile),
    ];

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
      width: isMobile ? double.infinity : null, // Stretch full width on mobile
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

  // 🚀 RESPONSIVE: Added isMobile flag to hide width constraints when in a Drawer
  Widget _buildSidebar({bool isMobile = false}) {
    return Container(
      width: isMobile ? null : 260,
      color: _cardDark,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            // 🚀 NEW: Replaced the Cloud icon with your large logo
            Image.asset(
              'assets/boitex_logo.png',
              width: 180, // Made it nice and big! Adjust if needed.
              height: 100, // Provides plenty of space
              fit: BoxFit.contain, // Ensures the logo doesn't get stretched or cropped
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

            // Add Store selector explicitly to Sidebar on Mobile (Since Top AppBar is small)
            if (isMobile && _userStores.isNotEmpty)
              ListTile(
                leading: Icon(Icons.store, color: _accentCyan),
                title: Text(_isFrench ? 'Changer de Magasin' : 'Switch Store', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context); // Close Drawer
                  _showStoreSelectorDialog();
                },
              ),

            ListTile(leading: Icon(Icons.dashboard, color: _accentCyan), title: Text(_isFrench ? 'Tableau de bord' : 'Dashboard', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),

            // 🚀 NEW: Hooked up the sidebar button to launch the Export Screen!
            ListTile(
              leading: const Icon(Icons.download, color: Colors.white),
              title: Text(_isFrench ? 'Exporter Rapports' : 'Export Reports', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                if (isMobile) Navigator.pop(context); // Close the drawer first if on mobile
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

  // 🚀 RESPONSIVE: Main Content extracted out to handle both Desktop/Mobile Views efficiently
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
                  mainAxisSize: MainAxisSize.min, // Ensures it shrinks well
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white54), onPressed: () => _shiftDate(-1)),
                    GestureDetector(onTap: _pickDateRange, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                    IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white54), onPressed: () => _shiftDate(1)),
                  ],
                ),
              ),
            ],
          ),

          // Show Camera Selector here on Mobile instead of App Bar
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

  // 🚀 THE MAGIC: The build method now watches screen size!
  @override
  Widget build(BuildContext context) {
    // Check if screen is less than 900px wide
    bool isMobile = MediaQuery.of(context).size.width < 900;
    double padding = isMobile ? 16.0 : 32.0;

    return Scaffold(
      backgroundColor: _bgDark,
      // Create a slide-out hamburger menu drawer for the sidebar if on mobile
      drawer: isMobile ? Drawer(child: _buildSidebar(isMobile: true)) : null,
      appBar: isMobile ? _buildMobileAppBar() : null,
      body: isMobile
      // If Mobile: Just show content (Sidebar is in Drawer now)
          ? _buildMainContent(isMobile, padding)
      // If Desktop: Show Sidebar row alongside Main Content
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