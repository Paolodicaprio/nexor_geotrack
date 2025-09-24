import 'package:flutter/material.dart';
import 'package:geotrack_frontend/pages/dashboard_page.dart';
import 'package:geotrack_frontend/pages/forgot_pin_page.dart';
import 'package:geotrack_frontend/pages/login_page.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/utils/auth_wrapper.dart';
import 'package:provider/provider.dart';

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
        home: const AuthWrapper(), // Utilisez le nouveau wrapper
        routes: {
          '/login': (context) => const LoginPage(),
          '/dashboard': (context) => const DashboardPage(),
          '/forgot-pin': (context) => const ForgotPinPage(),
        },
      ),
    );
  }
}
