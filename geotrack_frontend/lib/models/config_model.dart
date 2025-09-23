class Config {
  final int id;
  final int collectionInterval;
  final int sendInterval;
  final DateTime createdAt;
  final DateTime updatedAt;

  Config({
    required this.id,
    required this.collectionInterval,
    required this.sendInterval,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Config.fromJson(Map<String, dynamic> json) {
    return Config(
      id: json['id'] ?? 0,
      collectionInterval: json['collection_interval'] ?? 300,
      sendInterval: json['send_interval'] ?? 600,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
