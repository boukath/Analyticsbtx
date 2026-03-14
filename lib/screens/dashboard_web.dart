// lib/screens/dashboard_web.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
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

          // 🚀 PARSE NEW MULTI-CAMERA STRUCTURE
          if (data.containsKey('cameras')) {
            Map<String, dynamic> cameras = data['cameras'];
            cameras.forEach((cameraName, hourly) {
              if (hourly is Map) {
                hourly.forEach((time, counts) {
                  loadedData.add(PeopleCount(
                    date: "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}",
                    time: time,
                    doorName: cameraName, // Extract specific camera name!
                    inCount: counts['in'] ?? 0,
                    outCount: counts['out'] ?? 0,
                    shopId: _selectedStoreId,
                  ));
                });
              }
            });
          }
          // 🚀 BACKWARDS COMPATIBILITY FOR OLD DATA
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
            _currentCa += (data['pos']['ca'] ?? 0).toDouble();
            _currentClients += (data['pos']['clients'] ?? 0) as int;
            _currentArticles += (data['pos']['articles'] ?? 0) as int;
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

  void _applyFilter() {
    setState(() {
      // 1. Build dynamic camera list based on available data
      Set<String> cams = {'All Doors'};
      for (var item in _rawData) {
        // Only add individual cameras to the dropdown, don't duplicate "All Doors"
        if (item.doorName != 'All Doors') {
          cams.add(item.doorName);
        }
      }
      _availableCameras = cams.toList()..sort(); // Sorting makes it look cleaner!

      // Reset if selected camera doesn't exist in new date range
      if (!_availableCameras.contains(_selectedCamera)) {
        _selectedCamera = 'All Doors';
      }

      // 2. Filter data by working hours AND the selected camera
      List<PeopleCount> filteredData = _rawData.where((item) {
        // 🚀 FIXED: Only filter by camera if a specific camera is chosen!
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

  // ===========================================================================
  // 🚀 UI BUILDERS
  // ===========================================================================

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

    List<String> monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    List<String> monthsFr = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];
    List<String> months = _isFrench ? monthsFr : monthsEn;

    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;

    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) {
      return _isFrench
          ? "${start.day} ${months[start.month - 1]} ${start.year}"
          : "${months[start.month - 1]} ${start.day}, ${start.year}";
    }
    return "${months[start.month - 1]} ${start.day} - ${months[end.month - 1]} ${end.day}";
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

          _buildLanguageToggle(),
          const SizedBox(width: 32),

          if (_userStores.isNotEmpty)
            Row(
              children: [
                // 🚀 CAMERA SELECTOR DROPDOWN
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

                // STORE SELECTOR
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

  Widget _buildHeroChart() {
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
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: _cardDark, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40, offset: const Offset(0, 20))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isFrench ? 'TRAFIC GLOBAL' : 'GLOBAL TRAFFIC', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 3.0)),
                  Text(totalVisitors.toString(), style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w900, letterSpacing: -3, height: 1.0)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_isFrench ? "Total Entrées" : "Total In"}: $_totalIn', style: const TextStyle(color: Color(0xFF00C6FF), fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('${_isFrench ? "Total Sorties" : "Total Out"}: $_totalOut', style: const TextStyle(color: Color(0xFFFF512F), fontSize: 15, fontWeight: FontWeight.w900)),
                ],
              )
            ],
          ),
          const SizedBox(height: 50),
          SizedBox(
            height: 380,
            child: LineChart(
              LineChartData(
                minY: 0, maxY: maxTrafficY * 1.15,
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [8, 8])),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.white38, fontSize: 12)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) {
                    int index = value.toInt();
                    if (index >= 0 && index < _displayedData.length) {
                      return Padding(padding: const EdgeInsets.only(top: 12.0), child: Text(_displayedData[index].time.split(':')[0], style: const TextStyle(color: Colors.white54, fontSize: 11)));
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

  Widget _buildBentoGrid() {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
    double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
    double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

    return Row(
      children: [
        Expanded(flex: 2, child: _buildBentoCard(title: _isFrench ? "CHIFFRE D'AFFAIRES" : 'REVENUE', value: _currentCa.toStringAsFixed(0), unit: 'DZD', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF38EF7D))), const SizedBox(width: 24),
        Expanded(flex: 1, child: _buildBentoCard(title: _isFrench ? 'TAUX DE CONV.' : 'CONV. RATE', value: conversionRate.toStringAsFixed(1), unit: '%', icon: Icons.track_changes_rounded, color: const Color(0xFFFF512F))), const SizedBox(width: 24),
        Expanded(flex: 1, child: _buildBentoCard(title: _isFrench ? 'PANIER MOYEN' : 'AVG BASKET', value: avgBasket.toStringAsFixed(0), unit: 'DZD', icon: Icons.shopping_bag_rounded, color: const Color(0xFF00C6FF))), const SizedBox(width: 24),
        Expanded(flex: 1, child: _buildBentoCard(title: _isFrench ? 'INDICE DE VENTE' : 'U.P.T', value: upt.toStringAsFixed(2), unit: 'ART', icon: Icons.layers_rounded, color: const Color(0xFF8E2DE2))),
      ],
    );
  }

  Widget _buildBentoCard({required String title, required String value, required String unit, required IconData icon, required Color color}) {
    return Container(
      height: 220, padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5)),
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
                children: [Text(value, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white)), const SizedBox(width: 6), Text(unit, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260, color: _cardDark,
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.cloud, color: _accentCyan, size: 60),
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

          ListTile(leading: Icon(Icons.dashboard, color: _accentCyan), title: Text(_isFrench ? 'Tableau de bord' : 'Dashboard', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.download, color: Colors.white54), title: Text(_isFrench ? 'Exporter Rapports' : 'Export Reports', style: const TextStyle(color: Colors.white54))),

          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(_isFrench ? 'Déconnexion' : 'Sign Out', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: _signOut,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopAppBar(),
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: _accentCyan))
                      : SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_isFrench ? "Vue d'Ensemble" : 'Command Center', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
                            Container(
                              decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.1))),
                              child: Row(
                                children: [
                                  IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white54), onPressed: () => _shiftDate(-1)),
                                  GestureDetector(onTap: _pickDateRange, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                                  IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white54), onPressed: () => _shiftDate(1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        if (_rawData.isEmpty)
                          Center(child: Padding(padding: const EdgeInsets.all(80.0), child: Text(_isFrench ? "Aucune donnée trouvée pour ce magasin à cette date." : "No data found for this store on this date.", style: const TextStyle(color: Colors.white54, fontSize: 18))))
                        else ...[
                          _buildHeroChart(),
                          const SizedBox(height: 32),

                          Container(
                            width: double.infinity, padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1))),
                            child: Column(
                              children: [
                                const Icon(Icons.videocam_off, color: Colors.white24, size: 48),
                                const SizedBox(height: 16),
                                Text(_isFrench ? 'Flux en direct indisponible à distance' : 'Live Feed Unavailable Remotely', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text(_isFrench ? 'Pour des raisons de sécurité, les flux des caméras ne peuvent être consultés que sur le PC local du magasin.' : 'For security reasons, live camera streams can only be viewed on the local store PC.', style: const TextStyle(color: Colors.white54)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          _buildBentoGrid(),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}