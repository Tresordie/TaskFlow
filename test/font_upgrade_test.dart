import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('pairing presets after the Inter→Manrope switch', () {
    test('preset ids are kept and now use bundled Manrope', () {
      final byId = {for (final f in AppFonts.presets) f.id: f};
      final notoPair = byId['pairInterNoto']!;
      final miPair = byId['pairInterMiSans']!;
      expect(notoPair.fontFamily, 'Manrope');
      expect(notoPair.cjkFamily, 'Noto Sans SC');
      expect(notoPair.isGoogleFont, isFalse); // bundled Latin half
      expect(miPair.fontFamily, 'Manrope');
      expect(miPair.cjkFamily, 'MiSans');
      expect(miPair.isGoogleFont, isFalse);
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
      SharedPreferences.setMockInitialValues(
          {'settings.fontId': 'pairInterMiSans'});
      final notifier = FontNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.id, 'pairInterMiSans');
      expect(notifier.state.fontFamily, 'Manrope');
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
