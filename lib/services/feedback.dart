/// Sound and haptics. Both are optional subsystems: every call is guarded, so a missing asset
/// or an audio driver error can never take the game down.
library;

import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Sfx { drop, impact, tap, big, bigbang, perfect, coin, unlock, record, danger, gameover }

abstract class AudioService {
  bool sfxOn = true;
  bool musicOn = true;
  Future<void> init();
  void play(Sfx sfx, {double volume = 1});

  /// Merge note: [step] 0.. climbs the scale as a chain grows.
  void playMerge(int step, {double volume = 1});
  void setMusic(bool on);
  void pauseAll();
  void resumeAll();
}

class SilentAudio extends AudioService {
  final List<String> played = [];

  @override
  Future<void> init() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) {
    if (sfxOn) played.add(sfx.name);
  }

  @override
  void playMerge(int step, {double volume = 1}) {
    if (sfxOn) played.add('merge_$step');
  }

  @override
  void setMusic(bool on) => musicOn = on;

  @override
  void pauseAll() {}

  @override
  void resumeAll() {}
}

class FlameAudioService extends AudioService {
  static const int mergeNotes = 8;

  final Map<String, AudioPool> _pools = {};
  final Map<String, int> _lastPlayedMs = {};
  bool _ready = false;
  bool _musicStarted = false;
  bool _paused = false;

  @override
  Future<void> init() async {
    try {
      final files = <String, int>{
        for (final s in Sfx.values) '${s.name}.wav': s == Sfx.impact || s == Sfx.drop ? 3 : 2,
        for (var i = 0; i < mergeNotes; i++) 'merge_$i.wav': 3,
      };
      for (final entry in files.entries) {
        try {
          _pools[entry.key] = await FlameAudio.createPool(entry.key, maxPlayers: entry.value);
        } catch (e) {
          debugPrint('audio: ${entry.key} unavailable: $e');
        }
      }
      _ready = true;
      if (musicOn) _startMusic();
    } catch (e) {
      debugPrint('audio init failed: $e');
    }
  }

  void _playFile(String file, double volume, int minGapMs) {
    if (!_ready || !sfxOn || _paused) return;
    final pool = _pools[file];
    if (pool == null) return;
    // Throttle: a burst of identical sounds in the same instant is one sound, not a wall.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastPlayedMs[file] ?? 0) < minGapMs) return;
    _lastPlayedMs[file] = now;
    try {
      unawaited(pool.start(volume: volume.clamp(0.0, 1.0)).then<void>((_) {}).catchError((_) {}));
    } catch (_) {}
  }

  @override
  void play(Sfx sfx, {double volume = 1}) => _playFile('${sfx.name}.wav', volume, sfx == Sfx.impact ? 70 : 40);

  @override
  void playMerge(int step, {double volume = 1}) {
    final i = step < 0 ? 0 : (step >= mergeNotes ? mergeNotes - 1 : step);
    _playFile('merge_$i.wav', volume, 45);
  }

  void _startMusic() {
    try {
      unawaited(FlameAudio.bgm.play('music.ogg', volume: 0.45).catchError((_) {}));
      _musicStarted = true;
    } catch (_) {}
  }

  @override
  void setMusic(bool on) {
    musicOn = on;
    if (!_ready) return;
    try {
      if (on) {
        if (_musicStarted) {
          unawaited(FlameAudio.bgm.resume().catchError((_) {}));
        } else {
          _startMusic();
        }
      } else if (_musicStarted) {
        unawaited(FlameAudio.bgm.pause().catchError((_) {}));
      }
    } catch (_) {}
  }

  @override
  void pauseAll() {
    _paused = true;
    try {
      if (_musicStarted) unawaited(FlameAudio.bgm.pause().catchError((_) {}));
    } catch (_) {}
  }

  @override
  void resumeAll() {
    _paused = false;
    try {
      if (_musicStarted && musicOn) unawaited(FlameAudio.bgm.resume().catchError((_) {}));
    } catch (_) {}
  }
}

enum Haptic { drop, merge, bigMerge, combo, danger, gameOver, tap }

class Haptics {
  bool enabled = true;

  /// Counts requests - lets tests check feedback without a device.
  int fired = 0;

  void fire(Haptic h) {
    if (!enabled) return;
    fired++;
    try {
      final f = switch (h) {
        Haptic.drop || Haptic.tap => HapticFeedback.selectionClick(),
        Haptic.merge => HapticFeedback.lightImpact(),
        Haptic.combo => HapticFeedback.mediumImpact(),
        Haptic.bigMerge || Haptic.gameOver => HapticFeedback.heavyImpact(),
        Haptic.danger => HapticFeedback.vibrate(),
      };
      unawaited(f.catchError((_) {}));
    } catch (_) {}
  }
}
