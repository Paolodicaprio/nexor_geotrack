class Config {
  final int collectionInterval; // en secondes
  final int sendInterval; // en secondes
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Config({
    required this.collectionInterval,
    required this.sendInterval,
    this.createdAt,
    this.updatedAt,
  });

  factory Config.fromJson(Map<String, dynamic> json) {
    return Config(
      collectionInterval: json['collection_interval'],
      sendInterval: json['send_interval'],
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : null,
      updatedAt:
          json['updated_at'] != null
              ? DateTime.parse(json['updated_at'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collection_interval': collectionInterval,
      'send_interval': sendInterval,
    };
  }
}
