// Renders the procedural art to PNG files so it can be looked at without a device.
// Output goes to NOVALITH_PREVIEW_DIR; without that variable the test only checks that every
// sprite bakes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novalith/core/balance.dart';
import 'package:novalith/game/sprites.dart';

void main() {
  final outDir = Platform.environment['NOVALITH_PREVIEW_DIR'];

  testWidgets('every level bakes for every theme', (tester) async {
    await tester.runAsync(() async {
      const b = Balance.standard;
      for (final theme in orbThemes.keys) {
        final sprites = OrbSprites()..build(theme, b);
        for (final lv in b.levels) {
          expect(sprites.image(lv.id), isNotNull, reason: '$theme/${lv.key}');
        }
        if (outDir != null) {
          const w = 1200.0;
          const h = 640.0;
          final rec = ui.PictureRecorder();
          final c = Canvas(rec);
          paintBackground(c, const Size(w, h), backgroundTheme('bg_deep'));
          var x = 30.0;
          var y = 130.0;
          for (final lv in b.levels) {
            final r = lv.radius;
            if (x + r * 2 > w - 20) {
              x = 30;
              y += 260;
            }
            sprites.draw(c, lv.id, x + r, y, r, 0);
            x += r * 2 + 34;
          }
          final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$outDir/orbs_$theme.png').writeAsBytesSync(data!.buffer.asUint8List());
        }
        sprites.dispose();
      }
    });
  });
}
