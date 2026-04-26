/// Common generic / brand medication name hints for offline OCR ranking.
/// Not a medical database — expand as needed. Used to prefer known drug tokens
/// when scoring [PillDetailsParser] name lines.

/// Normalizes [line] for phrase / token matching (OCR noise, punctuation).
String _normalizeForMatch(String line) {
  return line
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Multi-word entries (substrings after normalization).
const List<String> kMedicationNamePhrases = [
  'acetaminophen with codeine',
  'insulin glargine',
  'insulin lispro',
];

/// Single-word medication names (lowercase). Derived from a representative
/// primary-care / common prescription list.
const Set<String> kMedicationNameTokens = {
  'acetaminophen',
  'codeine',
  'insulin',
  'ibuprofen',
  'naproxen',
  'tramadol',
  'hydrocodone',
  'oxycodone',
  'amoxicillin',
  'azithromycin',
  'ciprofloxacin',
  'doxycycline',
  'clindamycin',
  'cephalexin',
  'sertraline',
  'fluoxetine',
  'escitalopram',
  'citalopram',
  'alprazolam',
  'lorazepam',
  'diazepam',
  'adderall',
  'ritalin',
  'gabapentin',
  'lisinopril',
  'losartan',
  'amlodipine',
  'metoprolol',
  'atorvastatin',
  'simvastatin',
  'warfarin',
  'clopidogrel',
  'metformin',
  'glipizide',
  'albuterol',
  'fluticasone',
  'montelukast',
  'levothyroxine',
  'prednisone',
  'estradiol',
  'testosterone',
  'omeprazole',
  'pantoprazole',
  'ondansetron',
  'tamsulosin',
  'sildenafil',
  'zolpidem',
  'cyclobenzaprine',
  'hydroxyzine',
  'allopurinol',
};

/// Additional score for a candidate *name* line when it matches the lexicon.
/// Phrase match (strong) > single-token match.
class MedicationNameLexicon {
  MedicationNameLexicon._();

  static const double phraseBoost = 9.0;
  static const double tokenBoost = 7.0;

  static double nameLineBoost(String rawLine) {
    final norm = _normalizeForMatch(rawLine);
    if (norm.isEmpty) return 0;

    for (final phrase in kMedicationNamePhrases) {
      if (norm.contains(phrase)) return phraseBoost;
    }

    for (final word in norm.split(' ')) {
      if (word.length < 4) continue;
      final w = word.replaceAll(RegExp(r'[^a-z]'), '');
      if (w.length < 4) continue;
      if (kMedicationNameTokens.contains(w)) return tokenBoost;
    }
    return 0;
  }
}
