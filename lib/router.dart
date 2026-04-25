import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/role/landing_page.dart';
import 'screens/reminder/reminder_screen.dart';
import 'screens/shell/home_shell.dart';
import 'state/session_store.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final session = context.read<SessionStore>();
      if (!session.bootstrapped) return null;

      final isLoggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      final isPublic = state.matchedLocation == '/' || isLoggingIn || state.matchedLocation == '/reminder';

      if (!session.isAuthed && !isPublic) {
        return '/login';
      }

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
        path: '/home',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/reminder',
        builder: (context, state) => ReminderScreen(payload: state.uri.queryParameters['p']),
      ),
    ],
  );
