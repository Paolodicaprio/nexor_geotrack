import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/power_optimizations.dart';
import 'package:provider/provider.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _collectIntervalController =TextEditingController();
  final TextEditingController _syncIntervalController = TextEditingController();
  final TextEditingController _configSyncIntervalController = TextEditingController();
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _deviceCodeController = TextEditingController();
  final TextEditingController _databaseNameController = TextEditingController();

  final _settingsFormKey = GlobalKey<FormState>();
  final _apiFormKey = GlobalKey<FormState>();

  bool _showApiSection = false;
  bool _configLoading = false;
  bool _isBatteryOptimized = true;
  bool _checkingBattery = false;

  @override
  void initState() {
    super.initState();
    StorageService().reloadStorage();
    _loadSettings();
    _loadApiSettings();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    
    setState(() => _checkingBattery = true);
    try {
      final isIgnoring = await PowerOptimizationsService.isIgnoringBatteryOptimizations();
      setState(() => _isBatteryOptimized = !isIgnoring);
    } catch (e) {
      debugPrint('Error checking battery optimization: $e');
    } finally {
      setState(() => _checkingBattery = false);
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    final success = await PowerOptimizationsService.requestIgnoreBatteryOptimizations();
    if (success) {
      // Give system time to process, then recheck
      await Future.delayed(const Duration(seconds: 2));
      await _checkBatteryOptimization();
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();
      await StorageService().saveConfig(config);

      setState(() {
        _collectIntervalController.text = config.collectionInterval.toString();
        _syncIntervalController.text = config.sendInterval.toString();
        _configSyncIntervalController.text = config.configSyncInterval.toString();
      });
    } catch (e) {
      // En cas d'erreur, charger depuis SharedPreferences
     final conf = await StorageService().getConfig();
      setState(() {
        _collectIntervalController.text =conf.collectionInterval.toString();
        _syncIntervalController.text =conf.sendInterval.toString();
        _configSyncIntervalController.text =conf.configSyncInterval.toString();
      });
    } finally {
      setState(() => _configLoading = false);
    }
  }

  Future<void> _loadApiSettings() async {
    final apiUrl = await ApiService.getApiUrl();
    final dbName = await StorageService().getDatabaseName();
    final String? deviceCode = await StorageService().getDeviceCode();
    setState(() {
      _apiUrlController.text = apiUrl;
      _databaseNameController.text = dbName;
     if (deviceCode !=null){
       _deviceCodeController.text = deviceCode;
     }
    });
  }

  Future<void> _refetchSettings() async {
      try {
        final apiService = ApiService();
        final newConfig = await apiService.getConfig();
        if( !newConfig.hasSameIntervals(await StorageService().getConfig())){
          await StorageService().saveConfig(newConfig);
          FlutterBackgroundService().invoke("config_changed");
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurations successfully retrieved'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during retrieval: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  Future<void> showConfirmDialog()async{
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout',style: TextStyle(fontSize: 18),),
          content: const Text(
            "You will be logged out to be able to modify the API settings"
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _logout();
                },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveDeviceCode()async{
    await StorageService().saveDeviceId(_deviceCodeController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device code successfully modified'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Section Intervalles
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _settingsFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.timer, color: Colors.green),
                          SizedBox(width: 12),
                          Text(
                            'Synchronization Intervals',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        enabled: false,
                        controller: _collectIntervalController,
                        decoration: const InputDecoration(
                          labelText: 'Collection interval (seconds)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.gps_fixed),
                        ),
                        keyboardType: TextInputType.number,

                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _syncIntervalController,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Synchronization interval (seconds)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.sync),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _configSyncIntervalController,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Configuration synchronization (minutes)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.sync),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.update),
                          label:
                              _configLoading
                                  ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                  : const Text('Reload Configurations'),
                          onPressed: _configLoading ? null : _refetchSettings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section Configuration API
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.api, color: Colors.green),
                        const SizedBox(width: 12),
                        const Text(
                          'API Configuration',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _showApiSection
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.green,
                          ),
                          onPressed: () {
                            setState(() {
                              _showApiSection = !_showApiSection;
                            });
                          },
                        ),
                      ],
                    ),
                    if (_showApiSection) ...[
                      const SizedBox(height: 16),
                      Form(
                        key: _apiFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _deviceCodeController,
                              decoration: const InputDecoration(
                                labelText: 'Your Device Code',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.numbers),
                                hintText: 'abcd123',
                              ),
                              keyboardType: TextInputType.text,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a device code';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16,),
                            SizedBox(
                              width: double.infinity,
                              child:ElevatedButton(
                                onPressed: _saveDeviceCode,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text("Validate"),
                              )
                            ),
                            const SizedBox(height: 24),
                            (Divider()),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _apiUrlController,
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'API Base URL',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.link),
                                hintText: 'https://mybaseurl.com',
                              ),
                              keyboardType: TextInputType.url,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the API URL';
                                }
                                final uri = Uri.tryParse(value.trim());
                                if (uri == null ||
                                    (!uri.hasScheme || !uri.hasAuthority)) {
                                  return 'Invalid URL';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _databaseNameController,
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'Database Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.storage),
                                hintText: 'my_db_name',
                              ),
                              keyboardType: TextInputType.text,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a database name';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.update),
                                label: const Text('Modify Settings'),
                                onPressed: showConfirmDialog,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Battery Optimization Section (Android only)
            if (Platform.isAndroid)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isBatteryOptimized ? Icons.battery_alert : Icons.battery_full,
                            color: _isBatteryOptimized ? Colors.orange : Colors.green,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Battery Optimization',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_checkingBattery)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isBatteryOptimized
                            ? 'Battery optimization is enabled. This may stop GPS collection when the app is in the background.'
                            : 'Battery optimization is disabled. GPS collection will work reliably in background.',
                        style: TextStyle(
                          color: _isBatteryOptimized ? Colors.orange[800] : Colors.green[800],
                          fontSize: 13,
                        ),
                      ),
                      if (_isBatteryOptimized) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.settings),
                            label: const Text('Disable Battery Optimization'),
                            onPressed: _requestBatteryOptimizationExemption,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Optimal configuration for GPS tracking',
                              style: TextStyle(color: Colors.green[700], fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (Platform.isAndroid) const SizedBox(height: 24),

            // Bouton de déconnexion
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: _logout,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _collectIntervalController.dispose();
    _syncIntervalController.dispose();
    _apiUrlController.dispose();
    _deviceCodeController.dispose();
    super.dispose();
  }
}
