import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/sync_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/database_service.dart';
import 'package:geotrack_frontend/widgets/connection_status.dart';
import 'package:geotrack_frontend/pages/settings_page.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:geotrack_frontend/services/background_manager.dart';
import 'package:provider/provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final GpsService _gpsService = GpsService();
  final SyncService _syncService = SyncService();
  final StorageService _storageService = StorageService();
  final DatabaseService _databaseService = DatabaseService();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

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

  // Variables d'état pour les données
  List<GpsData> _pendingData = [];
  List<GpsData> _historyData = [];
  bool _pendingLoading = true;
  bool _historyLoading = true;

  // Variables statiques pour préserver l'état entre les hot reloads
  static DateTime? _lastCollectionTime;
  static DateTime? _lastSyncTime;
  static bool _timersInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // S'abonner aux changements du cycle de vie
    WidgetsBinding.instance.addObserver(this);

    // Initialiser en séquence
    _initializeApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // L'app va en arrière-plan
      print('📱 App en arrière-plan');
    } else if (state == AppLifecycleState.resumed) {
      // L'app revient au premier plan
      print('📱 App au premier plan - Actualisation des données');
      _refreshData();
    }
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Charger les intervalles depuis le cache
      await _loadIntervals();

      // 2. Charger les données
      await _loadAllData();

      // 3. Charger la configuration API
      await _loadConfig();

      // 4. Initialiser les timers si pas déjà fait
      if (!_timersInitialized) {
        _initTimers();
        _timersInitialized = true;
      }

      // 5. Initialiser les prochains temps
      _initNextTimes();

      // 6. Démarrer les vérifications
      _startPreferencesChecker();

      // 7. Démarrer le background manager
      _startBackgroundManager();
    } catch (e) {
      print('❌ Erreur d\'initialisation: $e');
      // Continuer avec les valeurs par défaut
      await _loadIntervals();
      _initNextTimes();
    }
  }

  void _initNextTimes() {
    // Utiliser les temps sauvegardés ou calculer de nouveaux
    setState(() {
      _nextCollection =
          _lastCollectionTime ??
          DateTime.now().add(Duration(minutes: _collectInterval));
      _nextSync =
          _lastSyncTime ?? DateTime.now().add(Duration(minutes: _syncInterval));
    });
  }

  void _initTimers() {
    // Annuler les timers existants
    _collectTimer?.cancel();
    _syncTimer?.cancel();
    _statsTimer?.cancel();

    // Démarrer les timers de collecte
    _collectTimer = Timer.periodic(
      Duration(minutes: _collectInterval),
      (timer) => _performAutoCollect(),
    );

    // Démarrer les timers de synchronisation
    _syncTimer = Timer.periodic(
      Duration(minutes: _syncInterval),
      (timer) => _performAutoSync(),
    );

    // Timer pour mettre à jour le compte à rebours
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // Forcer le recalcul du compte à rebours
        });
      }
    });

    print(
      '⏰ Timers initialisés: collecte=$_collectInterval min, sync=$_syncInterval min',
    );
  }

  Future<void> _loadConfig() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();

      // Convertir secondes en minutes
      final collectIntervalMinutes = (config.collectionInterval / 60).round();
      final syncIntervalMinutes = (config.sendInterval / 60).round();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('collect_interval', collectIntervalMinutes);
      await prefs.setInt('sync_interval', syncIntervalMinutes);

      setState(() {
        _currentConfig = config;
        _collectInterval = collectIntervalMinutes;
        _syncInterval = syncIntervalMinutes;
      });

      // Mettre à jour les timers si les intervalles ont changé
      if (_timersInitialized) {
        _updateTimers();
      }

      print(
        '⚙️ Configuration chargée: $_collectInterval min collecte, $_syncInterval min sync',
      );
    } catch (e) {
      print('⚠️ Erreur chargement config: $e - Utilisation du cache');
    } finally {
      setState(() => _configLoading = false);
    }
  }

  void _updateTimers() {
    _collectTimer?.cancel();
    _syncTimer?.cancel();

    _collectTimer = Timer.periodic(
      Duration(minutes: _collectInterval),
      (timer) => _performAutoCollect(),
    );

    _syncTimer = Timer.periodic(
      Duration(minutes: _syncInterval),
      (timer) => _performAutoSync(),
    );

    print('🔄 Timers mis à jour avec nouveaux intervalles');
  }

  Future<void> _startBackgroundManager() async {
    try {
      final backgroundManager = context.read<BackgroundManager>();
      final authService = context.read<AuthService>();

      if (authService.isAuthenticated) {
        print('✅ Démarrage du background manager...');
        await backgroundManager.start();
      }
    } catch (e) {
      print('⚠️ Erreur démarrage background manager: $e');
    }
  }

  Future<void> _loadIntervals() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _collectInterval = prefs.getInt('collect_interval') ?? 5;
      _syncInterval = prefs.getInt('sync_interval') ?? 10;
    });
  }

  Future<void> _loadStats() async {
    try {
      final pendingCount = await _databaseService.getPendingCount();
      final syncedCount = await _databaseService.getSyncedCount();
      final lastSync = await _storageService.getLastSyncTime();
      final lastCollection = await _databaseService.getLastCollectionTime();

      setState(() {
        _stats = {
          'pending_count': pendingCount,
          'synced_count': syncedCount,
          'last_sync': lastSync,
          'last_collection': lastCollection,
          'total_data': pendingCount + syncedCount,
        };
      });
    } catch (e) {
      print('❌ Erreur chargement stats: $e');
    }
  }

  Future<void> _loadPendingData() async {
    setState(() => _pendingLoading = true);
    final data = await _databaseService.getPendingGpsData();
    setState(() {
      _pendingData = data;
      _pendingLoading = false;
    });
  }

  Future<void> _loadHistoryData() async {
    setState(() => _historyLoading = true);

    // Charger toutes les données triées par date
    final allData = await _databaseService.getAllGpsData();
    setState(() {
      _historyData = allData;
      _historyLoading = false;
    });
  }

  Future<void> _loadAllData() async {
    await Future.wait([_loadPendingData(), _loadHistoryData(), _loadStats()]);
  }

  Future<void> _refreshData() async {
    print('🔄 Rafraîchissement manuel des données');
    try {
      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Données rafraîchies avec succès'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Erreur rafraîchissement données: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du rafraîchissement: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _startPreferencesChecker() {
    _prefsCheckTimer = Timer.periodic(const Duration(seconds: 5), (
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

        setState(() {
          _collectInterval = newCollectInterval;
          _syncInterval = newSyncInterval;
        });

        // Mettre à jour les timers
        _collectTimer?.cancel();
        _syncTimer?.cancel();

        _collectTimer = Timer.periodic(
          Duration(minutes: _collectInterval),
          (timer) => _performAutoCollect(),
        );

        _syncTimer = Timer.periodic(
          Duration(minutes: _syncInterval),
          (timer) => _performAutoSync(),
        );

        // Mettre à jour le background manager
        try {
          final backgroundManager = context.read<BackgroundManager>();
          await backgroundManager.updateIntervals();
        } catch (e) {
          print('⚠️ Erreur mise à jour intervals background: $e');
        }
      }
    });
  }

  Future<void> _performAutoCollect() async {
    try {
      print('📍 Début collecte automatique...');

      // Sauvegarder le temps actuel
      _lastCollectionTime = DateTime.now().add(
        Duration(minutes: _collectInterval),
      );

      // Utiliser AutoCollectService pour la collecte
      await AutoCollectService.manualCollect();

      // Recharger les données
      await _loadPendingData();
      await _loadStats();

      // Mettre à jour le prochain temps de collecte
      setState(() {
        _nextCollection = _lastCollectionTime;
      });

      print('✅ Collecte automatique terminée');
    } catch (e) {
      print('❌ Erreur collecte automatique: $e');
    }
  }

  Future<void> _performAutoSync() async {
    try {
      print('🔄 Début synchronisation automatique...');

      // Sauvegarder le temps actuel
      _lastSyncTime = DateTime.now().add(Duration(minutes: _syncInterval));

      await _syncService.syncPendingData();

      // Recharger les données
      await Future.wait([_loadStats(), _loadPendingData(), _loadHistoryData()]);

      // Mettre à jour le prochain temps de synchronisation
      setState(() {
        _nextSync = _lastSyncTime;
      });

      print('✅ Synchronisation automatique terminée');
    } catch (e) {
      print('❌ Erreur synchronisation automatique: $e');
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Effacer toutes les données'),
            content: const Text(
              'Êtes-vous sûr de vouloir effacer toutes les données GPS locales ? '
              'Cette action est irréversible.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Effacer',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _databaseService.clearAllData();
        await _loadAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Toutes les données GPS ont été effacées'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur lors de l\'effacement: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Déconnexion'),
            content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Déconnexion',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        // Arrêter le background manager
        final backgroundManager = context.read<BackgroundManager>();
        await backgroundManager.stop();

        // Déconnexion
        final authService = context.read<AuthService>();
        await authService.logout();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } catch (e) {
        print('❌ Erreur lors de la déconnexion: $e');
      }
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _collectTimer?.cancel();
    _syncTimer?.cancel();
    _statsTimer?.cancel();
    _prefsCheckTimer?.cancel();
    _tabController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _refreshData();
        },
        backgroundColor: Colors.green[700],
        child: const Icon(Icons.refresh),
        tooltip: 'Rafraîchir les données',
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'clear_data') {
                _clearAllData();
              } else if (value == 'force_sync') {
                _performAutoSync();
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder:
                (BuildContext context) => [
                  const PopupMenuItem<String>(
                    value: 'force_sync',
                    child: Row(
                      children: [
                        Icon(Icons.sync, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Forcer synchronisation'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'clear_data',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Effacer données locales'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Déconnexion'),
                      ],
                    ),
                  ),
                ],
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () async {
              final needsRefresh = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );

              if (needsRefresh == true && mounted) {
                await _refreshData();
              }
            },
            tooltip: 'Paramètres',
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
          children: [
            RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _refreshData,
              color: Colors.green,
              backgroundColor: Colors.white,
              child: _buildDashboardTab(),
            ),
            RefreshIndicator(
              onRefresh: _refreshData,
              color: Colors.green,
              backgroundColor: Colors.white,
              child: _buildHistoryTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 Pour rafraîchir :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• Glisser vers le bas\n'
                        '• Appuyer sur le bouton 🔄\n'
                        '• Appuyer sur le FAB',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDataList() {
    if (_pendingData.isEmpty) {
      return Container(
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
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.pending_actions, color: Colors.orange),
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
                    color: data.synced ?? false ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  dense: true,
                );
              },
            ),
          ),
        ],
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

    return ListView.separated(
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
