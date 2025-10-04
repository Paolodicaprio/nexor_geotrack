class Constants {
  static const String apiBaseUrl = 'http://10.0.2.2:8000'; // Android emulator
  // static const String apiBaseUrl = 'http://localhost:8000'; // iOS simulator
  // static const String apiBaseUrl = 'http://192.168.x.x:8000'; // Physical device

  // Storage keys
  static const String authTokenKey = 'auth_token';
  static const String pendingDataKey = 'pending_gps_data';
  static const String apiUrlKey = 'api_url';
  static const String syncIntervalKey = 'sync_interval';

  // Default values
  // static const int defaultSyncInterval = 5; // minutes
  static const int defaultConfigSyncInterval = 180; //minutes
  static const int defaultCollectionInterval = 60; //seconds
  static const int defaultSendInterval = 300; //seconds
}
