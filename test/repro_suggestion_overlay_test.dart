import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taskflow/core/theme/app_theme.dart';
import 'package:taskflow/presentation/shared/suggestion_field.dart';

/// v1.12.46 regression (user: "创建的任务更改设置时，页面被覆盖"): the
/// SuggestionField dropdown inside the Edit Task dialog painted a giant
/// translucent wash over the whole page and stretched its rows edge to edge.
/// Two independent causes, two contracts pinned here:
///  1. The Overlay's theater lays out non-positioned entries with TIGHT
///     full-screen constraints, so a bare SizedBox(width:) was clamped back
///     to the screen size. The dropdown must end up exactly as wide as the
///     field it belongs to (Align now loosens the constraints).
///  2. With Interface Glass on, theme.colorScheme.surface is translucent —
///     and the floating menu inherited it, so dialog text bled through the
///     rows. The dropdown surface must stay fully opaque.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDropdown(WidgetTester tester, {bool glass = false}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(AppThemeMode.notionBoard,
          glass: glass, glassOpacity: 0.75),
      home: Scaffold(
        body: Center(
          child: Builder(builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SuggestionField(
                          controller: controller,
                          suggestions: const ['Bike', 'Cosmo', 'Metro'],
                          headerText: 'Recent projects',
                          decoration: const InputDecoration(
                              hintText: 'Project name'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
  }

  /// The dropdown's own Material — the only elevation-12 Material in the tree.
  Finder dropdownMaterial() => find.byWidgetPredicate(
      (w) => w is Material && w.elevation == 12 && w.borderRadius != null);

  testWidgets('dropdown is sized to its field, not the whole overlay',
      (tester) async {
    await openDropdown(tester);

    expect(dropdownMaterial(), findsOneWidget);
    final dropdown = tester.getSize(dropdownMaterial());
    final field = tester.getSize(find.byType(TextField));
    // The bug: dropdown came out 1400x900 (the full overlay). It must match
    // the field width and stay bounded to its content height.
    expect(dropdown.width, field.width);
    expect(dropdown.height, lessThan(300));
    // Rows must not stretch across the screen either.
    expect(tester.getSize(find.text('Bike')).width, lessThan(field.width));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('dropdown stays opaque while glass mode makes surface translucent',
      (tester) async {
    await openDropdown(tester, glass: true);

    // Premise: the theme surface really is translucent in glass mode.
    final context = tester.element(find.byType(SuggestionField));
    final surface = Theme.of(context).colorScheme.surface;
    expect(surface.a, lessThan(1.0));

    // The floating menu must not inherit it.
    final material = tester.widget<Material>(dropdownMaterial());
    expect(material.color!.a, 1.0);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
