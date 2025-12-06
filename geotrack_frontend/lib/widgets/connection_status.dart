import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectionStatus extends StatefulWidget {
  const ConnectionStatus({super.key});

  @override
  ConnectionStatusState createState() => ConnectionStatusState();
}

class ConnectionStatusState extends State<ConnectionStatus> {
  final Connectivity _connectivity = Connectivity();
  ConnectivityResult _connectionStatus = ConnectivityResult.none;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _initConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    setState(() {
      _connectionStatus = result;
    });
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    setState(() {
      _connectionStatus = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color:
          _connectionStatus == ConnectivityResult.none
              ? Colors.orange
              : Colors.green,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _connectionStatus == ConnectivityResult.none
                ? Icons.signal_wifi_off
                : Icons.wifi,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            _connectionStatus == ConnectivityResult.none
                ? 'Offline Mode'
                : 'Online',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
