import 'package:flutter/material.dart';

import 'medication_name_lexicon.dart';
import 'pill_details.dart';

class PillDetailsParser {
  // Dosage: number + (mg, mL, etc.) or concentration (mg/5mL) — shared by [_extractDosage].
  // Allow sloppy spacing around hyphens (OCR / handwriting).
  static final RegExp _reDosageConcentration = RegExp(
    r'\b\d+(?:\s*[.\-]\s*\d+){1,3}\s*(?:mg|mcg|g)\s*/\s*\d+(?:\.\d+)?\s*(?:m[lL]|ml)\b',
    caseSensitive: false,
  );
  static final RegExp _reDosageNumberUnit = RegExp(
    r'\b\d+(?:\.\d+)?\s+(?:mg|mcg|g|m[lL]|ml|ug|iu|units?/h(?:r)?|units?)\b',
    caseSensitive: false,
  );
  static final RegExp _reDosageNumberTouchingUnit = RegExp(
    r'\b\d+(?:\.\d+)?(?:mg|mcg|g|m[lL]|ml|ug|iu)\b',
    caseSensitive: false,
  );
  /// Tight: “25 mg tablet” (strength then form; [group 1] = 25 mg).
  static final RegExp _reDosageTabletForm = RegExp(
    r'\b('
    r'\d+(?:[.,]\d+)?\s*(?:m\s*g|m\s*l|m\s*c\s*g|mcg|m[lL]|ml|ug|iu|g)\b'
    r')'
    r'\s*(?:t\s*abs?|t\s*ab\.?|t\s*ab|tablets?|tabs?|t\s*ablets?|softgels?|capsule|capsules?|caplets?|caps?)\b',
    caseSensitive: false,
  );
  /// “100 MG 30 TABLETS”, “500mg  60  TABS”, “250 mcg 28 caplets” — [group 1] = 100 MG / 500 mg, not the “30/60/28” count.
  static final RegExp _reDoseUnitBeforePillForm = RegExp(
    r'\b('
    r'\d+(?:[.,]\d+)?\s*(?:m\s*g|m\s*l|m\s*c\s*g|mcg|m[lL]|ml|ug|iu|g)\b'
    r')'
    r'(?:\s*[\-–/])?'
    r'(?:\s*#?\d+\b){0,2}\s*'
    r'(?:t\s*abs?|t\s*ab\.?|t\s*ab|tablets?|tabs?|t\s*ablets?|softgels?|capsule|capsules?|caplets?|caps?)\b',
    caseSensitive: false,
  );
  /// Same block but strength and “TAB(LET)…” are farther apart (OCR, wrapping).
  static final RegExp _reStrengthMentionedBeforePillFormWord = RegExp(
    r'\b('
    r'\d+(?:[.,]\d+)?\s*(?:m\s*g|m\s*l|m\s*c\s*g|mcg|m[lL]|ml|ug|iu|g)\b'
    r')'
    r'[\s\w•·,./#%\-–—]{0,160}?\b(?:t\s*abs?|t\s*ab|tablets?|tabs?|t\s*ablets?|softgels?|capsule|capsules?|caplets?|caps?)\b',
    caseSensitive: false,
  );
  // Handwriting / bad OCR: optional colon or bullet before number, comma decimals.
  static final RegExp _reDosageLoose = RegExp(
    r'(?:^|[\s:•\-])(\d+(?:[.,]\d+)?)\s*[-]?\s*(?:mg|mcg|m[lL]|ml|ug|iu)\b',
    caseSensitive: false,
  );
  static final RegExp _reDosageFractionMl = RegExp(
    r'\b\d+\s*/\s*\d+\s*(?:m[lL]|ml)\b',
    caseSensitive: false,
  );
  // OCR often inserts noise between a number and a unit (e.g. 50.mg, 5O0m g, “500     mg”).
  static final RegExp _reDosageMangledNumberUnit = RegExp(
    r'\b(\d+(?:[.,]\d+)?).{0,12}(m\s*g|m\s*l|m\s*c\s*g|mcg|i\.?u\.?|units?|%)',
    caseSensitive: false,
  );

  /// Collapse common label OCR splits so [mg] patterns can match the strength line
  /// (often the 3rd line in handwritten / sticky notes).
  static String _collapseOcrForDosage(String s) {
    var t = s;
    // Common OCR: letter O or o for zero inside dose numbers.
    t = t.replaceAll(RegExp(r'(?<=\d)[oO](?=\d)', caseSensitive: false), '0');
    // e.g. “5oo” read for “500” before mg
    t = t.replaceAllMapped(
      RegExp(r'(\d)oo(?=\s*mg)', caseSensitive: false),
      (m) => '${m[1]}00',
    );
    t = t.replaceAll(RegExp(r'm\s*[/\\]\s*g', caseSensitive: false), 'mg');
    t = t.replaceAll(RegExp(r'm\s+c\s*g|m\s*c\s*g', caseSensitive: false), 'mcg');
    t = t.replaceAll(RegExp(r'm\s+g\b', caseSensitive: false), 'mg');
    t = t.replaceAllMapped(
      RegExp(r'(\d)\s*([.,])\s*(\d)'),
      (m) => '${m[1]}${m[2]}${m[3]}',
    );
    // “10 0 mg” / “1 0 0 mg” (spaces inside hundreds) would otherwise match “0 mg” in [_reDosageLoose].
    for (var k = 0; k < 3; k++) {
      t = t.replaceAllMapped(
        RegExp(
          r'(\d+(?:\s+\d+)+)(?=\s*(?:m\s*g|m\s*l|m\s*c\s*g|mcg|i\.?u\.?|ug|iu|units?|%))',
          caseSensitive: false,
        ),
        (m) => m[1]!.replaceAll(RegExp(r'\s+'), ''),
      );
    }
    return t;
  }

  static bool _looksLikeInstructionLineForDosage(String line) {
    final l = line.toLowerCase();
    if (RegExp(r'^\s*(note|name|medication)\s*[:]', caseSensitive: false).hasMatch(l)) {
      return false;
    }
    if (l.contains('take') && (l.contains('mouth') || l.contains('tab') || l.contains('day'))) {
      return true;
    }
    if (RegExp(r'\b(swallow|every\s+\d|by\s+mouth|times\s+per|once\s+(daily|a\s+day))', caseSensitive: false)
        .hasMatch(l)) {
      return true;
    }
    return false;
  }

  static PillDetails parse(String text) {
    final normalized = text.trim();
    final lines = normalized
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final name = _extractName(lines);
    final dosage = _extractDosage(lines);
    final instructions = _extractInstructions(lines);
    final intervalMinutes = _extractIntervalMinutes(lines, normalized);
    final times = _extractTimes(lines, normalized);

    return PillDetails(
      name: name,
      dosage: dosage,
      instructions: instructions,
      times: times,
      intervalMinutes: intervalMinutes,
      rawText: normalized,
    );
  }

  static String _extractName(List<String> lines) {
    if (lines.isEmpty) return '';
    // Scored candidate selection. We score each OCR line for "drug-likeness"
    // and pick the highest-confidence line (keeps the entire line).
    //
    // This is intentionally lightweight + offline; it’s not a drug database lookup.
    final dashDrug = RegExp(r'\b[A-Za-z0-9]{2,}(?:-[A-Za-z0-9]{1,})+\b');
    final allCapsWords = RegExp(r'^[A-Z0-9]{2,}(?:\s+[A-Z0-9]{2,}){1,4}$');
    final unitsRe = RegExp(r'\b(mg|mcg|g|ml|units?)\b', caseSensitive: false);
    final rxJunkRe = RegExp(
      r'\b(patient|pharmacy|address|rx\b|refill|doctor|dr\.|phone|qty|quantity|date|dob)\b',
      caseSensitive: false,
    );
    final saltWords = <String>{
      'potassium',
      'sodium',
      'hydrochloride',
      'hcl',
      'acetate',
      'phosphate',
      'sulfate',
      'succinate',
      'tartrate',
      'citrate',
      'carbonate',
      'nitrate',
      'chloride',
      'maleate',
      'mesylate',
      'besylate',
      'fumarate',
    };
    final drugSuffixes = <String>[
      'pril',
      'sartan',
      'olol',
      'statin',
      'prazole',
      'tidine',
      'caine',
      'mycin',
      'cillin',
      'cycline',
      'floxacin',
      'azole',
      'vir',
      'mab',
      'nib',
      'zepam',
      'zine',
      'triptan',
      'oxetine',
      'opram',
      'ine',
      'one',
    ];

    bool isAllCapsLine(String s) {
      final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.isEmpty || letters.length < 3) return false;
      final upper = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
      return upper / letters.length >= 0.8;
    }

    bool looksLikePersonName(String line) {
      final s = line.trim();
      if (RegExp(r'[\d/-]').hasMatch(s)) return false;
      if (unitsRe.hasMatch(s)) return false;
      if (s.contains(',')) return false;
      final parts = s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length < 2 || parts.length > 3) return false;
      bool isNameWord(String w) => RegExp(r'^[A-Z][a-z]{1,}$').hasMatch(w);
      if (!parts.every(isNameWord)) return false;
      final lower = s.toLowerCase();
      if (lower.contains('tablet') || lower.contains('capsule') || lower.contains('solution')) {
        return false;
      }
      return true;
    }

    double scoreLine(String line, int lineIndex, int lineCount) {
      final t = line.trim();
      if (t.isEmpty) return double.negativeInfinity;
      if (t.length < 3 || t.length > 70) return double.negativeInfinity;

      final lower = t.toLowerCase();
      final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      double score = 0;

      // Medication *names* are essentially never numeric; numbers belong in dosage / dates / Rx lines.
      if (RegExp(r'\d').hasMatch(t)) {
        // Allow hyphenated chemical names (letters only, e.g. BROMPHEN-PSE-DM) — they have no digits.
        score -= 14;
      }

      // Hard negatives.
      if (rxJunkRe.hasMatch(lower)) score -= 8;
      if (looksLikePersonName(t)) score -= 7;
      // IDs / long digit sequences.
      if (RegExp(r'\b\d{4,}\b').hasMatch(t)) score -= 6;

      // Handwriting/sticky notes: 2nd line is often all-caps for “carrying” (heading, not the drug name).
      final isSecondAllCapsCarrier = lineIndex == 1 &&
          lineCount >= 2 &&
          isAllCapsLine(t) &&
          !dashDrug.hasMatch(t) &&
          !words.any(saltWords.contains);
      if (isSecondAllCapsCarrier) {
        score -= 9;
      }

      // Positives: patterns commonly seen in medication names.
      if (dashDrug.hasMatch(t)) score += 10;
      // All-caps is common on labels; for notes, 1st line is more often the drug than a carrier line.
      if (allCapsWords.hasMatch(t)) {
        if (lineIndex == 0) {
          score += 6;
        } else if (!isSecondAllCapsCarrier) {
          score += 4;
        } else {
          score -= 1;
        }
      }

      // Multi-word generic/salt forms (Gabapentin Potassium, etc.)
      if (words.length >= 2 && words.length <= 5) score += 1.5;
      if (words.any(saltWords.contains)) score += 4;

      // Drug-y suffixes on the last token.
      final last = words.isEmpty ? '' : words.last.replaceAll(RegExp(r'[^a-z]'), '');
      for (final suf in drugSuffixes) {
        if (last.length >= suf.length + 2 && last.endsWith(suf)) {
          score += 2.5;
          break;
        }
      }

      // Penalize lines that look like strength/directions, not names.
      if (unitsRe.hasMatch(t)) score -= 4;
      if (lower.contains('take ') || lower.contains('by mouth') || lower.contains('every ')) {
        score -= 4;
      }
      if (lower.contains('tablet') ||
          lower.contains('capsule') ||
          lower.contains('solution') ||
          lower.contains('suspension')) {
        score -= 1.5;
      }

      // Prefer cleaner "name-only" lengths.
      if (t.length >= 4 && t.length <= 35) score += 1;

      // Known medication names (curated lexicon) — strong signal vs. headings / carrier lines.
      score += MedicationNameLexicon.nameLineBoost(t);

      return score;
    }

    String best = '';
    double bestScore = double.negativeInfinity;
    for (var i = 0; i < lines.length; i++) {
      final s = scoreLine(lines[i], i, lines.length);
      if (s > bestScore) {
        bestScore = s;
        best = lines[i].trim();
      }
    }
    if (best.isNotEmpty && bestScore > -5) return best;

    // Next: explicit "Name:" format.
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('name:')) return line.substring(5).trim();
    }

    // Avoid obvious non-drug lines (patient names, addresses, ids).
    bool isJunk(String line) {
      final l = line.toLowerCase();
      if (l.contains('patient') ||
          l.contains('pharmacy') ||
          l.contains('address') ||
          l.contains('rx') ||
          l.contains('refill') ||
          l.contains('doctor') ||
          l.contains('phone')) {
        return true;
      }
      // No digits in a medication *name* line (dose, dates, IDs live elsewhere).
      if (RegExp(r'\d').hasMatch(line)) return true;
      if (RegExp(r'\b(mg|mcg|ml|units?)\b', caseSensitive: false).hasMatch(line)) return true;
      return false;
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 2 || trimmed.length > 60) continue;
      if (isJunk(trimmed)) continue;
      return trimmed;
    }

    // Fallback: first line without digits, else first line.
    for (final line in lines) {
      if (!RegExp(r'\d').hasMatch(line)) return line.trim();
    }
    return lines.first;
  }

  static int _leadingDoseNumberValue(String? token) {
    if (token == null || token.isEmpty) return 0;
    final t = token.replaceAll(' ', '');
    if (t.isEmpty) return 0;
    final d = t.replaceAll(',', '.');
    final n = num.tryParse(d);
    if (n != null) return n.round();
    return int.tryParse(RegExp(r'^\d+').firstMatch(t)?.group(0) ?? '') ?? 0;
  }

  /// Prefer “100 mg” over a leftmost spurious “0 mg” on the same text.
  static String? _bestDoseStringNumberAndUnit(String text) {
    Match? best;
    var bestV = -1;
    for (final m in <Match>[..._reDosageNumberUnit.allMatches(text), ..._reDosageNumberTouchingUnit.allMatches(text)]) {
      final numPart = RegExp(r'\d+(?:[.,]\d+)?', caseSensitive: false)
              .firstMatch(m.group(0) ?? '')?.group(0) ??
          '';
      final v = _leadingDoseNumberValue(numPart);
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (best == null) return null;
    return best.group(0)!.trim();
  }

  static String? _bestDoseStringMangled(String text) {
    Match? best;
    var bestV = -1;
    for (final m in _reDosageMangledNumberUnit.allMatches(text)) {
      final v = _leadingDoseNumberValue(m.group(1));
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (best == null) return null;
    return best.group(0)!.trim();
  }

  static String? _bestDoseStringLoose(String text) {
    Match? best;
    var bestV = -1;
    for (final m in _reDosageLoose.allMatches(text)) {
      final v = _leadingDoseNumberValue(m.group(1));
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (best == null) return null;
    return best.group(0)!.replaceAll(RegExp(r'^[\s:•\-]+'), '').trim();
  }

  /// Picks strength (e.g. 100 MG, 500 mg) when [TAB(LET)S] / [CAPS] appear on the label (with or without a count in between).
  static String? _bestDoseFromTabletMentions(String text) {
    Match? bestM;
    var bestN = -1;
    for (final re in [
      _reDoseUnitBeforePillForm,
      _reStrengthMentionedBeforePillFormWord,
      _reDosageTabletForm,
    ]) {
      for (final m in re.allMatches(text)) {
        final g1 = m.group(1);
        if (g1 == null || g1.isEmpty) continue;
        final n = _leadingDoseNumberValue(
          RegExp(r'\d+(?:[.,]\d+)?', caseSensitive: false).firstMatch(g1.trim())?.group(0),
        );
        if (n > bestN) {
          bestN = n;
          bestM = m;
        }
      }
    }
    if (bestM == null) return null;
    return bestM.group(1)!.trim();
  }

  static String _extractDosage(List<String> lines) {
    // Normalize OCR splits (e.g. “m g”, “5 O 0”) so unit regexes can fire.
    // Does not change medication name extraction.
    final normLines = lines.map((l) => _collapseOcrForDosage(l.trim())).toList();
    // Join lines so “10” and “0 mg” on two lines become “10 0 mg” and merge to “100 mg”.
    final mergedFull = _collapseOcrForDosage(normLines.join(' '));

    String pickLoose(String blob) {
      if (_reDosageFractionMl.hasMatch(blob)) {
        return _reDosageFractionMl.firstMatch(blob)!.group(0)!.trim();
      }
      final conc = _reDosageConcentration.firstMatch(blob);
      if (conc != null) return conc.group(0)!.trim();
      final tabDose = _bestDoseFromTabletMentions(blob);
      if (tabDose != null) return tabDose;
      final nu = _bestDoseStringNumberAndUnit(blob);
      if (nu != null) return nu;
      final lo = _bestDoseStringLoose(blob);
      if (lo != null) return lo;
      return _bestDoseStringMangled(blob) ?? '';
    }

    for (final line in normLines) {
      if (line.isEmpty) continue;
      if (_reDosageConcentration.hasMatch(line)) {
        return _reDosageConcentration.firstMatch(line)!.group(0)!.trim();
      }
    }
    for (final line in normLines) {
      if (line.isEmpty) continue;
      final lo = line.toLowerCase();
      if (lo.contains('dosage') || lo.contains('strength')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          final rest = parts.sublist(1).join(':').trim();
          final got = pickLoose(rest);
          if (got.isNotEmpty) return got;
        }
      }
    }
    for (final line in normLines) {
      if (line.isEmpty) continue;
      final tD = _bestDoseFromTabletMentions(line);
      if (tD != null) return tD;
    }
    for (final line in normLines) {
      if (line.isEmpty) continue;
      final s = _bestDoseStringNumberAndUnit(line);
      if (s != null) return s;
    }
    for (final line in normLines) {
      if (line.isEmpty) continue;
      final s = _bestDoseStringLoose(line);
      if (s != null) return s;
    }
    for (final line in normLines) {
      if (line.isEmpty) continue;
      final s2 = _bestDoseStringMangled(line);
      if (s2 != null) return s2;
    }
    // Line breaks (or even spaces) may split “500” and “mg” — search merged text.
    var fromBlob = pickLoose(mergedFull);
    if (fromBlob.isNotEmpty) return fromBlob;
    fromBlob = pickLoose(normLines.join('\n'));
    if (fromBlob.isNotEmpty) return fromBlob;
    fromBlob = pickLoose(normLines.join(' '));
    if (fromBlob.isNotEmpty) return fromBlob;

    // Common layout: name / heading / **third line = strength** (handwritten, sticky).
    if (normLines.length >= 3) {
      final t = normLines[2].trim();
      if (t.isNotEmpty &&
          RegExp(r'\d').hasMatch(t) &&
          !_looksLikeInstructionLineForDosage(t)) {
        var got = pickLoose(t);
        if (got.isNotEmpty) return got;
        final m3 = _bestDoseStringMangled(t);
        if (m3 != null) return m3;
        if (t.length <= 22 && RegExp(r'^\d+(?:[.,]\d+)?\s*$').hasMatch(t)) {
          return t;
        }
        if (t.length <= 48 &&
            RegExp(r'\b(mg|ml|mcg|m\s*g|m\s*l|unit|units|%)', caseSensitive: false).hasMatch(t) &&
            !RegExp(r'\b(take|swallow|every|daily)\b', caseSensitive: false).hasMatch(t)) {
          return t;
        }
      }
    }
    return '';
  }

  static String _extractInstructions(List<String> lines) {
    for (final line in lines) {
      final lower = line.toLowerCase().trim();
      const prefixes = ['instructions:', 'sig:', 'directions:', 'direction:'];
      for (final p in prefixes) {
        if (lower.startsWith(p)) {
          return line.substring(p.length).trim();
        }
      }
    }
    // Prefer lines with SIG-like language; penalize lines that are mostly strength.
    int scoreInstructionLine(String line) {
      final l = line.toLowerCase();
      var s = 0;
      for (final w in [
        'by mouth',
        'swallow',
        'orally',
        'with food',
        'with water',
        'empty stomach',
        ' every ',
        ' daily',
        'twice',
        'once daily',
        'at bedtime',
        'before meals',
        'after meals',
        'as needed',
        'as directed',
        'prn',
        'per day',
        'do not',
        'dilute',
        'shake',
        'apply',
      ]) {
        if (l.contains(w)) s++;
      }
      if (RegExp(r'\btake\b', caseSensitive: false).hasMatch(l)) s += 2;
      if (RegExp(r'\bevery\b', caseSensitive: false).hasMatch(l)) s++;
      if (RegExp(r'every\s+\d', caseSensitive: false).hasMatch(l)) s += 2;
      if (RegExp(r'^\d', dotAll: false).hasMatch(line) &&
          RegExp(r'\b(mg|mcg|m[lL]|/)\b', caseSensitive: false).hasMatch(l) &&
          !RegExp(r'\btake\b', caseSensitive: false).hasMatch(l) &&
          !l.contains('mouth')) {
        s -= 3;
      }
      return s;
    }

    String? best;
    var bestS = 0;
    for (final line in lines) {
      final t = line.trim();
      if (t.length < 3) continue;
      final sc = scoreInstructionLine(t);
      if (sc > bestS) {
        bestS = sc;
        best = t;
      }
    }
    if (best != null && bestS >= 1) return best;

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (RegExp(r'\b(take|swallow|drink)\b', caseSensitive: false).hasMatch(line) ||
          RegExp(r'\bwith (food|water|milk)\b', caseSensitive: false).hasMatch(line) ||
          (lower.contains('every') && RegExp(r'\d').hasMatch(line))) {
        return line;
      }
    }
    return '';
  }

  static int _extractIntervalMinutes(List<String> lines, String fullText) {
    final lower = fullText.toLowerCase();

    // "every 6 hours"
    final everyHours = RegExp(r'\bevery\s+(\d{1,2})\s*(hours?|hrs?|hr|h)\b');
    final m = everyHours.firstMatch(lower);
    if (m != null) {
      final hours = int.tryParse(m.group(1) ?? '');
      if (hours != null && hours > 0) return hours * 60;
    }

    // Daily phrases.
    if (lower.contains('once daily') || RegExp(r'\bdaily\b').hasMatch(lower)) {
      return 24 * 60;
    }
    if (lower.contains('twice daily') || lower.contains('2 times daily')) {
      return 12 * 60;
    }
    if (lower.contains('three times daily') || lower.contains('3 times daily')) {
      return 8 * 60;
    }

    // Unknown / not interval-based.
    return 0;
  }

  static List<TimeOfDay> _extractTimes(List<String> lines, String fullText) {
    final results = <TimeOfDay>{};

    final timeRegex = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);
    for (final line in lines) {
      for (final match in timeRegex.allMatches(line)) {
        final hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2) ?? '0');
        final period = match.group(3)!.toLowerCase();
        final hour24 = _to24Hour(hour, period);
        results.add(TimeOfDay(hour: hour24, minute: minute));
      }
    }

    final lowerText = fullText.toLowerCase();
    if (results.isEmpty) {
      if (lowerText.contains('once daily')) {
        results.add(const TimeOfDay(hour: 9, minute: 0));
      } else if (lowerText.contains('twice daily')) {
        results
          ..add(const TimeOfDay(hour: 9, minute: 0))
          ..add(const TimeOfDay(hour: 21, minute: 0));
      } else if (lowerText.contains('three times daily')) {
        results
          ..add(const TimeOfDay(hour: 8, minute: 0))
          ..add(const TimeOfDay(hour: 13, minute: 0))
          ..add(const TimeOfDay(hour: 20, minute: 0));
      }
    }

    final sorted = results.toList()
      ..sort((a, b) {
        final aMinutes = a.hour * 60 + a.minute;
        final bMinutes = b.hour * 60 + b.minute;
        return aMinutes.compareTo(bMinutes);
      });
    return sorted;
  }

  static int _to24Hour(int hour, String period) {
    if (period == 'am') return hour == 12 ? 0 : hour;
    return hour == 12 ? 12 : hour + 12;
  }
}
