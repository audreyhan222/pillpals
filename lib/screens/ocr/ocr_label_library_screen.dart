import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../firestore/ocr_label_correction_model.dart';
import '../../firestore/ocr_label_correction_repository.dart';

/// Saved raw OCR + your corrected name / dosage / instructions (one analysis pipeline).
class OcrLabelLibraryScreen extends StatefulWidget {
  const OcrLabelLibraryScreen({super.key});

  @override
  State<OcrLabelLibraryScreen> createState() => _OcrLabelLibraryScreenState();
}

class _OcrLabelLibraryScreenState extends State<OcrLabelLibraryScreen> {
  final _repo = OcrLabelCorrectionRepository();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  String? _streamError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openStream());
  }

  Future<void> _openStream() async {
    if (!mounted) return;
    try {
      final s = await _repo.openSnapshots(context);
      if (mounted) setState(() => _stream = s);
    } catch (e) {
      if (mounted) setState(() => _streamError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Label text library'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _streamError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_streamError!, textAlign: TextAlign.center),
              ),
            )
          : _stream == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('${snap.error}'));
                    }
                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No saved label text yet.\nAfter you scan a label and Save, the OCR and your edits are stored here for next time.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.6),
                              height: 1.3,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final c = OcrLabelCorrection.fromDoc(d.id, d.data());
                        return _CorrectionCard(
                          correction: c,
                          onEdit: () => _editDialog(context, c),
                          onDelete: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Remove this entry?'),
                                content: const Text(
                                    'Future scans won’t use these corrections for this OCR text.',),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              try {
                                await _repo.deleteCorrection(
                                    context: context, docId: c.id,);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Delete failed: $e')),
                                  );
                                }
                              }
                            }
                          },
                        );
                      },
                    );
                  },
                ),
    );
  }

  Future<void> _editDialog(BuildContext context, OcrLabelCorrection c) async {
    final name = TextEditingController(text: c.correctName);
    final dose = TextEditingController(text: c.correctDosage);
    final inst = TextEditingController(text: c.correctInstructions);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Edit correct fields'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'OCR (read-only)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    c.rawOcrText.isEmpty ? '—' : c.rawOcrText,
                    style: const TextStyle(fontSize: 12, height: 1.2),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Medication name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dose,
                    decoration: const InputDecoration(labelText: 'Dosage'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inst,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Instructions'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (saved == true && context.mounted) {
        await _repo.upsertCorrection(
          context: context,
          rawOcrText: c.rawOcrText,
          correctName: name.text,
          correctDosage: dose.text,
          correctInstructions: inst.text,
        );
      }
    } finally {
      name.dispose();
      dose.dispose();
      inst.dispose();
    }
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({
    required this.correction,
    required this.onEdit,
    required this.onDelete,
  });

  final OcrLabelCorrection correction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x14000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    correction.correctName.isEmpty ? '—' : correction.correctName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2D4A),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 20),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
            Text(
              'Dosage: ${correction.correctDosage.isEmpty ? '—' : correction.correctDosage}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              correction.correctInstructions.isEmpty
                  ? '—'
                  : correction.correctInstructions,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.55),
                height: 1.2,
              ),
            ),
            if (correction.rawOcrText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'OCR snapshot',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                correction.rawOcrText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
