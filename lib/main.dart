import 'dart:async';

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

  // Start the FCM pipeline early; token is optional for the first config
  // request (arrives on next launch or on rotate).
  unawaited(gateway.ignite());

  runApp(JesterTreasureShell(
    vault: vault,
    netSensor: netSensor,
    attribution: attribution,
    routingApi: routingApi,
    gateway: gateway,
  ));
}
