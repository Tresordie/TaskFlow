import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_glass_provider.dart';
import '../../providers/theme_provider.dart';
import 'custom_title_bar.dart';
import 'glass_panel.dart';

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width > 768;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // v1.12.5: app-wide interface glass — when enabled, an ambient canvas
    // (gradient + drifting orbs) sits behind the whole shell and the title
    // bar / sidebar / content panel become frosted-glass panels via
    // GlassPanel + the theme's translucent surface color.
    final glass = ref.watch(appGlassStyleProvider);
    final glassOn = glass.glass;
    // v1.12.15: light themes ALWAYS sit on the ambient canvas — a whisper
    // without glass, vivid with glass — so every page reads as designed
    // rather than dead-flat white. Dark themes keep flat (they already
    // read well); glass mode keeps its vivid recipe.
    final showCanvas = glassOn || !isDark;

    // v1.4.71: the app-wide SelectionArea was REMOVED. Flutter's
    // SelectableRegion collapses the active selection on right-click
    // (its _handleRightClickDown hit-tests the selection rects and
    // clears the selection whenever the click misses them — which
    // happens constantly, because the rects are glyph-tight while the
    // visible highlight covers whole lines). It also hijacks nested
    // SelectableText widgets and breaks THEIR native right-click Copy /
    // Copy-as-Markdown menus. Instead, every content area that needs
    // selection renders a SelectableText-based widget (SelectableMarkdownBody
    // for whole-document select + right-click menu, MarkdownBody with
    // selectable: true elsewhere) — verified to keep the selection on
    // right-click.
    final content = child;

    return Scaffold(
      body: Stack(
        children: [
          // Ambient canvas behind everything — the layer the glass panels
          // blur. Light non-glass mode gets a whisper version; off-mode
          // dark keeps the historic flat scaffold.
          if (showCanvas)
            Positioned.fill(
              child: IgnorePointer(
                child: _ambientBackdrop(context, ref, glass: glassOn),
              ),
            ),
          Column(
            children: [
              // Custom title bar (replaces native) — glass-wrapped in glass
              // mode (its fill follows the theme's translucent surface).
              // v1.12.15: transparent in light non-glass mode so the canvas
              // flows behind the title text.
              GlassPanel(
                glass: glassOn,
                blur: glass.blur,
                child: CustomTitleBar(
                  backgroundColor:
                      (!glassOn && !isDark) ? Colors.transparent : null,
                ),
              ),
              // Main content
              Expanded(
                child: isWide
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        child: Row(
                          children: [
                            GlassPanel(
                              glass: glassOn,
                              blur: glass.blur,
                              borderRadius: BorderRadius.circular(14),
                              child: _Sidebar(
                                  currentLocation:
                                      GoRouterState.of(context).uri.path),
                            ),
                            const SizedBox(width: 10),
                            // Rounded content panel — v1.12.15: light
                            // non-glass mode gets a soft shadow (a "sheet"
                            // on the canvas) and a whisper of canvas tint
                            // through a 90% fill.
                            Expanded(
                              child: GlassPanel(
                                glass: glassOn,
                                blur: glass.blur,
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: (!glassOn && !isDark)
                                        ? theme.colorScheme.surface
                                            .withOpacity(0.90)
                                        : theme.colorScheme.surface,
                                    border: Border.all(
                                      // v1.12.6: bright glass rim instead of
                                      // the faint outline — the edge highlight
                                      // is what makes the panel read as glass.
                                      color: glassOn
                                          ? Colors.white.withOpacity(
                                              isDark ? 0.16 : 0.55)
                                          : theme.colorScheme.outline
                                              .withOpacity(0.3),
                                    ),
                                    boxShadow: !glassOn
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                  isDark ? 0.15 : 0.06),
                                              blurRadius: 16,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: content,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : content,
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : _BottomNav(currentLocation: GoRouterState.of(context).uri.path),
    );
  }

  /// v1.12.5: the ambient canvas behind the glass shell — deepened
  /// surface→bg gradient plus three slowly drifting accent orbs (same
  /// recipe as the Today board's backdrop, so all screens share the
  /// "texture" layer the frosted panels blur).
  /// v1.12.6: stronger gradient and brighter orbs — at the old 5–8% orb
  /// opacity the frosted panels had almost nothing to show (user feedback:
  /// glass effect too subtle).
  /// v1.12.11: light canvas deepens further — near-white light palettes
  /// converged to white under stacked translucency, washing the glass out
  /// (user screenshot: light poor vs dark good).
  /// v1.12.15: two intensities — [glass] keeps the vivid recipe, while
  /// light non-glass mode gets a whisper (border 20%/32% blend, 3.5–5%
  /// orbs) so every page breathes without hurting clarity.
  Widget _ambientBackdrop(BuildContext context, WidgetRef ref,
      {required bool glass}) {
    final theme = Theme.of(context);
    final palette = theme.colorScheme;
    final p = ref.watch(themeModeProvider).palette;
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark
        ? p.bg
        : Color.alphaBlend(
            p.border.withOpacity(glass ? 0.55 : 0.20), p.surface);
    final deep = isDark
        ? p.bg
        : Color.alphaBlend(
            p.border.withOpacity(glass ? 0.72 : 0.32), p.surface);
    final orbAlpha = glass ? 1.0 : 0.32;

    Widget orb(Color color, double size, double opacity) {
      final container = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              color.withOpacity(opacity * orbAlpha),
              color.withOpacity(0.0)
            ],
          ),
        ),
      );
      // v1.12.15: the drift animation runs only in glass mode — the whisper
      // canvas stays STATIC so pages settle cleanly (pumpAndSettle) and the
      // motion language stays reserved for the glass look.
      if (!glass) return container;
      return container
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .moveX(
            begin: -18,
            end: 18,
            duration: 18000.ms,
            curve: Curves.easeInOut,
          );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [base, deep],
              ),
            ),
          ),
        ),
        Positioned(
            top: -140, right: -100, child: orb(palette.primary, 440, 0.16)),
        Positioned(
            bottom: 60, left: -140, child: orb(palette.secondary, 400, 0.13)),
        Positioned(
            bottom: -150, right: 220, child: orb(AppColors.success, 360, 0.10)),
      ],
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  final String currentLocation;

  const _Sidebar({required this.currentLocation});

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // v1.12.5: in glass mode the sidebar gets a slightly stronger tint —
    // it sits over the ambient canvas and must keep nav text readable.
    // v1.12.7: the tinted fill now follows the Interface Glass opacity
    // slider (a fixed 10% tint never responded to the user's knobs).
    final appGlass = ref.watch(appGlassStyleProvider);
    final glassOn = appGlass.glass;
    final p = ref.watch(themeModeProvider).palette;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 210,
        decoration: BoxDecoration(
          // macOS-style: slightly tinted translucent feel. v1.12.15: light
          // non-glass mode floats the sidebar as a card-colored sheet with
          // a soft shadow (module differentiation — the sidebar reads as a
          // distinct panel rather than a ghost stripe).
          color: glassOn
              ? Color.alphaBlend(
                      theme.colorScheme.primary.withOpacity(0.18), p.surface)
                  .withOpacity(appGlass.opacity)
              : (theme.brightness == Brightness.dark
                  ? theme.colorScheme.primary.withOpacity(0.03)
                  : p.card),
          border: Border.all(
            // v1.12.6: bright glass rim in glass mode.
            color: glassOn
                ? Colors.white.withOpacity(
                    theme.brightness == Brightness.dark ? 0.16 : 0.55)
                : theme.colorScheme.outline.withOpacity(0.3),
          ),
          boxShadow: !glassOn
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                        theme.brightness == Brightness.dark ? 0.15 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Logo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'TaskFlow',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Nav section label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'MENU',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 1.0,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 8),

            _NavItem(
              icon: Icons.today_outlined,
              activeIcon: Icons.today,
              label: 'Today',
              isActive: widget.currentLocation == '/today',
              onTap: () => context.go('/today'),
            ),
            _NavItem(
              icon: Icons.timeline_outlined,
              activeIcon: Icons.timeline,
              label: 'Timeline',
              isActive: widget.currentLocation == '/timeline',
              onTap: () => context.go('/timeline'),
            ),
            _NavItem(
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month,
              label: 'Calendar',
              isActive: widget.currentLocation == '/calendar',
              onTap: () => context.go('/calendar'),
            ),
            _NavItem(
              icon: Icons.grid_on_outlined,
              activeIcon: Icons.grid_on,
              label: 'Activity',
              isActive: widget.currentLocation == '/activity',
              onTap: () => context.go('/activity'),
            ),
            _NavItem(
              icon: Icons.auto_awesome_outlined,
              activeIcon: Icons.auto_awesome,
              label: 'AI Parse',
              isActive: widget.currentLocation == '/ai',
              onTap: () => context.go('/ai'),
            ),
            _NavItem(
              icon: Icons.auto_fix_high_outlined,
              activeIcon: Icons.auto_fix_high,
              label: 'AI Prompts',
              isActive: widget.currentLocation == '/prompts',
              onTap: () => context.go('/prompts'),
            ),
            _NavItem(
              icon: Icons.summarize_outlined,
              activeIcon: Icons.summarize,
              label: 'Reports',
              isActive: widget.currentLocation == '/reports',
              onTap: () => context.go('/reports'),
            ),
            _NavItem(
              icon: Icons.edit_note_outlined,
              activeIcon: Icons.edit_note,
              label: 'Work Log',
              isActive: widget.currentLocation == '/worklog',
              onTap: () => context.go('/worklog'),
            ),

            const Spacer(),

            // Settings
            _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              isActive: widget.currentLocation == '/settings',
              onTap: () => context.go('/settings'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    // v1.4.29: active item gets a leading accent bar + a soft tinted pill;
    // hover (when inactive) reveals a faint wash so the nav feels alive.
    final bg = isActive
        ? theme.colorScheme.primary.withOpacity(0.12)
        : _hovered
            ? theme.colorScheme.onSurface.withOpacity(0.05)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hovered = h),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // Leading accent bar for the active item.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 3,
                  height: 18,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  isActive ? widget.activeIcon : widget.icon,
                  size: 18,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(width: 10),
                // Flexible + ellipsis: longer labels ("AI Prompts") must
                // never overflow the fixed-width sidebar in narrow windows
                // (pitfall 8.7).
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final String currentLocation;

  const _BottomNav({required this.currentLocation});

  int _getSelectedIndex() {
    if (currentLocation.startsWith('/timeline')) return 1;
    if (currentLocation.startsWith('/calendar')) return 2;
    if (currentLocation.startsWith('/activity')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _getSelectedIndex(),
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/today');
          case 1:
            context.go('/timeline');
          case 2:
            context.go('/calendar');
          case 3:
            context.go('/activity');
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today),
          label: 'Today',
        ),
        NavigationDestination(
          icon: Icon(Icons.timeline_outlined),
          selectedIcon: Icon(Icons.timeline),
          label: 'Timeline',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: 'Calendar',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_on_outlined),
          selectedIcon: Icon(Icons.grid_on),
          label: 'Activity',
        ),
      ],
    );
  }
}
