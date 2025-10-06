import 'package:uuid/uuid.dart';

class GpsData {
  final String? id;
  final double lat;
  final double lon;
  final DateTime timestamp;
  final bool? synced;
  final DateTime? createdAt;

  GpsData({
    String? id,
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.synced,
    this.createdAt,
  }) : id = id ?? const Uuid().v4();

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      id: json['id']?.toString(),
      lat: json['lat']?.toDouble() ?? json['latitude']?.toDouble() ?? 0.0,
      lon: json['lon']?.toDouble() ?? json['longitude']?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] ?? json['datetime']),
      synced: json['synced'],
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': lat,
      'lon': lon,
      'timestamp': timestamp.toIso8601String(),
      'synced': synced,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  // Pour l'envoi à l'API
  Map<String, dynamic> toApiJson() {
    return {
      'latitude': lat,
      'longitude': lon,
      'timestamp': timestamp.toUtc().toIso8601String().split('.').first+'Z',
    };
  }

  GpsData copyWith({bool? synced}) {
    return GpsData(
      id: id,
      lat: lat,
      lon: lon,
      timestamp: timestamp,
      synced: synced ?? this.synced,
      createdAt: createdAt,
    );
  }
}
