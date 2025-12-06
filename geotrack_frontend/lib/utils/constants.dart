class Constants {
  // Changer l'URL pour pointer vers votre API GeoTrack
  static const String apiBaseUrl = 'https://portal.inma.ucl.ac.be/geotrack';

  // Storage keys
  static const String authTokenKey = 'auth_token';
  static const String pendingDataKey = 'pending_gps_data';
  static const String apiUrlKey = 'api_url';
  static const String syncIntervalKey = 'sync_interval';

  // Default values
  static const int defaultSyncInterval = 5; // minutes
}
