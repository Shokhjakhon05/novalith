/// Every celestial body is painted by code and baked once into an image per level and theme.
/// No bitmap art ships with the game.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/balance.dart';

/// How far the baked image extends beyond the collision radius (room for glows and rings).
const double orbBleed = 1.36;

Color _c(int hex, [double alpha = 1]) => Color(0xFF000000 | hex).withValues(alpha: alpha);

void _glow(Canvas c, double r, int hex, double spread, double alpha) {
  final rr = r * spread;
  c.drawCircle(
    Offset.zero,
    rr,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        rr,
        [_c(hex, alpha), _c(hex, alpha * 0.45), _c(hex, 0)],
        [r / rr * 0.75, r / rr, 1],
      ),
  );
}

void _sphere(Canvas c, double r, int light, int mid, int dark) {
  c.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(-r * 0.36, -r * 0.42),
        r * 1.6,
        [_c(light), _c(mid), _c(dark)],
        const [0, 0.5, 1],
      ),
  );
}

void _shade(Canvas c, double r, [double strength = 0.42]) {
  c.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(-r * 0.25, -r * 0.3),
        r * 1.32,
        [_c(0, 0), _c(0, 0), _c(0, strength)],
        const [0, 0.62, 1],
      ),
  );
}

void _gloss(Canvas c, double r, [double alpha = 0.34]) {
  c.drawOval(
    Rect.fromCenter(center: Offset(-r * 0.36, -r * 0.46), width: r * 0.62, height: r * 0.34),
    Paint()
      ..color = _c(0xFFFFFF, alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.1),
  );
}

void _craters(Canvas c, double r, int count, int seed, int dark, int rim) {
  final rnd = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final a = rnd.nextDouble() * math.pi * 2;
    final d = math.sqrt(rnd.nextDouble()) * r * 0.72;
    final cr = r * (0.09 + rnd.nextDouble() * 0.13);
    final o = Offset(math.cos(a) * d, math.sin(a) * d);
    c.drawCircle(o.translate(cr * 0.14, cr * 0.16), cr, Paint()..color = _c(rim, 0.5));
    c.drawCircle(o, cr, Paint()..color = _c(dark, 0.55));
  }
}

void _blobs(Canvas c, double r, int count, int seed, List<int> colors, double alpha, double size) {
  final rnd = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final a = rnd.nextDouble() * math.pi * 2;
    final d = math.sqrt(rnd.nextDouble()) * r * 0.85;
    final w = r * size * (0.6 + rnd.nextDouble());
    final h = w * (0.45 + rnd.nextDouble() * 0.5);
    c.save();
    c.translate(math.cos(a) * d, math.sin(a) * d);
    c.rotate(rnd.nextDouble() * math.pi);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()
        ..color = _c(colors[rnd.nextInt(colors.length)], alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.035),
    );
    c.restore();
  }
}

void _clipCircle(Canvas c, double r) => c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));

void _ringHalf(Canvas c, double rx, double ry, double tilt, double width, List<Color> colors, bool front) {
  c.save();
  c.rotate(tilt);
  final rect = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
  c.drawArc(
    rect,
    front ? 0 : math.pi,
    math.pi,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(Offset(-rx, 0), Offset(rx, 0), colors, [
        for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
      ]),
  );
  c.restore();
}

/// Paints level [key] centred on the origin with collision radius [r].
void paintOrb(Canvas c, String key, double r) {
  switch (key) {
    case 'dust':
      _glow(c, r, 0xBFE3FF, 1.3, 0.4);
      _sphere(c, r, 0xFFFFFF, 0xA9C6EA, 0x4F6A96);
      _shade(c, r, 0.3);
      final rnd = math.Random(3);
      for (var i = 0; i < 5; i++) {
        final a = rnd.nextDouble() * 6.28;
        final d = rnd.nextDouble() * r * 0.6;
        _sparkle(c, Offset(math.cos(a) * d, math.sin(a) * d), r * (0.12 + rnd.nextDouble() * 0.1), 0.9);
      }
      _gloss(c, r, 0.4);
    case 'meteor':
      _sphere(c, r, 0xE9B98A, 0xA5653A, 0x47240F);
      c.save();
      _clipCircle(c, r);
      _craters(c, r, 4, 11, 0x3A1C0B, 0xF0C79C);
      c.restore();
      _shade(c, r);
      _gloss(c, r, 0.22);
    case 'asteroid':
      _sphere(c, r, 0xD9DCE6, 0x858A9C, 0x343747);
      c.save();
      _clipCircle(c, r);
      _craters(c, r, 8, 21, 0x2A2C39, 0xEEF0F7);
      final crack = Paint()
        ..color = _c(0x20222C, 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..strokeCap = StrokeCap.round;
      c.drawPath(
        Path()
          ..moveTo(-r * 0.7, r * 0.1)
          ..lineTo(-r * 0.3, r * 0.22)
          ..lineTo(-r * 0.1, r * 0.55)
          ..lineTo(r * 0.25, r * 0.7),
        crack,
      );
      c.restore();
      _shade(c, r);
      _gloss(c, r, 0.2);
    case 'moon':
      _glow(c, r, 0xFFF6D6, 1.22, 0.28);
      _sphere(c, r, 0xFFFDF2, 0xDDD6BD, 0x8A8470);
      c.save();
      _clipCircle(c, r);
      _craters(c, r, 6, 31, 0x8E8873, 0xFFFFFF);
      c.restore();
      _shade(c, r, 0.36);
      _gloss(c, r, 0.3);
    case 'planet':
      _glow(c, r, 0x6FD3FF, 1.2, 0.45);
      _sphere(c, r, 0x9BE2FF, 0x2F80ED, 0x0F347F);
      c.save();
      _clipCircle(c, r);
      _blobs(c, r, 7, 41, [0x5FD46B, 0x2FA24E, 0x8BE07A], 0.95, 0.5);
      _blobs(c, r, 6, 42, [0xFFFFFF], 0.5, 0.55);
      c.restore();
      _shade(c, r, 0.5);
      c.drawCircle(
        Offset.zero,
        r * 0.985,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..color = _c(0xA8ECFF, 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04),
      );
      _gloss(c, r, 0.36);
    case 'giant':
      final br = r * 0.72;
      final ring = [_c(0xC58A55), _c(0xFFE9C4), _c(0xC58A55)];
      _ringHalf(c, r * 0.97, r * 0.3, -0.32, r * 0.11, ring, false);
      _sphere(c, br, 0xFFE9BF, 0xE9A45E, 0x8C481B);
      c.save();
      _clipCircle(c, br);
      final bands = [0xC97B3E, 0xFFDCA6, 0xB7652E, 0xFFE9C6, 0xD48B4C];
      for (var i = 0; i < bands.length; i++) {
        final y = -br * 0.72 + i * br * 0.36;
        c.drawOval(
          Rect.fromCenter(center: Offset(0, y), width: br * 2.6, height: br * 0.22),
          Paint()
            ..color = _c(bands[i], 0.5)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.03),
        );
      }
      c.drawOval(
        Rect.fromCenter(center: Offset(br * 0.3, br * 0.24), width: br * 0.42, height: br * 0.24),
        Paint()..color = _c(0xC2412B, 0.8),
      );
      c.restore();
      _shade(c, br, 0.48);
      _gloss(c, br, 0.3);
      _ringHalf(c, r * 0.97, r * 0.3, -0.32, r * 0.11, ring, true);
    case 'dwarf':
      _glow(c, r, 0xA9CCFF, 1.34, 0.6);
      _sphere(c, r, 0xFFFFFF, 0xC4DCFF, 0x4F7FE8);
      _shade(c, r, 0.3);
      _sparkle(c, Offset.zero, r * 1.3, 0.75);
      _gloss(c, r, 0.5);
    case 'sun':
      _glow(c, r, 0xFFB03A, 1.34, 0.65);
      _sphere(c, r, 0xFFFBC4, 0xFFC53D, 0xFF7417);
      c.save();
      _clipCircle(c, r);
      _blobs(c, r, 16, 81, [0xFFF2A0, 0xFF8A1F, 0xFFD45A], 0.33, 0.34);
      c.restore();
      c.drawCircle(
        Offset.zero,
        r * 0.97,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07
          ..color = _c(0xFFE38A, 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
      );
      _gloss(c, r, 0.3);
    case 'redgiant':
      _glow(c, r, 0xFF4A2E, 1.34, 0.6);
      _sphere(c, r, 0xFFC09A, 0xEA4630, 0x76101B);
      c.save();
      _clipCircle(c, r);
      _blobs(c, r, 22, 91, [0x8C1420, 0xFF8A4A, 0xC2281F, 0xFFB070], 0.34, 0.36);
      c.restore();
      _shade(c, r, 0.34);
      _gloss(c, r, 0.22);
    case 'neutron':
      _glow(c, r, 0x5AD8FF, 1.3, 0.5);
      c.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            r,
            [_c(0x6F5BFF, 0.95), _c(0x2B1C78), _c(0x140C3D)],
            const [0, 0.6, 1],
          ),
      );
      c.save();
      _clipCircle(c, r);
      for (final dir in [1.0, -1.0]) {
        final beam = Path()
          ..moveTo(0, 0)
          ..lineTo(dir * r * 0.78, -dir * r * 1.05)
          ..lineTo(dir * r * 1.05, -dir * r * 0.78)
          ..close();
        c.drawPath(
          beam,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(dir * r * 0.9, -dir * r * 0.9), [
              _c(0xE6FBFF, 0.95),
              _c(0x4FD6FF, 0.0),
            ])
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03),
        );
      }
      c.restore();
      for (final k in [0.62, 0.84]) {
        c.save();
        c.rotate(0.78);
        c.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2 * k, height: r * 0.62 * k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.025
            ..color = _c(0x9BEBFF, 0.7),
        );
        c.restore();
      }
      _glow(c, r * 0.4, 0xC8F7FF, 1.9, 0.8);
      _sphere(c, r * 0.4, 0xFFFFFF, 0xC4F6FF, 0x45CBFF);
      c.drawCircle(
        Offset.zero,
        r * 0.975,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04
          ..color = _c(0x8FE6FF, 0.75),
      );
    case 'blackhole':
      _glow(c, r, 0xA04BFF, 1.3, 0.45);
      c.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            r,
            [_c(0x000000), _c(0x1A0A2E), _c(0x3A1560), _c(0x12081F)],
            const [0.4, 0.62, 0.86, 1],
          ),
      );
      final disk = [_c(0x7A2BFF), _c(0xFF3D6E), _c(0xFFB04A), _c(0xFFF4CC), _c(0xFFB04A), _c(0xFF3D6E), _c(0x7A2BFF)];
      _ringHalf(c, r * 0.9, r * 0.3, -0.38, r * 0.17, disk, false);
      c.drawCircle(Offset.zero, r * 0.46, Paint()..color = _c(0x000000));
      c.drawCircle(
        Offset.zero,
        r * 0.47,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.035
          ..color = _c(0xFFE9B8, 0.9)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.02),
      );
      _ringHalf(c, r * 0.9, r * 0.3, -0.38, r * 0.17, disk, true);
      c.drawCircle(
        Offset.zero,
        r * 0.975,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.035
          ..color = _c(0xC79BFF, 0.7),
      );
    case 'galaxy':
    default:
      _glow(c, r, 0x9F8BFF, 1.32, 0.55);
      c.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, r, [_c(0x3A2580), _c(0x1B1150), _c(0x090520)], const [0, 0.55, 1]),
      );
      c.save();
      _clipCircle(c, r);
      final rnd = math.Random(120);
      final star = Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.008);
      for (var arm = 0; arm < 2; arm++) {
        for (var i = 0; i < 420; i++) {
          final t = i / 420;
          final ang = arm * math.pi + t * 5.2 + (rnd.nextDouble() - 0.5) * 0.5;
          final rad = r * (0.1 + 0.84 * t) + (rnd.nextDouble() - 0.5) * r * 0.2;
          final size = r * (0.032 - 0.016 * t) * (0.5 + rnd.nextDouble());
          final col = Color.lerp(
            Color.lerp(_c(0xFFF3D6), _c(0x9FD4FF), (t * 1.6).clamp(0, 1)),
            _c(0xD08BFF),
            ((t - 0.55) * 2.2).clamp(0, 1),
          )!;
          star.color = col.withValues(alpha: 0.35 + rnd.nextDouble() * 0.4);
          c.drawCircle(Offset(math.cos(ang) * rad, math.sin(ang) * rad), size, star);
        }
      }
      c.restore();
      c.drawCircle(
        Offset.zero,
        r * 0.42,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            r * 0.42,
            [_c(0xFFFFFF), _c(0xFFE9A8, 0.85), _c(0xFFE9A8, 0)],
            const [0, 0.35, 1],
          ),
      );
      c.drawCircle(
        Offset.zero,
        r * 0.975,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.035
          ..color = _c(0xCDBBFF, 0.75),
      );
  }
}

void _sparkle(Canvas c, Offset at, double size, double alpha) {
  final p = Paint()..shader = ui.Gradient.radial(at, size, [_c(0xFFFFFF, alpha), _c(0xFFFFFF, 0)]);
  final thin = size * 0.09;
  c.drawPath(
    Path()
      ..moveTo(at.dx - size, at.dy)
      ..quadraticBezierTo(at.dx, at.dy - thin, at.dx + size, at.dy)
      ..quadraticBezierTo(at.dx, at.dy + thin, at.dx - size, at.dy)
      ..moveTo(at.dx, at.dy - size)
      ..quadraticBezierTo(at.dx + thin, at.dy, at.dx, at.dy + size)
      ..quadraticBezierTo(at.dx - thin, at.dy, at.dx, at.dy - size),
    p,
  );
}

/// A cosmetic theme: a colour transform applied to the whole body plus an optional overlay.
class OrbTheme {
  const OrbTheme(this.id, this.matrix, this.accent, {this.outline = false, this.facets = false});
  final String id;
  final List<double>? matrix;

  /// Preview / UI accent colour.
  final int accent;
  final bool outline;
  final bool facets;
}

List<double> _saturation(double s, [double gain = 1]) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final a = (1 - s);
  return [
    (a * lr + s) * gain,
    a * lg * gain,
    a * lb * gain,
    0,
    0,
    a * lr * gain,
    (a * lg + s) * gain,
    a * lb * gain,
    0,
    0,
    a * lr * gain,
    a * lg * gain,
    (a * lb + s) * gain,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _hueRotate(double degrees) {
  final a = degrees * math.pi / 180;
  final cs = math.cos(a);
  final sn = math.sin(a);
  return [
    0.213 + cs * 0.787 - sn * 0.213,
    0.715 - cs * 0.715 - sn * 0.715,
    0.072 - cs * 0.072 + sn * 0.928,
    0,
    0,
    0.213 - cs * 0.213 + sn * 0.143,
    0.715 + cs * 0.285 + sn * 0.140,
    0.072 - cs * 0.072 - sn * 0.283,
    0,
    0,
    0.213 - cs * 0.213 - sn * 0.787,
    0.715 - cs * 0.715 + sn * 0.715,
    0.072 + cs * 0.928 + sn * 0.072,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

final Map<String, OrbTheme> orbThemes = {
  'theme_cosmos': const OrbTheme('theme_cosmos', null, 0xFFB03A),
  'theme_neon': OrbTheme('theme_neon', _saturation(1.9, 1.08), 0x39FFB6, outline: true),
  'theme_crystal': const OrbTheme(
    'theme_crystal',
    [0.50, 0.30, 0.10, 0, 18, 0.22, 0.62, 0.16, 0, 30, 0.20, 0.36, 0.60, 0, 60, 0, 0, 0, 1, 0],
    0x9FE4FF,
    facets: true,
  ),
  'theme_ember': const OrbTheme('theme_ember', [
    1.00,
    0.42,
    0.20,
    0,
    12,
    0.16,
    0.62,
    0.10,
    0,
    0,
    0.04,
    0.10,
    0.34,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ], 0xFF6A2B),
  'theme_aurora': OrbTheme('theme_aurora', _hueRotate(118), 0x58F0C0),
  'theme_void': const OrbTheme(
    'theme_void',
    [0.36, 0.72, 0.10, 0, 6, 0.26, 0.62, 0.08, 0, 0, 0.44, 0.80, 0.16, 0, 22, 0, 0, 0, 1, 0],
    0xB48CFF,
    outline: true,
  ),
};

OrbTheme orbTheme(String id) => orbThemes[id] ?? orbThemes['theme_cosmos']!;

/// Baked images of every level for one theme.
class OrbSprites {
  /// Image pixels per world unit: enough for a 1080p-wide board without visible blur.
  static const double bake = 3.0;

  final Map<int, ui.Image> _images = {};
  String themeId = '';

  bool get isBuilt => _images.isNotEmpty;
  ui.Image? image(int level) => _images[level];

  void build(String theme, Balance balance) {
    if (theme == themeId && _images.isNotEmpty) return;
    dispose();
    themeId = theme;
    final t = orbTheme(theme);
    for (final lv in balance.levels) {
      final half = lv.radius * orbBleed;
      final px = (half * 2 * bake).ceil();
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.scale(bake);
      c.translate(half, half);
      final bounds = Rect.fromCircle(center: Offset.zero, radius: half);
      if (t.matrix != null) {
        c.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(Float64List.fromList(t.matrix!)));
      }
      paintOrb(c, lv.key, lv.radius);
      if (t.matrix != null) c.restore();
      if (t.facets) _facets(c, lv.radius);
      if (t.outline) {
        c.drawCircle(
          Offset.zero,
          lv.radius * 0.97,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = lv.radius * 0.05
            ..color = _c(t.accent, 0.95)
            ..maskFilter = MaskFilter.blur(BlurStyle.solid, lv.radius * 0.05),
        );
      }
      _images[lv.id] = rec.endRecording().toImageSync(px, px);
    }
  }

  void _facets(Canvas c, double r) {
    c.save();
    _clipCircle(c, r);
    final p = Paint()
      ..color = _c(0xFFFFFF, 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.02;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + 0.3;
      c.drawLine(Offset(-r * 0.2, -r * 0.25), Offset(math.cos(a) * r, math.sin(a) * r), p);
    }
    c.drawCircle(Offset(-r * 0.2, -r * 0.25), r * 0.3, Paint()..color = _c(0xFFFFFF, 0.14));
    c.restore();
  }

  static final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Draws [level] at world position ([x], [y]) with collision radius [r].
  void draw(
    Canvas c,
    int level,
    double x,
    double y,
    double r,
    double angle, {
    double sx = 1,
    double sy = 1,
    double alpha = 1,
  }) {
    final img = _images[level];
    if (img == null) return;
    c.save();
    c.translate(x, y);
    if (sx != 1 || sy != 1) c.scale(sx, sy);
    if (angle != 0) c.rotate(angle);
    final half = r * orbBleed;
    _paint.color = Color.fromRGBO(255, 255, 255, alpha);
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTRB(-half, -half, half, half),
      _paint,
    );
    c.restore();
  }

  void dispose() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
  }
}

/// Background recipes.
class BackgroundTheme {
  const BackgroundTheme(this.id, this.top, this.bottom, this.nebulaA, this.nebulaB, this.star);
  final String id;
  final int top;
  final int bottom;
  final int nebulaA;
  final int nebulaB;
  final int star;
}

const Map<String, BackgroundTheme> backgrounds = {
  'bg_deep': BackgroundTheme('bg_deep', 0x090C24, 0x180A30, 0x963CFF, 0x1EBEFF, 0xFFFFFF),
  'bg_nebula': BackgroundTheme('bg_nebula', 0x1A0B3A, 0x3B0F4E, 0xFF4FB3, 0x7A5BFF, 0xFFE3FA),
  'bg_dawn': BackgroundTheme('bg_dawn', 0x101A44, 0x5A2548, 0xFF8A5C, 0xFFD27A, 0xFFF1DC),
  'bg_emerald': BackgroundTheme('bg_emerald', 0x04201F, 0x06342B, 0x2CFFB0, 0x1E9DFF, 0xDFFFF3),
  'bg_crimson': BackgroundTheme('bg_crimson', 0x1C0508, 0x3A0A16, 0xFF3A4E, 0xFF8A3A, 0xFFE2DC),
  'bg_singularity': BackgroundTheme('bg_singularity', 0x000000, 0x0C0616, 0x7A2BFF, 0xFFB04A, 0xE6DBFF),
};

BackgroundTheme backgroundTheme(String id) => backgrounds[id] ?? backgrounds['bg_deep']!;

/// Paints a static space backdrop of [size]: gradient, two soft nebulae and far stars.
void paintBackground(Canvas c, Size size, BackgroundTheme bg) {
  final rect = Offset.zero & size;
  c.drawRect(
    rect,
    Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [_c(bg.top), _c(bg.bottom)]),
  );
  final m = size.shortestSide;
  void nebula(Offset at, double radius, int hex, double alpha) {
    c.drawCircle(at, radius, Paint()..shader = ui.Gradient.radial(at, radius, [_c(hex, alpha), _c(hex, 0)]));
  }

  nebula(Offset(size.width * 0.15, size.height * 0.2), m * 0.75, bg.nebulaA, 0.30);
  nebula(Offset(size.width * 0.9, size.height * 0.78), m * 0.85, bg.nebulaB, 0.24);
  nebula(Offset(size.width * 0.55, size.height * 0.5), m * 0.5, bg.nebulaA, 0.10);
  final rnd = math.Random(5);
  final p = Paint();
  for (var i = 0; i < 110; i++) {
    p.color = _c(bg.star, 0.15 + rnd.nextDouble() * 0.5);
    c.drawCircle(
      Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
      0.4 + rnd.nextDouble() * 1.1,
      p,
    );
  }
}
