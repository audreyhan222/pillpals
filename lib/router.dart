import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/dashboard/dashboard_left_screen.dart';
import 'screens/dashboard/dashboard_right_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/role/landing_page.dart';
import 'screens/role/role_select_screen.dart';
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
      final isRolePick = state.matchedLocation == '/role';
      // For now, dashboard is public (no credentials required yet).
      final isPublic = state.matchedLocation == '/' ||
          isLoggingIn ||
          isRolePick ||
          state.matchedLocation == '/reminder' ||
          state.matchedLocation == '/dashboard' ||
          state.matchedLocation == '/dashboard/left' ||
          state.matchedLocation == '/dashboard/right';

      if (!session.isAuthed && !isPublic) {
        return '/login';
      }

      if (session.isAuthed && isLoggingIn) {
        return session.hasRole ? '/dashboard' : '/role';
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
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/dashboard/left',
        builder: (context, state) => const DashboardLeftScreen(),
      ),
      GoRoute(
        path: '/dashboard/right',
        builder: (context, state) => const DashboardRightScreen(),
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
