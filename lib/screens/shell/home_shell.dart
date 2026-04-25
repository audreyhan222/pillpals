import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../notifications/notification_service.dart';
import '../../state/session_store.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('PillPals'),
        actions: [
          IconButton(
            onPressed: () => session.logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Next: profile setup + dashboards',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'This is the scaffolded home shell. From here we’ll branch into Elderly vs Caregiver experiences.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await NotificationService.instance.scheduleTestReminder(fromNow: const Duration(seconds: 10));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test reminder scheduled for 10 seconds from now.')),
                    );
                  }
                },
                child: const Text('Test phone notification (10s)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

