# GeoTrack Frontend

Flutter application for GPS tracking with offline capabilities.

## Features

- User authentication with JWT
- GPS location tracking
- Offline data storage
- Automatic synchronization
- Real-time connection status

## Setup

1. Install Flutter SDK
2. Clone the repository
3. Install dependencies:
   ```bash
   flutter pub get
4. Run:
  ```bash
   Flutter run
3. Pour le buid apk l'emplacement se trouve à:
   ```bash
   Built build\app\outputs\flutter-apk\app-release.apk

## When building apk for Mobile Device Management (MDM)

Always use the build_prod.sh script to build the apk for MDM and ensure to build with (may need to update the script):
- the same signature as the previous build
- a greater version code and version name than the previous build

```bash
./build_prod.sh
```

At the date of this writing, the build_prod.sh the version name is 1.0.7 and the version code is 26012323. 

