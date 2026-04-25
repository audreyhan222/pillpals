import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'router.dart';
import 'notifications/notification_service.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionStore>();
    final apiConfig = context.watch<ApiConfigStore>();
    if (_didRegister) return;
    if (!session.bootstrapped) return;
    if (!apiConfig.bootstrapped) return;
    if (!session.isAuthed) return;

    _didRegister = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.registerFcmTokenWithBackend(
        authToken: session.token,
        baseUrl: apiConfig.baseUrl,
      );
    });
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

