import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
part 'gps_data_model.g.dart';

@collection
class GpsData {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  final String? uuid;

  final double lat;

  final double lon;

  @Index()
  final DateTime timestamp;

  @Index()
  final bool synced;

  final DateTime? createdAt;

  GpsData({
    this.id = Isar.autoIncrement,
    String? uuid,
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.synced = false,
    this.createdAt,
  }): uuid = uuid ?? const Uuid().v4();

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      uuid: json['id']?.toString(),
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
      'id': uuid,
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
      uuid: uuid,
      lat: lat,
      lon: lon,
      timestamp: timestamp,
      synced: synced ?? this.synced,
      createdAt: createdAt,
    );
  }
}
