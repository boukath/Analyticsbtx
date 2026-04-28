// lib/screens/dashboard_web.dart

import 'dart:ui';
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
  // --- Data States ---
  List<PeopleCount> _rawData = [];
  List<PeopleCount> _displayedData = [];
  Map<String, List<PeopleCount>> _perDoorData = {};

  // --- Compare Mode States ---
  bool _isCompareMode = false;
  List<PeopleCount> _compareRawData = [];
  List<PeopleCount> _compareDisplayedData = [];

  bool _isLoading = true;
  ChartFilter _currentFilter = ChartFilter.hourly;
  DateTimeRange? _selectedDateRange;

  bool _isFrench = false;
  int _workingMinuteStart = 0;
  int _workingMinuteEnd = 1439;

  bool _isTableMode = false;
  bool _enablePosFeatures = true;
  bool _isSingleEntrance = false;

  List<String> _availableCameras = ['All Doors'];
  String _selectedCamera = 'All Doors';

  // --- Metrics ---
  int _totalIn = 0;
  int _totalOut = 0;
  int _occupancy = 0;
  String _peakHour = "--:--";

  int _compareTotalIn = 0;
  int _compareTotalOut = 0;
  int _compareTotalVisitors = 0;

  double _currentCa = 0;
  int _currentClients = 0;
  int _currentArticles = 0;

  double _compareCa = 0;
  int _compareClients = 0;
  int _compareArticles = 0;

  Map<String, Map<String, num>> _posDatabase = {};

  // --- Firebase User States ---
  String _loggedInUserName = "Loading...";
  String _loggedInRole = "client";
  String _clientId = "";
  String _storeName = "Loading...";
  String _storeLocation = "CLOUD";
  String _selectedStoreId = "";
  List<Map<String, dynamic>> _userStores = [];

  // =========================================================================
  // 🎨 iOS 26 THEME CONSTANTS & GLASSMORPHISM UTILITIES
  // =========================================================================
  final Color _bgDeep = const Color(0xFF05050A);
  final Color _accentCyan = const Color(0xFF00F0FF);
  final Color _accentMagenta = const Color(0xFFFF003C);
  final Color _accentPurple = const Color(0xFF7000FF);
  final Color _accentGrey = const Color(0xFF8E8E93);
  final Color _glassWhiteTint = Colors.white.withOpacity(0.06);
  final Color _glassBorder = Colors.white.withOpacity(0.12);
  final double _glassBlur = 30.0;

  Widget _buildGlassContainer({
    required Widget child,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 24,
    bool isInteractive = false,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _glassBlur, sigmaY: _glassBlur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: padding,
            decoration: BoxDecoration(
              color: isInteractive ? Colors.white.withOpacity(0.1) : _glassWhiteTint,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: _glassBorder, width: 1.0),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, spreadRadius: -5)],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

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
    setState(() { _isFrench = prefs.getString('app_language') == 'fr'; });
  }

  Future<void> _toggleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isFrench = !_isFrench);
    await prefs.setString('app_language', _isFrench ? 'fr' : 'en');
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _verifyUserAndLoadStores() async {
    setState(() => _isLoading = true);
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) { _signOut(); return; }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists || userDoc.data() == null) {
        setState(() { _storeName = _isFrench ? "Accès Refusé" : "Access Denied"; _isLoading = false; });
        return;
      }

      var userData = userDoc.data() as Map<String, dynamic>;
      setState(() {
        _loggedInUserName = userData['full_name'] ?? "User";
        _loggedInRole = userData['role'] ?? "client";
        _clientId = userData['client_id'] ?? userData['client_brand'] ?? "";
      });

      if (_clientId.isEmpty) {
        setState(() { _storeName = _isFrench ? "Aucun ID Client" : "No Client ID"; _isLoading = false; });
        return;
      }

      QuerySnapshot storeSnapshot = await FirebaseFirestore.instance.collection('clients').doc(_clientId).collection('stores').get();
      List<Map<String, dynamic>> stores = [];
      for (var doc in storeSnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        stores.add({
          'id': doc.id,
          'brand': data.containsKey('brand') ? data['brand'] : 'Unknown',
          'location': data.containsKey('location') ? data['location'] : doc.id,
          'enable_pos_features': data.containsKey('enable_pos_features') ? data['enable_pos_features'] : true,
          'is_single_entrance': data.containsKey('is_single_entrance') ? data['is_single_entrance'] : false,
        });
      }

      if (stores.isNotEmpty) {
        setState(() {
          _userStores = stores;
          _selectedStoreId = stores.first['id'];
          _storeName = stores.first['brand'];
          _storeLocation = stores.first['location'];
          _enablePosFeatures = stores.first['enable_pos_features'];
          _isSingleEntrance = stores.first['is_single_entrance'];
        });
        await _fetchCloudDataForDateRange();
      } else {
        setState(() { _storeName = _isFrench ? "Aucun Magasin" : "No Stores"; _isLoading = false; });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCloudDataForDateRange() async {
    if (_selectedDateRange == null || _selectedStoreId.isEmpty || _clientId.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // 1. Fetch Primary Date Range
      var primaryResult = await _fetchDataFromFirestore(_selectedDateRange!.start, _selectedDateRange!.end);

      // 2. Fetch Compare Date Range (If needed)
      List<PeopleCount> compareData = [];
      if (_isCompareMode) {
        Duration duration = _selectedDateRange!.end.difference(_selectedDateRange!.start);
        DateTime compareEnd = _selectedDateRange!.start.subtract(const Duration(days: 1));
        DateTime compareStart = compareEnd.subtract(duration);
        var compareResult = await _fetchDataFromFirestore(compareStart, compareEnd);
        compareData = compareResult['rawData'];
      }

      setState(() {
        _rawData = primaryResult['rawData'];
        _compareRawData = compareData;
        _posDatabase = primaryResult['posDatabase'];
        _applyFilter();
        _isLoading = false;
      });

    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchDataFromFirestore(DateTime start, DateTime end) async {
    List<PeopleCount> loadedData = [];
    Map<String, Map<String, num>> posDb = {};

    for (DateTime d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
      String dateKey = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      String niceDate = "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}";

      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('clients').doc(_clientId)
          .collection('stores').doc(_selectedStoreId).collection('daily_traffic').doc(dateKey).get();

      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('cameras')) {
          data['cameras'].forEach((cameraName, hourly) {
            if (hourly is Map) {
              hourly.forEach((time, counts) {
                loadedData.add(PeopleCount(date: niceDate, time: time, doorName: cameraName, inCount: counts['in'] ?? 0, outCount: counts['out'] ?? 0, shopId: _selectedStoreId));
              });
            }
          });
        } else if (data.containsKey('hourly_data')) {
          data['hourly_data'].forEach((time, counts) {
            loadedData.add(PeopleCount(date: niceDate, time: time, doorName: "All Doors", inCount: counts['in'] ?? 0, outCount: counts['out'] ?? 0, shopId: _selectedStoreId));
          });
        }

        if (data.containsKey('pos')) {
          posDb[dateKey] = {
            'ca': ((data['pos']['ca'] ?? 0) as num).toDouble(),
            'clients': ((data['pos']['clients'] ?? 0) as num).toInt(),
            'articles': ((data['pos']['articles'] ?? 0) as num).toInt(),
          };
        }
      }
    }
    return {'rawData': loadedData, 'posDatabase': posDb};
  }

  void _applyFilter() {
    setState(() {
      _currentFilter = (_selectedDateRange != null && _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays > 0) ? ChartFilter.daily : ChartFilter.hourly;

      Set<String> cams = {'All Doors'};
      for (var item in _rawData) { if (item.doorName != 'All Doors') cams.add(item.doorName); }
      _availableCameras = cams.toList()..sort();
      if (!_availableCameras.contains(_selectedCamera)) _selectedCamera = 'All Doors';

      // -- Filter Primary Data --
      List<PeopleCount> filteredData = _rawData.where((item) {
        if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;
        var tParts = item.time.split(':');
        int mins = (int.tryParse(tParts[0]) ?? 0) * 60 + (tParts.length > 1 ? (int.tryParse(tParts[1]) ?? 0) : 0);
        return mins >= _workingMinuteStart && mins <= _workingMinuteEnd;
      }).toList();

      _displayedData = _currentFilter == ChartFilter.daily ? DataAggregator.aggregateByDay(filteredData) : DataAggregator.aggregateByHour(filteredData);

      // -- Per Door Data (for Matrix Table) --
      _perDoorData.clear();
      if (_selectedCamera == 'All Doors' && _availableCameras.length > 2 && !_isCompareMode) {
        for (String door in _availableCameras) {
          if (door == 'All Doors') continue;
          var doorData = filteredData.where((item) => item.doorName == door).toList();
          _perDoorData[door] = _currentFilter == ChartFilter.daily ? DataAggregator.aggregateByDay(doorData) : DataAggregator.aggregateByHour(doorData);
        }
      }

      _totalIn = 0; _totalOut = 0; int maxTraffic = 0; _peakHour = "--:--";
      for (var item in _displayedData) {
        _totalIn += item.inCount; _totalOut += item.outCount;
        int t = (item.inCount + item.outCount) ~/ 2;
        if (t > maxTraffic) { maxTraffic = t; _peakHour = item.time; }
      }
      _occupancy = (_totalIn - _totalOut).clamp(0, 999999);

      // -- Filter Compare Data --
      if (_isCompareMode && _compareRawData.isNotEmpty) {
        List<PeopleCount> compareFiltered = _compareRawData.where((item) {
          if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;
          var tParts = item.time.split(':');
          int mins = (int.tryParse(tParts[0]) ?? 0) * 60 + (tParts.length > 1 ? (int.tryParse(tParts[1]) ?? 0) : 0);
          return mins >= _workingMinuteStart && mins <= _workingMinuteEnd;
        }).toList();

        _compareDisplayedData = _currentFilter == ChartFilter.daily ? DataAggregator.aggregateByDay(compareFiltered) : DataAggregator.aggregateByHour(compareFiltered);

        _compareTotalIn = 0; _compareTotalOut = 0;
        for (var item in _compareDisplayedData) {
          _compareTotalIn += item.inCount; _compareTotalOut += item.outCount;
        }
        _compareTotalVisitors = (_compareTotalIn + _compareTotalOut) ~/ 2;
      }

      _calculatePosMetrics();
    });
  }

  void _calculatePosMetrics() {
    _currentCa = 0; _currentClients = 0; _currentArticles = 0;
    _compareCa = 0; _compareClients = 0; _compareArticles = 0;

    if (_selectedDateRange != null) {
      DateTime start = _selectedDateRange!.start;
      DateTime end = _selectedDateRange!.end;
      for (DateTime d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        String dateStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
        if (_posDatabase.containsKey(dateStr)) {
          _currentCa += _posDatabase[dateStr]!['ca'] ?? 0;
          _currentClients += (_posDatabase[dateStr]!['clients'] ?? 0).toInt();
          _currentArticles += (_posDatabase[dateStr]!['articles'] ?? 0).toInt();
        }
      }
    }
  }

  void _shiftDate(int days) {
    if (_selectedDateRange == null) return;
    setState(() {
      _selectedDateRange = DateTimeRange(start: _selectedDateRange!.start.add(Duration(days: days)), end: _selectedDateRange!.end.add(Duration(days: days)));
    });
    _fetchCloudDataForDateRange();
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(
          data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: _accentCyan, surface: _bgDeep, onSurface: Colors.white)),
          child: child!
      ),
    );
    if (pickedRange != null) { setState(() => _selectedDateRange = pickedRange); _fetchCloudDataForDateRange(); }
  }

  String _getFormattedDateString() {
    if (_selectedDateRange == null) return _isFrench ? "De tout temps" : "All Time";
    List<String> monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    List<String> monthsFr = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];
    List<String> weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    List<String> weekdaysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;

    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) {
      String dayName = _isFrench ? weekdaysFr[start.weekday - 1] : weekdaysEn[start.weekday - 1];
      String monthName = _isFrench ? monthsFr[start.month - 1] : monthsEn[start.month - 1];
      return _isFrench ? "$dayName ${start.day} $monthName ${start.year}" : "$dayName, $monthName ${start.day}, ${start.year}";
    }
    return "${_isFrench ? monthsFr[start.month - 1] : monthsEn[start.month - 1]} ${start.day} - ${_isFrench ? monthsFr[end.month - 1] : monthsEn[end.month - 1]} ${end.day}";
  }

  Widget _buildTrendBadge(num current, num previous) {
    if (!_isCompareMode || previous == 0) return const SizedBox.shrink();
    double change = ((current - previous) / previous) * 100;
    bool isPositive = change >= 0;

    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: isPositive ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isPositive ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3))
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: isPositive ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 6),
              Text('${change.abs().toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isPositive ? Colors.greenAccent : Colors.redAccent)),
            ]
        )
    );
  }

  Widget _buildLanguageToggle() {
    return GestureDetector(
      onTap: _toggleLanguage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 100, height: 44, padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: _glassWhiteTint, borderRadius: BorderRadius.circular(30), border: Border.all(color: _glassBorder, width: 1)),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 400), curve: Curves.easeOutBack,
              alignment: _isFrench ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(width: 46, height: 36, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))])),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1, color: !_isFrench ? _accentCyan : Colors.white38), child: const Text('EN')))),
                Expanded(child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1, color: _isFrench ? _accentCyan : Colors.white38), child: const Text('FR')))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar() {
    return AppBar(
      backgroundColor: _bgDeep,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_storeName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
      actions: [ Padding(padding: const EdgeInsets.only(right: 8.0), child: _buildLanguageToggle()) ],
    );
  }

  Widget _buildTopAppBar() {
    return _buildGlassContainer(
      height: 100,
      borderRadius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          children: [
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final now = DateTime.now();
                String hour = now.hour.toString().padLeft(2, '0');
                String minute = now.minute.toString().padLeft(2, '0');
                return Text("$hour:$minute", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5));
              },
            ),
            const Spacer(),
            _buildLanguageToggle(),
            const SizedBox(width: 40),
            InkWell(
              onTap: () { if (_userStores.length > 1) { /* Show Store Selector */ } },
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
                      const SizedBox(height: 2),
                      Text(_storeName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle, border: Border.all(color: _glassBorder, width: 1.5)),
                    child: Icon(Icons.storefront_rounded, color: _accentCyan, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroChart(bool isMobile) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    List<LineChartBarData> chartLines = [];
    bool showPerDoor = !_isSingleEntrance && _selectedCamera == 'All Doors' && _availableCameras.length > 2 && !_isCompareMode;

    List<List<Color>> luxuryGradients = [
      [_accentCyan, const Color(0xFF0072FF)],
      [_accentMagenta, const Color(0xFFDD2476)],
      [const Color(0xFF38EF7D), const Color(0xFF11998E)],
      [_accentPurple, const Color(0xFF4A00E0)],
      [const Color(0xFFFDC830), const Color(0xFFF37335)],
    ];

    double maxTrafficY = 1.0;
    double sumTraffic = 0;
    int dataPointCount = 0;

    void processSpotForMetrics(double value) {
      if (value > maxTrafficY) maxTrafficY = value;
      sumTraffic += value;
      dataPointCount++;
    }

    if (showPerDoor) {
      int colorIndex = 0;
      for (String door in _perDoorData.keys) {
        if (_perDoorData[door] != null) {
          for (var item in _perDoorData[door]!) processSpotForMetrics((item.inCount + item.outCount) / 2);

          List<FlSpot> spots = [];
          for (int i = 0; i < _displayedData.length; i++) {
            var match = _perDoorData[door]!.where((d) => d.time == _displayedData[i].time && d.date == _displayedData[i].date).toList();
            double total = match.isNotEmpty ? ((match.first.inCount + match.first.outCount) / 2).toDouble() : 0;
            spots.add(FlSpot(i.toDouble(), total));
          }
          chartLines.add(LineChartBarData(
            spots: spots, isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[colorIndex % luxuryGradients.length]), barWidth: 4, isStrokeCapRound: true,
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [luxuryGradients[colorIndex % luxuryGradients.length].first.withOpacity(0.4), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            dotData: const FlDotData(show: false),
          ));
          colorIndex++;
        }
      }
    } else if (_isCompareMode) {
      for (var item in _displayedData) processSpotForMetrics((item.inCount + item.outCount) / 2);
      for (var item in _compareDisplayedData) processSpotForMetrics((item.inCount + item.outCount) / 2);

      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, gradient: LinearGradient(colors: luxuryGradients[0]), barWidth: 5,
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [luxuryGradients[0].first.withOpacity(0.4), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)), dotData: const FlDotData(show: false),
      ));
      chartLines.add(LineChartBarData(
        spots: _compareDisplayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, color: _accentGrey.withOpacity(0.8), barWidth: 3, dashArray: [8, 6], dotData: const FlDotData(show: false),
      ));
    } else {
      for (var item in _displayedData) { processSpotForMetrics(item.inCount.toDouble()); processSpotForMetrics(item.outCount.toDouble()); }
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
        isCurved: true, gradient: LinearGradient(colors: luxuryGradients[0]), barWidth: 5,
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [luxuryGradients[0].first.withOpacity(0.4), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)), dotData: const FlDotData(show: false),
      ));
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
        isCurved: true, gradient: LinearGradient(colors: luxuryGradients[1]), barWidth: 5,
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [luxuryGradients[1].first.withOpacity(0.4), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)), dotData: const FlDotData(show: false),
      ));
    }

    double averageTraffic = dataPointCount > 0 ? (sumTraffic / dataPointCount) : 0;
    double yInterval = maxTrafficY > 1000 ? 200 : (maxTrafficY > 100 ? 50 : (maxTrafficY > 20 ? 5 : 2));

    return _buildGlassContainer(
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      borderRadius: isMobile ? 24 : 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isFrench ? 'TRAFIC GLOBAL' : 'GLOBAL TRAFFIC', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 4.0)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(totalVisitors.toString(), style: TextStyle(color: Colors.white, fontSize: isMobile ? 52 : 84, fontWeight: FontWeight.w900, letterSpacing: -4.0, height: 1.0)),
                      const SizedBox(width: 20),
                      _buildTrendBadge(totalVisitors, _compareTotalVisitors),
                    ],
                  )
                ],
              ),
              if (!isMobile) Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(24), border: Border.all(color: _glassBorder)),
                        child: Row(
                          children: [
                            IconButton(icon: Icon(Icons.show_chart_rounded, color: !_isTableMode ? _accentCyan : Colors.white54, size: 22), onPressed: () => setState(() => _isTableMode = false)),
                            IconButton(icon: Icon(Icons.table_chart_rounded, color: _isTableMode ? _accentCyan : Colors.white54, size: 22), onPressed: () => setState(() => _isTableMode = true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (showPerDoor) ...[
                    ..._perDoorData.keys.toList().asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: luxuryGradients[entry.key % luxuryGradients.length].first, shape: BoxShape.circle)), const SizedBox(width: 12), Text("${entry.value.toUpperCase()} Total", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))]))).toList(),
                  ] else if (_isCompareMode) ...[
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: luxuryGradients[0].first, shape: BoxShape.circle)), const SizedBox(width: 12), Text(_isFrench ? 'Période Actuelle' : 'Current Period', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 12),
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: _accentGrey, shape: BoxShape.circle)), const SizedBox(width: 12), Text(_isFrench ? 'Période Précédente' : 'Previous Period', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))]),
                  ] else ...[
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: luxuryGradients[0].first, shape: BoxShape.circle)), const SizedBox(width: 12), Text('${_isFrench ? "Total Entrées" : "Total In"}: $_totalIn', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 12),
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: luxuryGradients[1].first, shape: BoxShape.circle)), const SizedBox(width: 12), Text('${_isFrench ? "Total Sorties" : "Total Out"}: $_totalOut', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))]),
                  ]
                ],
              )
            ],
          ),
          SizedBox(height: isMobile ? 30 : 60),

          SizedBox(
            height: isMobile ? 300 : 400,
            child: _isTableMode ? _buildStandardTable() : LineChart(
              LineChartData(
                minY: 0, maxY: maxTrafficY * 1.15,
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: yInterval, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 1.5, dashArray: [10, 10])),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 60, interval: yInterval, getTitlesWidget: (value, meta) => value == meta.max ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(right: 20.0), child: Text(value.toInt().toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800))))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, interval: 1, getTitlesWidget: (value, meta) {
                    int index = value.toInt();
                    if (index >= 0 && index < _displayedData.length) {
                      String displayText = _currentFilter == ChartFilter.hourly ? _displayedData[index].time.split(':')[0] : _displayedData[index].date.substring(0, 5);
                      return Padding(padding: const EdgeInsets.only(top: 16.0), child: Text(displayText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800)));
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

  Widget _buildStandardTable() {
    bool isCompare = _isCompareMode && _compareDisplayedData.isNotEmpty;
    return _buildGlassContainer(
      borderRadius: 24,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(_isFrench ? 'Période' : 'Time', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                Expanded(child: Text(_isFrench ? 'Entrées' : 'In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800))),
                Expanded(child: Text(_isFrench ? 'Sorties' : 'Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800))),
                if (isCompare) ...[
                  Expanded(child: Text(_isFrench ? 'Préc. In' : 'Prev In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800))),
                  Expanded(child: Text(_isFrench ? 'Préc. Out' : 'Prev Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800))),
                ],
                Expanded(child: Text(_isFrench ? 'Total' : 'Total', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _displayedData.length,
              itemBuilder: (context, index) {
                var item = _displayedData[index];
                int total = (item.inCount + item.outCount) ~/ 2;
                PeopleCount? compareItem;
                if (isCompare && index < _compareDisplayedData.length) compareItem = _compareDisplayedData[index];

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02)))),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(_currentFilter == ChartFilter.hourly ? item.time : item.date, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      Expanded(child: Text(item.inCount.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600))),
                      Expanded(child: Text(item.outCount.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600))),
                      if (isCompare) ...[
                        Expanded(child: Text(compareItem?.inCount.toString() ?? '-', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))),
                        Expanded(child: Text(compareItem?.outCount.toString() ?? '-', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))),
                      ],
                      Expanded(child: Text(total.toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoGrid(bool isMobile) {
    List<Widget> gridItems = [];
    if (!_enablePosFeatures) {
      gridItems = [
        _buildBentoCard(title: _isFrench ? 'TOTAL ENTRÉES' : 'TOTAL IN', value: '$_totalIn', unit: _isFrench ? 'PERS' : 'PAX', icon: Icons.login_rounded, color: const Color(0xFF38EF7D), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'TOTAL SORTIES' : 'TOTAL OUT', value: '$_totalOut', unit: _isFrench ? 'PERS' : 'PAX', icon: Icons.logout_rounded, color: const Color(0xFFFF512F), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'HEURE DE POINTE' : 'PEAK HOUR', value: _peakHour, unit: 'TIME', icon: Icons.access_time_filled_rounded, color: _accentCyan, isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'OCCUPATION' : 'OCCUPANCY', value: '$_occupancy', unit: _isFrench ? 'ACTUEL' : 'NOW', icon: Icons.people_alt_rounded, color: _accentPurple, isMobile: isMobile),
      ];
    } else {
      int totalVisitors = (_totalIn + _totalOut) ~/ 2;
      double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
      double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
      double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

      double compareConv = _compareTotalVisitors > 0 ? (_compareClients / _compareTotalVisitors) * 100 : 0.0;
      double compareBasket = _compareClients > 0 ? (_compareCa / _compareClients) : 0.0;
      double compareUpt = _compareClients > 0 ? (_compareArticles / _compareClients) : 0.0;

      gridItems = [
        _buildBentoCard(title: _isFrench ? "CHIFFRE D'AFFAIRES" : 'REVENUE', value: _currentCa.toStringAsFixed(0), unit: 'DZD', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF38EF7D), trendWidget: _buildTrendBadge(_currentCa, _compareCa), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'TAUX DE CONV.' : 'CONV. RATE', value: conversionRate.toStringAsFixed(1), unit: '%', icon: Icons.track_changes_rounded, color: const Color(0xFFFF512F), trendWidget: _buildTrendBadge(conversionRate, compareConv), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'PANIER MOYEN' : 'AVG BASKET', value: avgBasket.toStringAsFixed(0), unit: 'DZD', icon: Icons.shopping_bag_rounded, color: _accentCyan, trendWidget: _buildTrendBadge(avgBasket, compareBasket), isMobile: isMobile),
        _buildBentoCard(title: _isFrench ? 'INDICE DE VENTE' : 'U.P.T', value: upt.toStringAsFixed(2), unit: 'ART', icon: Icons.layers_rounded, color: _accentPurple, trendWidget: _buildTrendBadge(upt, compareUpt), isMobile: isMobile),
      ];
    }

    if (!isMobile) {
      return Row(children: [ Expanded(flex: 2, child: gridItems[0]), const SizedBox(width: 32), Expanded(flex: 1, child: gridItems[1]), const SizedBox(width: 32), Expanded(flex: 1, child: gridItems[2]), const SizedBox(width: 32), Expanded(flex: 1, child: gridItems[3]) ]);
    } else {
      return Column(children: [ gridItems[0], const SizedBox(height: 16), Row(children: [Expanded(child: gridItems[1]), const SizedBox(width: 16), Expanded(child: gridItems[2])]), const SizedBox(height: 16), gridItems[3] ]);
    }
  }

  Widget _buildBentoCard({required String title, required String value, required String unit, required IconData icon, required Color color, Widget? trendWidget, required bool isMobile}) {
    return _buildGlassContainer(
      height: isMobile ? 200 : 240,
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      borderRadius: isMobile ? 24 : 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.4), width: 1.5), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 20)]),
                child: Icon(icon, color: color, size: isMobile ? 24 : 32),
              ),
              if (trendWidget != null) trendWidget,
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: TextStyle(fontSize: isMobile ? 36 : 52, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2.0)),
                  const SizedBox(width: 8),
                  Text(unit, style: TextStyle(fontSize: isMobile ? 14 : 18, fontWeight: FontWeight.w800, color: color.withOpacity(0.9))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isMobile) {
    return _buildGlassContainer(
      width: isMobile ? null : 280,
      borderRadius: 0,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 50),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/boitex_logo.png', width: 140, height: 140, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => Icon(Icons.business, color: _accentCyan, size: 80)),
                  const SizedBox(height: 24),
                  const Text('BoitexInfo', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0, height: 1.1)),
                  Text('CLOUD ANALYTICS', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _accentCyan, letterSpacing: 4.0)),
                ],
              ),
            ),
            const SizedBox(height: 40),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: _glassBorder)),
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: _accentCyan.withOpacity(0.2), child: Icon(Icons.person, color: _accentCyan, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_loggedInUserName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text(_loggedInRole.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.0)),
                  ]))
                ],
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSidebarItem(
                        Icons.dashboard_rounded,
                        _isFrench ? 'Tableau de bord' : 'Dashboard',
                        isActive: true
                    ),
                    _buildSidebarItem(
                        Icons.download_rounded,
                        _isFrench ? 'Exporter Rapports' : 'Export Reports',
                        onTap: () {
                          if (isMobile) Navigator.pop(context);
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
                                      onFetchWebData: (DateTimeRange range) => _fetchDataFromFirestore(range.start, range.end),
                                      storeName: _storeName,
                                      storeLocation: _storeLocation
                                  )
                              )
                          );
                        }
                    ),
                  ],
                ),
              ),
            ),
            ListTile(leading: const Icon(Icons.logout_rounded, color: Colors.redAccent), title: Text(_isFrench ? 'Déconnexion' : 'Sign Out', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: _signOut),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, {bool isActive = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
        leading: Icon(icon, color: isActive ? _accentCyan : Colors.white54),
        title: Text(title, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, fontSize: 15)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLiveFeedPlaceholder(bool isMobile) {
    return _buildGlassContainer(
      margin: const EdgeInsets.only(top: 32), padding: const EdgeInsets.all(32), borderRadius: 32,
      child: Column(
        children: [
          const Icon(Icons.videocam_off, color: Colors.white24, size: 64),
          const SizedBox(height: 24),
          Text(_isFrench ? 'FLUX EN DIRECT SÉCURISÉ' : 'SECURE LOCAL STREAM', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
          const SizedBox(height: 12),
          Text(_isFrench ? 'Pour des raisons de confidentialité et de sécurité, la visualisation en direct des caméras est restreinte au réseau local du magasin (Dashboard Desktop).' : 'For privacy and security reasons, live camera preview is restricted to the store\'s local network (Desktop Dashboard).', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: _bgDeep,
      drawer: isMobile ? Drawer(child: _buildSidebar(true)) : null,
      body: Stack(
        children: [
          // 🌌 SPATIAL BACKGROUND MESH (Ambient Orbs)
          Positioned(top: -200, left: -200, child: Container(width: 600, height: 600, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentPurple.withOpacity(0.20), boxShadow: [BoxShadow(blurRadius: 200, color: _accentPurple.withOpacity(0.20))]))),
          Positioned(bottom: -200, right: -100, child: Container(width: 700, height: 700, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentCyan.withOpacity(0.15), boxShadow: [BoxShadow(blurRadius: 250, color: _accentCyan.withOpacity(0.15))]))),
          Positioned(top: 300, right: 300, child: Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentMagenta.withOpacity(0.10), boxShadow: [BoxShadow(blurRadius: 200, color: _accentMagenta.withOpacity(0.10))]))),

          Row(
            children: [
              if (!isMobile) _buildSidebar(false),
              Expanded(
                child: Column(
                  children: [
                    if (!isMobile) _buildTopAppBar() else _buildMobileAppBar(),
                    Expanded(
                      child: _isLoading
                          ? Center(child: CircularProgressIndicator(color: _accentCyan))
                          : SingleChildScrollView(
                        padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, spacing: 16, runSpacing: 16,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_isFrench ? "Vue d'Ensemble" : 'Command Center', style: TextStyle(fontSize: isMobile ? 32 : 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2.0)),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_rawData.isNotEmpty && !isMobile) ...[
                                      FilterChip(
                                        selected: _isCompareMode,
                                        onSelected: (val) { setState(() => _isCompareMode = val); _fetchCloudDataForDateRange(); },
                                        label: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(_isFrench ? 'Comparer au Préc.' : 'Compare vs Prev', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _isCompareMode ? Colors.black : Colors.white))),
                                        selectedColor: _accentCyan, checkmarkColor: Colors.black, backgroundColor: _glassWhiteTint,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _isCompareMode ? _accentCyan : _glassBorder, width: 1.5)),
                                      ),
                                      const SizedBox(width: 20),
                                    ],
                                    _buildGlassContainer(
                                      padding: const EdgeInsets.all(6), borderRadius: 20,
                                      child: Row(
                                        children: [
                                          IconButton(icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54), onPressed: () => _shiftDate(-1)),
                                          GestureDetector(onTap: _pickDateRange, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16, letterSpacing: 0.5)))),
                                          IconButton(icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54), onPressed: () => _shiftDate(1)),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                            const SizedBox(height: 32),

                            if (_rawData.isEmpty)
                              Center(child: Padding(padding: const EdgeInsets.only(top: 80.0), child: Text(_isFrench ? "Aucune donnée trouvée." : "No data found.", style: const TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w600))))
                            else ...[
                              _buildHeroChart(isMobile),
                              if (!_isSingleEntrance) ...[
                                const SizedBox(height: 40),
                                Text(_isFrench ? 'ZONES ET CAMÉRAS' : 'ZONES & CAMERAS', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3.0)),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 60,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal, itemCount: _availableCameras.length, physics: const BouncingScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      String cam = _availableCameras[index];
                                      bool isSel = _selectedCamera == cam;
                                      return GestureDetector(
                                        onTap: () => setState(() { _selectedCamera = cam; _applyFilter(); }),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 300), margin: const EdgeInsets.only(right: 16), padding: const EdgeInsets.symmetric(horizontal: 32),
                                          decoration: BoxDecoration(color: isSel ? Colors.white : _glassWhiteTint, borderRadius: BorderRadius.circular(30), border: Border.all(color: isSel ? Colors.white : _glassBorder, width: 1.5), boxShadow: isSel ? [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)] : []),
                                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                            if (cam != 'All Doors') ...[Container(width: 10, height: 10, decoration: BoxDecoration(color: isSel ? Colors.black : _accentCyan, shape: BoxShape.circle)), const SizedBox(width: 12)],
                                            Text(cam == 'All Doors' ? (_isFrench ? 'Vue Globale' : 'Global View') : cam.toUpperCase(), style: TextStyle(color: isSel ? Colors.black : Colors.white70, fontWeight: isSel ? FontWeight.w900 : FontWeight.w700, fontSize: 15))
                                          ]),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              _buildLiveFeedPlaceholder(isMobile),
                              const SizedBox(height: 40),
                              _buildBentoGrid(isMobile),
                              const SizedBox(height: 60),
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
        ],
      ),
    );
  }
}