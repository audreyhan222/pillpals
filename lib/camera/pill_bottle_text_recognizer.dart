import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// First-pass heuristics only (no new model). Used to pick a crop + second-pass strategy.
/// Parsed medication fields still come from a single [PillDetailsParser] path on the client.
enum OcrMediaKind {
  /// Printed pharmacy / prescription label: many blocks, pharmacy/patient phrasing, tight drug/SIG crop.
  officialLabel,
  /// Sticky note / loose writing: few blocks, avoid aggressive ROI that can clip the note.
  handwrittenNote,
}

class PillBottleTextRecognizer {
  PillBottleTextRecognizer() : _textRecognizer = TextRecognizer();

  final TextRecognizer _textRecognizer;

  /// Last detected media from the most recent [extractTextFromPath] (for optional UI / debugging).
  OcrMediaKind? lastMediaKind;

  Future<String> extractTextFromPath(String imagePath) async {
    // 2-pass OCR:
    // 1) Bake orientation, run ML Kit once; classify "label vs handwriting" for crop strategy.
    // 2) Second pass: official labels use union ROI of important blocks; notes use a gentle center crop.
    // Sorting into name/dosage/SIG is always [PillDetailsParser] (same for both).
    lastMediaKind = null;
    final oriented = await _writeOrientedTempImage(imagePath);
    if (oriented == null) {
      final recognizedText = await _textRecognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return recognizedText.text.trim();
    }

    final firstPass = await _textRecognizer.processImage(
      InputImage.fromFilePath(oriented.path),
    );

    final kind = _classifyMediaKind(firstPass);
    lastMediaKind = kind;

    final _Roi roi;
    if (kind == OcrMediaKind.handwrittenNote) {
      // Keep almost the full frame; light trim of edges to drop noise.
      roi = _centerRoi(oriented.width, oriented.height, keepW: 0.95, keepH: 0.93);
    } else {
      roi = _roiFromImportantBlocks(
            recognizedText: firstPass,
            imageWidth: oriented.width,
            imageHeight: oriented.height,
          ) ??
          _centerRoi(oriented.width, oriented.height, keepW: 0.92, keepH: 0.88);
    }

    final croppedPath = await _cropToRoi(oriented.path, roi);
    if (croppedPath == null) {
      return firstPass.text.trim();
    }

    final secondPass = await _textRecognizer.processImage(
      InputImage.fromFilePath(croppedPath),
    );
    final first = firstPass.text.trim();
    final second = secondPass.text.trim();
    if (second.isEmpty) return first;
    // Handwriting: if the second pass is much shorter, the crop may have been wrong — prefer first.
    if (kind == OcrMediaKind.handwrittenNote && second.length < first.length * 0.55) {
      return first;
    }
    return second;
  }

  Future<String> extractTextFromFile(File imageFile) {
    return extractTextFromPath(imageFile.path);
  }

  Future<_TempOriented?> _writeOrientedTempImage(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Normalize EXIF orientation (common on iOS photos).
      final oriented = img.bakeOrientation(decoded);

      final out = File(
        '${Directory.systemTemp.path}/pillpals_ocr_oriented_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(img.encodeJpg(oriented, quality: 92), flush: true);
      return _TempOriented(path: out.path, width: oriented.width, height: oriented.height);
    } catch (_) {
      return null;
    }
  }

  /// Heuristic from ML Kit [RecognizedText] only (no extra ML model):
  /// - Labels: pharmacy / dose units / “take” / many blocks.
  /// - Notes: *strict* few-block + long freeform, so printed labels are not misclassified.
  OcrMediaKind _classifyMediaKind(RecognizedText recognizedText) {
    final text = recognizedText.text.trim();
    if (text.isEmpty) return OcrMediaKind.officialLabel;

    final labelWord = RegExp(
      r'\b(patient|pharmacy|pharmacist|prescri|refill|ndc|quantity|rx\b|dispense|substitution|sig\b)\b',
      caseSensitive: false,
    );
    // Med-label cues (handwriting path was too sensitive; most real labels hit this).
    final looksLikeMedicationLine = RegExp(
      r'\b(mg|mcg|m[lL]|ml|ug|mcgs?|units?|take|by\s+mouth|swallow|every\s+\d|daily|tablet|capsule|solution|suspension)\b',
      caseSensitive: false,
    );
    if (looksLikeMedicationLine.hasMatch(text)) {
      return OcrMediaKind.officialLabel;
    }

    int labelBlockHits = 0;
    for (final b in recognizedText.blocks) {
      if (labelWord.hasMatch(b.text)) labelBlockHits++;
    }
    final fullLabel = labelWord.hasMatch(text);
    final blockCount = recognizedText.blocks.length;
    if (blockCount == 0) return OcrMediaKind.officialLabel;

    final int maxBlockLen = recognizedText.blocks
        .map((b) => b.text.length)
        .reduce((a, b) => a > b ? a : b);
    // Stricter than before: one block must carry most of the text to call it a “note”.
    final bool oneDominantBlock = maxBlockLen > text.length * 0.64;

    // Strong official: repeated label vocabulary or typical dense label layout.
    if (labelBlockHits >= 2 || (fullLabel && blockCount >= 4)) {
      return OcrMediaKind.officialLabel;
    }
    if (labelBlockHits >= 1 && blockCount >= 5) {
      return OcrMediaKind.officialLabel;
    }

    // Handwriting / loose sticky: very few blocks, no med keywords above, one long paragraph.
    if (blockCount == 1 && !fullLabel && text.length > 48 && oneDominantBlock) {
      return OcrMediaKind.handwrittenNote;
    }
    if (blockCount == 2 &&
        !fullLabel &&
        oneDominantBlock &&
        text.length > 32 &&
        maxBlockLen > text.length * 0.58) {
      return OcrMediaKind.handwrittenNote;
    }
    if (blockCount == 3 &&
        !fullLabel &&
        oneDominantBlock &&
        text.length > 40 &&
        maxBlockLen > text.length * 0.55) {
      return OcrMediaKind.handwrittenNote;
    }

    return OcrMediaKind.officialLabel;
  }

  _Roi? _roiFromImportantBlocks({
    required RecognizedText recognizedText,
    required int imageWidth,
    required int imageHeight,
  }) {
    // We look for:
    // - Drug names: mostly ALL CAPS, hyphenated tokens, salt words.
    // - Instructions: "take", "by mouth", "every", "daily", etc.
    bool isAllCapsHeavy(String s) {
      final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.isEmpty || letters.length < 4) return false;
      final upper = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
      return upper / letters.length >= 0.75;
    }

    bool looksLikeDrugName(String s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      if (RegExp(r'\b[A-Za-z0-9]{2,}(?:-[A-Za-z0-9]{1,})+\b').hasMatch(t)) return true;
      if (isAllCapsHeavy(t)) return true;
      final lower = t.toLowerCase();
      return lower.contains('hydrochloride') ||
          lower.contains('hcl') ||
          lower.contains('potassium') ||
          lower.contains('sodium');
    }

    bool looksHandwrittenLike(String s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      // If it's mostly letters/spaces and not obviously meta, it might be handwriting text.
      final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
      if (letters < 5) return false;
      if (RegExp(r'\b(patient|pharmacy|address|rx)\b', caseSensitive: false).hasMatch(t)) {
        return false;
      }
      // Avoid pure person-name-ish short lines; we just want to broaden crop, not classify name.
      final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length == 2 &&
          RegExp(r'^[A-Z][a-z]+$').hasMatch(words[0]) &&
          RegExp(r'^[A-Z][a-z]+$').hasMatch(words[1])) {
        return false;
      }
      return true;
    }

    bool looksLikeInstruction(String s) {
      final l = s.toLowerCase();
      return l.contains('take') ||
          l.contains('by mouth') ||
          l.contains('every') ||
          l.contains('daily') ||
          l.contains('at bedtime') ||
          l.contains('with food') ||
          l.contains('swallow') ||
          l.contains('as needed');
    }

    int score(String s) {
      int sc = 0;
      if (looksLikeDrugName(s)) sc += 6;
      if (looksLikeInstruction(s)) sc += 5;
      if (isAllCapsHeavy(s)) sc += 2;
      // Looser: if we see handwriting-like blocks, include them to anchor crop.
      if (looksHandwrittenLike(s)) sc += 2;
      if (RegExp(r'\b(mg|mcg|ml)\b', caseSensitive: false).hasMatch(s)) sc += 1;
      // Down-rank junky meta lines.
      final l = s.toLowerCase();
      if (l.contains('patient') || l.contains('pharmacy') || l.contains('address') || l.contains('rx')) {
        sc -= 6;
      }
      return sc;
    }

    int bestScore = 0;
    _Roi? union;

    for (final block in recognizedText.blocks) {
      final text = block.text.trim();
      final sc = score(text);
      if (sc <= 0) continue;

      // Keep top-ish blocks by absolute score threshold.
      if (sc >= 3) {
        final r = block.boundingBox;
        final rect = _Roi(
          left: r.left.round(),
          top: r.top.round(),
          width: r.width.round(),
          height: r.height.round(),
        );
        union = union == null ? rect : _union(union, rect);
        if (sc > bestScore) bestScore = sc;
      }
    }

    if (union == null) return null;

    // Expand margins a bit so we don't crop too tight.
    final padX = (union.width * 0.18).round();
    final padY = (union.height * 0.22).round();
    final x = (union.left - padX).clamp(0, imageWidth - 1);
    final y = (union.top - padY).clamp(0, imageHeight - 1);
    final right = (union.left + union.width + padX).clamp(1, imageWidth);
    final bottom = (union.top + union.height + padY).clamp(1, imageHeight);
    final w = (right - x).clamp(1, imageWidth);
    final h = (bottom - y).clamp(1, imageHeight);

    // If ROI is basically the whole image, don't bother.
    if (w > imageWidth * 0.95 && h > imageHeight * 0.95) return null;
    return _Roi(left: x, top: y, width: w, height: h);
  }

  _Roi _centerRoi(int imageWidth, int imageHeight, {required double keepW, required double keepH}) {
    final cropW = (imageWidth * keepW).round().clamp(1, imageWidth);
    final cropH = (imageHeight * keepH).round().clamp(1, imageHeight);
    final left = ((imageWidth - cropW) / 2).round().clamp(0, imageWidth - 1);
    final top = ((imageHeight - cropH) / 2).round().clamp(0, imageHeight - 1);
    return _Roi(left: left, top: top, width: cropW, height: cropH);
  }

  _Roi _union(_Roi a, _Roi b) {
    final left = a.left < b.left ? a.left : b.left;
    final top = a.top < b.top ? a.top : b.top;
    final rightA = a.left + a.width;
    final rightB = b.left + b.width;
    final bottomA = a.top + a.height;
    final bottomB = b.top + b.height;
    final right = rightA > rightB ? rightA : rightB;
    final bottom = bottomA > bottomB ? bottomA : bottomB;
    return _Roi(left: left, top: top, width: right - left, height: bottom - top);
  }

  Future<String?> _cropToRoi(String imagePath, _Roi roi) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final x = roi.left.clamp(0, decoded.width - 1);
      final y = roi.top.clamp(0, decoded.height - 1);
      final w = roi.width.clamp(1, decoded.width - x);
      final h = roi.height.clamp(1, decoded.height - y);

      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      final out = File(
        '${Directory.systemTemp.path}/pillpals_ocr_roi_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}

class _TempOriented {
  const _TempOriented({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;
}

class _Roi {
  const _Roi({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  final int left;
  final int top;
  final int width;
  final int height;
}
