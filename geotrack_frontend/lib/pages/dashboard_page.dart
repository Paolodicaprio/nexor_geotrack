import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/sync_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/widgets/connection_status.dart';
import 'package:geotrack_frontend/pages/settings_page.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:geotrack_frontend/services/background_manager.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  final GpsService _gpsService = GpsService();
  final SyncService _syncService = SyncService();
  final StorageService _storageService = StorageService();
  final BackgroundManager _backgroundManager = BackgroundManager();
  Config? _currentConfig;
  bool _configLoading = false;

  Map<String, dynamic> _stats = {};
  Timer? _collectTimer;
  Timer? _syncTimer;
  Timer? _statsTimer;
  Timer? _prefsCheckTimer;

  DateTime? _nextCollection;
  DateTime? _nextSync;

  late TabController _tabController;

  int _collectInterval = 5; // en minutes
  int _syncInterval = 10; // en minutes

  // Ajout des variables d'état pour les données
  List<GpsData> _pendingData = [];
  List<GpsData> _historyData = [];
  bool _pendingLoading = true;
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Vérifier et démarrer le background manager si nécessaire
    _checkAndStartBackgroundManager();

    // Initialiser en séquence
    _initializeApp();
  }

  Future<void> _checkAndStartBackgroundManager() async {
    try {
      final token = await _storageService.getToken();
      if (token != null && token.isNotEmpty) {
        // Démarrer après un petit délai pour que l'interface soit stable
        await Future.delayed(const Duration(seconds: 2));
        await _backgroundManager.start();
        print('✅ Background manager started from dashboard');
      }
    } catch (e) {
      print('⚠️ Failed to start background manager: $e');
    }
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Charger la configuration
      await _loadConfig();

      // 2. Initialiser les intervalles et timers
      await _initIntervalsAndTimers();

      // 3. Charger les données
      await Future.wait([_loadStats(), _loadPendingData(), _loadHistoryData()]);

      // 4. Démarrer les vérifications
      _startPreferencesChecker();

      // 5. Première collecte immédiate
      await _performAutoCollect();
    } catch (e) {
      print('❌ Initialization error: $e');
      // Continuer même en cas d'erreur
      await _loadIntervals(); // Charger les intervalles depuis le cache
      setState(() {
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      });
    }
  }

  Future<void> _initIntervalsAndTimers() async {
    // Charger d'abord depuis SharedPreferences
    await _loadIntervals();

    // Mettre à jour les compteurs
    setState(() {
      _nextCollection = DateTime.now().add(Duration(minutes: _collectInterval));
      _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
    });

    // Annuler les timers existants
    _collectTimer?.cancel();
    _syncTimer?.cancel();

    // Démarrer les timers avec les nouveaux intervalles
    _startAutoCollect();
    _startAutoSync();

    // Démarrer le timer des statistiques
    _startStatsTimer();

    print(
      '⏰ Timers initialized: collect=$_collectInterval min, sync=$_syncInterval min',
    );
  }

  Future<void> _loadConfig() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();

      // Convertir secondes en minutes pour l'interface
      final collectIntervalMinutes = (config.collectionInterval / 60).round();
      final syncIntervalMinutes = (config.sendInterval / 60).round();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('collect_interval', collectIntervalMinutes);
      await prefs.setInt('sync_interval', syncIntervalMinutes);

      setState(() {
        _currentConfig = config;
        _collectInterval = collectIntervalMinutes;
        _syncInterval = syncIntervalMinutes;
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      });

      print(
        '⚙️ Config loaded: $collectIntervalMinutes min collect, $syncIntervalMinutes min sync',
      );
    } catch (e) {
      print('⚠️ Error loading config: $e - Using default intervals');
      // Utiliser les valeurs par défaut
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('collect_interval', 5);
      await prefs.setInt('sync_interval', 10);

      setState(() {
        _collectInterval = 5;
        _syncInterval = 10;
      });
    } finally {
      setState(() => _configLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final pendingData = await _storageService.getPendingGpsData();
      final lastSync = await _storageService.getLastSyncTime();

      setState(() {
        _stats = {
          'pending_count': pendingData.length,
          'last_collection': lastSync,
          'total_data': pendingData.length + _historyData.length,
        };
      });
    } catch (e) {
      print('❌ Error loading stats: $e');
    }
  }

  Future<void> _loadIntervals() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _collectInterval = prefs.getInt('collect_interval') ?? 5;
      _syncInterval = prefs.getInt('sync_interval') ?? 10;
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

    // S'assurer que les données en attente ont synced: false
    final pendingWithStatus =
        pendingData.map((data) => data.copyWith(synced: false)).toList();

    // S'assurer que les données synchronisées ont synced: true
    final syncedWithStatus =
        syncedData.map((data) => data.copyWith(synced: true)).toList();

    // Combiner toutes les données et trier par datetime
    final allData = [...pendingWithStatus, ...syncedWithStatus];
    allData.sort((a, b) => b.datetime.compareTo(a.datetime));

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
    _tabController.dispose();

    // Arrêter le background manager
    try {
      _backgroundManager.stop();
    } catch (e) {
      print('⚠️ Error stopping background manager: $e');
    }

    super.dispose();
  }

  void _startAutoCollect() {
    _collectTimer?.cancel();
    _collectTimer = Timer.periodic(Duration(minutes: _collectInterval), (
      timer,
    ) async {
      await _performAutoCollect();
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
      await _performAutoSync();
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

  // Nouvelle méthode pour vérifier les changements de préférences
  void _startPreferencesChecker() {
    _prefsCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final newCollectInterval = prefs.getInt('collect_interval') ?? 5;
      final newSyncInterval = prefs.getInt('sync_interval') ?? 10;

      if (newCollectInterval != _collectInterval ||
          newSyncInterval != _syncInterval) {
        print(
          '🔄 Intervalles modifiés: $newCollectInterval min, $newSyncInterval min',
        );
        await _restartTimersWithNewIntervals();
      }
    });
  }

  Future<void> _restartTimersWithNewIntervals() async {
    // D'abord charger les nouveaux intervalles depuis SharedPreferences
    await _loadIntervals();

    _collectTimer?.cancel();
    _syncTimer?.cancel();

    // Redémarrer les timers avec les nouveaux intervalles
    _startAutoCollect();
    _startAutoSync();

    // Mettre à jour l'interface
    setState(() {
      _nextCollection = DateTime.now().add(Duration(minutes: _collectInterval));
      _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
    });
  }

  Future<void> _performAutoCollect() async {
    try {
      // Utilisation de la méthode automatique
      await AutoCollectService.collectGpsDataBackground();
      await _loadStats();
      await _loadPendingData(); // Recharger les données en attente
      await _loadHistoryData(); // Recharger l'historique
    } catch (e) {
      print('❌ Auto collect error: $e');
    }
  }

  Future<void> _performAutoSync() async {
    try {
      print('🔄 Starting auto sync...');
      await _syncService.syncPendingData();

      // Recharger toutes les données
      await Future.wait([_loadStats(), _loadPendingData(), _loadHistoryData()]);

      print('✅ Auto sync completed');
    } catch (e) {
      print('❌ Auto sync error: $e');
    }
  }

  String _formatCountdown(DateTime? target) {
    if (target == null) return 'N/A';
    final now = DateTime.now();
    final diff = target.difference(now);
    if (diff.isNegative) return 'Maintenant';
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
          ).showSnackBar(const SnackBar(content: Text('Données rafraîchies')));
        },
        backgroundColor: Colors.green[700],
        child: const Icon(Icons.refresh),
      ),
      appBar: AppBar(
        title: const Text(
          'Nexor GeoTrack',
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
                await Future.wait([
                  _loadPendingData(),
                  _loadHistoryData(),
                  _loadStats(),
                ]);
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
            Tab(text: 'Tableau de bord', icon: Icon(Icons.dashboard)),
            Tab(text: 'Historique', icon: Icon(Icons.history)),
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
            'Données en attente de synchronisation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _pendingLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildPendingDataList(),
          const SizedBox(height: 16),
          // SUPPRIMÉ: Les boutons "Collecter maintenant" et "Synchroniser"
          // La collecte et synchronisation sont maintenant entièrement automatiques
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
                  'Toutes les données sont synchronisées',
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
                title: const Text('Données en attente'),
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
                        '${data.latitude.toStringAsFixed(6)}, ${data.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        DateFormat('dd/MM HH:mm').format(data.datetime),
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
      return const Center(child: Text('Aucune donnée historique disponible'));
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
                '${data.latitude.toStringAsFixed(6)}, ${data.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                DateFormat('dd/MM/yyyy HH:mm').format(data.datetime),
                style: const TextStyle(fontSize: 13),
              ),
              trailing: Text(
                isSynced ? 'Synchronisé' : 'En attente',
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
                      'Statistiques de Collecte',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard(
                      '📦 En attente',
                      '${_stats['pending_count'] ?? 0}',
                      Colors.orange,
                    ),
                    _buildStatCard(
                      '⏰ Prochaine collecte',
                      _formatCountdown(_nextCollection),
                      Colors.blue,
                    ),
                    _buildStatCard(
                      '🔄 Prochaine sync',
                      _formatCountdown(_nextSync),
                      Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Section d'information sur l'automatisation
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[100]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.autorenew, color: Colors.green[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Collecte automatique toutes les $_collectInterval minutes\n'
                          'Synchronisation automatique toutes les $_syncInterval minutes',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
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
                        'Dernière collecte',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Text(
                        _stats['last_collection'] != null
                            ? DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(_stats['last_collection'])
                            : 'Jamais',
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
