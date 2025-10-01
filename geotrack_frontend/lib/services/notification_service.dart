import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static const int SERVICE_NOTIFICATION_ID = 888;
  static const String CHANNEL_ID = 'geotrack_channel';

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notifications.initialize(initializationSettings);

    // Créer le canal de notification pour Android 15
    await createNotificationChannel();
  }

  static Future<void> createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      CHANNEL_ID,
      'GeoTrack Service',
      description: 'Canal pour les notifications du service GeoTrack',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Notification persistante du service
  static Future<void> showPersistentNotification({
    required String title,
    required String content,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      CHANNEL_ID,
      'GeoTrack Service',
      channelDescription: 'Service de collecte GPS en arrière-plan',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority  ,
      ongoing: true, // Notification persistante
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      showWhen: true,
      usesChronometer: false,
      showProgress: false,
      icon: '@mipmap/ic_launcher', // Utilise l'icône de l'app
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notifications.show(
      SERVICE_NOTIFICATION_ID,
      title,
      content,
      platformChannelSpecifics,
    );
  }

  // Notification temporaire pour les événements
  static Future<void> showTemporaryNotification({
    required String title,
    required String content,
    int? id,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      CHANNEL_ID,
      'GeoTrack Événements',
      channelDescription: 'Notifications pour les événements GeoTrack',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notifications.show(
      id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      content,
      platformChannelSpecifics,
    );
  }

  // Notification avec barre de progression
  static Future<void> showProgressNotification({
    required String title,
    required String content,
    required int progress,
    required int maxProgress,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      CHANNEL_ID,
      'GeoTrack Progress',
      channelDescription: 'Progression des tâches GeoTrack',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      showWhen: false,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      indeterminate: false,
    );

    final NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notifications.show(
      SERVICE_NOTIFICATION_ID + 1, // ID différent pour éviter les conflits
      title,
      content,
      platformChannelSpecifics,
    );
  }

  // Annuler une notification spécifique
  static Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  // Annuler toutes les notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}