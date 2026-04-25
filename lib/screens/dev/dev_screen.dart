import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../state/pill_completion_store.dart';
import '../../state/api_config_store.dart';
import '../../state/session_store.dart';
import '../../notifications/notification_service.dart';

class DevScreen extends StatefulWidget {
  const DevScreen({super.key});

  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen> {
  DateTime _selected = DateTime.now();
  final _baseUrl = TextEditingController();

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PillCompletionStore>();
    final session = context.watch<SessionStore>();
    final apiConfig = context.watch<ApiConfigStore>();
    final taken = store.takenDoseIdsForDay(_selected).toList()..sort();
    final key = PillCompletionStore.dayKey(_selected);

    if (_baseUrl.text.isEmpty) {
      // Keep this lightweight; only seed once.
      _baseUrl.text = apiConfig.baseUrl;
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.35, 0.7, 1.0],
            colors: [
              Color(0xFFC2DEFF),
              Color(0xFFE8EFFE),
              Color(0xFFFFF3C4),
              Color(0xFFFFE07A),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => context.pop(),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Dev Page',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2D4A),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionTitle('Backend API URL'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _baseUrl,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'API base URL',
                              hintText: 'http://192.168.1.10:8000',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    HapticFeedback.lightImpact();
                                    await apiConfig.setBaseUrl(_baseUrl.text);
                                    if (!mounted) return;
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('Saved: ${apiConfig.baseUrl}'),
                                      ),
                                    );
                                  },
                                  child: const Text('Save'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.tonal(
                                  onPressed: () async {
                                    HapticFeedback.lightImpact();
                                    await apiConfig.resetToDefault();
                                    _baseUrl.text = apiConfig.baseUrl;
                                    if (!mounted) return;
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Reset to default: ${apiConfig.baseUrl}',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Reset'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _SectionHint(
                            'If you are running on a real phone, 127.0.0.1 points to the phone, not your Mac. Set API_BASE_URL in the project’s `.env` to your Mac’s LAN IP, run the API with --host 0.0.0.0, then use Reset here or do a full restart. '
                            'Build default: ${AppConfig.apiBaseUrl}',
                          ),
                          const SizedBox(height: 22),
                          const _SectionTitle('Medication completion'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () {
                                    final now = DateTime.now();
                                    setState(
                                      () => _selected = DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.today_rounded),
                                  label: const Text('Today'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _selected,
                                      firstDate: DateTime(2020, 1, 1),
                                      lastDate: DateTime(2100, 12, 31),
                                    );
                                    if (picked == null || !mounted) return;
                                    setState(
                                      () => _selected = DateTime(
                                        picked.year,
                                        picked.month,
                                        picked.day,
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.calendar_month_rounded,
                                  ),
                                  label: const Text('Pick date'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.70),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 1.25,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1E2D4A),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  taken.isEmpty
                                      ? 'No pills marked taken on this day.'
                                      : 'Taken (${taken.length}): ${taken.join(', ')}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black.withValues(alpha: 0.60),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () async {
                                    await store.clearDay(_selected);
                                  },
                                  icon: const Icon(Icons.restart_alt_rounded),
                                  label: const Text('Reset day'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFE8E8),
                                    foregroundColor: const Color(0xFF8A1F1F),
                                  ),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          title: const Text(
                                            'Reset all history?',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          content: const Text(
                                            'This clears all “taken” history stored on this device.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(true),
                                              child: const Text('Reset'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (ok != true) return;
                                    await store.clearAll();
                                  },
                                  icon: const Icon(Icons.delete_forever_rounded),
                                  label: const Text('Reset all'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const _SectionHint(
                            'These tools affect the calendar + “taken” state used to mark completed days.',
                          ),
                          const SizedBox(height: 22),
                          const _SectionTitle('Notifications'),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () async {
                              await NotificationService.instance.triggerDevPush(
                                message: 'Triggered from Dev screen.',
                                authToken: session.token,
                              );
                            },
                            icon: const Icon(
                              Icons.notifications_active_rounded,
                            ),
                            label: const Text('Trigger push notification'),
                          ),
                          const SizedBox(height: 10),
                          const _SectionHint(
                            'Calls your backend to send a real push; falls back to a local notification if the backend is not set up yet.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFF4A90D9),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: Color(0xFF1E2D4A),
      ),
    );
  }
}

class _SectionHint extends StatelessWidget {
  const _SectionHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: Colors.black.withValues(alpha: 0.55),
      ),
    );
  }
}

