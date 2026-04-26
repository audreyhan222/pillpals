import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../notifications/notification_service.dart';
import '../../state/pill_completion_store.dart';

class ReminderScreen extends StatelessWidget {
  const ReminderScreen({super.key, this.payload});

  final String? payload;

  @override
  Widget build(BuildContext context) {
    final parsed = DoseReminderPayload.tryDecode(payload);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Reminder'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'It’s time to take your medication',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  parsed == null
                      ? (payload == null ? 'No payload' : 'Payload: $payload')
                      : parsed.medicationName,
                  style: const TextStyle(fontSize: 16),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    if (parsed != null) {
                      await context.read<PillCompletionStore>().markDoseTaken(
                            date: DateTime.now(),
                            doseId: parsed.doseId,
                          );
                      await NotificationService.instance
                          .cancelEscalationSeries(doseId: parsed.doseId);
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('I took it'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

