// Jester Treasure — shell-level routing bridge for push URLs.
//
// [PortalStage.onWarmLink] handles the case where a push arrives while
// the user is already inside the WebView. But a push can also arrive
// during any of the OTHER stages — BootStage while attribution is still
// resolving, AlertPromoStage before Accept/Skip, TempestStage while
// waiting for the network, or the native arena. Without a shell-level
// fallback the warm-tap URL is silently dropped.
//
// This bridge:
//   • Owns the root [NavigatorState] via [rootNavigatorKey] so it can
//     push a route from anywhere without a BuildContext.
//   • Exposes [launchPortal] which sanitises the URL, opens (or
//     re-opens) [PortalStage] via `pushAndRemoveUntil`, and gracefully
//     degrades to persisting the URL as a cold-tap payload if the
//     navigator is not yet available.
//
// The bridge is [seed]ed once from `main.dart` before `runApp` and
// is idempotent thereafter.

import 'package:flutter/material.dart';

import '../stages/portal_stage.dart';
import 'alert_gateway.dart';
import 'link_hygiene.dart';
import 'local_vault.dart';
import 'net_sensor.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class SessionBridge {
  SessionBridge._();

  static LocalVault? _vault;
  static NetSensor? _netSensor;
  static AlertGateway? _gateway;

  static void seed({
    required LocalVault vault,
    required NetSensor netSensor,
    required AlertGateway gateway,
  }) {
    _vault = vault;
    _netSensor = netSensor;
    _gateway = gateway;
  }

  /// Attempts to route the incoming URL to a fresh [PortalStage].
  /// If the navigator has not mounted yet, or the URL fails the
  /// sanitiser, the URL is persisted as a cold-tap payload so that the
  /// next call to [BootStage] picks it up.
  static Future<void> launchPortal(String rawUrl) async {
    final vault = _vault;
    final netSensor = _netSensor;
    final gateway = _gateway;
    if (vault == null || netSensor == null || gateway == null) return;

    final uri = sanitiseInboundLink(rawUrl);
    if (uri == null) return;

    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      // Navigator not attached (e.g. deep-tap during first-frame boot).
      // Fall back to cold-tap persistence — the next BootStage read
      // will resume the flow with this URL.
      await vault.writeColdTapLink(uri.toString());
      return;
    }

    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => PortalStage(
          url: uri.toString(),
          vault: vault,
          gateway: gateway,
          netSensor: netSensor,
        ),
      ),
      (route) => false,
    );
  }
}
