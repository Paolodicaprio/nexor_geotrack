import 'package:flutter/material.dart';
import 'package:geotrack_frontend/pages/dashboard_page.dart';
import 'package:geotrack_frontend/pages/login_page.dart' as login_page;
import 'package:geotrack_frontend/pages/register_page.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:provider/provider.dart';

// Dans le GeoTrackApp, mettre à jour les routes
class GeoTrackApp extends StatelessWidget {
  const GeoTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => StorageService()),
      ],
      child: MaterialApp(
        title: 'Nexor GeoTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: FutureBuilder(
          future: StorageService().getToken(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              if (snapshot.hasData && snapshot.data != null) {
                return const DashboardPage();
              } else {
                return const login_page.LoginPage(); // Utiliser directement LoginPage
              }
            } else {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
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
