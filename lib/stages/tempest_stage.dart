// Jester Treasure — "no wifi" screen.
//
// Full-screen artwork backdrop (portrait / landscape aware) with a single
// oversized "TRY AGAIN" plaque overlaid at the bottom. The plaque style is
// intentionally different from every other button in the app (jewelled
// scroll rather than gradient bar) so this project's UI fingerprint does
// not overlap with sibling submissions.

import 'package:flutter/material.dart';

class TempestStage extends StatefulWidget {
  final WidgetBuilder onRetry;

  const TempestStage({super.key, required this.onRetry});

  @override
  State<TempestStage> createState() => _TempestStageState();
}

class _TempestStageState extends State<TempestStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.onRetry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final backdrop = orientation == Orientation.landscape
        ? 'assets/Horizontal_NoWiFi_GREY.webp'
        : 'assets/Vertical_NoWiFi_GREY.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0518),
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
                  const ColoredBox(color: Color(0xFF0B0518)),
            ),
            // Soft vignette so the button is legible on any variant.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: orientation == Orientation.landscape
                  ? size.height * 0.09
                  : size.height * 0.09,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: orientation == Orientation.landscape
                        ? size.width * 0.42
                        : size.width * 0.78,
                  ),
                  child: _ScrollButton(
                    label: _reconnecting ? 'RECONNECTING' : 'TRY AGAIN',
                    busy: _reconnecting,
                    shimmer: _shimmerCtrl,
                    onTap: _handleRetry,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollButton extends StatefulWidget {
  final String label;
  final bool busy;
  final AnimationController shimmer;
  final VoidCallback onTap;

  const _ScrollButton({
    required this.label,
    required this.busy,
    required this.shimmer,
    required this.onTap,
  });

  @override
  State<_ScrollButton> createState() => _ScrollButtonState();
}

class _ScrollButtonState extends State<_ScrollButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!widget.busy) setState(() => _pressed = true);
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.busy) widget.onTap();
      },
      child: AnimatedBuilder(
        animation: widget.shimmer,
        builder: (context, _) {
          final t = widget.shimmer.value;
          return AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.busy
                      ? const <Color>[
                          Color(0xFF5C4020),
                          Color(0xFF33200D),
                        ]
                      : <Color>[
                          Color.lerp(const Color(0xFFFFE694),
                              const Color(0xFFFFD24D), t)!,
                          const Color(0xFFEF9A0F),
                          const Color(0xFF8A3B08),
                        ],
                ),
                border: Border.all(
                  color: const Color(0xFFFFF3B0),
                  width: 3,
                ),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.elliptical(60, 40),
                  right: Radius.elliptical(60, 40),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFFB300)
                        .withValues(alpha: widget.busy ? 0.15 : 0.55),
                    blurRadius: 22,
                    spreadRadius: 1,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (widget.busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFF3B0),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 28,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.4,
                      shadows: <Shadow>[
                        Shadow(
                          color: Color(0xFF3D1400),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
