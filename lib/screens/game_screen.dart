import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EnemyType { goblin, mimic }

class Enemy {
  Enemy({
    required this.id,
    required this.position,
    required this.type,
    required this.speed,
    required this.hp,
  });

  final int id;
  Offset position;
  final EnemyType type;
  double speed;
  double hp;
  double hitFlash = 0;
  double angle = 0;
  double bob = 0;
  bool dying = false;
  double dyingT = 0;

  double get radius => type == EnemyType.goblin ? 42 : 50;
}

class Coin {
  Coin({
    required this.id,
    required this.position,
    required this.velocity,
  });

  final int id;
  Offset position;
  Offset velocity;
  double rotation = 0;
  double life = 0;
  bool active = true;
}

class Particle {
  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.lifetime,
  });

  Offset position;
  Offset velocity;
  Color color;
  double size;
  double lifetime;
  double age = 0;
}

class FloatingText {
  FloatingText({
    required this.position,
    required this.text,
    required this.color,
  });

  Offset position;
  final String text;
  final Color color;
  double age = 0;
  final double lifetime = 0.9;
}

class GameImages {
  GameImages({
    required this.hero,
    required this.goblin,
    required this.mimic,
    required this.coin,
    required this.burst,
    required this.vault,
  });

  final ui.Image hero;
  final ui.Image goblin;
  final ui.Image mimic;
  final ui.Image coin;
  final ui.Image burst;
  final ui.Image vault;

  static Future<GameImages> load() async {
    Future<ui.Image> load(String path) async {
      final ByteData data = await rootBundle.load(path);
      final ui.Codec codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    }

    final List<ui.Image> imgs = await Future.wait<ui.Image>(<Future<ui.Image>>[
      load('assets/Hero.webp'),
      load('assets/Enemy_GoldGoblin.webp'),
      load('assets/Enemy_TreasureMimic.webp'),
      load('assets/Collectible_TreasureCoin.webp'),
      load('assets/Powerup_TreasureBurst.webp'),
      load('assets/Obstacle_GoldenWheel.webp'),
    ]);
    return GameImages(
      hero: imgs[0],
      goblin: imgs[1],
      mimic: imgs[2],
      coin: imgs[3],
      burst: imgs[4],
      vault: imgs[5],
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  final math.Random _rng = math.Random();
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  GameImages? _images;

  // Game state
  bool _running = false;
  bool _paused = false;
  bool _gameOver = false;
  bool _bursting = false;
  double _burstT = 0;

  int _score = 0;
  int _coinsThisRun = 0;
  int _bestScore = 0;
  double _burstMeter = 0;
  double _difficulty = 0;
  double _timeSurvived = 0;
  double _spawnCooldown = 1.4;

  Size _size = Size.zero;
  Offset _heroPos = Offset.zero;
  Offset _vaultPos = Offset.zero;
  double _vaultRadius = 90;

  final List<Enemy> _enemies = <Enemy>[];
  final List<Coin> _coins = <Coin>[];
  final List<Particle> _particles = <Particle>[];
  final List<FloatingText> _floatingTexts = <FloatingText>[];
  int _nextEnemyId = 0;
  int _nextCoinId = 0;

  bool _aiming = false;
  Offset _aimStart = Offset.zero;
  Offset _aimCurrent = Offset.zero;

  double _obstacleAngle = 0;
  double _shakeT = 0;
  double _shakeAmount = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final GameImages images = await GameImages.load();
    if (!mounted) return;
    setState(() {
      _bestScore = prefs.getInt('best_score') ?? 0;
      _images = images;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGame());
  }

  Future<void> _persistResults() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int currentBest = prefs.getInt('best_score') ?? 0;
    if (_score > currentBest) {
      await prefs.setInt('best_score', _score);
    }
    final int totalCoins = prefs.getInt('total_coins') ?? 0;
    await prefs.setInt('total_coins', totalCoins + _coinsThisRun);
  }

  void _startGame() {
    _score = 0;
    _coinsThisRun = 0;
    _burstMeter = 0;
    _difficulty = 0;
    _timeSurvived = 0;
    _spawnCooldown = 1.6;
    _enemies.clear();
    _coins.clear();
    _particles.clear();
    _floatingTexts.clear();
    _gameOver = false;
    _paused = false;
    _bursting = false;
    _burstT = 0;
    _lastTick = Duration.zero;
    _running = true;
    if (_ticker != null && !_ticker!.isActive) _ticker!.start();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    double dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    if (dt > 0.05) dt = 0.05;

    if (!_running || _paused || _gameOver) {
      setState(() {});
      return;
    }

    _update(dt);
    setState(() {});
  }

  void _update(double dt) {
    _timeSurvived += dt;
    _difficulty = _timeSurvived / 20.0;
    _obstacleAngle += dt * 0.6;
    if (_shakeT > 0) {
      _shakeT -= dt;
      if (_shakeT < 0) _shakeT = 0;
    }

    if (_bursting) {
      _burstT += dt;
      if (_rng.nextDouble() < 0.9) {
        final Offset center = _vaultPos;
        for (int i = 0; i < 6; i++) {
          final double a = _rng.nextDouble() * math.pi * 2;
          final double s = 250 + _rng.nextDouble() * 500;
          _particles.add(Particle(
            position: center,
            velocity: Offset(math.cos(a) * s, math.sin(a) * s),
            color: _randomGemColor(),
            size: 6 + _rng.nextDouble() * 10,
            lifetime: 0.8 + _rng.nextDouble() * 0.6,
          ));
        }
      }
      if (_burstT >= 1.2) {
        _bursting = false;
        _burstT = 0;
      }
    }

    _spawnCooldown -= dt;
    final double baseCd = math.max(0.35, 1.6 - _difficulty * 0.5);
    if (_spawnCooldown <= 0) {
      _spawnEnemy();
      _spawnCooldown = baseCd * (0.7 + _rng.nextDouble() * 0.6);
    }

    for (final Enemy e in _enemies) {
      if (e.dying) {
        e.dyingT += dt;
        continue;
      }
      final Offset toVault = _vaultPos - e.position;
      final double d = toVault.distance;
      if (d > 1) {
        final Offset dir = toVault / d;
        e.position += dir * e.speed * dt;
        e.angle = math.atan2(dir.dy, dir.dx);
      }
      e.bob += dt * 6;
      if (e.hitFlash > 0) e.hitFlash -= dt * 3;
      if (d < _vaultRadius * 0.85) {
        _triggerGameOver();
        return;
      }
    }
    _enemies.removeWhere((Enemy e) => e.dying && e.dyingT > 0.35);

    for (final Coin c in _coins) {
      if (!c.active) continue;
      c.position += c.velocity * dt;
      c.rotation += dt * 14;
      c.life += dt;
      final Rect area =
          Rect.fromLTWH(-80, -80, _size.width + 160, _size.height + 160);
      if (!area.contains(c.position) || c.life > 2.2) {
        c.active = false;
        continue;
      }
      for (final Enemy e in _enemies) {
        if (e.dying) continue;
        if ((e.position - c.position).distance < e.radius) {
          c.active = false;
          _hitEnemy(e, c.position);
          break;
        }
      }
    }
    _coins.removeWhere((Coin c) => !c.active);

    for (final Particle p in _particles) {
      p.age += dt;
      p.position += p.velocity * dt;
      p.velocity += const Offset(0, 380) * dt;
      p.velocity *= math.pow(0.6, dt).toDouble();
    }
    _particles.removeWhere((Particle p) => p.age >= p.lifetime);

    for (final FloatingText t in _floatingTexts) {
      t.age += dt;
      t.position += const Offset(0, -60) * dt;
    }
    _floatingTexts.removeWhere((FloatingText t) => t.age >= t.lifetime);
  }

  void _spawnEnemy() {
    final int side = _rng.nextInt(4);
    Offset pos;
    switch (side) {
      case 0:
        pos = Offset(_rng.nextDouble() * _size.width, -60);
        break;
      case 1:
        pos = Offset(_size.width + 60, _rng.nextDouble() * _size.height);
        break;
      case 2:
        pos = Offset(_rng.nextDouble() * _size.width, _size.height + 60);
        break;
      default:
        pos = Offset(-60, _rng.nextDouble() * _size.height);
        break;
    }
    final bool isMimic = _difficulty > 0.6 && _rng.nextDouble() < 0.35;
    final double baseSpeedGoblin = 70 + _difficulty * 26;
    final double baseSpeedMimic = 45 + _difficulty * 18;
    _enemies.add(Enemy(
      id: _nextEnemyId++,
      position: pos,
      type: isMimic ? EnemyType.mimic : EnemyType.goblin,
      speed: isMimic ? baseSpeedMimic : baseSpeedGoblin,
      hp: isMimic ? 2 : 1,
    ));
  }

  void _hitEnemy(Enemy e, Offset hitPoint) {
    e.hitFlash = 1.0;
    e.hp -= 1;
    _shakeT = 0.15;
    _shakeAmount = 6;
    for (int i = 0; i < 8; i++) {
      final double a = _rng.nextDouble() * math.pi * 2;
      final double s = 120 + _rng.nextDouble() * 200;
      _particles.add(Particle(
        position: hitPoint,
        velocity: Offset(math.cos(a) * s, math.sin(a) * s),
        color: const Color(0xFFFFE082),
        size: 4 + _rng.nextDouble() * 5,
        lifetime: 0.35 + _rng.nextDouble() * 0.3,
      ));
    }
    if (e.hp <= 0) {
      e.dying = true;
      _coinsThisRun += 1;
      final int pts = e.type == EnemyType.mimic ? 25 : 10;
      _score += pts;
      _addBurst(0.08);
      _floatingTexts.add(FloatingText(
        position: e.position,
        text: '+$pts',
        color: const Color(0xFFFFF176),
      ));
      for (int i = 0; i < 14; i++) {
        final double a = _rng.nextDouble() * math.pi * 2;
        final double s = 200 + _rng.nextDouble() * 300;
        _particles.add(Particle(
          position: e.position,
          velocity: Offset(math.cos(a) * s, math.sin(a) * s),
          color: i % 3 == 0 ? _randomGemColor() : const Color(0xFFFFC107),
          size: 5 + _rng.nextDouble() * 6,
          lifetime: 0.5 + _rng.nextDouble() * 0.4,
        ));
      }
    }
  }

  Color _randomGemColor() {
    const List<Color> colors = <Color>[
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFFAB47BC),
      Color(0xFFFFB300),
      Color(0xFF26C6DA),
    ];
    return colors[_rng.nextInt(colors.length)];
  }

  void _addBurst(double amount) {
    if (_burstMeter >= 1.0) return;
    _burstMeter = (_burstMeter + amount).clamp(0.0, 1.0);
  }

  void _triggerBurst() {
    if (_burstMeter < 1.0 || _bursting || _gameOver) return;
    _burstMeter = 0;
    _bursting = true;
    _burstT = 0;
    _shakeT = 0.6;
    _shakeAmount = 14;
    int killed = 0;
    for (final Enemy e in _enemies) {
      if (!e.dying) {
        e.dying = true;
        killed++;
        _coinsThisRun += 1;
        for (int i = 0; i < 10; i++) {
          final double a = _rng.nextDouble() * math.pi * 2;
          final double s = 200 + _rng.nextDouble() * 250;
          _particles.add(Particle(
            position: e.position,
            velocity: Offset(math.cos(a) * s, math.sin(a) * s),
            color: _randomGemColor(),
            size: 5 + _rng.nextDouble() * 6,
            lifetime: 0.5 + _rng.nextDouble() * 0.4,
          ));
        }
      }
    }
    _score += 100 + killed * 15;
    _floatingTexts.add(FloatingText(
      position: _vaultPos - const Offset(0, 120),
      text: 'TREASURE BURST!',
      color: const Color(0xFFFFF176),
    ));
    HapticFeedback.heavyImpact();
  }

  Future<void> _triggerGameOver() async {
    if (_gameOver) return;
    _gameOver = true;
    _running = false;
    _shakeT = 0.5;
    _shakeAmount = 12;
    HapticFeedback.mediumImpact();
    await _persistResults();
    if (!mounted) return;
    setState(() {
      _bestScore = math.max(_bestScore, _score);
    });
  }

  void _onPanStart(DragStartDetails d) {
    if (_gameOver || _paused) return;
    _aiming = true;
    _aimStart = _heroPos;
    _aimCurrent = d.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_aiming) return;
    _aimCurrent = d.localPosition;
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_aiming) return;
    _aiming = false;
    _throwCoin(_aimCurrent);
  }

  void _onTapUp(TapUpDetails d) {
    if (_gameOver || _paused) return;
    _throwCoin(d.localPosition);
  }

  void _throwCoin(Offset target) {
    final Offset dir = target - _heroPos;
    final double d = dir.distance;
    if (d < 10) return;
    final Offset norm = dir / d;
    const double speed = 900;
    _coins.add(Coin(
      id: _nextCoinId++,
      position: _heroPos + norm * 40,
      velocity: norm * speed,
    ));
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final GameImages? images = _images;
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          _size = Size(c.maxWidth, c.maxHeight);
          _vaultPos = Offset(_size.width / 2, _size.height * 0.55);
          _heroPos = Offset(_size.width / 2, _size.height * 0.78);
          _vaultRadius = math.min(_size.width, _size.height) * 0.16;

          final Offset shake = _shakeT > 0
              ? Offset(
                  (_rng.nextDouble() - 0.5) * _shakeAmount,
                  (_rng.nextDouble() - 0.5) * _shakeAmount,
                )
              : Offset.zero;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(
                'assets/Background_RoyalVault.webp',
                fit: BoxFit.cover,
              ),
              Container(color: Colors.black.withValues(alpha: 0.20)),

              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                ),
              ),

              if (images != null)
                IgnorePointer(
                  child: Transform.translate(
                    offset: shake,
                    child: CustomPaint(
                      size: _size,
                      painter: _GamePainter(
                        heroPos: _heroPos,
                        vaultPos: _vaultPos,
                        vaultRadius: _vaultRadius,
                        obstacleAngle: _obstacleAngle,
                        enemies: _enemies,
                        coins: _coins,
                        particles: _particles,
                        floatingTexts: _floatingTexts,
                        aiming: _aiming,
                        aimStart: _aimStart,
                        aimCurrent: _aimCurrent,
                        images: images,
                        bursting: _bursting,
                        burstT: _burstT,
                      ),
                    ),
                  ),
                ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _Hud(
                    score: _score,
                    coins: _coinsThisRun,
                    best: _bestScore,
                    burstMeter: _burstMeter,
                    onPause: () => setState(() => _paused = true),
                    onBurst: _triggerBurst,
                    burstReady: _burstMeter >= 1.0,
                  ),
                ),
              ),

              if (_paused && !_gameOver)
                _PauseOverlay(
                  onResume: () => setState(() => _paused = false),
                  onQuit: () => Navigator.of(context).pop(),
                ),

              if (_gameOver)
                _GameOverOverlay(
                  score: _score,
                  coins: _coinsThisRun,
                  best: _bestScore,
                  onRetry: _startGame,
                  onMenu: () => Navigator.of(context).pop(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter({
    required this.heroPos,
    required this.vaultPos,
    required this.vaultRadius,
    required this.obstacleAngle,
    required this.enemies,
    required this.coins,
    required this.particles,
    required this.floatingTexts,
    required this.aiming,
    required this.aimStart,
    required this.aimCurrent,
    required this.images,
    required this.bursting,
    required this.burstT,
  });

  final Offset heroPos;
  final Offset vaultPos;
  final double vaultRadius;
  final double obstacleAngle;
  final List<Enemy> enemies;
  final List<Coin> coins;
  final List<Particle> particles;
  final List<FloatingText> floatingTexts;
  final bool aiming;
  final Offset aimStart;
  final Offset aimCurrent;
  final GameImages images;
  final bool bursting;
  final double burstT;

  @override
  void paint(Canvas canvas, Size size) {
    // Vault glow
    final Paint glow = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFFFC107).withValues(alpha: 0.55),
          const Color(0xFFFFC107).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: vaultPos, radius: vaultRadius * 2.4));
    canvas.drawCircle(vaultPos, vaultRadius * 2.4, glow);

    // Vault (Golden wheel)
    _paintImage(
      canvas,
      images.vault,
      vaultPos,
      vaultRadius * 2.6,
      rotation: obstacleAngle,
    );

    // Enemies (draw behind hero if below, in front if above? Just draw sorted by y)
    final List<Enemy> sorted = List<Enemy>.from(enemies)
      ..sort((Enemy a, Enemy b) => a.position.dy.compareTo(b.position.dy));
    for (final Enemy e in sorted) {
      final double bob = math.sin(e.bob) * 4;
      final ui.Image img =
          e.type == EnemyType.goblin ? images.goblin : images.mimic;
      final double dyingScale =
          e.dying ? (1.0 - e.dyingT / 0.35).clamp(0.0, 1.0) : 1.0;
      final double baseSize = e.type == EnemyType.goblin ? 92 : 108;
      // Shadow
      final Paint shadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.35 * dyingScale)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawOval(
        Rect.fromCenter(
          center: e.position + Offset(0, baseSize * 0.42),
          width: baseSize * 0.7,
          height: baseSize * 0.22,
        ),
        shadow,
      );
      _paintImage(
        canvas,
        img,
        e.position + Offset(0, bob),
        baseSize * dyingScale,
        opacity: dyingScale,
        tint: e.hitFlash > 0
            ? Colors.white.withValues(alpha: e.hitFlash * 0.6)
            : null,
      );
    }

    // Thrown coins
    for (final Coin c in coins) {
      final Paint trail = Paint()
        ..color = const Color(0xFFFFE082).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      final Offset back = c.position - c.velocity.normalizeSafe() * 34;
      canvas.drawLine(back, c.position, trail);
      _paintImage(
        canvas,
        images.coin,
        c.position,
        44,
        rotation: c.rotation,
      );
    }

    // Hero shadow
    final Paint heroShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: heroPos + const Offset(0, 70),
        width: 110,
        height: 26,
      ),
      heroShadow,
    );

    _paintImage(canvas, images.hero, heroPos, 160);

    // Aim indicator
    if (aiming) {
      final Offset dir = aimCurrent - aimStart;
      final double d = dir.distance;
      if (d > 12) {
        final Offset norm = dir / d;
        final Paint linePaint = Paint()
          ..color = const Color(0xFFFFE082).withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        const double dash = 14;
        const double gap = 10;
        double t = 60;
        final double totalLen = math.min(d + 200, math.max(size.width, size.height));
        while (t < totalLen) {
          final Offset a = heroPos + norm * t;
          final Offset b = heroPos + norm * math.min(t + dash, totalLen);
          canvas.drawLine(a, b, linePaint);
          t += dash + gap;
        }
        final Offset tip = heroPos + norm * totalLen;
        final Paint tri = Paint()
          ..color = const Color(0xFFFFF176)
          ..style = PaintingStyle.fill;
        final Path head = Path();
        final Offset perp = Offset(-norm.dy, norm.dx);
        head.moveTo(tip.dx, tip.dy);
        head.lineTo((tip - norm * 26 + perp * 14).dx,
            (tip - norm * 26 + perp * 14).dy);
        head.lineTo((tip - norm * 26 - perp * 14).dx,
            (tip - norm * 26 - perp * 14).dy);
        head.close();
        canvas.drawPath(head, tri);
      }
    }

    // Particles
    for (final Particle p in particles) {
      final double t = (1 - p.age / p.lifetime).clamp(0.0, 1.0);
      final Paint pp = Paint()
        ..color = p.color.withValues(alpha: t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5);
      canvas.drawCircle(p.position, p.size * t, pp);
    }

    // Floating texts
    for (final FloatingText t in floatingTexts) {
      final double a = (1 - t.age / t.lifetime).clamp(0.0, 1.0);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color.withValues(alpha: a),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            shadows: <Shadow>[
              Shadow(
                color: Colors.black.withValues(alpha: a),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, t.position - Offset(tp.width / 2, tp.height / 2));
    }

    // Burst overlay
    if (bursting) {
      final double intensity = (1 - burstT / 1.2).clamp(0.0, 1.0);
      final Paint flash = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFFFF9C4).withValues(alpha: 0.85 * intensity),
            const Color(0xFFFFC107).withValues(alpha: 0.4 * intensity),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.3, 1.0],
        ).createShader(
          Rect.fromCircle(center: vaultPos, radius: size.longestSide),
        );
      canvas.drawRect(Offset.zero & size, flash);
      final double s = 260 + burstT * 400;
      _paintImage(canvas, images.burst, vaultPos, s, opacity: intensity);
    }
  }

  void _paintImage(
    Canvas canvas,
    ui.Image image,
    Offset center,
    double displaySize, {
    double rotation = 0,
    double opacity = 1.0,
    Color? tint,
  }) {
    final double aspect = image.width / image.height;
    final double w = displaySize;
    final double h = displaySize / aspect;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (rotation != 0) canvas.rotate(rotation);
    final Rect dst =
        Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final Paint paint = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1.0) {
      paint.colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: opacity),
        BlendMode.modulate,
      );
    }
    if (tint != null) {
      paint.colorFilter = ColorFilter.mode(tint, BlendMode.srcATop);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}

extension _OffsetX on Offset {
  Offset normalizeSafe() {
    final double d = distance;
    if (d < 0.0001) return Offset.zero;
    return this / d;
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.score,
    required this.coins,
    required this.best,
    required this.burstMeter,
    required this.onPause,
    required this.onBurst,
    required this.burstReady,
  });

  final int score;
  final int coins;
  final int best;
  final double burstMeter;
  final VoidCallback onPause;
  final VoidCallback onBurst;
  final bool burstReady;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            _HudPanel(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.emoji_events_rounded,
                      color: Color(0xFFFFD54F), size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'BEST $best',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _HudPanel(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Image.asset('assets/Collectible_TreasureCoin.webp',
                      width: 22, height: 22),
                  const SizedBox(width: 6),
                  Text(
                    coins.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _HudIconButton(icon: Icons.pause_rounded, onTap: onPause),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            _HudPanel(
              child: Text(
                'SCORE $score',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
        const Spacer(),
        GestureDetector(
          onTap: burstReady ? onBurst : null,
          behavior: HitTestBehavior.opaque,
          child: _BurstMeter(progress: burstMeter, ready: burstReady),
        ),
      ],
    );
  }
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
      ),
      child: child,
    );
  }
}

class _HudIconButton extends StatelessWidget {
  const _HudIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFD54F), width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _BurstMeter extends StatelessWidget {
  const _BurstMeter({required this.progress, required this.ready});
  final double progress;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ready ? const Color(0xFFFFF176) : const Color(0xFFFFB300),
          width: 2.5,
        ),
        boxShadow: ready
            ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.7),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: <Widget>[
          Image.asset('assets/Powerup_TreasureBurst.webp',
              width: 46, height: 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  ready ? 'TAP TO UNLEASH TREASURE BURST!' : 'TREASURE BURST',
                  style: TextStyle(
                    color: ready ? const Color(0xFFFFF176) : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LayoutBuilder(
                    builder: (BuildContext c, BoxConstraints cs) {
                      return Container(
                        height: 14,
                        color: Colors.black45,
                        child: Row(
                          children: <Widget>[
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: cs.maxWidth * progress,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Color(0xFFFFF176),
                                    Color(0xFFFFC107),
                                    Color(0xFFFF8F00),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onQuit});
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'PAUSED',
                style: TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 24),
              _OverlayButton(label: 'RESUME', onTap: onResume, primary: true),
              const SizedBox(height: 12),
              _OverlayButton(label: 'QUIT', onTap: onQuit),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.score,
    required this.coins,
    required this.best,
    required this.onRetry,
    required this.onMenu,
  });
  final int score;
  final int coins;
  final int best;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'GAME OVER',
                  style: TextStyle(
                    color: Color(0xFFFF7043),
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFFFD54F), width: 2.5),
                  ),
                  child: Column(
                    children: <Widget>[
                      _StatRow(label: 'SCORE', value: score.toString()),
                      const SizedBox(height: 10),
                      _StatRow(label: 'COINS', value: coins.toString()),
                      const SizedBox(height: 10),
                      _StatRow(label: 'BEST', value: best.toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _OverlayButton(label: 'RETRY', onTap: onRetry, primary: true),
                const SizedBox(height: 12),
                _OverlayButton(label: 'MENU', onTap: onMenu),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFFE082),
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 30),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
      ],
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: primary ? 64 : 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: primary
                ? const <Color>[
                    Color(0xFFFFF176),
                    Color(0xFFFFB300),
                    Color(0xFFE65100),
                  ]
                : const <Color>[
                    Color(0xFF6D4C41),
                    Color(0xFF3E2723),
                  ],
          ),
          border: Border.all(
            color: primary ? const Color(0xFFFFF9C4) : const Color(0xFFFFD54F),
            width: 2.5,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: primary ? 22 : 18,
            letterSpacing: 2,
            shadows: const <Shadow>[
              Shadow(
                  color: Colors.black87,
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}
