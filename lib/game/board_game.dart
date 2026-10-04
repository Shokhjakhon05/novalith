/// The playing field: draws the simulation and turns its events into feedback (particles,
/// floating text, shake, sound, haptics). It never decides game rules - those live in GameCore.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../app/app_model.dart';
import '../core/game_core.dart';
import '../services/feedback.dart';
import 'sprites.dart';

const List<int> levelColors = [
  0xBFE3FF,
  0xC98A5A,
  0xA9AEC0,
  0xF2ECD2,
  0x4FA8FF,
  0xF0B070,
  0xDCEBFF,
  0xFFC53D,
  0xFF5A3C,
  0x7FE3FF,
  0xB36BFF,
  0xD9C8FF,
];

Color levelColor(int level, [double alpha = 1]) =>
    Color(0xFF000000 | levelColors[(level - 1) % levelColors.length]).withValues(alpha: alpha);

class _Particle {
  double x = 0, y = 0, vx = 0, vy = 0, life = 0, max = 1, size = 1;
  int color = 0xFFFFFF;
}

class _Ring {
  _Ring(this.x, this.y, this.r0, this.r1, this.max, this.color);
  final double x, y, r0, r1, max;
  final int color;
  double life = 0;
}

class _FloatText {
  _FloatText(this.painter, this.x, this.y, this.max, this.rise, this.tag);
  final TextPainter painter;

  /// Texts with the same non-empty tag replace each other (one combo banner at a time).
  final String tag;
  final double x, y, max, rise;
  double life = 0;
}

class BoardGame extends Game {
  BoardGame({required this.core, required this.model});

  GameCore core;
  final AppModel model;
  final OrbSprites sprites = OrbSprites();

  /// Screen space reserved for the HUD above and the system bar below the board.
  double topInset = 150;
  double bottomInset = 24;

  /// Called for every simulation event after the board has reacted to it.
  void Function(GameEvent event)? onEvent;

  /// Called once, a moment after the run ended (so the ending can be seen before any dialog).
  VoidCallback? onRunEnded;

  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> nextPiece = ValueNotifier(1);
  final ValueNotifier<int> dropsLeft = ValueNotifier(-1);

  bool showStats = false;

  /// Campaign levels play against their world's sky instead of the equipped backdrop.
  String? backgroundOverride;
  double aimX = 170;

  double _scale = 1;
  double _ox = 0;
  double _oy = 0;
  double _t = 0;
  double _ready = 0;
  double _shake = 0;
  double _flash = 0;
  int _flashColor = 0xFFFFFF;
  double _endTimer = -1;
  bool _endReported = false;
  double _fps = 60;

  ui.Image? _bg;
  String _bgId = '';
  Size _bgSize = Size.zero;

  static const int _maxParticles = 420;
  final List<_Particle> _particles = List.generate(_maxParticles, (_) => _Particle());
  int _particleCursor = 0;
  final List<_Ring> _rings = [];
  final List<_FloatText> _texts = [];
  final Map<int, double> _squash = {};
  final Map<int, double> _pop = {};
  final Map<int, TextPainter> _numberPainters = {};
  final math.Random _fx = math.Random(1);

  int get activeParticles => _particles.where((p) => p.life < p.max).length;

  /// Swaps in a new simulation (restart / continue keeps the same board object).
  void startRun(GameCore next) {
    core = next;
    _endTimer = -1;
    _endReported = false;
    _squash.clear();
    _pop.clear();
    _rings.clear();
    _texts.clear();
    for (final p in _particles) {
      p.life = p.max;
    }
    aimX = core.balance.worldW / 2;
    _sync();
  }

  void _sync() {
    score.value = core.score;
    nextPiece.value = core.nextPiece;
    dropsLeft.value = core.dropsLeft;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout();
  }

  void _layout() {
    if (!hasLayout) return;
    final b = core.balance;
    final availW = size.x - 16;
    final availH = size.y - topInset - bottomInset;
    _scale = math.max(0.1, math.min(availW / b.worldW, availH / b.floorY));
    _ox = (size.x - b.worldW * _scale) / 2;
    _oy = size.y - bottomInset - b.floorY * _scale;
  }

  void setInsets(double top, double bottom) {
    if (top == topInset && bottom == bottomInset) return;
    topInset = top;
    bottomInset = bottom;
    _layout();
  }

  // --- Input (screen coordinates) ---

  void aimAt(double screenX) {
    if (paused || core.over) return;
    aimX = (screenX - _ox) / _scale;
  }

  /// Returns true when a piece was actually released.
  bool release() {
    if (paused || core.over) return false;
    final ok = core.drop(aimX);
    if (ok) _drain();
    return ok;
  }

  // --- Simulation -> feedback ---

  @override
  void update(double dt) {
    if (!dt.isFinite || dt <= 0) return;
    final frame = dt > 0.05 ? 0.05 : dt;
    _fps += (1 / dt - _fps) * 0.05;
    if (sprites.themeId != model.profile.theme) sprites.build(model.profile.theme, core.balance);
    _t += frame;

    // The last moments before overflow play in slow motion: tension, and a last chance.
    final slow = core.overflow > 0.55 ? 1 - 0.62 * ((core.overflow - 0.55) / 0.45).clamp(0.0, 1.0) : 1.0;
    core.advance(frame, timeScale: slow);
    _drain();

    _ready = core.canDrop ? math.min(1, _ready + frame * 7) : 0;
    _shake = math.max(0, _shake - frame * 3.2);
    _flash = math.max(0, _flash - frame * 2.6);
    _squash.updateAll((_, v) => v - frame * 6);
    _squash.removeWhere((_, v) => v <= 0);
    _pop.updateAll((_, v) => v + frame);
    _pop.removeWhere((_, v) => v > 0.4);
    for (final p in _particles) {
      if (p.life >= p.max) continue;
      p.life += frame;
      p.vy += 520 * frame;
      p.vx *= 0.985;
      p.x += p.vx * frame;
      p.y += p.vy * frame;
    }
    for (final r in _rings) {
      r.life += frame;
    }
    _rings.removeWhere((r) => r.life >= r.max);
    for (final t in _texts) {
      t.life += frame;
    }
    _texts.removeWhere((t) => t.life >= t.max);

    if (_endTimer >= 0) {
      _endTimer += frame;
      if (_endTimer > 0.85 && !_endReported) {
        _endReported = true;
        onRunEnded?.call();
      }
    }
    _sync();
  }

  void _drain() {
    if (core.events.isEmpty) return;
    final events = List<GameEvent>.of(core.events);
    core.events.clear();
    for (final e in events) {
      _react(e);
      onEvent?.call(e);
    }
  }

  void _react(GameEvent e) {
    final audio = model.audio;
    final haptics = model.haptics;
    switch (e.type) {
      case EventType.drop:
        audio.play(Sfx.drop, volume: 0.55);
        haptics.fire(Haptic.drop);
        model.analytics.log('piece_dropped', {'level': e.level});
      case EventType.impact:
        _squash[e.id] = 1;
        if (e.speed > 160) {
          audio.play(Sfx.impact, volume: (e.speed / 1100).clamp(0.15, 0.7));
          _burst(e.x, e.y + core.balance.radius(e.level) * 0.8, 4, 0xFFFFFF, 90, 2.2, 0.35);
        }
      case EventType.merge:
        final big = e.level >= 8;
        final r = core.balance.radius(e.level);
        final col = levelColors[(e.level - 1) % levelColors.length];
        _pop[e.id] = 0;
        _burst(e.x, e.y, math.min(46, 10 + e.level * 3), col, 150 + e.level * 22.0, 2.4 + e.level * 0.22, 0.6);
        _rings.add(_Ring(e.x, e.y, r * 0.7, r * (big ? 2.6 : 1.9), big ? 0.5 : 0.34, col));
        _float('+${e.points}', e.x, e.y - r * 0.4, 15 + math.min(13, e.level * 1.1), 0xFFFFFF, 0.8);
        audio.playMerge(e.chain - 1, volume: 0.75);
        if (e.perfect) {
          _float(model.t('perfect'), e.x, e.y - r - 16, 15, 0x8CF0FF, 0.9);
          audio.play(Sfx.perfect, volume: 0.7);
        }
        if (e.chain >= 2) {
          _float(
            '${model.t('combo')} ×${core.balance.comboMultiplier(e.chain)}',
            core.balance.worldW / 2,
            core.balance.dangerY + 46,
            22 + math.min(12, e.chain * 2.0),
            0xFFD65A,
            1.0,
            tag: 'combo',
          );
          _shake = math.max(_shake, 0.12 + e.chain * 0.05);
          model.analytics.log('combo_created', {'chain': e.chain});
        }
        if (big) {
          audio.play(Sfx.big, volume: 0.9);
          _shake = math.max(_shake, 0.5);
          _flash = 0.35;
          _flashColor = col;
          haptics.fire(Haptic.bigMerge);
        } else {
          haptics.fire(e.chain >= 2 ? Haptic.combo : Haptic.merge);
        }
        model.analytics.log('merge_created', {'level': e.level});
        if (e.firstTime) model.analytics.log('evolution_reached', {'level': e.level});
      case EventType.bigBang:
        for (var i = 0; i < 5; i++) {
          _burst(e.x, e.y, 46, levelColors[_fx.nextInt(levelColors.length)], 520, 4.5, 1.2);
        }
        _rings
          ..add(_Ring(e.x, e.y, 20, 420, 0.9, 0xFFFFFF))
          ..add(_Ring(e.x, e.y, 10, 300, 0.7, 0xD9C8FF));
        _float(model.t('big_bang'), core.balance.worldW / 2, core.balance.floorY / 2, 34, 0xFFFFFF, 1.6);
        _float('+${e.points}', e.x, e.y, 30, 0xFFE38A, 1.4);
        _flash = 1;
        _flashColor = 0xFFFFFF;
        _shake = 1;
        audio.play(Sfx.bigbang);
        haptics.fire(Haptic.bigMerge);
      case EventType.dangerEnter:
        audio.play(Sfx.danger, volume: 0.7);
        haptics.fire(Haptic.danger);
        model.analytics.log('danger_entered');
      case EventType.dangerExit:
        break;
      case EventType.gameOver:
        _endTimer = 0;
        _endReported = false;
        _shake = math.max(_shake, 0.55);
        _flash = 0.5;
        _flashColor = core.endReason == EndReason.overflow ? 0xFF3A4E : 0xFFFFFF;
        if (core.endReason == EndReason.overflow) {
          audio.play(Sfx.gameover);
          haptics.fire(Haptic.gameOver);
        } else if (core.endReason == EndReason.completed) {
          _rings.add(_Ring(core.balance.worldW / 2, core.balance.floorY / 2, 30, 360, 0.7, 0xFFD65A));
          audio.play(Sfx.record);
          haptics.fire(Haptic.bigMerge);
        }
      case EventType.continued:
        _endTimer = -1;
        _endReported = false;
        _flash = 0.6;
        _flashColor = 0x8CF0FF;
        _rings.add(_Ring(core.balance.worldW / 2, core.balance.dangerY + 40, 30, 320, 0.6, 0x8CF0FF));
        audio.play(Sfx.unlock);
        model.analytics.log('continue_used');
    }
  }

  void _burst(double x, double y, int count, int color, double speed, double size, double life) {
    for (var i = 0; i < count; i++) {
      final p = _particles[_particleCursor];
      _particleCursor = (_particleCursor + 1) % _maxParticles;
      final a = _fx.nextDouble() * math.pi * 2;
      final v = speed * (0.35 + _fx.nextDouble() * 0.75);
      p
        ..x = x
        ..y = y
        ..vx = math.cos(a) * v
        ..vy = math.sin(a) * v - speed * 0.25
        ..life = 0
        ..max = life * (0.6 + _fx.nextDouble() * 0.6)
        ..size = size * (0.6 + _fx.nextDouble() * 0.8)
        ..color = color;
    }
  }

  void _float(String text, double x, double y, double fontSize, int color, double life, {String tag = ''}) {
    if (tag.isNotEmpty) _texts.removeWhere((t) => t.tag == tag);
    if (_texts.length > 24) _texts.removeAt(0);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Exo2',
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          fontVariations: const [ui.FontVariation('wght', 800)],
          color: Color(0xFF000000 | color),
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1.5))],
        ),
      ),
      textDirection: model.rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    final half = painter.width / 2;
    final w = core.balance.worldW;
    final cx = x < half + 4 ? half + 4 : (x > w - half - 4 ? w - half - 4 : x);
    _texts.add(_FloatText(painter, cx, y, life, 34, tag));
  }

  // --- Drawing ---

  @override
  void render(Canvas canvas) {
    if (!hasLayout) return;
    final b = core.balance;
    final screen = Size(size.x, size.y);
    _drawBackground(canvas, screen);

    canvas.save();
    if (_shake > 0) {
      final k = _shake * _shake * 9;
      canvas.translate(math.sin(_t * 71) * k, math.cos(_t * 83) * k);
    }
    canvas.translate(_ox, _oy);
    canvas.scale(_scale);

    _drawContainer(canvas);

    // Aim guide and the piece in hand.
    if (!core.over && core.canDrop && sprites.isBuilt) {
      final lv = core.currentPiece;
      final r = b.radius(lv);
      final x = core.clampAim(aimX);
      final land = core.landingY(x, r);
      final guide = Paint()
        ..color = const Color(0x40FFFFFF)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var y = b.spawnY + r + 6; y < land - r; y += 11) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 5, land - r)), guide);
      }
      canvas.drawCircle(
        Offset(x, land),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0x38FFFFFF),
      );
      final ease = 1 - math.pow(1 - _ready, 3).toDouble();
      final bob = math.sin(_t * 3.2) * 1.5;
      sprites.draw(canvas, lv, x, b.spawnY + bob, r, 0, sx: 0.4 + 0.6 * ease, sy: 0.4 + 0.6 * ease, alpha: ease);
    }

    for (final o in core.bodies) {
      var sx = 1.0;
      var sy = 1.0;
      final q = _squash[o.id];
      if (q != null) {
        final k = 0.13 * q * q;
        sx += k;
        sy -= k;
      }
      final pop = _pop[o.id];
      if (pop != null) {
        final k = 0.2 * math.exp(-pop * 11) * math.cos(pop * 30);
        sx += k;
        sy += k;
      }
      sprites.draw(canvas, o.level, o.x, o.y, o.r, o.angle, sx: sx, sy: sy);
      if (model.profile.showNumbers) _drawNumber(canvas, o);
    }

    _drawEffects(canvas);
    canvas.restore();

    if (core.overflow > 0 || core.danger > 0.5) {
      final a = math.max(core.overflow * 0.5, (core.danger - 0.5) * 0.25 * (0.6 + 0.4 * math.sin(_t * 6)));
      canvas.drawRect(
        Offset.zero & screen,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, _oy), Offset(0, _oy + screen.height * 0.45), [
            Color.fromRGBO(255, 40, 70, a.clamp(0.0, 0.6)),
            const Color(0x00FF2846),
          ]),
      );
    }
    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & screen,
        Paint()..color = Color(0xFF000000 | _flashColor).withValues(alpha: (_flash * 0.5).clamp(0.0, 0.6)),
      );
    }
    if (kDebugMode && showStats) _drawStats(canvas);
  }

  void _drawBackground(Canvas canvas, Size screen) {
    final id = backgroundOverride ?? model.profile.background;
    if (_bg == null || _bgId != id || _bgSize != screen) {
      _bg?.dispose();
      final rec = ui.PictureRecorder();
      paintBackground(Canvas(rec), screen, backgroundTheme(id));
      _bg = rec.endRecording().toImageSync(screen.width.ceil().clamp(1, 4096), screen.height.ceil().clamp(1, 4096));
      _bgId = id;
      _bgSize = screen;
    }
    canvas.drawImage(_bg!, Offset.zero, Paint());
    // A handful of twinkling stars over the static backdrop.
    final rnd = math.Random(9);
    final p = Paint();
    for (var i = 0; i < 22; i++) {
      final x = rnd.nextDouble() * screen.width;
      final y = rnd.nextDouble() * screen.height;
      final phase = rnd.nextDouble() * 6.28;
      final a = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(_t * (0.8 + rnd.nextDouble() * 1.6) + phase));
      p.color = Color.fromRGBO(255, 255, 255, a);
      canvas.drawCircle(Offset(x, y), 0.8 + rnd.nextDouble() * 1.1, p);
    }
  }

  void _drawContainer(Canvas canvas) {
    final b = core.balance;
    final w = b.worldW;
    final f = b.floorY;
    const corner = 20.0;
    final shape = Path()
      ..moveTo(0, 8)
      ..lineTo(0, f - corner)
      ..quadraticBezierTo(0, f, corner, f)
      ..lineTo(w - corner, f)
      ..quadraticBezierTo(w, f, w, f - corner)
      ..lineTo(w, 8);
    final fill = Path.from(shape)..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, f), const [Color(0x05FFFFFF), Color(0x1AFFFFFF)]),
    );
    final edge = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(0, f),
      const [Color(0x008CF0FF), Color(0xCC8CF0FF), Color(0xCCB48CFF)],
      const [0, 0.25, 1],
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..shader = edge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..shader = edge,
    );

    // Overflow line: quiet when calm, loud when the stack reaches it.
    final hot = math.max(core.danger, core.overflow);
    final pulse = hot > 0.5 ? 0.65 + 0.35 * math.sin(_t * 9) : 1.0;
    final line = Paint()
      ..strokeWidth = 1.6 + core.overflow * 2.4
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(
        const Color(0x40FFFFFF),
        const Color(0xFFFF4466),
        hot,
      )!.withValues(alpha: (0.25 + 0.7 * hot) * pulse);
    for (var x = 8.0; x < w - 8; x += 16) {
      canvas.drawLine(Offset(x, b.dangerY), Offset(math.min(x + 8, w - 8), b.dangerY), line);
    }
    if (core.overflow > 0) {
      canvas.drawLine(
        Offset(8, b.dangerY),
        Offset(8 + (w - 16) * core.overflow, b.dangerY),
        Paint()
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFF4466),
      );
    }
  }

  void _drawNumber(Canvas canvas, Body o) {
    final tp = _numberPainters.putIfAbsent(
      o.level,
      () => TextPainter(
        text: TextSpan(
          text: '${o.level}',
          style: const TextStyle(
            fontFamily: 'Exo2',
            fontSize: 40,
            fontWeight: FontWeight.w800,
            fontVariations: [ui.FontVariation('wght', 800)],
            color: Color(0xFFFFFFFF),
            shadows: [Shadow(color: Color(0xFF000000), blurRadius: 8)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    final k = o.r * 0.82 / 40;
    canvas.save();
    canvas.translate(o.x, o.y);
    canvas.scale(k);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _drawEffects(Canvas canvas) {
    final ringPaint = Paint()..style = PaintingStyle.stroke;
    for (final r in _rings) {
      final t = r.life / r.max;
      final e = 1 - (1 - t) * (1 - t);
      ringPaint
        ..strokeWidth = 5 * (1 - t) + 0.6
        ..color = Color(0xFF000000 | r.color).withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(Offset(r.x, r.y), r.r0 + (r.r1 - r.r0) * e, ringPaint);
    }
    final pp = Paint()..blendMode = BlendMode.plus;
    for (final p in _particles) {
      if (p.life >= p.max) continue;
      final t = p.life / p.max;
      pp.color = Color(0xFF000000 | p.color).withValues(alpha: (1 - t) * 0.9);
      canvas.drawCircle(Offset(p.x, p.y), p.size * (1 - t * 0.6), pp);
    }
    for (final f in _texts) {
      final t = f.life / f.max;
      final appear = math.min(1.0, f.life / 0.12);
      final scale = 0.6 + 0.4 * appear + 0.25 * math.exp(-f.life * 14);
      final alpha = t > 0.65 ? (1 - (t - 0.65) / 0.35) : 1.0;
      canvas.save();
      canvas.translate(f.x, f.y - f.rise * (1 - (1 - t) * (1 - t)));
      canvas.scale(scale);
      if (alpha < 1) {
        canvas.saveLayer(
          Rect.fromCenter(center: Offset.zero, width: f.painter.width + 24, height: f.painter.height + 24),
          Paint()..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0)),
        );
      }
      f.painter.paint(canvas, Offset(-f.painter.width / 2, -f.painter.height / 2));
      if (alpha < 1) canvas.restore();
      canvas.restore();
    }
  }

  void _drawStats(Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
        text:
            'fps ${_fps.toStringAsFixed(0)}  bodies ${core.bodies.length}  particles $activeParticles  seed ${core.seed}',
        style: const TextStyle(fontSize: 11, color: Color(0xFF7CFF9A)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, size.y - 18));
  }

  void disposeResources() {
    sprites.dispose();
    _bg?.dispose();
    _bg = null;
    score.dispose();
    nextPiece.dispose();
    dropsLeft.dispose();
  }
}
