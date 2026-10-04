/// The cosmetics shop: themes for the celestial bodies and backgrounds. Nothing here changes
/// gameplay.
library;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../core/progression.dart';
import '../game/sprites.dart';
import 'widgets.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ItemKind _kind = ItemKind.theme;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final items = shopItems.where((i) => i.kind == _kind).toList();
    return GameScaffold(
      title: model.t('shop'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: _Tab(
                    label: model.t('themes'),
                    active: _kind == ItemKind.theme,
                    onTap: () => setState(() => _kind = ItemKind.theme),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Tab(
                    label: model.t('backgrounds'),
                    active: _kind == ItemKind.background,
                    onTap: () => setState(() => _kind = ItemKind.background),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.74,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _ItemCard(item: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: active ? const Color(0x338CF0FF) : const Color(0x14FFFFFF),
            border: Border.all(color: active ? Palette.cyan : const Color(0x33FFFFFF), width: active ? 1.6 : 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(label, style: ts(15, weight: 700, color: active ? Palette.text : Palette.dim)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final owned = p.owned.contains(item.id);
    final equipped = p.theme == item.id || p.background == item.id;
    final levelLocked = !owned && item.earned;
    final rarity = Palette.rarity[item.rarity.clamp(0, 3)];

    Widget action;
    if (equipped) {
      action = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Palette.green, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(model.t('equipped'), style: ts(14, weight: 700, color: Palette.green)),
            ),
          ),
        ],
      );
    } else if (owned) {
      action = GameButton(label: model.t('equip'), compact: true, onTap: () => model.equip(item.id));
    } else if (levelLocked) {
      action = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_rounded, color: Palette.faint, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.reqWorld > 0
                  ? model.t('unlock_world', {'name': model.worldName(item.reqWorld)})
                  : item.archive
                  ? model.t('unlock_archive')
                  : model.t('unlock_level', {'n': item.reqLevel}),
              style: ts(12, weight: 600, color: Palette.dim),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      );
    } else {
      action = GameButton(
        label: formatNumber(item.price),
        compact: true,
        color: Palette.gold,
        trailing: const CoinIcon(size: 18),
        onTap: () {
          if (model.buy(item.id) == BuyResult.notEnoughCoins) showToast(context, model.t('not_enough'));
        },
      );
    }

    return GlassPanel(
      border: equipped ? Palette.green : rarity.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: item.kind == ItemKind.theme
                  ? ColoredBox(
                      color: const Color(0x33000000),
                      child: Center(
                        child: FittedBox(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OrbView(level: 5, size: 62, theme: item.id),
                              OrbView(level: 8, size: 84, theme: item.id),
                            ],
                          ),
                        ),
                      ),
                    )
                  : CustomPaint(painter: _BgPreview(item.id), child: const SizedBox.expand()),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(model.itemName(item), style: ts(16, weight: 700, color: rarity)),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 48, child: Center(child: action)),
        ],
      ),
    );
  }
}

class _BgPreview extends CustomPainter {
  _BgPreview(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) => paintBackground(canvas, size, backgroundTheme(id));

  @override
  bool shouldRepaint(_BgPreview old) => old.id != id;
}
