// Jester Treasure — push permission promo screen.
//
// Full-screen artwork with two overlaid buttons: primary "Accept"
// (asks for the OS permission), secondary "Skip" (snoozes the promo
// for the configured cooldown). The button visuals intentionally differ
// from every other project's version — twin gemstone plaques rather
// than the pill+text-link pattern used elsewhere.

import 'package:flutter/material.dart';

import '../core/alert_gateway.dart';
import '../core/local_vault.dart';
import '../env/app_facade.dart';

typedef PromoResolver = Future<void> Function();

class AlertPromoStage extends StatefulWidget {
  final LocalVault vault;
  final AlertGateway gateway;
  final PromoResolver onResolved;

  const AlertPromoStage({
    super.key,
    required this.vault,
    required this.gateway,
    required this.onResolved,
  });

  @override
  State<AlertPromoStage> createState() => _AlertPromoStageState();
}

class _AlertPromoStageState extends State<AlertPromoStage> {
  bool _handling = false;

  Future<void> _onAccept() async {
    if (_handling) return;
    setState(() => _handling = true);
    final granted = await widget.gateway.askOsPermission();
    if (!granted) {
      await _snooze();
    }
    if (!mounted) return;
    await widget.onResolved();
  }

  Future<void> _onSkip() async {
    if (_handling) return;
    setState(() => _handling = true);
    await _snooze();
    if (!mounted) return;
    await widget.onResolved();
  }

  Future<void> _snooze() async {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        AppFacade.alertPromoSnoozeSeconds;
    await widget.vault.stampPromoSnooze(until);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final backdrop = isLandscape
        ? 'assets/Horizontal_Notification_GREY.webp'
        : 'assets/Vertical_Notification_GREY.webp';

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
              errorBuilder: (_, __, ___) =>
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
            _ButtonDock(
              landscape: isLandscape,
              width: size.width,
              height: size.height,
              handling: _handling,
              onAccept: _onAccept,
              onSkip: _onSkip,
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonDock extends StatelessWidget {
  final bool landscape;
  final double width;
  final double height;
  final bool handling;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  const _ButtonDock({
    required this.landscape,
    required this.width,
    required this.height,
    required this.handling,
    required this.onAccept,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final acceptWidth = landscape ? width * 0.34 : width * 0.72;
    final skipWidth = landscape ? width * 0.24 : width * 0.5;

    return Positioned(
      left: 0,
      right: 0,
      bottom: landscape ? height * 0.07 : height * 0.09,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: acceptWidth,
            child: _GemPlaque(
              text: 'ACCEPT',
              disabled: handling,
              onTap: onAccept,
              tone: _PlaqueTone.gold,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: skipWidth,
            child: _GemPlaque(
              text: 'SKIP',
              disabled: handling,
              onTap: onSkip,
              tone: _PlaqueTone.slate,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlaqueTone { gold, slate }

class _GemPlaque extends StatefulWidget {
  final String text;
  final bool disabled;
  final VoidCallback onTap;
  final _PlaqueTone tone;

  const _GemPlaque({
    required this.text,
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

    return Opacity(
      opacity: widget.disabled ? 0.55 : 1.0,
      child: GestureDetector(
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
            padding: const EdgeInsets.symmetric(vertical: 16),
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
                    blurRadius: 22,
                    spreadRadius: 1,
                    offset: Offset(0, 6),
                  )
                else
                  const BoxShadow(
                    color: Color(0x77000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _CornerGem(
                    color: isGold
                        ? const Color(0xFF7A1B12)
                        : const Color(0xFFB78BE0),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: isGold ? 20 : 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CornerGem(
                    color: isGold
                        ? const Color(0xFF187B23)
                        : const Color(0xFFB78BE0),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerGem extends StatelessWidget {
  final Color color;
  const _CornerGem({required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: 10,
        height: 10,
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
