import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'router.dart';
import 'state/pill_completion_store.dart';
import 'state/session_store.dart';
import 'theme/app_theme.dart';

class PillPalsApp extends StatelessWidget {
  const PillPalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionStore()..bootstrap()),
        ChangeNotifierProvider(create: (_) => PillCompletionStore()..bootstrap()),
      ],
      child: MaterialApp.router(
        title: 'PillPals',
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}

