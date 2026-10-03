/// Settings: sound, haptics, accessibility, language, purchases and privacy.
library;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final p = model.profile;
    final current = p.language.isEmpty ? model.t('system_lang') : model.l10n.language.nativeName;
    return GameScaffold(
      title: model.t('settings'),
      showCoins: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          GlassPanel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _Switch(
                  icon: Icons.music_note_rounded,
                  label: model.t('music'),
                  value: p.music,
                  onChanged: model.setMusic,
                ),
                _Switch(icon: Icons.volume_up_rounded, label: model.t('sound'), value: p.sfx, onChanged: model.setSfx),
                _Switch(
                  icon: Icons.vibration_rounded,
                  label: model.t('vibration'),
                  value: p.haptics,
                  onChanged: model.setHaptics,
                ),
                _Switch(
                  icon: Icons.pin_rounded,
                  label: model.t('show_numbers'),
                  value: p.showNumbers,
                  onChanged: model.setShowNumbers,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _Row(
              icon: Icons.language_rounded,
              label: model.t('language'),
              value: current,
              onTap: () => _pickLanguage(context),
            ),
          ),
          if ((model.purchases.available && !p.removeAds) || p.removeAds || model.ads.privacyOptionsRequired) ...[
            const SizedBox(height: 12),
            GlassPanel(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  if (p.removeAds)
                    _Row(icon: Icons.verified_rounded, label: model.t('ads_removed'), value: '', onTap: null)
                  else if (model.purchases.available) ...[
                    _Row(
                      icon: Icons.block_rounded,
                      label: model.t('remove_ads'),
                      value: model.purchases.price,
                      onTap: model.purchases.buyRemoveAds,
                    ),
                    _Row(
                      icon: Icons.restore_rounded,
                      label: model.t('restore'),
                      value: '',
                      onTap: model.purchases.restore,
                    ),
                  ],
                  if (model.ads.privacyOptionsRequired)
                    _Row(
                      icon: Icons.privacy_tip_rounded,
                      label: model.t('privacy'),
                      value: '',
                      onTap: model.ads.showPrivacyOptions,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Center(
            child: Text('Novalith 1.0.0', style: ts(12, color: Palette.faint)),
          ),
        ],
      ),
    );
  }

  void _pickLanguage(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF2140F33),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheet) {
        final model = AppScope.of(sheet);
        final saved = model.profile.language;
        Widget option(String code, String name) {
          final selected = saved == code;
          return InkWell(
            onTap: () {
              model.setLanguage(code);
              Navigator.of(sheet).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: ts(17, weight: selected ? 800 : 600, color: selected ? Palette.cyan : Palette.text),
                    ),
                  ),
                  if (selected) const Icon(Icons.check_rounded, color: Palette.cyan),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [option('', model.t('system_lang')), for (final l in languages) option(l.code, l.nativeName)],
            ),
          ),
        );
      },
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Palette.cyan, size: 24),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: ts(16, weight: 600))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Palette.ink,
              activeTrackColor: Palette.cyan,
              inactiveThumbColor: Palette.dim,
              inactiveTrackColor: const Color(0x33FFFFFF),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Palette.cyan, size: 24),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: ts(16, weight: 600))),
            if (value.isNotEmpty) Text(value, style: ts(15, weight: 600, color: Palette.dim)),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: Palette.faint),
          ],
        ),
      ),
    );
  }
}
