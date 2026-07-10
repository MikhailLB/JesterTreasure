// Jester Treasure — connectivity oracle.
//
// Whitelists VPN, Bluetooth, and "other" as valid interfaces so that
// tunnelled traffic (paid users on cheap VPNs) doesn't trip the No-WiFi
// screen. DNS probe timeout is 7 s to survive slow tunnels.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

const Set<ConnectivityResult> _liveInterfaces = <ConnectivityResult>{
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

class NetSensor {
  final Connectivity _connectivity = Connectivity();
  final List<String> _probeHosts = const <String>[
    'www.google.com',
    'cloudflare.com',
    'apple.com',
  ];

  Stream<List<ConnectivityResult>> get statusStream =>
      _connectivity.onConnectivityChanged;

  Future<bool> hasLiveInterface() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any(_liveInterfaces.contains);
    } catch (_) {
      return false;
    }
  }

  Future<bool> canReachInternet() async {
    if (!await hasLiveInterface()) return false;
    for (final host in _probeHosts) {
      try {
        final answers = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 7));
        if (answers.isNotEmpty && answers.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return false;
  }
}
