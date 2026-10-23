import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/presentation/ai_page.dart';
import '../features/ai/presentation/chat_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/focus/presentation/focus_page.dart';
import '../features/growth/presentation/achievements_page.dart';
import '../features/growth/presentation/growth_page.dart';
import '../features/growth/presentation/profile_page.dart';
import '../features/growth/presentation/rank_wall_page.dart';
import '../features/growth/presentation/stats_page.dart';
import '../features/notes/presentation/notes_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/today/presentation/today_page.dart';
import 'home_shell.dart';

/// 应用路由：未登录 -> /login；登录后 -> 5 Tab 主壳
class AppRouter {
  static GoRouter create(ValueNotifier<String?> nickname) {
    return GoRouter(
      initialLocation: '/today',
      refreshListenable: nickname,
      redirect: (context, state) {
        final loggedIn = nickname.value != null;
        final onLogin = state.matchedLocation == '/login';
        if (!loggedIn && !onLogin) return '/login';
        if (loggedIn && onLogin) return '/ai';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        GoRoute(path: '/ai', builder: (_, _) => const AiPage()),
        GoRoute(path: '/ai/chat', builder: (_, _) => const ChatPage()),
        GoRoute(path: '/rank-wall', builder: (_, _) => const RankWallPage()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        GoRoute(path: '/stats', builder: (_, _) => const StatsPage()),
        GoRoute(
          path: '/achievements',
          builder: (_, _) => const AchievementsPage(),
        ),
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              HomeShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/today', builder: (_, _) => const TodayPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/focus', builder: (_, _) => const FocusPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/calendar',
                  builder: (_, _) => const CalendarPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/notes', builder: (_, _) => const NotesPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/me', builder: (_, _) => const GrowthPage()),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
