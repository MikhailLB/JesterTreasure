// Jester Treasure — boot / router stage.
//
// Presents the loading artwork (portrait AND landscape variants) with
// the horizontal progress bar and animated "Loading..." caption; while
// the user watches, it decides between the portal (WebView) and the
// arena (native game) using the routing endpoint verdict.
//
// The bar has three visible checkpoints:
//   • 0.00 → boot start
//   • 0.35 → attribution SDK finished bootstrapping
//   • 0.90 → routing verdict about to be dispatched
//   • 1.00 → about to hand off (portal OR arena)
//
// The bar climbs smoothly between checkpoints via a `Ticker` so it never
// looks stuck.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/alert_gateway.dart';
import '../core/attribution_agent.dart';
import '../core/link_hygiene.dart';
import '../core/local_vault.dart';
import '../core/net_sensor.dart';
import '../core/routing_api.dart';
import '../data/route_mode.dart';
import '../data/routing_verdict.dart';
import '../env/app_facade.dart';
import '../screens/menu_screen.dart' as arena;
import 'alert_promo_stage.dart';
import 'portal_stage.dart';
import 'tempest_stage.dart';

class BootStage extends StatefulWidget {
  final LocalVault vault;
  final NetSensor netSensor;
  final AttributionAgent attribution;
  final RoutingApi routingApi;
  final AlertGateway gateway;

  const BootStage({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.attribution,
    required this.routingApi,
    required this.gateway,
  });

  @override
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _uiTicker;
  double _barTarget = 0.0;
  double _barShown = 0.0;
  int _dots = 0;
  Timer? _dotsTimer;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _uiTicker = createTicker(_animateBar)..start();
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots + 1) % 4);
    });
    widget.gateway.onTokenRotate = _handleTokenRotate;
    _drive();
  }

  @override
  void dispose() {
    widget.gateway.onTokenRotate = null;
    _uiTicker.dispose();
    _dotsTimer?.cancel();
    super.dispose();
  }

  void _animateBar(Duration _) {
    if (!mounted) return;
    // Keep a continuous left→right drift towards the current checkpoint;
    // the delta rate (12%) is fast enough that the bar visibly grows
    // instead of looking stuck between checkpoints.
    final gap = _barTarget - _barShown;
    if (gap.abs() < 0.001) return;
    final step = gap * 0.12;
    setState(() {
      _barShown = (_barShown + step).clamp(0.0, 1.0);
    });
  }

  void _liftBar(double v) {
    if (!mounted) return;
    setState(() => _barTarget = v.clamp(0.0, 1.0));
  }

  Future<void> _drive() async {
    // Fresh cold-tap URL takes priority over EVERYTHING (see pitfalls §12).
    final coldTap = await widget.vault.pluckColdTapLink();
    if (coldTap != null) {
      final sanitised = sanitiseInboundLink(coldTap);
      if (sanitised != null) {
        _liftBar(1.0);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        _navigateToPortal(sanitised.toString());
        return;
      }
    }

    _liftBar(0.18);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final mode = widget.vault.currentMode();
    switch (mode) {
      case RouteMode.arena:
        await _resumeArena();
        break;
      case RouteMode.portal:
        await _resumePortal();
        break;
      case RouteMode.undecided:
        await _firstLaunch();
        break;
    }
  }

  // -- First-launch flow ---------------------------------------------

  Future<void> _firstLaunch() async {
    if (!await widget.netSensor.canReachInternet()) {
      _openTempestBackToBoot();
      return;
    }
    _liftBar(0.28);

    await widget.attribution.ignite();
    _liftBar(0.4);

    await Future.wait(<Future<void>>[
      widget.attribution
          .waitForInstall(
            capSeconds: AppFacade.firstLaunchAttributionSeconds,
          )
          .then((_) {}),
      widget.attribution
          .waitForDeepLink(capSeconds: AppFacade.deepLinkSeconds),
    ]);

    // Two-phase attribution (see pitfalls §11)
    if (!widget.attribution.hasInstallBody &&
        widget.attribution.looksNonOrganic) {
      _liftBar(0.6);
      await Future.any(<Future<void>>[
        widget.attribution.pollGcd(maxSeconds: 90, intervalSeconds: 4),
        widget.attribution.waitForInstall(capSeconds: 90).then((_) {}),
      ]);
    }
    _liftBar(0.78);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.assembleRoutingBody(
      locale: locale,
      pushToken: widget.gateway.pushToken,
    );

    _liftBar(0.9);
    final verdict = await widget.routingApi.dispatch(body);

    if (verdict.ok && verdict.hasUrl) {
      await widget.vault.stampMode(RouteMode.portal);
      _liftBar(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      _navigateToPortal(verdict.url!);
    } else {
      await widget.vault.stampMode(RouteMode.arena);
      _liftBar(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      _navigateToArena();
    }
  }

  // -- Portal resume flow --------------------------------------------

  Future<void> _resumePortal() async {
    if (!await widget.netSensor.canReachInternet()) {
      _openTempestBackToBoot();
      return;
    }

    final cached = await widget.vault.cachedPortalUrl();

    _liftBar(0.3);
    await widget.attribution.ignite();
    _liftBar(0.5);

    await Future.wait(<Future<void>>[
      widget.attribution
          .waitForInstall(capSeconds: AppFacade.returningAttributionSeconds)
          .then((_) {}),
      widget.attribution
          .waitForDeepLink(capSeconds: AppFacade.deepLinkSeconds),
    ]);
    _liftBar(0.75);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.assembleRoutingBody(
      locale: locale,
      pushToken: widget.gateway.pushToken,
    );

    final verdict = await widget.routingApi.dispatch(body);
    _liftBar(1.0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final RoutingVerdict v = verdict;
    if (v.ok && v.hasUrl) {
      _navigateToPortal(v.url!);
    } else if (cached != null && cached.isNotEmpty) {
      _navigateToPortal(cached);
    } else {
      _openTempestBackToBoot();
    }
  }

  // -- Arena resume flow ---------------------------------------------

  Future<void> _resumeArena() async {
    _liftBar(0.4);
    // The arena preload lives inside MenuScreen's own bootstrap; nothing
    // extra to fetch here. Keep a subtle bar animation for polish.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _liftBar(0.75);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _liftBar(1.0);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    _navigateToArena();
  }

  // -- Token refresh -------------------------------------------------

  Future<void> _handleTokenRotate(String newToken) async {
    try {
      final locale = Platform.localeName.replaceAll('-', '_');
      final body = await widget.attribution.assembleRoutingBody(
        locale: locale,
        pushToken: newToken,
      );
      await widget.routingApi.dispatch(body);
    } catch (_) {}
  }

  // -- Navigation helpers --------------------------------------------

  void _navigateToArena() {
    if (_routed) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const arena.MenuScreen(),
      ),
    );
  }

  Future<void> _navigateToPortal(String url) async {
    if (_routed) return;
    _routed = true;

    await primePortalEngine();
    if (!mounted) return;

    if (widget.vault.shouldPresentPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AlertPromoStage(
            vault: widget.vault,
            gateway: widget.gateway,
            netSensor: widget.netSensor,
            portalUrl: url,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PortalStage(
          url: url,
          vault: widget.vault,
          gateway: widget.gateway,
          netSensor: widget.netSensor,
        ),
      ),
    );
  }

  void _openTempestBackToBoot() {
    if (_routed) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TempestStage(
          onRetry: (_) => BootStage(
            vault: widget.vault,
            netSensor: widget.netSensor,
            attribution: widget.attribution,
            routingApi: widget.routingApi,
            gateway: widget.gateway,
          ),
        ),
      ),
    );
  }

  // -- UI ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final asset = orientation == Orientation.landscape
        ? 'assets/Horizontal_Loading.webp'
        : 'assets/Vertical_Loading.webp';
    final dots = '.' * _dots + ' ' * (3 - _dots);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0524),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            asset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF0F0524)),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const <double>[0.0, 0.5, 0.8, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _JewelledBar(progress: _barShown),
                const SizedBox(height: 14),
                Text(
                  'Loading$dots',
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JewelledBar extends StatelessWidget {
  final double progress;
  const _JewelledBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F), width: 2.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      // Explicit Align + FractionallySizedBox pins the fill to the
      // start edge (left in LTR) so the bar unambiguously grows
      // left→right regardless of parent constraints.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: clamped,
          heightFactor: 1.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0xFFFFF176),
                  Color(0xFFFFC107),
                  Color(0xFFFF8F00),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
