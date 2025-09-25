import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/pages/register_page.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/pages/forgot_pin_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePin = true;

  // Couleurs personnalisées
  final Color _primaryGreen = const Color(0xFF2ECC40);
  final Color _backgroundWhite = Colors.white;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: _backgroundWhite,
      appBar: AppBar(
        backgroundColor: _primaryGreen,
        elevation: 0,
        title: const Text(''),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _primaryGreen.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Icon(
                      Icons.location_on,
                      size: 80,
                      color: _primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Nexor GeoTrack',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entrez vos identifiants',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  // AJOUT: Champ email
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: _primaryGreen),
                      filled: true,
                      fillColor: _primaryGreen.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen, width: 2),
                      ),
                      prefixIcon: Icon(Icons.email, color: _primaryGreen),
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
                    controller: _pinController,
                    obscureText: _obscurePin,
                    decoration: InputDecoration(
                      labelText: 'Code d\'accès',
                      labelStyle: TextStyle(color: _primaryGreen),
                      filled: true,
                      fillColor: _primaryGreen.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryGreen, width: 2),
                      ),
                      prefixIcon: Icon(Icons.lock, color: _primaryGreen),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin ? Icons.visibility : Icons.visibility_off,
                          color: _primaryGreen,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePin = !_obscurePin;
                          });
                        },
                      ),
                      counterText: '',
                    ),
                    keyboardType: TextInputType.text,
                    maxLength: 8, // Code d'accès API = 8 caractères
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre code d\'accès';
                      }
                      if (value.length != 8) {
                        return 'Le code d\'accès doit contenir 8 caractères';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (authService.isBlocked())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Compte verrouillé. Réessayez dans ${authService.getRemainingBlockTime().inSeconds} secondes',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (authService.failedAttempts > 0 &&
                      !authService.isBlocked())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Tentatives échouées: ${authService.failedAttempts}/3',
                        style: TextStyle(color: Colors.orange[700]),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      onPressed:
                          authService.isBlocked() || _isLoading
                              ? null
                              : _handleLogin,
                      child:
                          _isLoading
                              ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                              : const Text(
                                'Connexion',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed:
                        authService.isBlocked()
                            ? null
                            : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterPage(),
                                ),
                              );
                            },
                    child: Text(
                      'Créer un compte',
                      style: TextStyle(
                        color:
                            authService.isBlocked()
                                ? Colors.grey
                                : _primaryGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed:
                        authService.isBlocked()
                            ? null
                            : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ForgotPinPage(),
                                ),
                              );
                            },
                    child: Text(
                      'Code d\'accès oublié ?',
                      style: TextStyle(
                        color:
                            authService.isBlocked()
                                ? Colors.grey
                                : _primaryGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();

      setState(() {
        _isLoading = true;
      });

      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await authService.login(
        _emailController.text,
        _pinController.text,
      );

      setState(() {
        _isLoading = false;
      });

      if (result.success) {
        print('✅ Login successful, checking token persistence...');

        // Test immédiat de la persistance
        final storedToken = await StorageService().getToken();
        final storedEmail = await StorageService().getUserEmail();

        print(
          '🔐 Stored token after login: ${storedToken != null ? "OK" : "FAILED"}',
        );
        print(
          '📧 Stored email after login: ${storedEmail != null ? "OK" : "FAILED"}',
        );
        // VÉRIFICATION DES PERMISSIONS DE LOCALISATION APRÈS CONNEXION
        await _checkLocationPermissions();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Échec de la connexion'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _checkLocationPermissions() async {
    final gpsService = GpsService();

    // Vérifier d'abord si la localisation du mobile est activée
    final isLocationEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isLocationEnabled) {
      // Localisation du mobile désactivée
      await _showEnableLocationDialog();
      return;
    }

    // Ensuite vérifier les permissions de l'app
    final hasAppPermission = await gpsService.checkPermission();

    if (!hasAppPermission) {
      // Permission de l'app refusée
      await _showLocationPermissionDialog();
    } else {
      // Tout est OK, rediriger
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  Future<void> _showEnableLocationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Localisation requise'),
          content: const Text(
            'La localisation de votre téléphone est désactivée. '
            'Veuillez l\'activer dans les paramètres de votre appareil pour utiliser l\'application.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Rediriger quand même vers le dashboard
                Navigator.pushReplacementNamed(context, '/dashboard');
              },
              child: const Text('Ignorer'),
            ),
            TextButton(
              onPressed: () async {
                // Ouvrir les paramètres de localisation du téléphone
                await Geolocator.openLocationSettings();
                Navigator.of(context).pop();
                // Re-vérifier après retour des paramètres
                await _checkLocationPermissions();
              },
              child: const Text('Activer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLocationPermissionDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission requise'),
          content: const Text(
            'L\'application a besoin d\'accéder à votre localisation pour fonctionner correctement.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacementNamed(context, '/dashboard');
              },
              child: const Text('Ignorer'),
            ),
            TextButton(
              onPressed: () async {
                // Demander la permission
                await Geolocator.requestPermission();
                Navigator.of(context).pop();
                // Re-vérifier après la permission
                await _checkLocationPermissions();
              },
              child: const Text('Autoriser'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }
}
