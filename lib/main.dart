import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/alert_gateway.dart';
import 'core/attribution_agent.dart';
import 'core/local_vault.dart';
import 'core/net_channel.dart';
import 'core/net_sensor.dart';
import 'core/routing_api.dart';
import 'core/session_bridge.dart';
import 'root_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + AppCheck — best-effort. The gray flow still works if the
  // Firebase project has not been wired yet (the config endpoint just
  // won't receive `push_token` / `firebase_project_id`).
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  // Allow every orientation. Individual stages tighten this if needed
  // (arena locks to portrait via MenuScreen when the game starts).
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await netChannel.boot();

  final vault = LocalVault();
  await vault.warmUp();

  final netSensor = NetSensor();
  final attribution = AttributionAgent();
  final routingApi = RoutingApi(vault);
  final gateway = AlertGateway(vault);

  // Register the shell-level fallback for warm push taps BEFORE we
  // ignite the FCM pipeline. If a background push arrives during boot,
  // it will land in this handler and either open the portal directly
  // (once the navigator is up) or persist the URL as a cold-tap
  // payload for the next BootStage pass.
  SessionBridge.seed(vault: vault, netSensor: netSensor, gateway: gateway);
  gateway.onWarmLink = SessionBridge.launchPortal;

  // Shell-level token beacon. BootStage used to own `onTokenRotate`
  // and null it out on dispose — meaning any post-boot token arrival
  // (first getToken after offline boot, an FCM-driven rotation, an
  // OS restore, etc.) was silently dropped and the backend never
  // learnt the device address. The device was then invisible to FCM
  // and no push ever reached it. Install the handler at shell scope
  // so it survives every stage transition.
  bool tokenSyncInFlight = false;
  String? lastSyncedToken;
  Future<void> syncTokenToBackend(String token) async {
    if (token.isEmpty) return;
    if (tokenSyncInFlight) return;
    if (lastSyncedToken == token) return;
    tokenSyncInFlight = true;
    try {
      await attribution.ignite();
      final locale = Platform.localeName.replaceAll('-', '_');
      final body = await attribution.assembleRoutingBody(
        locale: locale,
        pushToken: token,
      );
      await routingApi.dispatch(body);
      lastSyncedToken = token;
    } catch (_) {
      // Non-fatal — will be retried on the next connectivity tick.
    } finally {
      tokenSyncInFlight = false;
    }
  }

  gateway.onTokenRotate = (token) {
    unawaited(syncTokenToBackend(token));
  };

  // Await [ignite] so `getInitialMessage` has actually returned before
  // BootStage starts checking the vault for a cold-tap URL. Otherwise
  // a fresh cold-start push tap races the router and gets missed.
  //
  // ignite() only awaits the OFFLINE-safe phase; the network phase
  // (getToken / getInitialMessage) is dispatched inside and retried
  // once the shell observes connectivity via `statusStream` below.
  try {
    await gateway.ignite().timeout(const Duration(seconds: 4));
  } catch (_) {
    // Firebase or FCM not reachable — arena / portal flow still works
    // without push, so we swallow and keep going.
  }

  // Whenever the OS reports at least one live interface, retry the
  // network-dependent parts of the FCM pipeline. Idempotent — after
  // the first successful token pull this is essentially free.
  netSensor.statusStream.listen((results) {
    final isLive = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn ||
        r == ConnectivityResult.bluetooth ||
        r == ConnectivityResult.other);
    if (isLive) {
      unawaited(gateway.reattemptWithNetwork().then((_) {
        // If a token is already cached but the backend never received
        // it (e.g. the previous dispatch happened while offline), push
        // it now that the network is back.
        final t = gateway.pushToken;
        if (t != null && t.isNotEmpty && lastSyncedToken != t) {
          unawaited(syncTokenToBackend(t));
        }
      }));
    }
  });

  runApp(JesterTreasureShell(
    vault: vault,
    netSensor: netSensor,
    attribution: attribution,
    routingApi: routingApi,
    gateway: gateway,
  ));
}
