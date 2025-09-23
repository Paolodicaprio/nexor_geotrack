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
  final TextEditingController _oldPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _apiUrlController = TextEditingController();

  final _settingsFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();
  final _apiFormKey = GlobalKey<FormState>();

  bool _obscureOldPin = true;
  bool _obscureNewPin = true;
  bool _obscureConfirmPin = true;
  bool _isChangingPin = false;
  bool _showPinSection = false;
  bool _showApiSection = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUserEmail();
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

  Future<void> _loadUserEmail() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.userEmail != null) {
      _emailController.text = authService.userEmail!;
    }
  }

  Future<void> _saveSettings() async {
    if (_settingsFormKey.currentState!.validate()) {
      final collectInterval = int.parse(_collectIntervalController.text);
      final syncInterval = int.parse(_syncIntervalController.text);

      try {
        final apiService = ApiService();

        // Utiliser PUT au lieu de PATCH
        final updatedConfig = await apiService.updateConfig({
          'x_parameter': collectInterval,
          'y_parameter': syncInterval,
          // Ajouter device_id si requis par l'API
          'device_id': 'mobile-device', // ou récupérer la valeur actuelle
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('collect_interval', updatedConfig.xParameter);
        await prefs.setInt('sync_interval', updatedConfig.yParameter);

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

  Future<void> _changePin() async {
    if (_pinFormKey.currentState!.validate()) {
      final authService = Provider.of<AuthService>(context, listen: false);

      // Vérification plus robuste de l'authentification
      if (!authService.isAuthenticated || authService.token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session expirée. Veuillez vous reconnecter'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Vérifier que l'email correspond à celui du token
      final tokenEmail = authService.getEmailFromToken();
      if (tokenEmail != _emailController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email ne correspond pas au compte connecté'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isChangingPin = true;
      });

      final result = await authService.changePin(
        _emailController.text,
        _oldPinController.text,
        _newPinController.text,
      );

      setState(() {
        _isChangingPin = false;
      });

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );

        _oldPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();
        setState(() {
          _showPinSection = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
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
        _showApiSection=false;
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
        _showApiSection=false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Url reinitialisé avec succès'),
          backgroundColor: Colors.green,
        ),
      );
  }


  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

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
                            return 'Intervalle invalide';
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
                            return 'Intervalle invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text('Sauvegarder les paramètres'),
                          onPressed: _saveSettings,
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

            // Section Modification du PIN
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
                        const Icon(Icons.lock, color: Colors.green),
                        const SizedBox(width: 12),
                        const Text(
                          'Sécurité',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _showPinSection
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.green,
                          ),
                          onPressed: () {
                            setState(() {
                              _showPinSection = !_showPinSection;
                            });
                          },
                        ),
                      ],
                    ),

                    if (_showPinSection) ...[
                      const SizedBox(height: 16),
                      Form(
                        key: _pinFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Veuillez entrer votre email';
                                }
                                if (!RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                ).hasMatch(value)) {
                                  return 'Email invalide';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _oldPinController,
                              obscureText: _obscureOldPin,
                              decoration: InputDecoration(
                                labelText: 'Ancien PIN',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureOldPin
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureOldPin = !_obscureOldPin;
                                    });
                                  },
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Veuillez entrer votre ancien PIN';
                                }
                                if (value.length != 4) {
                                  return 'Le PIN doit contenir 4 chiffres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _newPinController,
                              obscureText: _obscureNewPin,
                              decoration: InputDecoration(
                                labelText: 'Nouveau PIN',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureNewPin
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureNewPin = !_obscureNewPin;
                                    });
                                  },
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Veuillez entrer un nouveau PIN';
                                }
                                if (value.length != 4) {
                                  return 'Le PIN doit contenir 4 chiffres';
                                }
                                if (value == _oldPinController.text) {
                                  return 'Le nouveau PIN doit être différent';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPinController,
                              obscureText: _obscureConfirmPin,
                              decoration: InputDecoration(
                                labelText: 'Confirmer le nouveau PIN',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPin
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPin = !_obscureConfirmPin;
                                    });
                                  },
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Veuillez confirmer votre PIN';
                                }
                                if (value != _newPinController.text) {
                                  return 'Les PIN ne correspondent pas';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon:
                                    _isChangingPin
                                        ? const CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        )
                                        : const Icon(Icons.lock_reset),
                                label: Text(
                                  _isChangingPin
                                      ? 'Modification...'
                                      : 'Modifier le PIN',
                                ),
                                onPressed: _isChangingPin ? null : _changePin,
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
                        const Icon(Icons.compare_arrows_rounded, color: Colors.green),
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
                                if (uri == null || (!uri.hasScheme || !uri.hasAuthority)) {
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
                                label: Text('Modifier l\'url'),
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
                                label: Text('Revenir a l \'url par défaut '),
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
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
