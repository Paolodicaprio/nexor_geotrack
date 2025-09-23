import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _collectIntervalController =
      TextEditingController();
  final TextEditingController _syncIntervalController = TextEditingController();
  final TextEditingController _apiUrlController = TextEditingController();

  final _settingsFormKey = GlobalKey<FormState>();
  final _apiFormKey = GlobalKey<FormState>();

  bool _showApiSection = false;
  bool _configLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadApiUrl();
  }

  Future<void> _loadSettings() async {
    setState(() => _configLoading = true);
    try {
      final apiService = ApiService();
      final config = await apiService.getConfig();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('collect_interval', config.collectionInterval ~/ 60);
      await prefs.setInt('sync_interval', config.sendInterval ~/ 60);

      setState(() {
        _collectIntervalController.text =
            (config.collectionInterval ~/ 60).toString();
        _syncIntervalController.text = (config.sendInterval ~/ 60).toString();
      });
    } catch (e) {
      // En cas d'erreur, charger depuis SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _collectIntervalController.text =
            (prefs.getInt('collect_interval') ?? 5).toString();
        _syncIntervalController.text =
            (prefs.getInt('sync_interval') ?? 10).toString();
      });
    } finally {
      setState(() => _configLoading = false);
    }
  }

  Future<void> _loadApiUrl() async {
    final apiUrl = await ApiService.getApiUrl();
    setState(() {
      _apiUrlController.text = apiUrl;
    });
  }

  Future<void> _saveSettings() async {
    if (_settingsFormKey.currentState!.validate()) {
      final collectInterval =
          int.parse(_collectIntervalController.text) *
          60; // Convertir en secondes
      final syncInterval =
          int.parse(_syncIntervalController.text) * 60; // Convertir en secondes

      try {
        final apiService = ApiService();

        // Utiliser les bons noms de paramètres pour l'API
        final updatedConfig = await apiService.updateConfig({
          'collection_interval': collectInterval,
          'send_interval': syncInterval,
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'collect_interval',
          updatedConfig.collectionInterval ~/ 60,
        );
        await prefs.setInt('sync_interval', updatedConfig.sendInterval ~/ 60);

        if (!mounted) return;
        Navigator.pop(context, true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres sauvegardés avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sauvegarde: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _changeApiUrl() async {
    if (_apiFormKey.currentState!.validate()) {
      await StorageService().saveCustomUrl(_apiUrlController.text);
      setState(() {
        _showApiSection = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL modifiée avec succès'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearApiUrl() async {
    await StorageService().clearCustomUrl();
    setState(() {
      _showApiSection = false;
    });
    await _loadApiUrl(); // Recharger l'URL par défaut
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('URL réinitialisée avec succès'),
        backgroundColor: Colors.green,
      ),
    );
  }

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
                        controller: _collectIntervalController,
                        decoration: const InputDecoration(
                          labelText: 'Intervalle de collecte (minutes)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.gps_fixed),
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
                      TextFormField(
                        controller: _syncIntervalController,
                        decoration: const InputDecoration(
                          labelText: 'Intervalle de synchronisation (minutes)',
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
                          icon: const Icon(Icons.save),
                          label:
                              _configLoading
                                  ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                  : const Text('Sauvegarder les paramètres'),
                          onPressed: _configLoading ? null : _saveSettings,
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
                              controller: _apiUrlController,
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
                                  return 'URL invalide (ex: http://10.0.2.2:8000)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.update),
                                label: const Text('Modifier l\'URL'),
                                onPressed: _changeApiUrl,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.clear),
                                label: const Text(
                                  'Revenir à l\'URL par défaut',
                                ),
                                onPressed: _clearApiUrl,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: Colors.orange,
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
    super.dispose();
  }
}
