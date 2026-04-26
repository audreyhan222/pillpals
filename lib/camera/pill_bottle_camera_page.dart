import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../firestore/elderly_medication_catalog_repository.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import 'pill_bottle_text_recognizer.dart';
import 'pill_details_parser.dart';
import 'scan_medication_analysis_screen.dart';

class PillBottleCameraPage extends StatefulWidget {
  const PillBottleCameraPage({super.key});

  @override
  State<PillBottleCameraPage> createState() => _PillBottleCameraPageState();
}

class _PillBottleCameraPageState extends State<PillBottleCameraPage> {
  final ImagePicker _imagePicker = ImagePicker();
  final PillBottleTextRecognizer _recognizer = PillBottleTextRecognizer();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();

  File? _capturedImage;
  String _recognizedText = '';
  final List<TimeOfDay> _times = [];
  bool _isProcessing = false;
  String? _error;

  @override
  void dispose() {
    _recognizer.dispose();
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _captureAndReadText() async {
    setState(() {
      _error = null;
      _isProcessing = true;
      _recognizedText = '';
    });

    try {
      final XFile? captured = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (captured == null) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No photo captured. If this keeps happening, enable Camera permission in phone Settings and try reinstalling the app.',
            ),
          ),
        );
        return;
      }

      final file = File(captured.path);
      final extractedText = await _recognizer.extractTextFromFile(file);

      if (!mounted) return;
      setState(() {
        _capturedImage = file;
        _recognizedText = extractedText.isEmpty
            ? 'No text found. Try a clearer image with better lighting.'
            : extractedText;
        final parsed = PillDetailsParser.parse(_recognizedText);
        _nameController.text = parsed.name;
        _dosageController.text = parsed.dosage;
        _instructionsController.text = parsed.instructions;
        _times
          ..clear()
          ..addAll(parsed.times);
      });

      // Immediately hand off to the AI analysis screen (it falls back to local parsing if AI fails).
      if (!mounted) return;
      context.push(
        '/scan/analysis',
        extra: ScanMedicationInput(
          imageFile: file,
          recognizedText: extractedText,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera error: ${e.code}${e.message != null ? ' — ${e.message}' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to scan text from photo: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _addTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final exists = _times.any(
        (time) => time.hour == selected.hour && time.minute == selected.minute,
      );
      if (!exists) {
        _times.add(selected);
        _times.sort((a, b) {
          final aMinutes = a.hour * 60 + a.minute;
          final bMinutes = b.hour * 60 + b.minute;
          return aMinutes.compareTo(bMinutes);
        });
      }
    });
  }

  void _removeTime(TimeOfDay time) {
    setState(() {
      _times.removeWhere(
        (item) => item.hour == time.hour && item.minute == time.minute,
      );
    });
  }

  Future<void> _promptManualMedicationAdd() async {
    final session = context.read<SessionStore>();
    final role = session.role;
    final username = session.username?.trim();

    if (role != 'elderly' || username == null || username.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manual medication add is available for elderly accounts only.'),
        ),
      );
      return;
    }

    final name = TextEditingController(text: _nameController.text.trim());
    final totalLeft = TextEditingController();
    final dosageAmount = TextEditingController(text: _dosageController.text.trim());
    final dosageSchedule = TextEditingController(
      text: _times.isEmpty ? '' : 'Daily at ${_times.map((t) => t.format(context)).join(', ')}',
    );

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Add medication manually'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Medication name',
                      hintText: 'e.g. Metformin',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: totalLeft,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total medicine left',
                      hintText: 'e.g. 30',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dosageAmount,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Dosage amount',
                      hintText: 'e.g. 500mg / 1 tablet',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dosageSchedule,
                    textInputAction: TextInputAction.done,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Dosage schedule',
                      hintText: 'e.g. Daily at 9am and 9pm',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (saved != true || !mounted) return;

      final trimmedName = name.text.trim();
      final left = int.tryParse(totalLeft.text.trim()) ?? 0;
      await ElderlyMedicationCatalogRepository().upsertMedication(
        elderlyUsername: username,
        name: trimmedName,
        totalLeft: left,
        dosageAmount: dosageAmount.text.trim(),
        dosageSchedule: dosageSchedule.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: ${trimmedName.isEmpty ? 'Medication' : trimmedName}')),
      );
    } finally {
      name.dispose();
      totalLeft.dispose();
      dosageAmount.dispose();
      dosageSchedule.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    InputDecoration deco({
      required String label,
      String? hint,
      IconData? icon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.75),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.55), width: 2),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.35, 0.7, 1.0],
            colors: [
              AppColors.pastelBlue.withValues(alpha: 0.55),
              const Color(0xFFE8EFFE).withValues(alpha: 0.9),
              AppColors.pastelYellow.withValues(alpha: 0.55),
              const Color(0xFFFFE07A).withValues(alpha: 0.55),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    _GlassCircleButton(
                      icon: Icons.arrow_back_rounded,
                      semanticsLabel: 'Back',
                      onTap: () => context.pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Scan pill bottle',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1E2D4A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: [
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Take a clear photo of the label.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.black.withValues(alpha: 0.68),
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _isProcessing ? null : _captureAndReadText,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.deepBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 26),
                            label: Text(
                              _isProcessing ? 'Processing…' : 'Take photo',
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            onPressed: _isProcessing ? null : _promptManualMedicationAdd,
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text('Manual add medication'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tip: Hold steady, fill the frame, and avoid glare.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.black.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_error != null) ...[
                      _GlassCard(
                        tint: AppColors.error.withValues(alpha: 0.10),
                        borderColor: AppColors.error.withValues(alpha: 0.25),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF1E2D4A),
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_capturedImage != null) ...[
                      _GlassCard(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(
                            _capturedImage!,
                            height: 220,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Confirm details',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: const Color(0xFF1E2D4A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            decoration: deco(
                              label: 'Medication name',
                              hint: 'e.g. Metformin',
                              icon: Icons.medication_outlined,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _dosageController,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            decoration: deco(
                              label: 'Dosage',
                              hint: 'e.g. 500 mg',
                              icon: Icons.scale_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _instructionsController,
                            minLines: 2,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25),
                            decoration: deco(
                              label: 'Instructions',
                              hint: 'e.g. Take with food',
                              icon: Icons.receipt_long_rounded,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Daily times',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1E2D4A),
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _addTime,
                                icon: const Icon(Icons.add_alarm_rounded),
                                label: const Text('Add'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.deepBlue,
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_times.isEmpty)
                            Text(
                              'No times added yet.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.black.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (_times.isNotEmpty)
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _times
                                  .map(
                                    (time) => InputChip(
                                      label: Text(
                                        time.format(context),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      onDeleted: () => _removeTime(time),
                                      deleteIcon: const Icon(Icons.close_rounded),
                                      backgroundColor: AppColors.pastelBlue.withValues(alpha: 0.6),
                                      side: BorderSide(
                                        color: AppColors.deepBlue.withValues(alpha: 0.25),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detected text',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1E2D4A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            _recognizedText.isEmpty
                                ? 'Detected text will appear here after scanning.'
                                : _recognizedText,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.68),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (tint ?? Colors.white).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (borderColor ?? Colors.white).withValues(alpha: 0.9),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.white.withValues(alpha: 0.72),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1E2D4A), size: 28),
          ),
        ),
      ),
    );
  }
}
