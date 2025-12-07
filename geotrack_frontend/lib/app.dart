import 'package:flutter/material.dart';
import 'package:geotrack_frontend/pages/dashboard_page.dart';
import 'package:geotrack_frontend/pages/login_page.dart' as login_page;
import 'package:geotrack_frontend/pages/register_page.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/background_manager.dart';
import 'package:provider/provider.dart';

class GeoTrackApp extends StatelessWidget {
  const GeoTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => StorageService()),
        Provider(create: (_) => BackgroundManager()),
      ],
      child: MaterialApp(
        title: 'Nexor GeoTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: Consumer<AuthService>(
          builder: (context, authService, child) {
            return FutureBuilder<bool>(
              future: authService.checkAuth(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.data == true) {
                    // Utilisateur authentifié
                    return const DashboardPage();
                  } else {
                    // Utilisateur non authentifié
                    return const login_page.LoginPage();
                  }
                } else {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
              },
            );
          },
        ),
        routes: {
          '/login': (context) => const login_page.LoginPage(),
          '/dashboard': (context) => const DashboardPage(),
          '/register': (context) => const RegisterPage(),
        },
      ),
    );
  }
}
