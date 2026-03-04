// lib/data/changelog.dart
//
// ─── CHANGELOG PFLEGEN ───────────────────────────────────────────────────────
// Neue Version einfach OBEN in die Liste einfügen.
// Typen: 'new' (grün), 'fix' (orange), 'improvement' (blau), 'breaking' (rot)
// ─────────────────────────────────────────────────────────────────────────────

class ChangelogEntry {
  final String version;
  final String date;
  final List<ChangelogItem> changes;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

class ChangelogItem {
  final String type; // 'new' | 'fix' | 'improvement' | 'breaking'
  final String text;

  const ChangelogItem({required this.type, required this.text});
}

// ─────────────────────────────────────────────────────────────────────────────
// CHANGELOG — neueste Version zuerst
// ─────────────────────────────────────────────────────────────────────────────

const List<ChangelogEntry> changelog = [

  ChangelogEntry(
    version: '1.3.0',
    date: '02.03.2026',
    changes: [
      ChangelogItem(type: 'new',         text: 'VIKING Prüfcheckliste mit 26 strukturierten Prüfpunkten'),
      ChangelogItem(type: 'new',         text: 'NIO-Kommentarfeld pro Prüfpunkt'),
      ChangelogItem(type: 'new',         text: '„Alle IO"-Schnellbutton pro Kategorie'),
      ChangelogItem(type: 'new',         text: 'Letzte Prüfung mit Mängeln im Prüfformular sichtbar'),
      ChangelogItem(type: 'improvement', text: 'Speichern der Prüfung jetzt Android-kompatibel (Batch-Write)'),
      ChangelogItem(type: 'fix',         text: 'Bearbeiten bestehender Prüfungen lädt Mängel korrekt'),
      ChangelogItem(type: 'fix',         text: 'Designanpassungen Overflow Fehler behoben'),
      ChangelogItem(type: 'new',         text: 'Rechteverwaltung umgebaut und optimiert, Rechtemenü hinzugefügt'),
    ],
  ),

  ChangelogEntry(
    version: '1.2.0',
    date: '10.06.2026',
    changes: [
      ChangelogItem(type: 'new',         text: 'NFC-Scan zum Identifizieren der Einsatzkleidung'),
      ChangelogItem(type: 'new',         text: 'Einsatzdokumentation mit Kleidungszuordnung'),
      ChangelogItem(type: 'improvement', text: 'Prüfhistorie in der Detailansicht'),
      ChangelogItem(type: 'fix',         text: 'Waschzyklen werden korrekt hochgezählt'),
    ],
  ),

  ChangelogEntry(
    version: '1.1.0',
    date: '15.05.2026',
    changes: [
      ChangelogItem(type: 'new',         text: 'Benutzerverwaltung mit Rollensystem'),
      ChangelogItem(type: 'new',         text: 'Feuerwehr-übergreifende Sichtbarkeitsrechte'),
      ChangelogItem(type: 'improvement', text: 'Dark Mode Unterstützung'),
      ChangelogItem(type: 'fix',         text: 'Login-Fehler bei langen Passwörtern behoben'),
    ],
  ),

  ChangelogEntry(
    version: '1.0.0',
    date: '01.04.2025',
    changes: [
      ChangelogItem(type: 'new', text: 'Erste Version der App'),
      ChangelogItem(type: 'new', text: 'Grundlegende Einsatzkleidungsverwaltung'),
      ChangelogItem(type: 'new', text: 'Firebase-Integration'),
    ],
  ),

];
