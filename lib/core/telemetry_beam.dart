// Jester Treasure — crash-safe Microsoft Clarity facade.
//
// Clarity records the NATIVE Flutter surface (BootStage, AlertPromo,
// Tempest, arena screens, and the WebView CONTAINER). The DOM INSIDE
// the WebView is NOT captured — the funnel signals that answer "where
// did the paid user drop off?" come from custom events + tags we emit
// from the injected JS probe (see [PortalStage]).
//
// Design rules:
//   • Every SDK call is guarded — a Clarity failure MUST NOT propagate
//     into the gray flow. Analytics is best-effort.
//   • Event names are STABLE and low-cardinality; high-cardinality
//     data (urls, hosts, error text) goes into tags, not event names.
//   • [identify] is called once af_id is known so the whole session is
//     grouped by acquired user for post-hoc slicing.

import 'package:clarity_flutter/clarity_flutter.dart';

import '../env/telemetry_env.dart';

class TelemetryBeam {
  const TelemetryBeam._();

  static ClarityConfig get workspaceConfig => ClarityConfig(
        projectId: kClarityWorkspaceId,
        // LogLevel.None in release. Flip to Verbose to debug a fresh
        // workspace — the SDK will then print 204/400/etc. transport
        // codes so you can confirm delivery.
        logLevel: LogLevel.None,
      );

  /// Group the session by AppsFlyer id + attach attribution tags.
  /// No-op on an empty id so a late-arriving af_id never overwrites a
  /// good one that was already sent.
  static void bindUser(String? aid, {Map<String, String> tags = const {}}) {
    if (aid != null && aid.isNotEmpty) {
      _shield(() => Clarity.setCustomUserId(_clip(aid, 255)));
      writeTag('aid', aid);
    }
    tags.forEach(writeTag);
  }

  /// Marks the current native surface AND fires a stable event for it.
  static void enterSurface(String name) {
    surfaceName(name);
    fireEvent('surface_$name');
  }

  /// Sets the current-screen label + mirrors it into a persistent
  /// `last_surface` tag. Clarity keeps the LAST tag value per session,
  /// so filtering by `last_surface` immediately shows where the user
  /// dropped off.
  static void surfaceName(String name) => _shield(() {
        final v = _clip(name, 255);
        Clarity.setCurrentScreenName(v);
        Clarity.setCustomTag('last_surface', v);
      });

  static void fireEvent(String name) =>
      _shield(() => Clarity.sendCustomEvent(_clip(name, 254)));

  static void writeTag(String key, String value) {
    if (value.isEmpty) return;
    _shield(() => Clarity.setCustomTag(key, _clip(value, 255)));
  }

  static String _clip(String v, int max) =>
      v.length <= max ? v : v.substring(0, max);

  static void _shield(void Function() body) {
    try {
      body();
    } catch (_) {
      // Clarity failure MUST never crash the gray flow.
    }
  }
}
