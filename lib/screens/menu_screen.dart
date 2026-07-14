import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/telemetry_beam.dart';
import '../stages/legal_stage.dart';
import 'game_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  int _bestScore = 0;
  int _totalCoins = 0;
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    TelemetryBeam.enterSurface('menu');
    _loadStats();
  }

  Future<void> _loadStats() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _bestScore = prefs.getInt('best_score') ?? 0;
      _totalCoins = prefs.getInt('total_coins') ?? 0;
    });
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _startGame() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const GameScreen(),
        transitionsBuilder: (_, Animation<double> a, __, Widget child) {
          return FadeTransition(opacity: a, child: child);
        },
      ),
    );
    _loadStats();
  }

  void _openWebView(String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalStage(title: title, url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/Background_RoyalVault.webp',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withValues(alpha: 0.25)),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double h = c.maxHeight;
                final double titleWidth = size.width * 0.78;
                final double heroHeight = (h * 0.22).clamp(120.0, 220.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 8),
                      _StatsBar(
                          bestScore: _bestScore, totalCoins: _totalCoins),
                      SizedBox(height: h * 0.03),
                      AnimatedBuilder(
                        animation: _floatController,
                        builder: (BuildContext context, Widget? child) {
                          final double t = Curves.easeInOut
                              .transform(_floatController.value);
                          return Transform.translate(
                            offset: Offset(0, -6 + t * 12),
                            child: child,
                          );
                        },
                        child: Image.asset(
                          'assets/Game_Name.webp',
                          width: titleWidth,
                          fit: BoxFit.contain,
                        ),
                      ),
                      SizedBox(height: h * 0.01),
                      Image.asset(
                        'assets/Hero.webp',
                        height: heroHeight,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: h * 0.02),
                      _MenuButton(
                        label: 'TAP TO PLAY',
                        icon: Icons.play_arrow_rounded,
                        onTap: _startGame,
                        big: true,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Expanded(
                            child: _MenuButton(
                              label: 'PRIVACY',
                              icon: Icons.privacy_tip_rounded,
                              onTap: () => _openWebView(
                                'Privacy Policy',
                                'https://jestertreasure.com/privacy-policy.html',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MenuButton(
                              label: 'SUPPORT',
                              icon: Icons.support_agent_rounded,
                              onTap: () => _openWebView(
                                'Support',
                                'https://jestertreasure.com/support.html',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.bestScore, required this.totalCoins});

  final int bestScore;
  final int totalCoins;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatChip(
            icon: Icons.emoji_events_rounded,
            label: 'BEST',
            value: bestScore.toString(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            imageAsset: 'assets/Collectible_TreasureCoin.webp',
            label: 'COINS',
            value: totalCoins.toString(),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.icon,
    this.imageAsset,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? imageAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD54F), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (imageAsset != null)
            Image.asset(imageAsset!, width: 26, height: 26)
          else
            Icon(icon, color: const Color(0xFFFFD54F), size: 24),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.big = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool big;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: widget.big ? 72 : 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: widget.big
                  ? const <Color>[
                      Color(0xFFFFF176),
                      Color(0xFFFFB300),
                      Color(0xFFE65100),
                    ]
                  : const <Color>[
                      Color(0xFFFFCA28),
                      Color(0xFFEF6C00),
                    ],
            ),
            border: Border.all(
              color: const Color(0xFFFFF9C4),
              width: 2.5,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: const Color(0xFFFFC107).withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                widget.icon,
                color: Colors.white,
                size: widget.big ? 34 : 24,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.big ? 24 : 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
