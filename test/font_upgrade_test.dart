import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taskflow/core/theme/font_stack.dart';
import 'package:taskflow/providers/font_provider.dart';
import 'package:taskflow/providers/typography_provider.dart';

/// v1.5.2 font upgrade contracts:
///  - FontStack owns the mixed-layout chain (Manrope → MiSans → safety
///    nets → Segoe UI Emoji);
///  - pairing preset ids survived the Inter→Manrope switch (saved user
///    choices migrate, they don't crash or vanish);
///  - a persisted-but-unknown font id falls back to the default safely
///    (same migration pattern as deleted theme enums);
///  - the content/input typography providers NEVER set fontFamily alone —
///    every family override carries the CJK fallback chain (D5 fix).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FontStack (v1.5.2)', () {
    test('Latin primary is bundled Manrope, CJK primary is MiSans', () {
      expect(FontStack.latin, 'Manrope');
      expect(FontStack.cjk, 'MiSans');
    });

    test('fallback chain order: CJK nets then emoji owner', () {
      final fb = FontStack.fallback;
      expect(fb.first, 'MiSans');
      expect(fb, contains('HarmonyOS Sans SC'));
      expect(fb, contains('Segoe UI Emoji'));
      expect(fb.indexOf('MiSans'), lessThan(fb.indexOf('HarmonyOS Sans SC')));
      expect(fb.indexOf('HarmonyOS Sans SC'),
          lessThan(fb.indexOf('Segoe UI Emoji')));
    });

    test('pairing fallback leads with the paired CJK family', () {
      final fb = FontStack.pairingFallback('Noto Sans SC');
      expect(fb.first, 'Noto Sans SC');
      expect(fb, contains('HarmonyOS Sans SC'));
      expect(fb, contains('Segoe UI Emoji'));
    });
  });

  group('v1.8.0/1.9.0 preset cull — removed ids fall back safely', () {
    test('the three curated pairings are the only presets', () {
      final ids = AppFonts.presets.map((f) => f.id).toSet();
      expect(ids, {'interMisans', 'jakartaNoto', 'lexendNoto'});
      // v1.8.0/1.9.0: every earlier preset is gone — users who had one
      // selected (including the old bare 'system') fall back to the
      // default through the unknown-id path.
      const removed = [
        'system', 'notoSansSC', 'poppins', 'pairInterNoto', 'pairInterMiSans',
        'pairLoraSerif', 'pairNunitoWenKai', 'pairPlexNoto', 'pairOutfitMiSans',
      ];
      for (final r in removed) {
        expect(ids.contains(r), isFalse, reason: '$r should be removed');
      }
    });

    test('removed ids persist no fonts: presets have no Manrope standalone',
        () {
      // The Manrope Latin half now lives only in the bundled FontStack
      // default (via the 'system' preset), not as a selectable preset.
      expect(
        AppFonts.presets
            .where((f) => f.fontFamily == 'Manrope')
            .map((f) => f.id),
        isEmpty,
      );
    });
  });

  group('v1.7.0 pairing presets', () {
    test('three new CN+EN pairings carry the designed halves', () {
      final byId = {for (final f in AppFonts.presets) f.id: f};
      final inter = byId['interMisans']!;
      expect(inter.fontFamily, 'Inter');
      expect(inter.isGoogleFont, isTrue);
      expect(inter.cjkFamily, 'MiSans');
      final jakarta = byId['jakartaNoto']!;
      expect(jakarta.fontFamily, 'Plus Jakarta Sans');
      expect(jakarta.isGoogleFont, isTrue);
      expect(jakarta.cjkFamily, 'Noto Sans SC');
      final lexend = byId['lexendNoto']!;
      expect(lexend.fontFamily, 'Lexend');
      expect(lexend.isGoogleFont, isTrue);
      expect(lexend.cjkFamily, 'Noto Sans SC');
    });

    test('every Google-hosted family a preset names exists in google_fonts',
        () {
      // v1.6.0 lesson: pairPlexNoto / pairOutfitMiSans shipped without a
      // download branch in TaskFlowApp._googleFontTextTheme, so the Latin
      // half never loaded. This contract pins (a) that every family named
      // by any preset is actually resolvable by the installed google_fonts
      // package, and (b) the reminder list of families the download switch
      // must cover — extending it when you add a preset, not after.
      const switchCovered = {
        'Noto Sans SC', // _ensureCjkFontLoaded (CJK half of two pairings)
        'Inter', // _googleFontTextTheme (Latin halves)
        'Plus Jakarta Sans',
        'Lexend',
      };
      final needed = <String>{
        for (final f in AppFonts.presets) ...[
          if (f.isGoogleFont) f.fontFamily!,
          if (f.cjkFamily != null &&
              f.cjkFamily != 'MiSans' && // bundled — no download needed
              f.cjkFamily != 'HarmonyOS Sans SC')
            f.cjkFamily!,
        ],
      };
      // The switch list must cover every downloadable family a preset needs.
      expect(needed.difference(switchCovered), isEmpty);
      // And google_fonts must actually host every one of them (catches
      // typos like 'Plus Jakarta' and package downgrades).
      final hosted = GoogleFonts.asMap().keys.toSet();
      for (final family in switchCovered) {
        expect(hosted, contains(family),
            reason: 'google_fonts must host "$family"');
      }
    });
  });

  group('font persistence migration safety', () {
    test('unknown persisted id falls back to default without crashing',
        () async {
      SharedPreferences.setMockInitialValues(
          {'settings.fontId': 'ghostFontFromAnOldVersion'});
      final notifier = FontNotifier();
      // _restore runs asynchronously in the constructor; let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.id, AppFonts.defaultFont.id);
    });

    test('known persisted id still restores', () async {
      SharedPreferences.setMockInitialValues({'settings.fontId': 'interMisans'});
      final notifier = FontNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.id, 'interMisans');
      expect(notifier.state.fontFamily, 'Inter');
    });
  });

  group('typography providers always carry the CJK fallback (D5)', () {
    testWidgets('applyInputTypography pairs family override with fallback',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final notifier = InputTypographyNotifier()..setFamily('Lora');
      late TextStyle resolved;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inputTypographyProvider.overrideWith((_) => notifier),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                resolved = applyInputTypography(
                    context, const TextStyle(fontSize: 13.5));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(resolved.fontFamily, 'Lora');
      expect(resolved.fontFamilyFallback, isNotNull);
      expect(resolved.fontFamilyFallback, contains('MiSans'));
      expect(resolved.fontFamilyFallback, contains('Segoe UI Emoji'));
    });

    testWidgets('applyContentTypography pairs family override with fallback',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final notifier = ContentTypographyNotifier()..setFamily('Lora');
      late MarkdownStyleSheet sheet;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentTypographyProvider.overrideWith((_) => notifier),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                sheet = applyContentTypography(
                    context,
                    MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 13, color: Colors.black)));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(sheet.p?.fontFamily, 'Lora');
      expect(sheet.p?.fontFamilyFallback, contains('MiSans'));
      expect(sheet.h1?.fontFamilyFallback, contains('MiSans'));
    });
  });
}
