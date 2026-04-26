import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'notifications/notification_service.dart';
import 'notifications/caregiver_reminder_sync_service.dart';
import 'state/api_config_store.dart';
import 'state/pill_completion_store.dart';
import 'state/session_store.dart';
import 'theme/app_theme.dart';

class PillPalsApp extends StatelessWidget {
  const PillPalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiConfigStore()..bootstrap()),
        ChangeNotifierProvider(create: (_) => SessionStore()..bootstrap()),
        ChangeNotifierProvider(create: (_) => PillCompletionStore()..bootstrap()),
      ],
      child: const _PushBootstrapper(),
    );
  }
}

class _PushBootstrapper extends StatefulWidget {
  const _PushBootstrapper();

  @override
  State<_PushBootstrapper> createState() => _PushBootstrapperState();
}

class _PushBootstrapperState extends State<_PushBootstrapper> {
  bool _didRegister = false;
  bool _didListen = false;
  bool _didStartCaregiverSync = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionStore>();
    final apiConfig = context.watch<ApiConfigStore>();
    final completion = context.watch<PillCompletionStore>();
    if (_didRegister) return;
    if (!session.bootstrapped) return;
    if (!apiConfig.bootstrapped) return;
    if (!completion.bootstrapped) return;
    if (!session.isAuthed) return;

    _didRegister = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.registerFcmTokenWithBackend(
        authToken: session.token,
        baseUrl: apiConfig.baseUrl,
      );
    });

    if (!_didStartCaregiverSync &&
        session.role == 'caregiver' &&
        (session.username ?? '').trim().isNotEmpty) {
      _didStartCaregiverSync = true;
      CaregiverReminderSyncService.instance.start(
        caregiverUsername: session.username!.trim(),
      );
    }

    if (!_didListen) {
      _didListen = true;
      NotificationService.instance.eventStream.listen((event) async {
        final payload = event.payload;
        final parsed = DoseReminderPayload.tryDecode(payload);

        if (event.actionId == NotificationService.actionTaken && parsed != null) {
          await completion.markDoseTaken(
            date: DateTime.now(),
            doseId: parsed.doseId,
          );
          await NotificationService.instance.cancelEscalationSeries(doseId: parsed.doseId);
          if (session.role == 'elderly' &&
              (session.username ?? '').trim().isNotEmpty) {
            await NotificationService.instance.writeDoseAcknowledgementToFirestore(
              elderlyUsername: session.username!.trim(),
              doseId: parsed.doseId,
              scheduledEpochMs: parsed.scheduledEpochMs,
            );
          }
          return;
        }

        if (event.actionId == NotificationService.actionSnooze10 && parsed != null) {
          await NotificationService.instance.cancelEscalationSeries(doseId: parsed.doseId);
          // Re-schedule stage 0 as a one-shot 10 minutes from now.
          await NotificationService.instance.scheduleTestReminder(fromNow: const Duration(minutes: 10));
          return;
        }

        // Default: open the reminder screen.
        // Avoid holding a BuildContext across async gaps; `rootNavigatorKey.currentContext`
        // is fetched at the moment we need it.
        final navContext = rootNavigatorKey.currentContext;
        if (navContext == null) return;
        if (!navContext.mounted) return;
        GoRouter.of(navContext).go(
          '/reminder?p=${Uri.encodeComponent(payload ?? '')}',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PillPals',
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}

