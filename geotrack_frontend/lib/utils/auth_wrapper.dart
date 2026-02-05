import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:provider/provider.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/pages/dashboard_page.dart';
import 'package:geotrack_frontend/pages/login_page.dart';
import 'package:geotrack_frontend/services/permissions_service.dart';

import '../services/background_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// Étape 1 : Vérifier les permissions nécessaires
  /// Étape 2 : Vérifier l'authentification si tout est accordé
  Future<void> _initializeApp() async {
    try {
      // 1️⃣ Vérifier d’abord les permissions
      final permissionResult = await checkPermissions();

      if (!permissionResult.allGranted) {
        // Certaines permissions manquent → les demander
        final requestResult = await requestPermissions();

        if (!requestResult.allGranted) {
          // Si toujours refusé → afficher un écran dédié
          setState(() {
            _permissionsGranted = false;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() => _permissionsGranted = true);

      // 2️⃣ Vérifier maintenant l’authentification
      final authService = Provider.of<AuthService>(context, listen: false);
      final authenticated = await authService.checkAuth();
      print('🔐 Auth check result: $authenticated');

      // s'executera alors uniquement si tout les permissions sont accordées
      await _initializeBackgroundService();
      setState(() {
        _isAuthenticated = authenticated;
        _isLoading = false;
      });

    } catch (e) {
      print('❌ Error during initialization: $e');
      setState(() {
        _isLoading = false;
        _permissionsGranted = false;
        _isAuthenticated = false;
      });
    }
  }

  Future<void> _initializeBackgroundService() async {
    print("Initializing background service communication...");
    final authService = Provider.of<AuthService>(context, listen: false);
    bool canSync = _isAuthenticated || authService.hasToken;
    await initializeBackgroundService(canSync);

  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initialisation en cours...'),
            ],
          ),
        ),
      );
    }

    // Cas où les permissions ne sont pas toutes accordées
    if (!_permissionsGranted) {
      return _buildPermissionScreen();
    }

    // Sinon, on navigue vers la page appropriée
    return _isAuthenticated ? const DashboardPage() : const LoginPage();
  }

  /// Écran si certaines permissions sont manquantes
  Widget _buildPermissionScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Autorisations requises')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                "Certaines autorisations sont nécessaires pour utiliser NexOR GeoTrack.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Autoriser maintenant'),
                onPressed: () async {
                  setState(() => _isLoading = true);
                  final result = await requestPermissions();
                  if (result.allGranted) {
                    setState(() {
                      _permissionsGranted = true;
                      _isLoading = false;
                    });
                    // Relancer la vérification d’auth après avoir les permissions
                    await _initializeApp();
                  } else {
                    setState(() => _isLoading = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
