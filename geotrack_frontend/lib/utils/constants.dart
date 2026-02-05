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
  static const int syncedLimit = 100; // le nombre de données synchronisées à garder
  static const int pendingLimit = 6000; // le nombre de données non synchronisées à garder

  // HTTP Retry Configuration
  static const int httpRetryBaseSeconds = 4; // Base for exponential backoff (4^n)
  static const int httpRetryMaxSeconds = 65; // Max backoff before long wait
  static const int httpRetryLongWaitMinutes = 30; // Long wait after max retries
  static const int httpMaxRetryAttempts = 3; // Max retry attempts before long wait

  // GPS Batch Sync Configuration
  static const int gpsBatchChunkSize = 500; // Max items per sync request (for 413 handling)
  static const int gpsBatchChunkSizeOnPayloadTooLarge = 100; // Smaller chunk size when 413 occurs
}
