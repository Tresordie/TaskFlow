import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'custom_title_bar.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 768;
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          // Custom title bar (replaces native)
          const CustomTitleBar(),
          // Main content
          Expanded(
            child: isWide
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      children: [
                        _Sidebar(
                            currentLocation:
                                GoRouterState.of(context).uri.path),
                        const SizedBox(width: 10),
                        // Rounded content panel
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                border: Border.all(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.2),
                                ),
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : child,
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : _BottomNav(
              currentLocation: GoRouterState.of(context).uri.path),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String currentLocation;

  const _Sidebar({required this.currentLocation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 210,
        decoration: BoxDecoration(
          // macOS-style: slightly tinted translucent feel
          color: theme.colorScheme.primary.withOpacity(0.03),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
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
                fontSize: 10,
                letterSpacing: 1.0,
                color: theme.colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
          const SizedBox(height: 8),

          _NavItem(
            icon: Icons.today_outlined,
            activeIcon: Icons.today,
            label: 'Today',
            isActive: currentLocation == '/today',
            onTap: () => context.go('/today'),
          ),
          _NavItem(
            icon: Icons.timeline_outlined,
            activeIcon: Icons.timeline,
            label: 'Timeline',
            isActive: currentLocation == '/timeline',
            onTap: () => context.go('/timeline'),
          ),
          _NavItem(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month,
            label: 'Calendar',
            isActive: currentLocation == '/calendar',
            onTap: () => context.go('/calendar'),
          ),
          _NavItem(
            icon: Icons.grid_on_outlined,
            activeIcon: Icons.grid_on,
            label: 'Activity',
            isActive: currentLocation == '/activity',
            onTap: () => context.go('/activity'),
          ),
          _NavItem(
            icon: Icons.auto_awesome_outlined,
            activeIcon: Icons.auto_awesome,
            label: 'AI Parse',
            isActive: currentLocation == '/ai',
            onTap: () => context.go('/ai'),
          ),
          _NavItem(
            icon: Icons.summarize_outlined,
            activeIcon: Icons.summarize,
            label: 'Reports',
            isActive: currentLocation == '/reports',
            onTap: () => context.go('/reports'),
          ),
          _NavItem(
            icon: Icons.edit_note_outlined,
            activeIcon: Icons.edit_note,
            label: 'Work Log',
            isActive: currentLocation == '/worklog',
            onTap: () => context.go('/worklog'),
          ),

          const Spacer(),

          // Settings
          _NavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: 'Settings',
            isActive: currentLocation == '/settings',
            onTap: () => context.go('/settings'),
          ),
          const SizedBox(height: 16),
        ],
      ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primary.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  size: 18,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.65),
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
