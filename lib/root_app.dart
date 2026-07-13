import 'package:flutter/material.dart';

import 'core/alert_gateway.dart';
import 'core/attribution_agent.dart';
import 'core/local_vault.dart';
import 'core/net_sensor.dart';
import 'core/routing_api.dart';
import 'core/session_bridge.dart';
import 'stages/boot_stage.dart';

class JesterTreasureShell extends StatelessWidget {
  final LocalVault vault;
  final NetSensor netSensor;
  final AttributionAgent attribution;
  final RoutingApi routingApi;
  final AlertGateway gateway;

  const JesterTreasureShell({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.attribution,
    required this.routingApi,
    required this.gateway,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jester Treasure',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC107),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0524),
      ),
      home: BootStage(
        vault: vault,
        netSensor: netSensor,
        attribution: attribution,
        routingApi: routingApi,
        gateway: gateway,
      ),
    );
  }
}
