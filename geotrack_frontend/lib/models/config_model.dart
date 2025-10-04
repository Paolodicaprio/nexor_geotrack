import '../utils/constants.dart';

class Config {
  final int id;
  final int collectionInterval; //en seconde
  final int sendInterval;       // en seconde
  final int configSyncInterval; // en minute

  Config({
    required this.id,
    required this.collectionInterval,
    required this.sendInterval,
    required this.configSyncInterval

  });
  factory Config.fromDefault(){
    return Config(
      id: 0,
      collectionInterval: Constants.defaultCollectionInterval,
      sendInterval: Constants.defaultSendInterval,
      configSyncInterval: Constants.defaultConfigSyncInterval
    );
  }

  factory Config.fromJson(Map<String, dynamic> json) {
    return Config(
      id: json['id'] ?? 0,
      collectionInterval: json['position_sampling_interval'] ?? Constants.defaultCollectionInterval,
      sendInterval: json['position_sync_interval'] ?? Constants.defaultSendInterval,
      configSyncInterval: json['config_sync_interval'] ?? Constants.defaultConfigSyncInterval
    );
  }
}
