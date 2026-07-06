import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  Timer? _progressTimer;
  Timer? _dotsTimer;
  int _dots = 0;
  late final AnimationController _finalController;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _finalController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Preload images so real work is done and progress goes up to ~90%.
    // The last 10% is filled just before navigation.
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() {
        _dots = (_dots + 1) % 4;
      });
    });

    _startFakeProgress();
    _preloadAssetsAndFinish();
  }

  void _startFakeProgress() {
    // Progress climbs to about 0.9 during load, then jumps to 1.0.
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 60), (Timer t) {
      if (!mounted) return;
      setState(() {
        if (_progress < 0.9) {
          _progress += 0.01 + (0.02 * (0.9 - _progress));
          if (_progress > 0.9) _progress = 0.9;
        }
      });
    });
  }

  Future<void> _preloadAssetsAndFinish() async {
    // Simulate/perform load work.
    final List<String> images = <String>[
      'assets/Background_RoyalVault.webp',
      'assets/Hero.webp',
      'assets/Enemy_GoldGoblin.webp',
      'assets/Enemy_TreasureMimic.webp',
      'assets/Collectible_TreasureCoin.webp',
      'assets/Powerup_TreasureBurst.webp',
      'assets/Game_Name.webp',
      'assets/Obstacle_GoldenWheel.webp',
      'assets/Vertical_Loading.webp',
      'assets/Horizontal_Loading.webp',
    ];
    for (final String path in images) {
      if (!mounted) return;
      try {
        await precacheImage(AssetImage(path), context);
      } catch (_) {}
    }
    // Ensure minimum splash time so users see the loading screen.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    _progressTimer?.cancel();
    // Fill to 100% right before launching.
    setState(() {
      _progress = 1.0;
      _completed = true;
    });
    await _finalController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const MenuScreen(),
        transitionsBuilder: (_, Animation<double> a, __, Widget child) {
          return FadeTransition(opacity: a, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _dotsTimer?.cancel();
    _finalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orientation = MediaQuery.of(context).orientation;
    final String bgAsset = orientation == Orientation.portrait
        ? 'assets/Vertical_Loading.webp'
        : 'assets/Horizontal_Loading.webp';
    final String dotsStr = '.' * _dots + ' ' * (3 - _dots);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0B2E),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            bgAsset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          // Dark tint for readability of the bar.
          Container(
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
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _LoadingBar(progress: _progress),
                const SizedBox(height: 14),
                Text(
                  'Loading$dotsStr',
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (_completed)
                  const SizedBox(height: 4)
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double filled = (width - 8) * progress.clamp(0.0, 1.0);
        return Container(
          height: 26,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFD54F),
              width: 2.5,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Stack(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: filled,
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
            ],
          ),
        );
      },
    );
  }
}
