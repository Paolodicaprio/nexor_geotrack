class Config {
  final int collectionInterval;
  final int sendInterval;
  final String deviceId;

  Config({
    required this.collectionInterval,
    required this.sendInterval,
    required this.deviceId,
  });

  factory Config.fromJson(Map<String, dynamic> json) {
    return Config(
      collectionInterval: json['collection_interval'] ?? 300,
      sendInterval: json['send_interval'] ?? 600,
      deviceId: json['device_id'] ?? 'mobile-device',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collection_interval': collectionInterval,
      'send_interval': sendInterval,
      'device_id': deviceId,
    };
  }
}
