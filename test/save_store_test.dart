import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/profile.dart';
import 'package:novalith/services/save_store.dart';

void main() {
  late Directory dir;
  late FileSaveStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('novalith_save_test');
    store = FileSaveStore(directory: dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  File file(String name) => File('${dir.path}/$name');

  test('no file yet: fresh profile', () async {
    final r = await store.load();
    expect(r.status, LoadStatus.fresh);
  });

  test('save then load round trip; no temp file is left behind', () async {
    await store.save(Profile()..coins = 77);
    expect(file('save.json').existsSync(), isTrue);
    expect(file('save.json.tmp').existsSync(), isFalse);
    final r = await store.load();
    expect(r.status, LoadStatus.ok);
    expect(r.profile.coins, 77);
  });

  test('many saves in a row are written in order: the last one wins', () async {
    final p = Profile();
    final writes = <Future<void>>[];
    for (var i = 1; i <= 40; i++) {
      p.coins = i;
      writes.add(store.save(p));
    }
    await Future.wait(writes);
    expect((await store.load()).profile.coins, 40);
  });

  test('app closed in the middle of a save: the previous save is intact', () async {
    await store.save(Profile()..coins = 10);
    // A half-written temp file is all an interrupted save can leave.
    file('save.json.tmp').writeAsStringSync('{"v":1,"coins":99');
    final r = await store.load();
    expect(r.status, LoadStatus.ok);
    expect(r.profile.coins, 10);
    await store.save(Profile()..coins = 11);
    expect((await store.load()).profile.coins, 11);
  });

  test('damaged main file falls back to the last good backup', () async {
    await store.save(
      Profile()
        ..coins = 500
        ..level = 9,
    );
    await store.load(); // a clean load refreshes the backup
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(file('save.bak').existsSync(), isTrue);
    file('save.json').writeAsStringSync('\u0000\u0000garbage');
    final r = await store.load();
    expect(r.status, LoadStatus.recovered);
    expect(r.profile.coins, 500);
    expect(r.profile.level, 9);
  });

  test('damaged main file and no backup: valid fields survive, nothing throws', () async {
    file('save.json').writeAsStringSync('{"v":1,"coins":12,"level":"x"}');
    final r = await store.load();
    expect(r.status, LoadStatus.recovered);
    expect(r.profile.coins, 12);
    expect(r.profile.level, 1);
  });

  test('unwritable location does not throw', () async {
    final broken = FileSaveStore(directory: Directory('${dir.path}/does/not/exist'));
    await broken.save(Profile());
    expect((await broken.load()).profile.coins, 0);
    await broken.reset();
  });

  test('reset removes everything', () async {
    await store.save(Profile()..coins = 5);
    await store.reset();
    expect((await store.load()).status, LoadStatus.fresh);
  });
}
