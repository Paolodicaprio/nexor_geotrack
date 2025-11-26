import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gps_data_model.dart';

class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = openDB();
  }

  Future<Isar> openDB() async {
    // Si une instance est déjà ouverte dans cet isolate, on la retourne
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      return await Isar.open(
        [GpsDataSchema], // Le schéma généré
        directory: dir.path,
        inspector: false,
      );
    }
    return Future.value(Isar.getInstance());
  }
}