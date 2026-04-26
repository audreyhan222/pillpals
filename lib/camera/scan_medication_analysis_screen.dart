import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../firestore/medication_repository.dart';
import '../firestore/ocr_label_correction_repository.dart';
import '../notifications/notification_service.dart';
import 'pill_details.dart';
import 'pill_details_parser.dart';

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
  final _nameC = TextEditingController();
  final _dosageC = TextEditingController();
  final _instructionsC = TextEditingController();

  late PillDetails _parsed;
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _parsed = PillDetailsParser.parse(widget.input.recognizedText);
    _parsed = _parsed.copyWith(rawText: widget.input.recognizedText);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedCorrections());
  }

  Future<void> _loadSavedCorrections() async {
    if (!mounted) return;
    try {
      final repo = OcrLabelCorrectionRepository();
      final c = await repo.getForRawOcr(context, widget.input.recognizedText);
      if (c != null) {
        _parsed = _parsed.copyWith(
          name: c.correctName.isNotEmpty ? c.correctName : _parsed.name,
          dosage: c.correctDosage.isNotEmpty ? c.correctDosage : _parsed.dosage,
          instructions:
              c.correctInstructions.isNotEmpty ? c.correctInstructions : _parsed.instructions,
        );
      }
    } catch (_) {
      // Non-fatal: show parser-only values.
    }
    if (!mounted) return;
    setState(() {
      _nameC.text = _parsed.name;
      _dosageC.text = _parsed.dosage;
      _instructionsC.text = _parsed.instructions;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _nameC.dispose();
    _dosageC.dispose();
    _instructionsC.dispose();
    super.dispose();
  }

  Future<TimeOfDay?> _pickStartTime() async {
    TimeOfDay selected = const TimeOfDay(hour: 9, minute: 0);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return SizedBox(
          height: 340,
          child: Column(
            children: [
              const SizedBox(height: 6),
              const Text(
                'Pick a start time',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: false,
                  initialDateTime: DateTime(2020, 1, 1, selected.hour, selected.minute),
                  onDateTimeChanged: (dt) {
                    selected = TimeOfDay(hour: dt.hour, minute: dt.minute);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Use'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return null;
    return selected;
  }

  List<TimeOfDay> _timesFromStartAndInterval({
    required TimeOfDay start,
    required int intervalMinutes,
  }) {
    if (intervalMinutes <= 0) return [start];
    final out = <TimeOfDay>[];
    int minutes = start.hour * 60 + start.minute;
    while (minutes < 24 * 60) {
      out.add(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
      minutes += intervalMinutes;
    }
    return out;
  }

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
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('OCR Results')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Results'),
        actions: [
          IconButton(
            tooltip: 'Saved label text library',
            onPressed: () {
              HapticFeedback.lightImpact();
              context.push('/ocr/labels');
            },
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: 'Pending reminders (debug)',
            onPressed: _showPendingReminders,
            icon: const Icon(Icons.notifications_active_outlined),
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
            const SizedBox(height: 8),
            Text(
              'One OCR pipeline, then you fix any mistakes. The exact text and your edits are saved for next time this label is scanned.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.55),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            _FieldCard(
              label: 'Medication name',
              controller: _nameC,
            ),
            const SizedBox(height: 10),
            _FieldCard(
              label: 'Dosage',
              controller: _dosageC,
            ),
            const SizedBox(height: 10),
            _FieldCard(
              label: 'Instructions',
              controller: _instructionsC,
              maxLines: 4,
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
                        final start = await _pickStartTime();
                        if (start == null) return;
                        if (!context.mounted) return;

                        final interval = _parsed.intervalMinutes;
                        final timesToSchedule = interval > 0
                            ? _timesFromStartAndInterval(
                                start: start,
                                intervalMinutes: interval,
                              )
                            : <TimeOfDay>[start];

                        final detailsToSave = _parsed.copyWith(
                          name: _nameC.text.trim(),
                          dosage: _dosageC.text.trim(),
                          instructions: _instructionsC.text.trim(),
                          times: timesToSchedule,
                          rawText: widget.input.recognizedText,
                        );

                        try {
                          await OcrLabelCorrectionRepository().upsertCorrection(
                            context: context,
                            rawOcrText: widget.input.recognizedText,
                            correctName: detailsToSave.name,
                            correctDosage: detailsToSave.dosage,
                            correctInstructions: detailsToSave.instructions,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not save label library: $e')),
                            );
                          }
                        }

                        if (!context.mounted) return;
                        final repo = MedicationRepository();
                        await repo.addMedicationFromScanForSession(
                          context: context,
                          details: detailsToSave,
                        );

                        final name =
                            detailsToSave.name.isEmpty ? 'Medication' : detailsToSave.name;
                        for (int i = 0; i < detailsToSave.times.length; i++) {
                          final t = detailsToSave.times[i];
                          final doseId =
                              '${name.toLowerCase()}_${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';
                          await NotificationService.instance.scheduleEscalatingDoseReminder(
                            doseId: doseId,
                            medicationName: name,
                            time: t,
                          );
                        }

                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Saved + reminders scheduled.')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
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
              title: const Text('OCR text (raw)'),
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

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.label,
    required this.controller,
    this.maxLines = 2,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.6),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
