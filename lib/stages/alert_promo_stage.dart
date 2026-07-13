// Jester Treasure — push permission promo screen.
//
// Full-screen artwork with two overlaid buttons: primary "Accept"
// (asks for the OS permission) and secondary "Skip" (snoozes the promo
// for the configured cooldown). Once the user picks, the stage
// self-navigates to the portal — the router is never re-entered so
// there is no risk of an orphaned `mounted=false` closure blocking the
// hand-off (that was the "Accept freezes the app" bug in the first cut).

import 'package:flutter/material.dart';

import '../core/alert_gateway.dart';
import '../core/local_vault.dart';
import '../core/net_sensor.dart';
import '../env/app_facade.dart';
import 'portal_stage.dart';

class AlertPromoStage extends StatefulWidget {
  final LocalVault vault;
  final AlertGateway gateway;
  final NetSensor netSensor;
  final String portalUrl;

  const AlertPromoStage({
    super.key,
    required this.vault,
    required this.gateway,
    required this.netSensor,
    required this.portalUrl,
  });

  @override
  State<AlertPromoStage> createState() => _AlertPromoStageState();
}

class _AlertPromoStageState extends State<AlertPromoStage> {
  bool _handling = false;

  Future<void> _onAccept() async {
    if (_handling) return;
    setState(() => _handling = true);
    try {
      final granted = await widget.gateway.askOsPermission();
      if (!granted) {
        await _snooze();
      }
    } catch (_) {
      // Even if the request throws (Firebase not configured, etc.), we
      // MUST still forward the user to the portal.
    }
    if (!mounted) return;
    await _forwardToPortal();
  }

  Future<void> _onSkip() async {
    if (_handling) return;
    setState(() => _handling = true);
    await _snooze();
    if (!mounted) return;
    await _forwardToPortal();
  }

  Future<void> _snooze() async {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        AppFacade.alertPromoSnoozeSeconds;
    await widget.vault.stampPromoSnooze(until);
  }

  Future<void> _forwardToPortal() async {
    await primePortalEngine();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PortalStage(
          url: widget.portalUrl,
          vault: widget.vault,
          gateway: widget.gateway,
          netSensor: widget.netSensor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final backdrop = isLandscape
        ? 'assets/Horizontal_Notification_GREY.webp'
        : 'assets/Vertical_Notification_GREY.webp';

    // Same width for Accept and Skip; landscape uses a much smaller
    // fraction so the plaques don't dominate the artwork.
    final buttonWidth = isLandscape ? size.width * 0.26 : size.width * 0.62;

    return Scaffold(
      backgroundColor: const Color(0xFF10061F),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              backdrop,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF10061F)),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const <double>[0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: isLandscape ? size.height * 0.06 : size.height * 0.09,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: buttonWidth,
                    child: _GemPlaque(
                      text: 'ACCEPT',
                      compact: isLandscape,
                      disabled: _handling,
                      onTap: _onAccept,
                      tone: _PlaqueTone.gold,
                    ),
                  ),
                  SizedBox(height: isLandscape ? 8 : 12),
                  SizedBox(
                    width: buttonWidth,
                    child: _GemPlaque(
                      text: 'SKIP',
                      compact: isLandscape,
                      disabled: _handling,
                      onTap: _onSkip,
                      tone: _PlaqueTone.slate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlaqueTone { gold, slate }

class _GemPlaque extends StatefulWidget {
  final String text;
  final bool compact;
  final bool disabled;
  final VoidCallback onTap;
  final _PlaqueTone tone;

  const _GemPlaque({
    required this.text,
    required this.compact,
    required this.disabled,
    required this.onTap,
    required this.tone,
  });

  @override
  State<_GemPlaque> createState() => _GemPlaqueState();
}

class _GemPlaqueState extends State<_GemPlaque> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isGold = widget.tone == _PlaqueTone.gold;
    final gradientColors = isGold
        ? const <Color>[
            Color(0xFFFFF3B0),
            Color(0xFFFFC633),
            Color(0xFFA05008),
          ]
        : const <Color>[
            Color(0xFF6A506D),
            Color(0xFF2E1B39),
            Color(0xFF0F0619),
          ];
    final borderColor =
        isGold ? const Color(0xFFFFF7CF) : const Color(0xFFB78BE0);
    final textColor = isGold ? const Color(0xFF20100C) : Colors.white;
    final vPad = widget.compact ? 10.0 : 16.0;
    final fontSize = widget.compact ? 14.0 : (isGold ? 20.0 : 17.0);
    final gemSize = widget.compact ? 7.0 : 10.0;

    return Opacity(
      opacity: widget.disabled ? 0.55 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (widget.disabled) return;
          setState(() => _pressed = true);
        },
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          if (widget.disabled) return;
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: vPad),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradientColors,
              ),
              border: Border.all(color: borderColor, width: 2.5),
              borderRadius: const BorderRadius.all(Radius.circular(22)),
              boxShadow: <BoxShadow>[
                if (isGold)
                  const BoxShadow(
                    color: Color(0x99FFB300),
                    blurRadius: 20,
                    spreadRadius: 1,
                    offset: Offset(0, 5),
                  )
                else
                  const BoxShadow(
                    color: Color(0x77000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CornerGem(
                  size: gemSize,
                  color: isGold
                      ? const Color(0xFF7A1B12)
                      : const Color(0xFFB78BE0),
                ),
                SizedBox(width: widget.compact ? 8 : 12),
                Text(
                  widget.text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: widget.compact ? 1.6 : 2.2,
                  ),
                ),
                SizedBox(width: widget.compact ? 8 : 12),
                _CornerGem(
                  size: gemSize,
                  color: isGold
                      ? const Color(0xFF187B23)
                      : const Color(0xFFB78BE0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerGem extends StatelessWidget {
  final double size;
  final Color color;
  const _CornerGem({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.65),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
