// lib/Lists/equipment_data.dart
//
// Zentrale Verwaltung aller Artikel und Größen.
// Analog zu fire_stations.dart — nur hier pflegen, nicht in Screens.

class EquipmentData {
  EquipmentData._();

  // ── Artikel ───────────────────────────────────────────────────────────────

  static const List<Map<String, String>> articles = [
    // Viking
    {'name': 'Viking Performer Evolution Einsatzjacke AGT', 'type': 'Jacke'},
    {'name': 'Viking Performer Evolution Einsatzhose AGT',  'type': 'Hose'},
    {'name': 'Viking Einsatzjacke TH Assistance',           'type': 'Jacke'},
    {'name': 'Viking Einsatzhose TH Assistance',            'type': 'Hose'},
    // HuPF
    {'name': 'HuPF Teil 1 Einsatzjacke',                    'type': 'Jacke'},
    {'name': 'HuPF Teil 2 Einsatzhose',                     'type': 'Hose'},
    // Rosenbauer
    {'name': 'Rosenbauer Einsatzjacke FLASH',               'type': 'Jacke'},
    {'name': 'Rosenbauer Einsatzhose FLASH',                'type': 'Hose'},
    // Dräger / Sonstiges — bei Bedarf ergänzen
  ];

  /// Alle Artikel-Namen als einfache Liste
  static List<String> get allArticleNames =>
      articles.map((a) => a['name']!).toList();

  /// Typ (Jacke/Hose) für einen Artikel-Namen ermitteln
  static String typeForArticle(String articleName) {
    return articles.firstWhere(
      (a) => a['name'] == articleName,
      orElse: () => {'type': 'Jacke'},
    )['type']!;
  }

  /// Artikel nach Typ filtern
  static List<Map<String, String>> byType(String type) =>
      articles.where((a) => a['type'] == type).toList();

  /// Suche (case-insensitive, Name oder Typ)
  static List<Map<String, String>> search(String query) {
    if (query.isEmpty) return articles;
    final q = query.toLowerCase();
    return articles
        .where((a) =>
            a['name']!.toLowerCase().contains(q) ||
            a['type']!.toLowerCase().contains(q))
        .toList();
  }

  // ── Größen ────────────────────────────────────────────────────────────────
  //
  // Format: "<Zahlenbereich>" + optional " <Zusatz>"
  // Zahlenbereich: immer "XX/YY" (z.B. 46/48)
  // Zusatz:        K (Kurz), L (Lang), LL (Extra Lang), S (Schmal) etc.
  //
  // Neue Größen einfach in die Liste eintragen.

  static const List<String> _baseRanges = [
    '42/44',
    '46/48',
    '50/52',
    '54/56',
    '58/60',
    '62/64',
    '66/68',
    '70/72',
    '74/76',
  ];

  static const List<String> _suffixes = [
    '',    // Standard (kein Zusatz)
    'K',   // Kurz
    'L',   // Lang
    'LL',  // Extra Lang
    'S',   // Schmal
  ];

  /// Alle Größen als fertige Strings, z.B. ["42/44", "42/44 K", "42/44 L", ...]
  static List<String> get allSizes {
    final result = <String>[];
    for (final base in _baseRanges) {
      for (final suffix in _suffixes) {
        result.add(suffix.isEmpty ? base : '$base $suffix');
      }
    }
    return result;
  }

  /// Nur Basis-Bereiche (ohne Zusätze), z.B. für eine erste Auswahl
  static List<String> get baseRanges => List.from(_baseRanges);

  /// Alle verfügbaren Zusätze
  static List<String> get suffixes => List.from(_suffixes);

  /// Größen-Suche
  static List<String> searchSizes(String query) {
    if (query.isEmpty) return allSizes;
    final q = query.toLowerCase();
    return allSizes.where((s) => s.toLowerCase().contains(q)).toList();
  }

  /// Validierung: Ist eine Größe gültig (bekannt oder freies Format)?
  /// Gibt null zurück wenn ok, sonst Fehlermeldung.
  static String? validateSize(String? value) {
    if (value == null || value.trim().isEmpty) return 'Größe angeben';
    // Freie Eingabe erlauben — nur auf Mindestlänge prüfen
    if (value.trim().length < 3) return 'Ungültige Größe';
    return null;
  }
}
