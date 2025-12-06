class GpsData {
  final int? id;
  final String idname; // deviceId dans l'API
  final double latitude; // lat dans l'API
  final double longitude; // lon dans l'API
  final DateTime datetime; // timestamp
  final DateTime? createdAt;
  final bool? synced;

  GpsData({
    this.id,
    required this.idname,
    required this.latitude,
    required this.longitude,
    required this.datetime,
    this.createdAt,
    this.synced,
  });

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      id: json['id']?.toInt(),
      idname: json['idname'] ?? json['device_id'] ?? 'UNKNOWN',
      // Accepter les deux formats
      latitude: (json['latitude'] ?? json['lat'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? json['lon'] ?? 0.0).toDouble(),
      datetime:
          json['datetime'] != null
              ? DateTime.parse(json['datetime'])
              : DateTime.now(),
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : null,
      synced: json['synced'] ?? true,
    );
  }

  // Pour l'envoi, utiliser une méthode intelligente
  Map<String, dynamic> toApiJson({bool useLatLon = false}) {
    if (useLatLon) {
      return {
        'idname': idname,
        'lat': latitude,
        'lon': longitude,
        'datetime': datetime.toIso8601String(),
      };
    } else {
      return {
        'idname': idname,
        'latitude': latitude,
        'longitude': longitude,
        'datetime': datetime.toIso8601String(),
      };
    }
  }

  // Pour le stockage local
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'idname': idname,
      'latitude': latitude,
      'longitude': longitude,
      'datetime': datetime.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'synced': synced ?? false,
    };
  }

  GpsData copyWith({
    int? id,
    String? idname,
    double? latitude,
    double? longitude,
    DateTime? datetime,
    DateTime? createdAt,
    bool? synced,
  }) {
    return GpsData(
      id: id ?? this.id,
      idname: idname ?? this.idname,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      datetime: datetime ?? this.datetime,
      createdAt: createdAt ?? this.createdAt,
      synced: synced ?? this.synced,
    );
  }
}
