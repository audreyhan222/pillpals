import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/role/role_select_screen.dart';
import 'screens/shell/home_shell.dart';
import 'state/session_store.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final session = context.read<SessionStore>();
      if (!session.bootstrapped) return null;

      final isLoggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      if (!session.isAuthed && !isLoggingIn) {
        return '/login';
      }
      if (session.isAuthed && isLoggingIn) {
        return '/role';
      }
      return null;
    },
    routes: [
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


