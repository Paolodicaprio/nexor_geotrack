import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/permissions_service.dart';
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

  DateTime? _nextCollection;
  DateTime? _nextSync;

  late TabController _tabController;
  late BuildContext rootContext;

  int _collectInterval = 5;
  int _syncInterval = 10;

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
      print('❌ Permissions refusées');
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
            title: const Text('Permission requise'),
            content: const Text(
              'Pour continuer la collecte GPS même lorsque l\'application est fermée, '
              'vous devez autoriser l\'accès à la localisation en arrière-plan.\n\n'
              'Cette fonctionnalité est essentielle pour le suivi continu.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(rootContext).pop();
                  // L'utilisateur refuse - continuer sans permission background
                },
                child: const Text('Refuser'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(rootContext).pop();
                  // Demander la permission background
                  final bgPermission;
                  if (actualPermission == LocationPermission.whileInUse) {
                     bgPermission =await Permission.locationAlways.request();
                  }else{
                    bgPermission = await Geolocator.requestPermission();
                  }

                  if (bgPermission == LocationPermission.always || bgPermission==PermissionStatus.granted ) {
                    // Permission accordée
                    if (mounted) {
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(
                          content: Text('Permission background accordée'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else {
                    // Permission refusée
                    if (mounted) {
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Permission background refusée - la collecte s\'arrêtera quand l\'app est fermée',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Autoriser'),
              ),
            ],
          ),
    );
  }

  Future<void> _initIntervalsAndTimers() async {
    // Attendre que la configuration soit chargée
    while (_currentConfig == null && _configLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Utiliser les valeurs de configuration ou les valeurs par défaut
    final collectInterval =
        _currentConfig?.collectionInterval ?? 300; // Secondes
    final syncInterval = _currentConfig?.sendInterval ?? 600; // Secondes

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'collect_interval',
      collectInterval ~/ 60,
    ); // Convertir en minutes
    await prefs.setInt(
      'sync_interval',
      syncInterval ~/ 60,
    ); // Convertir en minutes

    setState(() {
      _collectInterval =
          collectInterval ~/ 60; // Stocker en minutes pour l'interface
      _syncInterval = syncInterval ~/ 60; // Stocker en minutes pour l'interface
      _nextCollection = DateTime.now().add(Duration(minutes: _collectInterval));
      _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
    });

    // Première collecte dès l'ouverture
    await _autoCollect();
    await _loadPendingData();
    await _loadHistoryData();
    _startAutoCollect();
    _startAutoSync();
    _startStatsTimer();
  }

  Future<void> _loadConfig() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('collect_interval', config.collectionInterval ~/ 60);
      await prefs.setInt('sync_interval', config.sendInterval ~/ 60);

      setState(() {
        _currentConfig = config;
        _collectInterval = config.collectionInterval ~/ 60;
        _syncInterval = config.sendInterval ~/ 60;
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      });

      _restartTimersWithNewIntervals();
    } catch (e) {
      print('❌ Error loading config: $e');

      // Gestion spécifique du token expiré
      if (e.toString().contains('401') ||
          e.toString().contains('Token expiré')) {
        _handleTokenExpired();
        return;
      }

      // Utiliser les valeurs par défaut si autre erreur
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _collectInterval = prefs.getInt('collect_interval') ?? 5;
        _syncInterval = prefs.getInt('sync_interval') ?? 10;
        _nextCollection = DateTime.now().add(
          Duration(minutes: _collectInterval),
        );
        _nextSync = DateTime.now().add(Duration(minutes: _syncInterval));
      });
    } finally {
      setState(() => _configLoading = false);
    }
  }

  void _handleTokenExpired() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session expirée - Redirection...'),
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _collectInterval = prefs.getInt('collect_interval') ?? 5;
      _syncInterval = prefs.getInt('sync_interval') ?? 10;
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

    // S'assurer que les données en attente ont synced: false
    final pendingWithStatus =
        pendingData.map((data) => data.copyWith(synced: false)).toList();

    // S'assurer que les données synchronisées ont synced: true
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
    _tabController.dispose();
    super.dispose();
  }

  void _startAutoCollect() {
    _collectTimer?.cancel();
    _collectTimer = Timer.periodic(Duration(minutes: _collectInterval), (
      timer,
    ) async {
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

  Future<void> _autoCollect() async {
    try {
      // Vérifier les permissions background
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        print(
          '⚠️ Mode background non autorisé - collecte limitée à l\'app ouverte',
        );
        // Continuer quand même la collecte pour l'app ouverte
      }
      // Vérifier la localisation avant de collecter
      final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        _showLocationWarning();
        return;
      }

      // Vérifier les permissions
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
            title: const Text('Localisation désactivée'),
            content: const Text(
              'La localisation de votre téléphone est désactivée. '
              'Veuillez l\'activer pour permettre la collecte automatique des données GPS.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ignorer'),
              ),
              TextButton(
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                  Navigator.of(context).pop();
                },
                child: const Text('Activer'),
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
            title: const Text('Permission requise'),
            content: const Text(
              'L\'application a besoin de la permission de localisation '
              'pour collecter les données GPS.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ignorer'),
              ),
              TextButton(
                onPressed: () async {
                  await Geolocator.requestPermission();
                  Navigator.of(context).pop();
                },
                child: const Text('Autoriser'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _autoSync() async {
    try {
      // Utilisation de la nouvelle méthode
      await AutoCollectService.syncGpsDataBackground();
      // Recharger toutes les données après synchronisation
      await Future.wait([_loadStats(), _loadPendingData(), _loadHistoryData()]);
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
          ).showSnackBar(SnackBar(content: Text('Données rafraîchies')));
        },
        child: Icon(Icons.refresh),
        backgroundColor: Colors.green[700],
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
                        '${data.lat.toStringAsFixed(6)}, ${data.lon.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        DateFormat('dd/MM HH:mm').format(data.timestamp),
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
                '${data.lat.toStringAsFixed(6)}, ${data.lon.toStringAsFixed(6)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                DateFormat('dd/MM/yyyy HH:mm').format(data.timestamp),
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
                            : 'Jamais', // Ce texte devrait maintenant disparaître après première collecte
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
