import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/app.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geotrack_frontend/services/background_service.dart';
import 'package:geotrack_frontend/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charger les variables d'environnement
  await dotenv.load(fileName: ".env");

  // Initialiser le service background uniquement sur les plateformes mobiles
  if (!kIsWeb) {
    await NotificationService.initialize();
    final service = FlutterBackgroundService();

    // Configuration du service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: NotificationService.CHANNEL_ID,
        initialNotificationTitle: 'GeoTrack Service',
        initialNotificationContent: 'GPS collection service in progress...',
        foregroundServiceNotificationId: NotificationService.SERVICE_NOTIFICATION_ID,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }


  runApp(const GeoTrackApp());
}


