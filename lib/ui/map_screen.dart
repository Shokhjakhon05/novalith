/// The campaign map: five worlds on one winding path. Rows are built lazily and have a fixed
/// height, so a hundred levels scroll as cheaply as ten.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/campaign.dart';
import '../core/campaign_data.dart';
import '../core/progression.dart';
import 'campaign_widgets.dart';
import 'game_screen.dart';
import 'widgets.dart';

const double _rowHeight = 92;
const double _headerHeight = 150;

/// Horizontal position of a level's node, 0..1 across the path.
double _nodeX(int index) => 0.5 + 0.3 * math.sin(index * 0.95);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  ScrollController? _scroll;

  /// One entry per row: a world header (level == null) or a level.
  late final List<({WorldDef world, LevelDef? level})> _rows = [
    for (final w in worlds) ...[(world: w, level: null), for (final l in worldLevels(w.id)) (world: w, level: l)],
  ];

  double _offsetOf(int levelId) {
    var y = 0.0;
    for (final r in _rows) {
      if (r.level?.id == levelId) break;
      y += r.level == null ? _headerHeight : _rowHeight;
    }
    return y;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scroll != null) return;
    // The map climbs from the bottom up, so offsets are measured from the bottom edge:
    // open on the level the player is at, with the levels ahead in view above it.
    final model = AppScope.of(context);
    final at = model.nextCampaignLevel ?? campaignLevels.last;
    _scroll = ScrollController(initialScrollOffset: math.max(0, _offsetOf(at.id) - 220));
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  void _openLevel(LevelDef level) {
    final model = AppScope.read(context);
    if (!model.unlocked(level)) {
      showToast(context, model.t('locked_level'));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC050816),
      isScrollControlled: true,
      builder: (sheet) => _LevelSheet(
        level: level,
        onPlay: (master) {
          Navigator.of(sheet).pop();
          // Checked again at the moment of starting: a sheet left open must not start a
          // level that is not (or no longer) allowed.
          if (!model.unlocked(level) || (master && model.profile.starsOf(level.id) == 0)) return;
          Navigator.of(context).push(
            PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 180),
              reverseTransitionDuration: const Duration(milliseconds: 140),
              pageBuilder: (context, a, b) => GameScreen(level: level, master: master, exitLabel: 'map'),
              transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final current = model.nextCampaignLevel;
    final world = (current ?? campaignLevels.last).world;
    return GameScaffold(
      title: model.t('map'),
      showCoins: false,
      background: worldDef(world).background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: Palette.gold, size: 20),
                const SizedBox(width: 4),
                Text('${p.totalStars} / ${campaignLevels.length * 3}', style: ts(15, weight: 800, color: Palette.gold)),
                const SizedBox(width: 16),
                const Icon(Icons.diamond_rounded, color: Palette.cyan, size: 18),
                const SizedBox(width: 4),
                Text('${p.mastersDone} / ${campaignLevels.length}', style: ts(15, weight: 800, color: Palette.cyan)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.only(top: 40, bottom: 12),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final row = _rows[i];
                final level = row.level;
                if (level == null) return _WorldHeader(world: row.world);
                final next = i + 1 < _rows.length ? _rows[i + 1].level : null;
                return _LevelRow(
                  level: level,
                  next: next,
                  current: level.id == current?.id,
                  onTap: () => _openLevel(level),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldHeader extends StatelessWidget {
  const _WorldHeader({required this.world});
  final WorldDef world;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final levels = worldLevels(world.id);
    final open = model.unlocked(levels.first);
    final done = worldLevelsDone(p, world.id);
    final accent = worldColor(world.id);
    return SizedBox(
      height: _headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: GlassPanel(
          border: open ? accent.withValues(alpha: 0.8) : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              OrbView(level: world.emblem, size: 74, locked: !open),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.t('world_n', {'n': world.id}).toUpperCase(),
                      style: ts(11.5, weight: 700, color: Palette.faint, spacing: 1.4),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        model.worldName(world.id),
                        style: ts(22, weight: 800, color: open ? accent : Palette.dim),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ProgressBar(value: done / levels.length, color: accent, height: 6),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(model.t('level_of', {'n': done, 'm': levels.length}), style: ts(12.5, color: Palette.dim)),
                        const Spacer(),
                        const Icon(Icons.star_rounded, size: 15, color: Palette.gold),
                        const SizedBox(width: 3),
                        Text(
                          '${worldStars(p, world.id)} / ${levels.length * 3}',
                          style: ts(12.5, weight: 700, color: Palette.gold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!open) ...[const SizedBox(width: 8), const Icon(Icons.lock_rounded, color: Palette.faint)],
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level, required this.next, required this.current, required this.onTap});
  final LevelDef level;

  /// The level this one leads to within the same world, or null at the end of a world.
  final LevelDef? next;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final rec = model.profile.levels[level.id];
    final stars = rec?.stars ?? 0;
    final open = model.unlocked(level);
    final accent = worldColor(level.world);
    final size = level.trial ? 76.0 : (current ? 66.0 : 56.0);
    return SizedBox(
      height: _rowHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final x = _nodeX(level.index) * w;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (next != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PathPainter(
                      Offset(x, _rowHeight / 2),
                      Offset(_nodeX(next!.index) * w, -_rowHeight * 0.5),
                      stars > 0 ? accent : const Color(0x40FFFFFF),
                    ),
                  ),
                ),
              Positioned(
                left: x - 60,
                width: 120,
                top: 0,
                height: _rowHeight,
                child: Semantics(
                  button: true,
                  label: '${model.t('level_n', {'n': levelTag(level)})}${open ? '' : ' 🔒'}',
                  child: GestureDetector(
                    key: ValueKey('level-${level.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: size,
                          height: size,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.3, -0.4),
                              colors: !open
                                  ? const [Color(0xFF2A2748), Color(0xFF14122A)]
                                  : stars > 0
                                  ? [Color.lerp(accent, Colors.white, 0.35)!, Color.lerp(accent, Palette.ink, 0.45)!]
                                  : const [Color(0xFF4A4488), Color(0xFF211C4A)],
                            ),
                            border: Border.all(
                              color: current ? Palette.cyan : (open ? accent : const Color(0x33FFFFFF)),
                              width: current ? 3 : 1.6,
                            ),
                            boxShadow: current
                                ? const [BoxShadow(color: Color(0x998CF0FF), blurRadius: 18, spreadRadius: 1)]
                                : null,
                          ),
                          child: !open
                              ? const Icon(Icons.lock_rounded, color: Palette.faint, size: 22)
                              : level.trial
                              ? Icon(Icons.public_rounded, color: stars > 0 ? Palette.ink : Palette.text, size: 36)
                              : Text(
                                  '${level.index}',
                                  style: ts(
                                    current ? 24 : 20,
                                    weight: 800,
                                    color: stars > 0 ? Palette.ink : Palette.text,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 2),
                        if (open)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StarRow(stars: stars, size: 14),
                              if (rec?.master ?? false) ...[
                                const SizedBox(width: 3),
                                const Icon(Icons.diamond_rounded, size: 13, color: Palette.cyan),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.from, this.to, this.color);
  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = (from.dy + to.dy) / 2;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx, mid, to.dx, mid, to.dx, to.dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.from != from || old.to != to || old.color != color;
}

/// What a level asks for, what the stars need, the player's record - and the way in.
class _LevelSheet extends StatelessWidget {
  const _LevelSheet({required this.level, required this.onPlay});
  final LevelDef level;
  final void Function(bool master) onPlay;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final rec = model.profile.levels[level.id];
    final stars = rec?.stars ?? 0;
    final accent = worldColor(level.world);
    final assist = level.assistDrops(model.profile.fails[level.id] ?? 0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          solid: true,
          border: accent,
          radius: 26,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(levelTag(level), style: ts(26, weight: 800, color: accent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      level.trial ? model.t('trial') : model.worldName(level.world),
                      style: ts(15, weight: 700, color: Palette.dim),
                    ),
                  ),
                  StarRow(stars: stars, size: 22),
                ],
              ),
              const SizedBox(height: 14),
              _line(Icons.star_rounded, goalLines(model, level).join(' · '), stars >= 1, big: true),
              _line(Icons.star_rounded, starText(model, level, 2), stars >= 2),
              _line(Icons.star_rounded, starText(model, level, 3), stars >= 3),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.south_rounded, size: 16, color: Palette.cyan),
                  const SizedBox(width: 6),
                  Text(
                    model.t('drops_left', {'n': level.drops + assist}),
                    style: ts(13.5, weight: 600, color: Palette.dim),
                  ),
                  const Spacer(),
                  if ((rec?.best ?? 0) > 0)
                    Text('${model.t('best')} ${formatNumber(rec!.best)}', style: ts(13.5, color: Palette.dim)),
                ],
              ),
              const SizedBox(height: 16),
              GameButton(
                label: model.t(stars > 0 ? 'play_again' : 'start'),
                icon: Icons.play_arrow_rounded,
                primary: true,
                onTap: () => onPlay(false),
              ),
              if (stars > 0) ...[
                const SizedBox(height: 10),
                GameButton(
                  label: model.t('master'),
                  icon: Icons.diamond_rounded,
                  color: Palette.cyan,
                  compact: true,
                  onTap: () => onPlay(true),
                  trailing: (rec?.master ?? false)
                      ? const Icon(Icons.check_circle_rounded, color: Palette.green, size: 20)
                      : CoinBadge(amount: level.masterCoins, size: 13),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${goalLines(model, level, master: true).join(' · ')} · '
                    '${model.t('drops_left', {'n': level.master.drops})}',
                    style: ts(12, color: Palette.faint),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, bool done, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: done ? Palette.gold : Palette.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: ts(big ? 16.5 : 14.5, weight: big ? 700 : 600, color: done ? Palette.text : Palette.dim),
            ),
          ),
        ],
      ),
    );
  }
}
