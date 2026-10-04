/// Shared look: colours, typography and the handful of widgets every screen is built from.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/balance.dart';
import '../game/sprites.dart';
import '../services/feedback.dart';

class Palette {
  static const Color ink = Color(0xFF070A1C);
  static const Color cyan = Color(0xFF8CF0FF);
  static const Color violet = Color(0xFFB48CFF);
  static const Color gold = Color(0xFFFFD65A);
  static const Color rose = Color(0xFFFF4D7A);
  static const Color green = Color(0xFF58F0A0);
  static const Color text = Color(0xFFFFFFFF);
  static const Color dim = Color(0xB3FFFFFF);
  static const Color faint = Color(0x66FFFFFF);

  static const List<Color> rarity = [Color(0xFFB8C4D9), Color(0xFF6FD3FF), Color(0xFFC58BFF), Color(0xFFFFC53D)];
}

/// Exo 2 for Latin and Cyrillic; every other script falls back to the system font.
TextStyle ts(double size, {int weight = 600, Color color = Palette.text, double? height, double spacing = 0}) {
  return TextStyle(
    fontFamily: 'Exo2',
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
    fontVariations: [ui.FontVariation('wght', weight.toDouble())],
    color: color,
    height: height,
    letterSpacing: spacing,
    decoration: TextDecoration.none,
  );
}

/// The static space backdrop behind menus.
class SpaceBackdrop extends StatelessWidget {
  const SpaceBackdrop({super.key, required this.child, this.background});
  final Widget child;

  /// Null = the backdrop the player has equipped.
  final String? background;

  @override
  Widget build(BuildContext context) {
    final id = background ?? AppScope.of(context).profile.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: _BackdropPainter(id))),
        child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) => paintBackground(canvas, size, backgroundTheme(id));

  @override
  bool shouldRepaint(_BackdropPainter old) => old.id != id;
}

/// Baked pictures of the celestial bodies for menus, shop, collection and the map. A recipe is
/// rasterised once and then drawn as a plain image: painting the recipes live on every frame
/// (hundreds of blurred shapes each) is what froze the collection screen on phones.
class OrbImages {
  static const int _px = 256;
  static const int _capacity = 48;
  static final Map<String, ui.Image> _cache = {};

  static ui.Image get(EvoLevel level, String theme, bool locked) {
    final key = locked ? '${level.key}|locked' : '${level.key}|$theme';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    if (_cache.length >= _capacity) _cache.remove(_cache.keys.first)?.dispose();

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final r = _px / 2 / orbBleed;
    canvas.translate(_px / 2, _px / 2);
    final bounds = Rect.fromCircle(center: Offset.zero, radius: _px / 2);
    if (locked) {
      // Undiscovered: a dark silhouette.
      canvas.saveLayer(
        bounds,
        Paint()
          ..colorFilter = const ColorFilter.matrix([0, 0, 0, 0, 22, 0, 0, 0, 0, 26, 0, 0, 0, 0, 52, 0, 0, 0, 0.85, 0]),
      );
      paintOrb(canvas, level.key, r);
      canvas.restore();
    } else {
      final t = orbTheme(theme);
      if (t.matrix != null) {
        canvas.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(Float64List.fromList(t.matrix!)));
      }
      paintOrb(canvas, level.key, r);
      if (t.matrix != null) canvas.restore();
      if (t.outline) {
        canvas.drawCircle(
          Offset.zero,
          r * 0.97,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.05
            ..color = Color(0xFF000000 | t.accent),
        );
      }
    }
    return _cache[key] = rec.endRecording().toImageSync(_px, _px);
  }
}

/// A celestial body (used in menus, shop, collection and the map).
class OrbView extends StatelessWidget {
  const OrbView({super.key, required this.level, required this.size, this.theme, this.locked = false});
  final int level;
  final double size;
  final String? theme;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _OrbPainter(model.balance.level(level), theme ?? model.profile.theme, locked),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.level, this.theme, this.locked);
  final EvoLevel level;
  final String theme;
  final bool locked;

  static final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    final img = OrbImages.get(level, theme, locked);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.level.id != level.id || old.theme != theme || old.locked != locked;
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.radius = 22,
    this.solid = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;
  final double radius;

  /// Dialog-style panels sit on an opaque base so nothing behind shows through the text.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: solid ? const [Color(0xFF2A2456), Color(0xFF15102F)] : const [Color(0x2EFFFFFF), Color(0x12FFFFFF)],
        ),
        border: Border.all(color: border ?? const Color(0x33FFFFFF), width: 1.2),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The game's button: big touch target, press animation, click sound and haptic built in.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.color,
    this.enabled = true,
    this.trailing,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final Color? color;
  final bool enabled;
  final Widget? trailing;
  final bool compact;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final accent = widget.color ?? (widget.primary ? Palette.cyan : Palette.violet);
    final fg = widget.primary ? Palette.ink : Palette.text;
    return Semantics(
      button: true,
      enabled: active,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => setState(() => _down = true) : null,
        onTapCancel: active ? () => setState(() => _down = false) : null,
        onTapUp: active
            ? (_) {
                setState(() => _down = false);
                final model = AppScope.read(context);
                model.audio.play(Sfx.tap, volume: 0.6);
                model.haptics.fire(Haptic.tap);
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 70),
          child: Opacity(
            opacity: active ? 1 : 0.45,
            child: Container(
              constraints: BoxConstraints(minHeight: widget.compact ? 48 : 58),
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 16 : 22, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: widget.primary
                    ? LinearGradient(colors: [accent, Color.lerp(accent, Palette.violet, 0.55)!])
                    : const LinearGradient(colors: [Color(0x2EFFFFFF), Color(0x14FFFFFF)]),
                border: Border.all(
                  color: widget.primary ? const Color(0x66FFFFFF) : accent.withValues(alpha: 0.55),
                  width: 1.3,
                ),
                boxShadow: widget.primary
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: -4,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: fg, size: widget.compact ? 20 : 24),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        style: ts(widget.compact ? 16 : 19, weight: 700, color: fg),
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[const SizedBox(width: 10), widget.trailing!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button with a 48dp touch target.
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.onTap, required this.semantic});
  final IconData icon;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final model = AppScope.read(context);
          model.audio.play(Sfx.tap, volume: 0.6);
          model.haptics.fire(Haptic.tap);
          onTap();
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x24FFFFFF),
            border: Border.all(color: const Color(0x40FFFFFF)),
          ),
          child: Icon(icon, color: Palette.text, size: 24),
        ),
      ),
    );
  }
}

class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.amount, this.size = 17});
  final int amount;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoinIcon(size: size + 3),
        const SizedBox(width: 6),
        Text(formatNumber(amount), style: ts(size, weight: 700, color: Palette.gold)),
      ],
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          colors: [Color(0xFFFFF6C2), Color(0xFFFFC53D), Color(0xFFE08A12)],
        ),
        border: Border.all(color: const Color(0xFFFFE9A0), width: size * 0.07),
      ),
      child: Icon(Icons.star_rounded, size: size * 0.62, color: const Color(0xFFB8690A)),
    );
  }
}

/// 12345 -> "12 345". The separator is a no-break space: it keeps the digits together as one
/// number in right-to-left text (a plain space would let the groups be reordered).
String formatNumber(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('\u00A0');
    out.write(s[i]);
  }
  return out.toString();
}

/// Screen scaffold used by every secondary screen: backdrop, back button, title, coins.
class GameScaffold extends StatelessWidget {
  const GameScaffold({super.key, required this.title, required this.child, this.showCoins = true, this.background});
  final String title;
  final Widget child;
  final bool showCoins;
  final String? background;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    return Scaffold(
      backgroundColor: Palette.ink,
      body: SpaceBackdrop(
        background: background,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    RoundButton(
                      icon: model.rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                      semantic: model.t('home'),
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(title, style: ts(26, weight: 800)),
                      ),
                    ),
                    if (showCoins) ...[const SizedBox(width: 10), CoinBadge(amount: model.profile.coins)],
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: ts(15, weight: 600), textAlign: TextAlign.center),
        backgroundColor: const Color(0xF0231A4A),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        duration: const Duration(milliseconds: 1800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
}
