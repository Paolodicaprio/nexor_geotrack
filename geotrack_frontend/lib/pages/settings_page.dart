import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/background_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadApiUrl();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _collectIntervalController.text =
          (prefs.getInt('collect_interval') ?? 5).toString();
      _syncIntervalController.text =
          (prefs.getInt('sync_interval') ?? 10).toString();
    });
  }

  Future<void> _loadApiUrl() async {
    final apiUrl = await ApiService.getApiUrl();
    setState(() {
      _apiUrlController.text = apiUrl;
    });
  }

  Future<void> _saveSettings() async {
    if (_settingsFormKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });

      final collectInterval = int.parse(_collectIntervalController.text);
      final syncInterval = int.parse(_syncIntervalController.text);

      try {
        final apiService = ApiService();

        // Convertir minutes en secondes pour l'API
        final collectIntervalSeconds = collectInterval * 60;
        final syncIntervalSeconds = syncInterval * 60;

        // Utiliser PUT pour mettre à jour partiellement
        await apiService.updateConfig({
          'collection_interval': collectIntervalSeconds,
          'send_interval': syncIntervalSeconds,
        });

        // Convertir secondes en minutes pour le stockage local
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('collect_interval', collectInterval);
        await prefs.setInt('sync_interval', syncInterval);

        // Redémarrer le background manager avec les nouveaux intervalles
        try {
          final backgroundManager = BackgroundManager();
          await backgroundManager.stop();
          await backgroundManager.start();
        } catch (e) {
          print('⚠️ Error restarting background manager: $e');
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres sauvegardés avec succès'),
            backgroundColor: Colors.green,
          ),
        );

        // Retourner true pour indiquer que les paramètres ont été modifiés
        Navigator.pop(context, true);
      } catch (e) {
        // Si la config n'existe pas, essayer de la créer
        try {
          final apiService = ApiService();
          final collectIntervalSeconds = collectInterval * 60;
          final syncIntervalSeconds = syncInterval * 60;

          await apiService.createConfig(
            collectIntervalSeconds,
            syncIntervalSeconds,
          );

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('collect_interval', collectInterval);
          await prefs.setInt('sync_interval', syncInterval);

          // Redémarrer le background manager avec les nouveaux intervalles
          try {
            final backgroundManager = BackgroundManager();
            await backgroundManager.stop();
            await backgroundManager.start();
          } catch (e) {
            print('⚠️ Error restarting background manager: $e');
          }

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paramètres créés avec succès'),
              backgroundColor: Colors.green,
            ),
          );

          Navigator.pop(context, true);
        } catch (createError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur lors de la sauvegarde: $createError'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    // Confirmation
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
      // Arrêter le background manager
      try {
        await BackgroundManager().stop();
      } catch (e) {
        print('⚠️ Error stopping background manager: $e');
      }

      // Déconnexion
      await authService.logout();

      // Nettoyer les données (optionnel)
      // await StorageService().clearAllData();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
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
          content: Text('Url modifié avec succès'),
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
    await _loadApiUrl();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Url reinitialisé avec succès'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Effacer toutes les données'),
            content: const Text(
              'Êtes-vous sûr de vouloir effacer toutes les données locales ? '
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
        await StorageService().clearAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Toutes les données ont été effacées'),
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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    // Récupérer l'email de différentes manières
    String? userEmail =
        authService.userEmail ?? authService.getEmailFromToken();

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
                          if (val == null || val < 1 || val > 1440) {
                            return 'Doit être entre 1 et 1440 minutes';
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
                          if (val == null || val < 1 || val > 1440) {
                            return 'Doit être entre 1 et 1440 minutes';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon:
                              _isSaving
                                  ? const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  )
                                  : const Icon(Icons.save),
                          label: Text(
                            _isSaving
                                ? 'Sauvegarde...'
                                : 'Sauvegarder les paramètres',
                          ),
                          onPressed: _isSaving ? null : _saveSettings,
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

            // Section Information utilisateur - CORRIGÉE
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
                    const Row(
                      children: [
                        Icon(Icons.person, color: Colors.green),
                        SizedBox(width: 12),
                        Text(
                          'Information du compte',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Email de l'utilisateur
                    ListTile(
                      leading: const Icon(Icons.email, color: Colors.grey),
                      title: const Text(
                        'Email',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      subtitle: Text(
                        userEmail ?? 'Non disponible',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),

                    const SizedBox(height: 12),

                    // Statut de connexion
                    ListTile(
                      leading: Icon(
                        authService.isAuthenticated
                            ? Icons.check_circle
                            : Icons.error,
                        color:
                            authService.isAuthenticated
                                ? Colors.green
                                : Colors.orange,
                      ),
                      title: Text(
                        authService.isAuthenticated
                            ? 'Connecté'
                            : 'Non connecté',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              authService.isAuthenticated
                                  ? Colors.green
                                  : Colors.orange,
                        ),
                      ),
                      subtitle: const Text(
                        'Statut d\'authentification',
                        style: TextStyle(fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),

                    const Divider(height: 24),

                    // Message d'information
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info, color: Colors.amber, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Important',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Le code d\'accès est généré une seule fois lors de l\'inscription. '
                            'Conservez-le précieusement car il ne peut pas être modifié.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section Configuration de l'API
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
                        const Icon(
                          Icons.compare_arrows_rounded,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Configuration de L\'API',
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
                                labelText: 'Url de l\'API',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.link),
                              ),
                              keyboardType: TextInputType.text,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Veuillez entrer l\'URL de l\'API';
                                }
                                // Vérifier si l'URL est valide
                                final uri = Uri.tryParse(value.trim());
                                if (uri == null ||
                                    (!uri.hasScheme || !uri.hasAuthority)) {
                                  return 'URL invalide (doit contenir http:// ou https://)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.update),
                                label: const Text('Modifier l\'url'),
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
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.clear),
                                label: const Text(
                                  'Revenir a l \'url par défaut ',
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

            // Section Gestion des données
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
                    const Row(
                      children: [
                        Icon(Icons.storage, color: Colors.green),
                        SizedBox(width: 12),
                        Text(
                          'Gestion des Données',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Effacer toutes les données locales',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: _clearAllData,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Cette action effacera toutes les données GPS stockées localement, '
                        'y compris les données en attente de synchronisation.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
