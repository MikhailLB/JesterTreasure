// Jester Treasure — AppsFlyer attribution + deep-link controller.
//
// Two-phase attribution acquisition (see gray_part_pitfalls §11):
//   • Phase 1 races the SDK's `waitForAttribution` (25s cap) with
//     `waitForDeepLink` (5s cap).
//   • Phase 2 — activated only when phase 1 ended without an install
//     body but the deep-link callback already delivered a real click —
//     kicks off `pollGcd(90s, 4s)` racing against another SDK wait.
//     First hit unblocks the config request.
//
// Pure organic users skip phase 2 entirely because `looksNonOrganic`
// returns false, so their startup path stays cheap.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/app_facade.dart';
import '../env/attribution_seed.dart';
import 'net_channel.dart';

class AttributionAgent {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installBody;
  Map<String, dynamic>? _deepLinkBody;
  Map<String, dynamic>? _appOpenBody;

  final Completer<Map<String, dynamic>> _installReady = Completer();
  final Completer<void> _deepLinkReady = Completer();

  bool _booted = false;

  Future<void> ignite() async {
    if (_booted) return;
    _booted = true;

    final devKey = AppFacade.analyticsKey;
    if (devKey.isEmpty) {
      // No key wired yet — fail open so the arena path still works.
      _completeInstall(<String, dynamic>{});
      _completeDeepLink();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: '',
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((dynamic data) async {
      final payload = _unwrap(data);
      final afStatus = payload['af_status']?.toString();
      if (afStatus == 'Organic') {
        await Future<void>.delayed(
          Duration(seconds: AppFacade.organicRetrySeconds),
        );
        final retry = await _pullGcdOnce();
        _installBody = retry ?? payload;
      } else {
        _installBody = payload;
      }
      _completeInstall(_installBody!);
    });

    _sdk!.onAppOpenAttribution((dynamic data) {
      _appOpenBody = _unwrap(data);
    });

    _sdk!.onDeepLinking((DeepLinkResult result) {
      try {
        final ev = result.deepLink?.clickEvent;
        if (ev != null) {
          _deepLinkBody = Map<String, dynamic>.from(ev as Map);
        }
      } catch (_) {}
      _completeDeepLink();
    });

    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _completeInstall(<String, dynamic>{});
      _completeDeepLink();
    }
  }

  Map<String, dynamic> _unwrap(dynamic raw) {
    if (raw is Map) {
      final inner = raw['payload'];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  void _completeInstall(Map<String, dynamic> body) {
    if (!_installReady.isCompleted) _installReady.complete(body);
  }

  void _completeDeepLink() {
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  // -- Waiters -------------------------------------------------------

  Future<Map<String, dynamic>> waitForInstall({int? capSeconds}) {
    final cap = capSeconds ?? AppFacade.firstLaunchAttributionSeconds;
    return _installReady.future.timeout(
      Duration(seconds: cap),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> waitForDeepLink({int? capSeconds}) {
    final cap = capSeconds ?? AppFacade.deepLinkSeconds;
    return _deepLinkReady.future
        .timeout(Duration(seconds: cap), onTimeout: () {});
  }

  Future<String?> currentUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  bool get hasInstallBody =>
      _installBody != null && _installBody!.isNotEmpty;

  bool get looksNonOrganic {
    final dl = _deepLinkBody;
    if (dl == null || dl.isEmpty) return false;
    bool notEmpty(String key) =>
        (dl[key]?.toString().isNotEmpty ?? false);
    return notEmpty('deep_link_value') ||
        notEmpty('deep_link_sub1') ||
        notEmpty('shortlink') ||
        notEmpty('af_sub1');
  }

  // -- GCD polling ---------------------------------------------------

  Future<Map<String, dynamic>?> _pullGcdOnce() async {
    if (AppFacade.analyticsKey.isEmpty) return null;
    final uid = await currentUid();
    if (uid == null || uid.isEmpty) return null;
    final appId = Platform.isIOS ? '' : AppFacade.bundleId;
    if (appId.isEmpty) return null;

    final url = composeGcdUrl(appId: appId, deviceId: uid);
    if (url.isEmpty) return null;

    try {
      final response = await netChannel
          .get(
            Uri.parse(url),
            headers: <String, String>{
              'authorization': 'Bearer ${AppFacade.analyticsKey}',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  Future<void> pollGcd({
    int maxSeconds = 90,
    int intervalSeconds = 4,
  }) async {
    if (_installReady.isCompleted) return;
    if (AppFacade.analyticsKey.isEmpty) return;

    final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
    while (!_installReady.isCompleted && DateTime.now().isBefore(deadline)) {
      final data = await _pullGcdOnce();
      if (_installReady.isCompleted) return;
      if (data != null) {
        final status = data['af_status']?.toString() ?? '';
        if (status.isNotEmpty && status != 'error') {
          _installBody = data;
          _completeInstall(data);
          return;
        }
      }
      await Future<void>.delayed(Duration(seconds: intervalSeconds));
    }
  }

  // -- Body assembly -------------------------------------------------

  Future<Map<String, dynamic>> assembleRoutingBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    if (_installBody != null) body.addAll(_installBody!);

    _deepLinkBody?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpenBody?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = (await currentUid()) ?? '';
    body['bundle_id'] = AppFacade.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = AppFacade.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final proj = AppFacade.messagingProject;
    if (proj.isNotEmpty) body['firebase_project_id'] = proj;

    if (kDebugMode) {
      debugPrint('[attribution] request body: ${jsonEncode(body)}');
    }
    return body;
  }
}
