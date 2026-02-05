# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Isar database classes
-keep class dev.isar.** { *; }

# Keep Geolocator classes
-keep class com.baseflow.geolocator.** { *; }

# Keep background service classes
-keep class id.flutter.flutter_background_service.** { *; }
