import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/permissions_service.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/sync_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/widgets/connection_status.dart';
import 'package:geotrack_frontend/pages/settings_page.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';

import '../services/background_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  final GpsService _gpsService = GpsService();
  final SyncService _syncService = SyncService();
  final StorageService _storageService = StorageService();
  Config? _currentConfig;
  bool _configLoading = false;

  Map<String, dynamic> _stats = {};
  Timer? _collectTimer;
  Timer? _syncTimer;
  Timer? _statsTimer;
  Timer? _prefsCheckTimer;
  Timer? _configSyncTimer;


  DateTime? _nextCollection;
  DateTime? _nextSync;
  DateTime? _nextConfigSync;

  late TabController _tabController;
  late BuildContext rootContext;

// Valeur par défaut en minutes
  int _collectInterval = Constants.defaultCollectionInterval ~/ 60;
  int _syncInterval = Constants.defaultSendInterval ~/60;
  int _configSyncInterval = Constants.defaultConfigSyncInterval;


  // Ajout des variables d'état pour les données
  List<GpsData> _pendingData = [];
  List<GpsData> _historyData = [];
  bool _pendingLoading = true;
  bool _historyLoading = true;

  @override
  void initState(){
    super.initState();
    _checkBackgroundPermissions();
    _tabController = TabController(length: 2, vsync: this);
    _initIntervalsAndTimers();
    _loadStats();
    _loadConfig();
    _loadPendingData();
    _loadHistoryData();
    _startPreferencesChecker();
    _initBackgroundService();
    _checkDeviceCode();
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    rootContext = context; // garde le contexte du widget principal
  }

  Future<void> _initBackgroundService() async{
    PermissionResult permissionResult = await requestPermissions();
    if (permissionResult.allGranted){
      await initializeBackgroundService();
    }else{
      print('❌ Permissions denied');
    }
  }

  Future<void> _checkBackgroundPermissions() async {

    final permission = await Geolocator.checkPermission();
    print(permission);
    // Afficher la boîte de dialogue seulement si les permissions sont insuffisantes
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.whileInUse) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showBackgroundPermissionDialog(permission);
      });
    }
  }

  Future<void> _showBackgroundPermissionDialog(actualPermission) async {
    // Vérifier d'abord si la localisation est activée
    if (!await Geolocator.isLocationServiceEnabled()) {
      return; // Ne pas afficher la boîte si la localisation est désactivée
    }
    if (!mounted) return;
    await showDialog(
      context: rootContext,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'To continue GPS collection even when the app is closed, '
              'you must allow background location access.\n\n'
              'This feature is essential for continuous tracking.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(rootContext).pop();
                },
                child: const Text('Deny'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(rootContext).pop();
                  final bgPermission;
                  if (actualPermission == LocationPermission.whileInUse) {
                     bgPermission =await Permission.locationAlways.request();
                  }else{
                    bgPermission = await Geolocator.requestPermission();
                  }

                  if (bgPermission == LocationPermission.always || bgPermission==PermissionStatus.granted ) {
                    if (mounted) {
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(
                          content: Text('Background permission granted'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(
                          content: Text('Background permission denied - collection will stop when the app is closed'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Allow'),
              ),
            ],
          ),
    );
  }

  Future<void> _initIntervalsAndTimers() async {
    while (_currentConfig == null && _configLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final collectInterval =
        _currentConfig?.collectionInterval ?? Constants.defaultCollectionInterval; // Secondes
    final syncInterval = _currentConfig?.sendInterval ?? Constants.defaultSendInterval; // Secondes
    final configSyncInterval = _currentConfig?.configSyncInterval ?? Constants.defaultConfigSyncInterval; // Minutes

    await _storageService.saveConfig( Config(collectionInterval: collectInterval, sendInterval: syncInterval, configSyncInterval: configSyncInterval));

    setState(() {
      _collectInterval =
          collectInterval ~/ 60; // Stocker en minutes pour l'interface
      _syncInterval = syncInterval ~/ 60; // Stocker en minutes pour l'interface
      _configSyncInterval = configSyncInterval; // deja en minutes
      _nextCollection = DateTime.now().add(Duration(minutes: _collectInterval));
      _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      _nextConfigSync = DateTime.now().add(Duration(minutes: _configSyncInterval));
    });

    await _autoCollect();
    await _loadPendingData();
    await _loadHistoryData();
    _startAutoCollect();
    _startAutoSync();
    _startStatsTimer();
    _startConfigSync();
  }

  Future<void> _loadConfig() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();
      await _storageService.saveConfig(config);
      // final prefs = await SharedPreferences.getInstance();
      // await prefs.setInt('collect_interval', config.collectionInterval ~/ 60);
      // await prefs.setInt('sync_interval', config.sendInterval ~/ 60);
      // await prefs.setInt('config_sync_interval', config.configSyncInterval);

      setState(() {
        _currentConfig = config;
        _collectInterval = config.collectionInterval ~/ 60;
        _syncInterval = config.sendInterval ~/ 60;
        _configSyncInterval=config.configSyncInterval;
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
        _nextConfigSync =DateTime.now().add(Duration(minutes: _configSyncInterval));
      });

      _restartTimersWithNewIntervals();
    } catch (e) {
      print('❌ Error loading config: $e');

      if (e.toString().contains('401') ||
          e.toString().contains('Token expired')) {
        _handleTokenExpired();
        return;
      }

      final conf =await _storageService.getConfig();
      setState(() {
        //en minutes
        _collectInterval = conf.collectionInterval ~/60;
        _syncInterval = conf.sendInterval ~/60;
        _configSyncInterval = conf.configSyncInterval;
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
        _nextConfigSync = DateTime.now().add(Duration(minutes: _configSyncInterval));
      });
    } finally {
      setState(() => _configLoading = false);
    }
  }

  void _handleTokenExpired() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session expired - Redirecting...'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
  }

  Future<void> _loadIntervals() async {
    final conf =await _storageService.getConfig();
    setState(() {
      //en minutes
      _collectInterval = conf.collectionInterval ~/60;
      _syncInterval = conf.sendInterval ~/60;
      _configSyncInterval = conf.configSyncInterval;
    });
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await _storageService.getPendingGpsData();
    final lastCollectionString = prefs.getString('last_collection');

    setState(() {
      _stats = {
        'pending_count': pendingData.length,
        'last_collection':
            lastCollectionString != null
                ? DateTime.parse(lastCollectionString)
                : null,
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
    _prefsCheckTimer?.cancel();
    _configSyncTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
 Future<void> _checkDeviceCode() async {
    final deviceCode = await _storageService.getDeviceCode();
    if (deviceCode!=null){
      return;
    }
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
  void _startAutoCollect() {
    _collectTimer?.cancel();
    _collectTimer = Timer.periodic(Duration(minutes: _collectInterval), (
      timer,
    ) async {
      print("--------collect from auto--------");
      await _autoCollect();
      setState(() {
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
      });
      await _loadPendingData();
      await _loadHistoryData();
    });
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(minutes: _syncInterval), (
      timer,
    ) async {
      await _autoSync();
      setState(() {
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      });
      await _loadPendingData();
      await _loadHistoryData();
    });
  }

  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {});
    });
  }

  void _startPreferencesChecker() {
    _prefsCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!mounted) return;

     final conf = await _storageService.getConfig();
      final newCollectInterval = conf.collectionInterval ~/ 60;
      final newSyncInterval = conf.sendInterval ~/60;
      final newConfigSyncInterval = conf.configSyncInterval;

      if (newCollectInterval != _collectInterval ||
          newSyncInterval != _syncInterval || newConfigSyncInterval != _configSyncInterval) {
        print(
          '🔄 Intervals changed: $newCollectInterval min, $newSyncInterval min, $newConfigSyncInterval min',
        );
        await _restartTimersWithNewIntervals();
      }
    });
  }

  void _startConfigSync() {
    _configSyncTimer?.cancel();

    _configSyncTimer = Timer.periodic(
      Duration(minutes: _configSyncInterval),
          (timer) async {
        print('🔁 Automatic configuration refresh...');
        await _loadConfig();
        setState(() {
          _nextConfigSync = DateTime.now().add(
            Duration(minutes: _configSyncInterval),
          );
        });
      },
    );
  }

  Future<void> _restartTimersWithNewIntervals() async {
    await _loadIntervals();

    _collectTimer?.cancel();
    _syncTimer?.cancel();
    _configSyncTimer?.cancel();

    _startAutoCollect();
    _startAutoSync();
    _startConfigSync();

    setState(() {
      _nextCollection = DateTime.now().add(Duration(minutes: _collectInterval));
      _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      _nextConfigSync = DateTime.now().add(Duration(minutes: _configSyncInterval));

    });
  }

  Future<void> _autoCollect() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        print(
          '⚠️ Background mode not authorized - collection limited to when app is open',
        );
      }
      final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        _showLocationWarning();
        return;
      }

      final hasPermission = await _gpsService.checkPermission();
      if (!hasPermission) {
        _showPermissionWarning();
        return;
      }

      await AutoCollectService.collectGpsDataBackground();
      await _loadStats();
      await _loadPendingData();
      await _loadHistoryData();
    } catch (_) {}
  }

  void _showLocationWarning() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Location disabled'),
            content: const Text(
              'Your phone\'s location is disabled. '
              'Please enable it to allow automatic GPS data collection.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ignore'),
              ),
              TextButton(
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                  Navigator.of(context).pop();
                },
                child: const Text('Enable'),
              ),
            ],
          );
        },
      );
    });
  }

  void _showPermissionWarning() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Permission required'),
            content: const Text(
              'The application needs location permission '
              'to collect GPS data.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ignore'),
              ),
              TextButton(
                onPressed: () async {
                  await Geolocator.requestPermission();
                  Navigator.of(context).pop();
                },
                child: const Text('Allow'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _autoSync() async {
    try {
      await AutoCollectService.syncGpsDataBackground();
      await Future.wait([_loadStats(), _loadPendingData(), _loadHistoryData()]);
    } catch (e) {
      print('❌ Auto sync error: $e');
    }
  }

  String _formatCountdown(DateTime? target) {
    if (target == null) return 'N/A';
    final now = DateTime.now();
    final diff = target.difference(now);
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
          await Future.wait([
            _loadPendingData(),
            _loadHistoryData(),
            _loadStats(),
          ]);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Data refreshed')));
        },
        child: Icon(Icons.refresh),
        backgroundColor: Colors.green[700],
      ),
      appBar: AppBar(
        title: const Text(
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
              final needsRefresh = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );

              if (needsRefresh == true && mounted) {
                await _restartTimersWithNewIntervals();
              }
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
                          _formatCountdown(_nextCollection),
                          Colors.blue,
                        ),
                        _buildStatCard(
                          '🔄 Next sync',
                          _formatCountdown(_nextSync),
                          Colors.green,
                        ),
                        _buildStatCard(
                            '⚙️ Next config',
                            _formatCountdown(_nextConfigSync),
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
