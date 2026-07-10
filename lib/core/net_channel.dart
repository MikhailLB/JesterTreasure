// Jester Treasure — outbound HTTP channel + real-device User-Agent.
//
// Every outbound request from the gray flow (config POST, GCD retry,
// image download for BigPicture push) goes through this client so that
// the User-Agent header matches a real Android Chrome build. Attribution
// backends fingerprint UA strings — a naked Dart HTTP UA would spike as
// anomalous.
//
// The Chromium / WebKit build fragments are XOR-scrambled bytes so that
// static analysis of the APK will not surface an obvious version string.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../env/app_facade.dart';
import '../env/cipher.dart';

// -- UA fragment vaults (minted via tool/mint_secrets.dart) --------

const List<int> _uaChromeFragmentBytes = <int>[
  0x81, 0x65, 0x6b, 0x60, 0x16, 0x8a, 0xac, 0xbd, 0x91, 0x97, 0x83, 0x14,
  0x9f, 0xf0,
];

const List<int> _uaWebkitFragmentBytes = <int>[
  0x85, 0x62, 0x65, 0x60, 0x15, 0x92,
];

String _chromeFragment() {
  if (_uaChromeFragmentBytes.isEmpty) return '132.0.6834.163';
  final v = unveil(_uaChromeFragmentBytes);
  return v.isEmpty ? '132.0.6834.163' : v;
}

String _webkitFragment() {
  if (_uaWebkitFragmentBytes.isEmpty) return '537.36';
  final v = unveil(_uaWebkitFragmentBytes);
  return v.isEmpty ? '537.36' : v;
}

/// Base UA (no `appid` / `appname` suffix). Kept public so the WebView
/// controller and the HTTP layer can share the exact same fingerprint.
String _forgeBaseUa({
  required String androidSdk,
  required String brand,
  required String model,
  required String build,
}) {
  return 'Mozilla/5.0 (Linux; Android $androidSdk; $brand $model '
      'Build/$build) AppleWebKit/${_webkitFragment()} (KHTML, like Gecko) '
      'Chrome/${_chromeFragment()} Mobile Safari/${_webkitFragment()}';
}

String _forgeIosUa(String iosVersion) {
  final under = iosVersion.replaceAll('.', '_');
  final wk = _webkitFragment();
  return 'Mozilla/5.0 (iPhone; CPU iPhone OS $under like Mac OS X) '
      'AppleWebKit/$wk (KHTML, like Gecko) '
      'Version/$iosVersion Mobile/15E148 Safari/$wk';
}

class NetChannel extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _ua;

  Future<void> boot() async {
    if (_ua != null) return;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final display = info.display.isNotEmpty
            ? info.display
            : (info.id.isNotEmpty ? info.id : 'AP3A.240905.015.A2');
        _ua = _forgeBaseUa(
          androidSdk: info.version.release,
          brand: info.brand,
          model: info.model,
          build: display,
        );
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _ua = _forgeIosUa(info.systemVersion);
      }
    } catch (_) {
      // fall through to fallback
    }
    _ua ??= _forgeBaseUa(
      androidSdk: '15',
      brand: 'samsung',
      model: 'SM-S931U',
      build: 'AP3A.240905.015.A2',
    );
  }

  /// Full UA (with the required `appid/appname` suffix as demanded by the
  /// product spec). Everything outbound — HTTP client, WebView, big-picture
  /// image download — MUST use this so the fingerprint stays consistent.
  String get userAgent {
    final base = _ua ?? _forgeBaseUa(
      androidSdk: '15',
      brand: 'samsung',
      model: 'SM-S931U',
      build: 'AP3A.240905.015.A2',
    );
    return '$base appid/${AppFacade.bundleId} '
        'appname/${AppFacade.appIdentityTag}';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    request.headers.putIfAbsent('Accept-Language', () => 'en-US,en;q=0.9');
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Shared singleton — must be `boot()`ed before any dependant service
/// dispatches a request.
final NetChannel netChannel = NetChannel();
