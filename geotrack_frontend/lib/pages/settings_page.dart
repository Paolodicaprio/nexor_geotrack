import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadApiSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('collect_interval', config.collectionInterval ~/ 60);
      await prefs.setInt('sync_interval', config.sendInterval ~/ 60);
      await prefs.setInt('config_sync_interval', config.configSyncInterval);

      setState(() {
        _collectIntervalController.text = config.collectionInterval.toString();
        _syncIntervalController.text = config.sendInterval.toString();
        _configSyncIntervalController.text = config.configSyncInterval.toString();
      });
    } catch (e) {
      // En cas d'erreur, charger depuis SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _collectIntervalController.text =
            (prefs.getInt('collect_interval') ?? Constants.defaultCollectionInterval).toString();
        _syncIntervalController.text =
            (prefs.getInt('sync_interval') ?? Constants.defaultSendInterval).toString();
        _configSyncIntervalController.text =(prefs.getInt('config_sync_interval')?? Constants.defaultSendInterval).toString();
      });
    } finally {
      setState(() => _configLoading = false);
    }
  }

  Future<void> _loadApiSettings() async {
    final apiUrl = await ApiService.getApiUrl();
    final dbName = await StorageService().getDatabaseName();
    final deviceCode = await StorageService().getDeviceCode();
    setState(() {
      _apiUrlController.text = apiUrl;
      _databaseNameController.text = dbName;
      _deviceCodeController.text = deviceCode;
    });
  }

  Future<void> _refetchSettings() async {
      try {
        final apiService = ApiService();
        final newConfig = await apiService.getConfig();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'collect_interval',
          newConfig.collectionInterval ~/ 60,
        );
        await prefs.setInt('sync_interval', newConfig.sendInterval ~/ 60);
        await prefs.setInt('config_sync_interval', newConfig.configSyncInterval);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurations recupéré  avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la recuperation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  // Future<void> _changeApiSetting() async {
  //   if (_apiFormKey.currentState!.validate()) {
  //     await StorageService().saveCustomUrl(_apiUrlController.text);
  //     setState(() {
  //       _showApiSection = false;
  //     });
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Paramètres modifiée avec succès'),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //   }
  // }

  Future<void> showConfirmDialog()async{
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmer la deconnexion',style: TextStyle(fontSize: 18),),
          content: const Text(
            "Vous allez etre déconnecter afin de pouvoir modifier les parametres de l'api"
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _logout();
                },
              child: const Text('confirmer'),
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
        content: Text('Device code modifié avec succès'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Future<void> _clearApiUrl() async {
  //   await StorageService().clearCustomUrl();
  //   setState(() {
  //     _showApiSection = false;
  //   });
  //   await _loadApiSettings(); // Recharger l'URL par défaut
  //   if (!mounted) return;
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     const SnackBar(
  //       content: Text('URL réinitialisée avec succès'),
  //       backgroundColor: Colors.green,
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
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
                            'Intervalles de Synchronisation',
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
                          labelText: 'Intervalle de collecte (secondes)',
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
                          labelText: 'Intervalle de synchronisation (secondes)',
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
                          labelText: 'synchronisation de la configuration (minutes)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.sync),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Veuillez entrer un intervalle';
                          }
                          final val = int.tryParse(value);
                          if (val == null || val < 1) {
                            return 'Intervalle invalide (min. 1 minute)';
                          }
                          return null;
                        },
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
                                  : const Text('Recharger les configurations'),
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
                          'Configuration de l\'API',
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
                                labelText: 'Votre Device code',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.numbers),
                                hintText: 'abcd123',
                              ),
                              keyboardType: TextInputType.text,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Veuillez entrer un device code';
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
                                child: const Text("Valider"),
                              )
                            ),
                            const SizedBox(height: 24),
                            (Divider()),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _apiUrlController,
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'URL de l\'API',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.link),
                                hintText: 'http://10.0.2.2:8000',
                              ),
                              keyboardType: TextInputType.url,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Veuillez entrer l\'URL de l\'API';
                                }
                                final uri = Uri.tryParse(value.trim());
                                if (uri == null ||
                                    (!uri.hasScheme || !uri.hasAuthority)) {
                                  return 'URL invalide ';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _databaseNameController,
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'Nom de la base de donnée',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.storage),
                                hintText: 'ma-base-de-donnee',
                              ),
                              keyboardType: TextInputType.text,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Veuillez entrer un nom pour la base de donnée';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.update),
                                label: const Text('Modifier les paramètres'),
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
                            // const SizedBox(height: 8),
                            // SizedBox(
                            //   width: double.infinity,
                            //   child: ElevatedButton.icon(
                            //     icon: const Icon(Icons.clear),
                            //     label: const Text(
                            //       'Revenir à l\'URL par défaut',
                            //     ),
                            //     onPressed: _clearApiUrl,
                            //     style: ElevatedButton.styleFrom(
                            //       padding: const EdgeInsets.symmetric(
                            //         vertical: 16,
                            //       ),
                            //       backgroundColor: Colors.orange,
                            //       foregroundColor: Colors.white,
                            //     ),
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Bouton de déconnexion
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Déconnexion',
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
