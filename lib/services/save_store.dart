/// Where the profile lives on disk. Writes are atomic (temp file, then rename), so closing the
/// app in the middle of a save leaves either the old file or the new one - never half of each.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/profile.dart';

abstract class SaveStore {
  Future<LoadResult> load();
  Future<void> save(Profile profile);
  Future<void> reset();
}

class FileSaveStore implements SaveStore {
  FileSaveStore({this.directory});

  /// Overridable for tests; defaults to the app's private support directory.
  final Directory? directory;
  Future<void> _queue = Future.value();

  Future<Directory> _dir() async => directory ?? await getApplicationSupportDirectory();

  @override
  Future<LoadResult> load() async {
    try {
      final dir = await _dir();
      final main = File('${dir.path}/save.json');
      final backup = File('${dir.path}/save.bak');
      String? text;
      if (await main.exists()) text = await main.readAsString();
      final result = Profile.decode(text);
      if (result.status == LoadStatus.ok) {
        // Remember the last save that loaded cleanly.
        unawaited(main.copy(backup.path).then<void>((_) {}).catchError((_) {}));
        return result;
      }
      // Missing or damaged main file: the backup may be in better shape.
      if (await backup.exists()) {
        final fromBackup = Profile.decode(await backup.readAsString());
        if (fromBackup.status == LoadStatus.ok) {
          return LoadResult(fromBackup.profile, LoadStatus.recovered);
        }
      }
      return result;
    } catch (e) {
      debugPrint('save load failed: $e');
      return LoadResult(Profile(), LoadStatus.recovered);
    }
  }

  @override
  Future<void> save(Profile profile) {
    // Encode now (a consistent snapshot), write in order.
    final text = profile.encode();
    _queue = _queue.then((_) => _write(text));
    return _queue;
  }

  Future<void> _write(String text) async {
    try {
      final dir = await _dir();
      final tmp = File('${dir.path}/save.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('${dir.path}/save.json');
    } catch (e) {
      debugPrint('save write failed: $e');
    }
  }

  @override
  Future<void> reset() async {
    await _queue;
    try {
      final dir = await _dir();
      for (final name in ['save.json', 'save.bak', 'save.json.tmp']) {
        final f = File('${dir.path}/$name');
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('save reset failed: $e');
    }
  }
}

/// In-memory store for tests.
class MemorySaveStore implements SaveStore {
  String? text;
  int writes = 0;

  @override
  Future<LoadResult> load() async => Profile.decode(text);

  @override
  Future<void> save(Profile profile) async {
    text = profile.encode();
    writes++;
  }

  @override
  Future<void> reset() async => text = null;
}
