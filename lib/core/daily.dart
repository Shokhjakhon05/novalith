/// Daily challenge and daily reward. No server: the challenge is derived from the calendar date
/// and a versioned algorithm, so the same day gives every player the same pieces and target.
library;

import 'balance.dart';
import 'game_core.dart';
import 'profile.dart';
import 'rng.dart';

/// 20261004 for 4 October 2026.
int dateKeyOf(DateTime local) => local.year * 10000 + local.month * 100 + local.day;

/// Days since the epoch for a date key - used to measure the gap between two calendar days.
int dayNumber(int dateKey) {
  final y = dateKey ~/ 10000;
  final m = (dateKey ~/ 100) % 100;
  final d = dateKey % 100;
  return DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 86400000;
}

enum DailyType { score, evolution, chain }

class DailyChallenge {
  DailyChallenge._(this.dateKey, this.type, this.target, this.dropLimit, this.seed);

  /// Changing the generation rules means bumping this, so old days stay reproducible.
  static const int algorithmVersion = 1;

  final int dateKey;
  final DailyType type;
  final int target;
  final int dropLimit;
  final int seed;

  factory DailyChallenge.forDate(int dateKey) {
    final rng = SeededRng(hashSeed('novalith|$dateKey|v$algorithmVersion'));
    final type = DailyType.values[rng.nextInt(DailyType.values.length)];
    final seed = rng.nextU32();
    switch (type) {
      case DailyType.score:
        final drops = 40 + 10 * rng.nextInt(3);
        return DailyChallenge._(dateKey, type, scoreTargets[drops]!, drops, seed);
      case DailyType.evolution:
        return DailyChallenge._(dateKey, type, 8, 60 + 10 * rng.nextInt(2), seed);
      case DailyType.chain:
        return DailyChallenge._(dateKey, type, 5 + rng.nextInt(2), 50, seed);
    }
  }

  /// Score targets per drop limit, calibrated against the greedy bot (see BALANCE_REPORT).
  static const Map<int, int> scoreTargets = {40: 1500, 50: 2000, 60: 2600};

  /// Pieces are identical for everyone: the adaptive (recovery) weighting is off.
  GameCore createRun({Balance balance = Balance.standard}) =>
      GameCore(balance: balance, seed: seed, adaptiveSpawns: false, dropLimit: dropLimit);

  int progress(GameCore core) => switch (type) {
        DailyType.score => core.score,
        DailyType.evolution => core.maxLevel,
        DailyType.chain => core.maxChain,
      };

  bool completed(GameCore core) => progress(core) >= target;
}

enum RewardState { available, claimed, clockBehind }

class DailyRewardStatus {
  DailyRewardStatus(this.state, this.day, this.coins, {this.streakBroken = false});
  final RewardState state;

  /// Too many days were missed: claiming starts the cycle (and the streak) over.
  final bool streakBroken;

  /// 0..6: the slot that is (or will next be) claimable.
  final int day;
  final int coins;
}

/// Works out whether today's reward can be claimed.
///
/// Defensive rules:
///  * the device clock moved backwards -> nothing to claim, but the streak is left alone;
///  * a second claim needs a new calendar day AND at least 6 real hours, so hopping time zones
///    cannot farm rewards;
///  * a gap of up to 2 calendar days still continues the streak - crossing time zones can make
///    two honest consecutive claims look two days apart.
DailyRewardStatus dailyRewardStatus(
  Profile p,
  DateTime nowLocal,
  DateTime nowUtc, {
  Balance balance = Balance.standard,
}) {
  final rewards = balance.dailyRewardCoins;
  final today = dateKeyOf(nowLocal);
  final utcMs = nowUtc.millisecondsSinceEpoch;
  if (p.rewardLastDate == 0) return DailyRewardStatus(RewardState.available, 0, rewards[0]);

  final current = p.rewardDay % rewards.length;
  if (utcMs < p.rewardLastUtcMs - 5 * 60 * 1000) {
    return DailyRewardStatus(RewardState.clockBehind, current, rewards[current]);
  }
  final gap = dayNumber(today) - dayNumber(p.rewardLastDate);
  if (gap <= 0 || utcMs - p.rewardLastUtcMs < 6 * 3600 * 1000) {
    return DailyRewardStatus(RewardState.claimed, current, rewards[current]);
  }
  final day = gap <= 2 ? current : 0;
  return DailyRewardStatus(RewardState.available, day, rewards[day], streakBroken: gap > 2);
}

/// Claims today's reward. Returns the coins granted, or 0 when nothing was claimable.
int claimDailyReward(
  Profile p,
  DateTime nowLocal,
  DateTime nowUtc, {
  Balance balance = Balance.standard,
}) {
  final status = dailyRewardStatus(p, nowLocal, nowUtc, balance: balance);
  if (status.state != RewardState.available) return 0;
  p.rewardStreak = status.streakBroken ? 1 : p.rewardStreak + 1;
  p.rewardDay = (status.day + 1) % balance.dailyRewardCoins.length;
  p.rewardLastDate = dateKeyOf(nowLocal);
  p.rewardLastUtcMs = nowUtc.millisecondsSinceEpoch;
  p.coins += status.coins;
  return status.coins;
}
