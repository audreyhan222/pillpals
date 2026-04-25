import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../firestore/medication_repository.dart';
import '../notifications/notification_service.dart';
import '../state/api_config_store.dart';
import '../state/session_store.dart';
import 'pill_details.dart';
import 'pill_details_parser.dart';
import 'scan_medication_service.dart';

class ScanMedicationInput {
  const ScanMedicationInput({
    required this.imageFile,
    required this.recognizedText,
  });

  final File imageFile;
  final String recognizedText;
}

class ScanMedicationAnalysisScreen extends StatefulWidget {
  const ScanMedicationAnalysisScreen({super.key, required this.input});

  final ScanMedicationInput input;

  @override
  State<ScanMedicationAnalysisScreen> createState() => _ScanMedicationAnalysisScreenState();
}

class _ScanMedicationAnalysisScreenState extends State<ScanMedicationAnalysisScreen> {
  late PillDetails _local;
  PillDetails? _ai;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  Future<void> _showPendingReminders() async {
    try {
      final pending = await NotificationService.instance.pendingReminders();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return DraggableScrollableSheet(
            expand: false,
            minChildSize: 0.35,
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  const Text(
                    'Pending reminders (debug)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${pending.length} scheduled',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (pending.isEmpty)
                    const Text('No pending reminders found.')
                  else
                    ...pending.map(
                      (p) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.title ?? '—'),
                        subtitle: Text(
                          'id: ${p.id}'
                          '${p.body != null ? '\n${p.body}' : ''}'
                          '${p.payload != null ? '\npayload: ${p.payload}' : ''}',
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to read pending reminders: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _local = PillDetailsParser.parse(widget.input.recognizedText);
    _runAi();
  }

  Future<void> _runAi() async {
    setState(() {
      _loading = true;
      _error = null;
      _ai = null;
    });

    try {
      final token = context.read<SessionStore>().token;
      final baseUrl = context.read<ApiConfigStore>().baseUrl;
      final service = ScanMedicationService(token: token, baseUrl: baseUrl);
      final res = await service.analyzeText(text: widget.input.recognizedText);

      final merged = _local.copyWith(
        name: res.name.isNotEmpty ? res.name : _local.name,
        dosage: res.dosage.isNotEmpty ? res.dosage : _local.dosage,
        instructions: res.instructions.isNotEmpty ? res.instructions : _local.instructions,
      );

      if (!mounted) return;
      setState(() {
        _ai = merged;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'AI analysis failed (showing OCR results instead): $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _ai ?? _local;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Analysis'),
        actions: [
          IconButton(
            tooltip: 'Pending reminders (debug)',
            onPressed: _showPendingReminders,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          IconButton(
            tooltip: 'Re-run analysis',
            onPressed: _loading ? null : _runAi,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                widget.input.imageFile,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const ListTile(
                leading: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Analyzing label…'),
                subtitle: Text('Extracting dosage + instructions'),
              ),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _ResultCard(
              title: 'Medication name',
              value: details.name.isEmpty ? '—' : details.name,
            ),
            const SizedBox(height: 10),
            _ResultCard(
              title: 'Dosage',
              value: details.dosage.isEmpty ? '—' : details.dosage,
            ),
            const SizedBox(height: 10),
            _ResultCard(
              title: 'Instructions',
              value: details.instructions.isEmpty ? '—' : details.instructions,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() {
                        _saving = true;
                      });
                      try {
                        final repo = MedicationRepository();
                        await repo.addMedicationFromScan(details: details);

                        // Schedule one daily reminder per time.
                        for (int i = 0; i < details.times.length; i++) {
                          final t = details.times[i];
                          // Notification IDs must be stable ints. This is a simple deterministic mapping.
                          final id = details.name.hashCode ^ (t.hour * 60 + t.minute);
                          await NotificationService.instance.scheduleDailyDoseReminder(
                            id: id.abs() % 2147483647,
                            time: t,
                            title: details.name.isEmpty ? 'Medication reminder' : details.name,
                            body: details.dosage.isEmpty
                                ? 'Time to take your dose.'
                                : 'Time to take ${details.dosage}.',
                            payload: details.name,
                          );
                        }

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Saved + reminders scheduled.')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Save failed: $e')),
                        );
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? 'Saving…' : 'Save & schedule reminders'),
            ),
            const SizedBox(height: 14),
            ExpansionTile(
              title: const Text('OCR text (debug)'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SelectableText(
                    widget.input.recognizedText.isEmpty
                        ? 'No text recognized.'
                        : widget.input.recognizedText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.6),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

