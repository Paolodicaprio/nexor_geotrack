class Config {
  final int id;
  final int collectionInterval;
  final int sendInterval;

  Config({
    required this.id,
    required this.collectionInterval,
    required this.sendInterval,

  });

  factory Config.fromJson(Map<String, dynamic> json) {
    return Config(
      id: json['id'] ?? 0,
      collectionInterval: json['position_sampling_interval'] ?? 300,
      sendInterval: json['position_sync_interval'] ?? 600,
    );
  }
}
