import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';

import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/widgets/connection_status.dart';
import 'package:geotrack_frontend/pages/settings_page.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  Map<String, dynamic> _stats = {};
  Timer? _collectTimer;
  Timer? _syncTimer;
  Timer? _statsTimer;
  Timer? _prefsCheckTimer;
  Timer? _configSyncTimer;

  Timer? _uiTimer;

  DateTime? _nextCollection;
  DateTime? _nextSync;
  DateTime? _nextConfigSync;

  // Les durées restantes que nous allons afficher
  Duration _gpsCountdown = Duration.zero;
  Duration _syncCountdown = Duration.zero;
  Duration _configCountdown = Duration.zero;

  late TabController _tabController;

  // Ajout des variables d'état pour les données
  List<GpsData> _pendingData = [];
  List<GpsData> _historyData = [];
  bool _pendingLoading = false;
  bool _historyLoading = false;
  StreamSubscription? _dataUpdatedSubscription;
  StreamSubscription? _timerUpdatedSubscription;
  StreamSubscription? _errorNotificationSubscription;


  @override
  void initState(){
    super.initState();
    // 1. Écouter les mises à jour envoyées par le service de fond
   _timerUpdatedSubscription =  FlutterBackgroundService().on('update_ui_timers').listen((data) {
      if (data == null) return;
      setState(() {
        _nextCollection = data['nextGpsTime'] != null ? DateTime.parse(data['nextGpsTime']!) : null;
        _nextSync = data['nextSyncTime'] != null ? DateTime.parse(data['nextSyncTime']!) : null;
        _nextConfigSync = data['nextConfigSyncTime'] != null ? DateTime.parse(data['nextConfigSyncTime']!) : null;
      });
      _storageService.reloadStorage();
    });

    _dataUpdatedSubscription = FlutterBackgroundService().on('data_updated').listen((data) async {
       if (data == null ) return;
       if(data["task"] !=null){
         setState(() {
           _stats={
             'pending_count':data['stats']['pending_count'],
           'last_collection': data['stats']['last_collection'] != null ? DateTime.parse(data['stats']['last_collection']) : null,};
           final pendingList = data["pendingData"] as List<dynamic>;
           final allList = data["allData"] as List<dynamic>;
           _pendingData = pendingList
               .map((e) => GpsData.fromJson(Map<String, dynamic>.from(e)))
               .toList();

           _historyData = allList
               .map((e) => GpsData.fromJson(Map<String, dynamic>.from(e)))
               .toList();
         });
       }

    });

   _errorNotificationSubscription =  FlutterBackgroundService().on("error_notification").listen((data){
       if (data !=null && data['error'] !=null){
         ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(data['error']),backgroundColor: Colors.redAccent,duration: Duration(seconds: 5),)
         );
       }
     });

    // 2. Lancer un timer local pour rafraîchir l'UI chaque seconde
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      updateCountdowns();
    });

    // 3. Demander les données actuelles au service au cas où il tourne déjà
    FlutterBackgroundService().invoke('get_next_execution_times');
    _tabController = TabController(length: 2, vsync: this);
    FlutterBackgroundService().invoke("get_dashboard_infos");
    // _loadStats();
    // _loadHistoryData();
    // _loadPendingData();
    _checkDeviceCode();
  }

  void updateCountdowns() {
    if (!mounted) return;

    final now = DateTime.now();
    setState(() {
      _gpsCountdown = _nextCollection?.difference(now) ?? Duration.zero;
      _syncCountdown = _nextSync?.difference(now) ?? Duration.zero;
      _configCountdown = _nextConfigSync?.difference(now) ?? Duration.zero;

      // Si le compte à rebours est terminé, demander une nouvelle valeur au service
      if (_gpsCountdown.isNegative || _syncCountdown.isNegative || _configCountdown.isNegative) {
        FlutterBackgroundService().invoke('get_next_execution_times');
      }
    });
  }



  Future<void> _loadStats() async {
    final pendingData = await _storageService.getPendingGpsData();
    final lastCollection = await _storageService.getLastCollectionTime();

    setState(() {
      _stats = {
        'pending_count': pendingData.length,
        'last_collection': lastCollection
      };
    });
  }

  Future<void> _loadPendingData() async {
    setState(() => _pendingLoading = true);
    final data = await _storageService.getPendingGpsData();
    setState(() {
      _pendingData = data;
      _pendingLoading = false;
      _stats['pending_count'] = data.length;
    });
  }

  Future<void> _loadHistoryData() async {
    setState(() => _historyLoading = true);

    final pendingData = await _storageService.getPendingGpsData();
    final syncedData = await _storageService.getSyncedGpsData();

    final pendingWithStatus =
        pendingData.map((data) => data.copyWith(synced: false)).toList();
    final syncedWithStatus =
        syncedData.map((data) => data.copyWith(synced: true)).toList();

    // Combiner toutes les données et trier par timestamp
    final allData = [...pendingWithStatus, ...syncedWithStatus];
    allData.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _historyData = allData;
      _historyLoading = false;
    });
  }

  @override
  void dispose() {
    _collectTimer?.cancel();
    _syncTimer?.cancel();
    _statsTimer?.cancel();
    _uiTimer?.cancel();
    _prefsCheckTimer?.cancel();
    _configSyncTimer?.cancel();
    _tabController.dispose();
    _dataUpdatedSubscription?.cancel();
    _timerUpdatedSubscription?.cancel();
    _errorNotificationSubscription?.cancel();
    super.dispose();
  }
 Future<void> _checkDeviceCode() async {
    final deviceCode = await _storageService.getDeviceCode();
    if (deviceCode!=null){
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
        title: const Text('Device Code Required'),
        content: const Text(
          'Please provide the device code on the parameters to be able to sync the data',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
 }


  String _formatCountdown(Duration diff) {
    // if (target == null) return 'N/A';
    // final now = DateTime.now();
    // final diff = target.difference(now);
    if (diff.isNegative) return 'Now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    return '${diff.inHours}h${diff.inMinutes.remainder(60)}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          FlutterBackgroundService().invoke("get_dashboard_infos");
          ScaffoldMessenger.of(
            context,
          ).showSnackBar( SnackBar(content: const Text('Data refreshed')));
        },
        child: Icon(Icons.refresh),
        backgroundColor: Colors.green[700],
      ),
      appBar: AppBar(
        title:  Text(
          'NexOR GeoTrack',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Dashboard', icon: Icon(Icons.dashboard)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: Container(
        color: Colors.white,
        child: TabBarView(
          controller: _tabController,
          children: [_buildDashboardTab(), _buildHistoryTab()],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ConnectionStatus(),
          const SizedBox(height: 16),
          _buildStatsCards(),
          const SizedBox(height: 24),
          const Text(
            'Data pending synchronization',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _pendingLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildPendingDataList(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPendingDataList() {
    if (_pendingData.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await _loadPendingData();
          await _loadHistoryData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 8),
                Text(
                  'All data is synchronized',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadPendingData();
        await _loadHistoryData();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.pending_actions,
                  color: Colors.orange,
                ),
                title: const Text('Pending data'),
                trailing: Chip(
                  label: Text('${_pendingData.length}'),
                  backgroundColor: Colors.orange.withOpacity(0.2),
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _pendingData.length,
                  itemBuilder: (context, index) {
                    final data = _pendingData[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on, size: 20),
                      title: Text(
                        '${data.lat.toStringAsFixed(6)}, ${data.lon.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text("${data.timestamp.toUtc().toIso8601String().split('.').first}Z UTC",
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Icon(
                        data.synced ?? false
                            ? Icons.check_circle
                            : Icons.access_time,
                        color:
                            data.synced ?? false ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      dense: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_historyData.isEmpty) {
      return const Center(child: Text('No historical data available'));
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadPendingData();
        await _loadHistoryData();
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _historyData.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final data = _historyData[index];
          final isSynced = data.synced ?? false;

          return Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              leading: Icon(
                isSynced ? Icons.check_circle : Icons.location_on,
                color: isSynced ? Colors.green : Colors.blue,
              ),
              title: Text(
                '${data.lat.toStringAsFixed(6)}, ${data.lon.toStringAsFixed(6)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text("${data.timestamp.toUtc().toIso8601String().split('.').first}Z UTC",
                style: const TextStyle(fontSize: 13),
              ),
              trailing: Text(
                isSynced ? 'Synced' : 'Pending',
                style: TextStyle(
                  color: isSynced ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsCards() {
    return Column(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Collection Statistics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                      children: [
                        _buildStatCard(
                          '📦 Pending',
                          '${_stats['pending_count'] ?? 0}',
                          Colors.orange,
                        ),
                        _buildStatCard(
                          '⏰ Next collection',
                          _formatCountdown(_gpsCountdown),
                          Colors.blue,
                        ),
                        _buildStatCard(
                          '🔄 Next sync',
                          _formatCountdown(_syncCountdown),
                          Colors.green,
                        ),
                        _buildStatCard(
                            '⚙️ Next config',
                            _formatCountdown(_configCountdown),
                            Colors.purple
                        ),
                      ].map((card) => Padding(
                      padding: const EdgeInsets.only(right: 10.0),
                      child: card,
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last collection',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Text(
                        _stats['last_collection'] != null
                            ? "${DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(_stats['last_collection'].toUtc())} UTC"
                            : 'Never',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            title.split(' ')[0],
            style: const TextStyle(fontSize: 20),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          title.split(' ').skip(1).join(' '),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
