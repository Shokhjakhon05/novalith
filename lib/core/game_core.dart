/// The whole game simulation: physics, merging, combos, scoring, overflow. Pure Dart, no
/// rendering, fixed time step - the same seed and the same inputs always give the same run.
library;

import 'dart:math' as math;

import 'balance.dart';
import 'rng.dart';

enum EventType { drop, impact, merge, bigBang, dangerEnter, dangerExit, gameOver, continued }

enum EndReason { none, overflow, dropsExhausted, completed }

class GameEvent {
  const GameEvent(
    this.type, {
    this.x = 0,
    this.y = 0,
    this.level = 0,
    this.chain = 0,
    this.points = 0,
    this.perfect = false,
    this.speed = 0,
    this.firstTime = false,
    this.id = 0,
  });

  final EventType type;
  final double x;
  final double y;

  /// For merge: the level that was created. For drop/impact: the level of the piece.
  final int level;
  final int chain;
  final int points;
  final bool perfect;
  final double speed;

  /// Merge only: this level was created for the first time in this run.
  final bool firstTime;

  /// The body the event is about (the dropped / hit piece, or the newly merged one).
  final int id;
}

class Body {
  Body(this.id, this.level, this.x, this.y, this.r, this.targetR) : px = x, py = y;

  final int id;
  final int level;
  double x;
  double y;
  double px;
  double py;
  double r;
  final double targetR;
  double age = 0;

  /// How long this body has been resting above the danger line.
  double over = 0;
  double angle = 0;

  /// True until the body touches something after being dropped by the player.
  bool fresh = false;
  bool touched = false;
  bool dead = false;
  bool merging = false;
}

class GameCore {
  GameCore({this.balance = Balance.standard, required this.seed, bool adaptiveSpawns = true, this.dropLimit = 0})
    : spawner = FairSpawner(balance: balance, seed: seed, adaptive: adaptiveSpawns);

  GameCore._restored(this.balance, this.seed, this.dropLimit, this.spawner);

  final Balance balance;
  final int seed;

  /// 0 = unlimited (classic). Daily challenges may cap the number of drops.
  final int dropLimit;
  final FairSpawner spawner;

  final List<Body> bodies = [];

  /// Filled by [step]/[drop]; the presentation layer drains it every frame.
  final List<GameEvent> events = [];

  int _nextId = 1;
  double time = 0;
  double _accumulator = 0;
  double cooldown = 0;
  double grace = 0;

  int score = 0;
  int drops = 0;
  int merges = 0;
  int chain = 0;
  int maxChain = 0;
  int maxLevel = 0;
  int perfects = 0;
  int bigBangs = 0;

  /// Coins from high-level merges, combos and big bangs (score-based coins are added at the end).
  int bonusCoins = 0;
  int continuesUsed = 0;
  double _lastMergeTime = -1e9;
  double _lastDropTime = 0;
  double _quiet = 0;

  bool over = false;
  EndReason endReason = EndReason.none;
  bool _inDanger = false;

  /// 0 = calm, 1 = the stack touches the line.
  double danger = 0;

  /// 0..1 progress of the overflow countdown; 1 ends the run.
  double overflow = 0;

  final List<_MergePair> _pending = [];
  final Set<int> _created = {};

  int get currentPiece => spawner.current;
  int get nextPiece => spawner.next;
  bool get canDrop => !over && cooldown <= 0 && (dropLimit == 0 || drops < dropLimit);
  int get dropsLeft => dropLimit == 0 ? -1 : dropLimit - drops;

  /// The last piece of a drop-limited run is out: all that is left is for the pile to settle.
  bool get windingDown => !over && dropLimit > 0 && drops >= dropLimit;

  double get sinceLastDrop => time - _lastDropTime;
  bool get canContinue => over && endReason == EndReason.overflow && continuesUsed < balance.continuesPerRun;
  int get comboMultiplier => balance.comboMultiplier(chain);

  /// Levels created by merges during this run (for the collection / "new discovery").
  Set<int> get createdLevels => _created;

  /// Clamps an aim position so the current piece stays inside the walls.
  double clampAim(double x) {
    final r = balance.radius(currentPiece);
    return x < r ? r : (x > balance.worldW - r ? balance.worldW - r : x);
  }

  /// Y of the centre where a circle of radius [r] dropped at [x] first touches something.
  double landingY(double x, double r) {
    var best = balance.floorY - r;
    for (final b in bodies) {
      final dx = (b.x - x).abs();
      final sum = b.r + r;
      if (dx < sum) {
        final y = b.y - math.sqrt(sum * sum - dx * dx);
        if (y < best) best = y;
      }
    }
    return best;
  }

  /// Releases the current piece at [x]. Returns false if a drop is not allowed right now.
  bool drop(double x) {
    if (!canDrop) return false;
    final onBoard = <int>{for (final b in bodies) b.level};
    final level = spawner.take(onBoard, danger > 0.5);
    final r = balance.radius(level);
    // A sub-pixel, deterministic offset: pieces dropped on exactly the same spot would otherwise
    // balance in a perfect tower, which no real pile does.
    final nudge = ((drops * 0.6180339887) % 1 - 0.5) * 0.7;
    final ax = x.isFinite ? x + nudge : balance.worldW / 2;
    final cx = ax < r ? r : (ax > balance.worldW - r ? balance.worldW - r : ax);
    var cy = balance.spawnY;
    // Safe spawn: never create a piece inside another one.
    for (var tries = 0; tries < 60 && _overlapsAny(cx, cy, r); tries++) {
      cy -= 4;
    }
    final body = Body(_nextId++, level, cx, cy, r, r)..fresh = true;
    bodies.add(body);
    drops++;
    cooldown = balance.dropCooldown;
    _lastDropTime = time;
    // A chain is the reaction to one drop: releasing the next piece starts a new count.
    chain = 0;
    events.add(GameEvent(EventType.drop, x: cx, y: cy, level: level, id: body.id));
    return true;
  }

  bool _overlapsAny(double x, double y, double r) {
    for (final b in bodies) {
      final dx = b.x - x;
      final dy = b.y - y;
      final s = b.r + r;
      if (dx * dx + dy * dy < s * s) return true;
    }
    return false;
  }

  /// Advances the simulation by real frame time using fixed steps.
  void advance(double frameDt, {double timeScale = 1}) {
    if (!frameDt.isFinite || frameDt <= 0) return;
    _accumulator += frameDt * timeScale;
    final maxAcc = balance.stepDt * balance.maxStepsPerFrame;
    if (_accumulator > maxAcc) _accumulator = maxAcc;
    while (_accumulator >= balance.stepDt) {
      _accumulator -= balance.stepDt;
      step();
    }
  }

  /// One fixed physics step.
  void step() {
    if (over) return;
    final b = balance;
    final dt = b.stepDt;
    time += dt;
    if (cooldown > 0) cooldown -= dt;
    if (grace > 0) grace -= dt;
    if (chain > 0 && time - _lastMergeTime > b.comboWindow) chain = 0;

    final gdt2 = b.gravity * dt * dt;
    final maxD = b.maxSpeed * dt;
    final growRate = dt / b.growTime * 0.4;
    var fastest = 0.0;

    for (final o in bodies) {
      if (o.r < o.targetR) {
        o.r += o.targetR * growRate;
        if (o.r > o.targetR) o.r = o.targetR;
      }
      final damp = o.touched ? b.contactDamping : b.airDamping;
      var vx = (o.x - o.px) * damp;
      var vy = (o.y - o.py) * damp + gdt2;
      final d2 = vx * vx + vy * vy;
      if (d2 > maxD * maxD) {
        final k = maxD / math.sqrt(d2);
        vx *= k;
        vy *= k;
      }
      if (o.touched) o.angle += vx / o.r * 0.8;
      o.px = o.x;
      o.py = o.y;
      o.x += vx;
      o.y += vy;
      if (!o.x.isFinite || !o.y.isFinite) {
        // Unexpected physics state: put the body back where it last was valid.
        o.x = o.px.isFinite ? o.px : b.worldW / 2;
        o.y = o.py.isFinite ? o.py : b.spawnY;
        o.px = o.x;
        o.py = o.y;
      }
      o.touched = false;
      o.age += dt;
      final sp = d2 > maxD * maxD ? maxD : math.sqrt(d2);
      if (sp > fastest) fastest = sp;
    }
    fastest /= dt;

    _sortByLeftEdge();
    for (var it = 0; it < b.solverIterations; it++) {
      _solvePairs(dt);
      _solveWalls(dt);
    }

    if (_pending.isNotEmpty) _applyMerges();
    _checkOverflow(dt);

    if (!over && dropLimit > 0 && drops >= dropLimit) {
      final sinceDrop = time - _lastDropTime;
      _quiet = (fastest < b.settleSpeed && chain == 0) ? _quiet + dt : 0;
      if ((sinceDrop > 0.8 && _quiet > 0.6) || sinceDrop > 6) {
        _end(EndReason.dropsExhausted);
      }
    }
  }

  void _sortByLeftEdge() {
    // Insertion sort: the list is almost sorted from the previous step.
    final list = bodies;
    for (var i = 1; i < list.length; i++) {
      final o = list[i];
      final key = o.x - o.r;
      var j = i - 1;
      while (j >= 0 && list[j].x - list[j].r > key) {
        list[j + 1] = list[j];
        j--;
      }
      list[j + 1] = o;
    }
  }

  void _solvePairs(double dt) {
    final list = bodies;
    final friction = balance.friction;
    final n = list.length;
    for (var i = 0; i < n; i++) {
      final a = list[i];
      final aRight = a.x + a.r;
      for (var j = i + 1; j < n; j++) {
        final c = list[j];
        // Sorted by left edge at the start of the step; the slack covers movement since.
        if (c.x - c.r > aRight + 2) break;
        final dx = c.x - a.x;
        final dy = c.y - a.y;
        final sum = a.r + c.r;
        final d2 = dx * dx + dy * dy;
        if (d2 >= sum * sum) continue;

        if (a.fresh || c.fresh) _firstContact(a, c, dt);
        if (a.level == c.level && !a.merging && !c.merging) {
          a.merging = true;
          c.merging = true;
          _pending.add(_MergePair(a, c, _wasPerfect));
        }
        _wasPerfect = false;

        double nx;
        double ny;
        double dist;
        if (d2 > 1e-12) {
          dist = math.sqrt(d2);
          nx = dx / dist;
          ny = dy / dist;
        } else {
          dist = 0;
          nx = a.id < c.id ? 1 : -1;
          ny = 0;
        }
        final overlap = sum - dist;
        final ma = a.r * a.r;
        final mc = c.r * c.r;
        final total = ma + mc;
        final ka = overlap * mc / total;
        final kc = overlap * ma / total;
        a.x -= nx * ka;
        a.y -= ny * ka;
        c.x += nx * kc;
        c.y += ny * kc;
        a.touched = true;
        c.touched = true;

        // Friction: bleed off the sliding (tangential) part of the relative velocity, so a pile
        // holds its shape instead of flowing like marbles.
        final rvx = (c.x - c.px) - (a.x - a.px);
        final rvy = (c.y - c.py) - (a.y - a.py);
        final vt = (-rvx * ny + rvy * nx) * friction;
        final fa = vt * mc / total;
        final fc = vt * ma / total;
        a.px -= -ny * fa;
        a.py -= nx * fa;
        c.px += -ny * fc;
        c.py += nx * fc;
      }
    }
  }

  bool _wasPerfect = false;

  void _firstContact(Body a, Body c, double dt) {
    final f = a.fresh ? a : c;
    final other = a.fresh ? c : a;
    final speed = math.sqrt((f.x - f.px) * (f.x - f.px) + (f.y - f.py) * (f.y - f.py)) / dt;
    // A perfect drop: the very first thing the piece touches is its twin.
    _wasPerfect = f.level == other.level && !f.merging && !other.merging;
    a.fresh = false;
    c.fresh = false;
    events.add(GameEvent(EventType.impact, x: f.x, y: f.y, level: f.level, speed: speed, id: f.id));
  }

  void _solveWalls(double dt) {
    final w = balance.worldW;
    final floor = balance.floorY;
    for (final o in bodies) {
      if (o.x < o.r) {
        o.x = o.r;
        o.touched = true;
      } else if (o.x > w - o.r) {
        o.x = w - o.r;
        o.touched = true;
      }
      if (o.y > floor - o.r) {
        if (o.fresh) {
          o.fresh = false;
          final speed = (o.y - o.py).abs() / dt;
          events.add(GameEvent(EventType.impact, x: o.x, y: floor, level: o.level, speed: speed, id: o.id));
        }
        o.y = floor - o.r;
        o.touched = true;
      }
    }
  }

  void _applyMerges() {
    final b = balance;
    for (final m in _pending) {
      final a = m.a;
      final c = m.b;
      if (a.dead || c.dead) continue;
      a.dead = true;
      c.dead = true;
      final mx = (a.x + c.x) / 2;
      final my = (a.y + c.y) / 2;

      chain = (time - _lastMergeTime <= b.comboWindow && chain > 0) ? chain + 1 : 1;
      _lastMergeTime = time;
      if (chain > maxChain) maxChain = chain;
      final mult = b.comboMultiplier(chain);
      merges++;
      if (m.perfect) perfects++;
      if (chain >= b.comboCoinFrom) bonusCoins++;

      if (a.level >= b.maxLevel) {
        // Two top-level bodies: the big bang. Both vanish and everything else is thrown outward.
        final pts = b.bigBangScore * mult;
        score += pts;
        bonusCoins += b.bigBangCoins;
        bigBangs++;
        final kick = b.bigBangImpulse * b.stepDt;
        for (final o in bodies) {
          if (o.dead) continue;
          final dx = o.x - mx;
          final dy = o.y - my;
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < 1e-6) continue;
          final f = kick * (1 - (d / 500).clamp(0.0, 0.8));
          o.px -= dx / d * f;
          o.py -= dy / d * f;
        }
        events.add(GameEvent(EventType.bigBang, x: mx, y: my, level: a.level, chain: chain, points: pts));
        continue;
      }

      final lv = a.level + 1;
      final tr = b.radius(lv);
      final base = b.mergeScore(lv);
      var pts = base * mult;
      if (m.perfect) pts += (base * b.perfectBonusFactor).round();
      score += pts;
      bonusCoins += b.level(lv).coins;
      if (lv > maxLevel) maxLevel = lv;
      final first = _created.add(lv);

      final vx = ((a.x - a.px) + (c.x - c.px)) / 2;
      final vy = ((a.y - a.py) + (c.y - c.py)) / 2;
      final r0 = tr * 0.6;
      var nx = mx;
      if (nx < r0) nx = r0;
      if (nx > b.worldW - r0) nx = b.worldW - r0;
      var ny = my;
      if (ny > b.floorY - r0) ny = b.floorY - r0;
      final nb = Body(_nextId++, lv, nx, ny, r0, tr)
        ..px = nx - vx
        ..py = ny - vy
        ..angle = (a.angle + c.angle) / 2;
      bodies.add(nb);
      events.add(
        GameEvent(
          EventType.merge,
          x: nx,
          y: ny,
          level: lv,
          chain: chain,
          points: pts,
          perfect: m.perfect,
          firstTime: first,
          id: nb.id,
        ),
      );
    }
    _pending.clear();
    bodies.removeWhere((o) => o.dead);
  }

  void _checkOverflow(double dt) {
    final b = balance;
    var worst = 0.0;
    var top = b.floorY;
    for (final o in bodies) {
      final edge = o.y - o.r;
      if (o.age > b.dropGrace && !o.fresh) {
        if (edge < top) top = edge;
      }
      if (edge < b.dangerY && o.age > b.dropGrace && grace <= 0) {
        o.over += dt;
        if (o.over > worst) worst = o.over;
      } else {
        o.over = 0;
      }
    }
    overflow = (worst / b.overflowTime).clamp(0.0, 1.0);
    const zone = 110.0;
    danger = ((b.dangerY + zone - top) / zone).clamp(0.0, 1.0);
    // Hysteresis: a pile hovering around the threshold must not fire the warning repeatedly.
    final inDanger = _inDanger ? danger > 0.35 : danger > 0.5;
    if (inDanger != _inDanger) {
      _inDanger = inDanger;
      events.add(GameEvent(inDanger ? EventType.dangerEnter : EventType.dangerExit));
    }
    if (worst >= b.overflowTime) _end(EndReason.overflow);
  }

  void _end(EndReason reason) {
    if (over) return;
    over = true;
    endReason = reason;
    events.add(const GameEvent(EventType.gameOver));
  }

  /// Ends the run as a success: a campaign level whose goal has just been reached.
  void complete() => _end(EndReason.completed);

  /// Puts the starting bodies of a campaign level on the board. Each entry is `[level, x]`; a
  /// body rests on the floor or on whatever was placed before it.
  void seedBoard(List<List<int>> pieces) {
    for (final p in pieces) {
      final level = p[0];
      if (level < 1 || level > balance.maxLevel) continue;
      final r = balance.radius(level);
      final x = p[1] < r ? r : (p[1] > balance.worldW - r ? balance.worldW - r : p[1].toDouble());
      bodies.add(Body(_nextId++, level, x, landingY(x, r), r, r));
    }
    grace = 1.0;
  }

  /// Debug / test helper: ends the run as an overflow.
  void forceGameOver() => _end(EndReason.overflow);

  /// Rewarded continue: clears the small pieces and everything in the danger zone, then gives a
  /// short window during which the overflow countdown is paused. One per run.
  bool continueRun() {
    if (!canContinue) return false;
    final b = balance;
    bodies.removeWhere((o) => o.level <= b.continueClearMaxLevel || o.y - o.r < b.dangerY + 70);
    for (final o in bodies) {
      o.over = 0;
      o.merging = false;
    }
    _pending.clear();
    continuesUsed++;
    grace = b.continueGrace;
    cooldown = 0.3;
    over = false;
    endReason = EndReason.none;
    overflow = 0;
    events.add(const GameEvent(EventType.continued));
    return true;
  }

  // --- Debug tools (wired to UI only in debug builds) ---

  void debugClear() {
    bodies.clear();
    _pending.clear();
  }

  void debugSpawn(int level, double x, double y) {
    final r = balance.radius(level);
    bodies.add(Body(_nextId++, level, x, y, r, r));
  }

  // --- Persistence of an unfinished run ---

  Map<String, dynamic> toJson() => {
    'seed': seed,
    'dropLimit': dropLimit,
    'adaptive': spawner.adaptive,
    'rng': spawner.rng.state,
    'cur': spawner.current,
    'next': spawner.next,
    'drawn': spawner.drawn,
    'last': spawner.lastLevel,
    'runLen': spawner.runLength,
    'pair': spawner.openingPairDone,
    'nextId': _nextId,
    'time': time,
    'score': score,
    'drops': drops,
    'merges': merges,
    'maxChain': maxChain,
    'maxLevel': maxLevel,
    'perfects': perfects,
    'bigBangs': bigBangs,
    'bonusCoins': bonusCoins,
    'continues': continuesUsed,
    'created': _created.toList(),
    'bodies': [
      for (final o in bodies) [o.id, o.level, o.x, o.y, o.r, o.angle],
    ],
  };

  /// Rebuilds a run from [toJson] output. Returns null when the data is unusable - a broken
  /// snapshot must never crash the game, the player simply starts a fresh run.
  static GameCore? fromJson(Object? raw, {Balance balance = Balance.standard}) {
    try {
      if (raw is! Map) return null;
      int i(String k) => (raw[k] as num).toInt();
      final cur = i('cur');
      final next = i('next');
      final spawnMax = balance.spawnWeights.length;
      if (cur < 1 || cur > spawnMax || next < 1 || next > spawnMax) return null;
      final spawner = FairSpawner.restore(
        balance: balance,
        adaptive: raw['adaptive'] == true,
        rngState: i('rng'),
        current: cur,
        next: next,
        drawn: i('drawn'),
        lastLevel: i('last'),
        runLength: i('runLen'),
        openingPairDone: raw['pair'] == true,
      );
      final core = GameCore._restored(balance, i('seed'), i('dropLimit'), spawner);
      core._nextId = i('nextId');
      core.time = (raw['time'] as num).toDouble();
      core.score = i('score');
      core.drops = i('drops');
      core.merges = i('merges');
      core.maxChain = i('maxChain');
      core.maxLevel = i('maxLevel');
      core.perfects = i('perfects');
      core.bigBangs = i('bigBangs');
      core.bonusCoins = i('bonusCoins');
      core.continuesUsed = i('continues');
      core._lastDropTime = core.time;
      for (final c in raw['created'] as List) {
        core._created.add((c as num).toInt());
      }
      if (core.score < 0 || core.drops < 0 || !core.time.isFinite) return null;
      for (final e in raw['bodies'] as List) {
        final l = e as List;
        final level = (l[1] as num).toInt();
        if (level < 1 || level > balance.maxLevel) return null;
        final x = (l[2] as num).toDouble();
        final y = (l[3] as num).toDouble();
        if (!x.isFinite || !y.isFinite) return null;
        final body = Body((l[0] as num).toInt(), level, x, y, balance.radius(level), balance.radius(level))
          ..angle = (l[5] as num).toDouble();
        core.bodies.add(body);
      }
      if (core.bodies.length > 400) return null;
      // A restored run gets a moment to settle before the overflow countdown may start.
      core.grace = 1.0;
      return core;
    } catch (_) {
      return null;
    }
  }
}

class _MergePair {
  _MergePair(this.a, this.b, this.perfect);
  final Body a;
  final Body b;
  final bool perfect;
}
