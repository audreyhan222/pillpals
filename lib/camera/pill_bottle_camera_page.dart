import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Pill Bottle'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _captureAndReadText,
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(_isProcessing ? 'Processing...' : 'Take Photo'),
              ),
              const SizedBox(height: 16),
              if (_capturedImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _capturedImage!,
                    height: 240,
                    fit: BoxFit.cover,
                  ),
                ),
              if (_capturedImage != null) const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (_error != null) const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dosageController,
                        decoration: const InputDecoration(
                          labelText: 'Dosage',
                          hintText: 'e.g. 25 mg',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _instructionsController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Instructions',
                          hintText: 'e.g. Take with food',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Daily Times',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addTime,
                            icon: const Icon(Icons.add_alarm_rounded),
                            label: const Text('Add Time'),
                          ),
                        ],
                      ),
                      if (_times.isEmpty)
                        const Text(
                          'No times added yet.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      if (_times.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _times
                              .map(
                                (time) => InputChip(
                                  label: Text(time.format(context)),
                                  onDeleted: () => _removeTime(time),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          _recognizedText.isEmpty
                              ? 'Detected text will appear here.'
                              : _recognizedText,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
