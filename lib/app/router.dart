import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../presentation/shared/app_shell.dart';
import '../presentation/task_board/task_board_screen.dart';
import '../presentation/task_detail/task_detail_screen.dart';
import '../presentation/timeline/timeline_screen.dart';
import '../presentation/calendar/calendar_screen.dart';
import '../presentation/heatmap/heatmap_screen.dart';
import '../presentation/ai_parse/ai_parse_screen.dart';
import '../presentation/ai_prompts/ai_prompts_screen.dart';
import '../presentation/reports/reports_screen.dart';
import '../presentation/settings/settings_screen.dart';
import '../presentation/work_log/work_log_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/today',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/today',
            name: 'today',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TaskBoardScreen(),
            ),
          ),
          GoRoute(
            path: '/timeline',
            name: 'timeline',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TimelineScreen(),
            ),
          ),
          GoRoute(
            path: '/calendar',
            name: 'calendar',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CalendarScreen(),
            ),
          ),
          GoRoute(
            path: '/activity',
            name: 'activity',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HeatmapScreen(),
            ),
          ),
          GoRoute(
            path: '/ai',
            name: 'aiParse',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AiParseScreen(),
            ),
          ),
          GoRoute(
            path: '/prompts',
            name: 'aiPrompts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AiPromptsScreen(),
            ),
          ),
          GoRoute(
            path: '/reports',
            name: 'reports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/worklog',
            name: 'workLog',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WorkLogScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
          GoRoute(
            path: '/task/:id',
            name: 'taskDetail',
            pageBuilder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return MaterialPage(
                child: TaskDetailScreen(taskId: id),
              );
            },
          ),
        ],
      ),
    ],
  );
});
