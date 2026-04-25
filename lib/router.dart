import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/landing_page.dart';
import 'screens/role/role_select_screen.dart';
import 'screens/shell/home_shell.dart';
import 'state/session_store.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final session = context.read<SessionStore>();
      if (!session.bootstrapped) return null;

      final isLanding = state.matchedLocation == '/';
      final isLoggingIn =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';

      // Landing is always allowed as the app's start screen.
      if (isLanding) return null;

      // If not authenticated, allow landing + auth routes only.
      if (!session.isAuthed && !isLoggingIn) {
        return '/';
      }

      // If already authenticated, don't force role selection at startup.
      // (Role selection can be an explicit step later if needed.)
      if (session.isAuthed && isLoggingIn) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/role',
        builder: (context, state) => const RoleSelectScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeShell(),
      ),
    ],
  );
}


