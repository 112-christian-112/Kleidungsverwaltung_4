// data/inspection_checklist_data.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// VIKING-PRÜFLISTE – EINSATZKLEIDUNG
// ═══════════════════════════════════════════════════════════════════════════
//
// Diese Datei enthält ausschließlich die Prüfpunkt-Definitionen.
// Die Prüflogik und UI befinden sich in equipment_inspection_form_screen.dart.
//
// ── Felder pro Prüfpunkt ────────────────────────────────────────────────────
//
//   id          Eindeutige ID — darf nach Erstanlage NIE geändert werden,
//               da bestehende Prüfungen in Firestore darauf referenzieren.
//
//   label       Anzeigetext im Formular (darf angepasst werden).
//
//   isCritical  true  → k.o.-Kriterium: ein einziges NIO führt sofort zu
//                        "Nicht bestanden", unabhängig von anderen Punkten.
//               false → Beobachtungspunkt: bis zu 2 NIO → "Bedingt bestanden"
//
//   checkType   CheckType.visual    → Sichtprüfung (kein Werkzeug nötig)
//               CheckType.function  → Funktionsprüfung (aktive Handlung)
//               CheckType.document  → Dokumentenprüfung (Etiketten, Papiere)
//
// ── Neue Prüfpunkte hinzufügen ──────────────────────────────────────────────
//
//   1. Neue CheckItemDef am Ende der passenden Kategorie einfügen.
//   2. id nach Schema wählen, z.B. 'ober_5' für fünften Oberstoff-Punkt.
//   3. isCritical und checkType sorgfältig setzen.
//
// ── Kategorien hinzufügen ───────────────────────────────────────────────────
//
//   Neue CheckCategoryDef am Ende der Liste in buildChecklist() einfügen.
//
// ═══════════════════════════════════════════════════════════════════════════

// ─── Typen (werden auch im Form-Screen verwendet) ─────────────────────────────

enum CheckType {
  visual,   // Sichtprüfung
  function, // Funktionsprüfung
  document, // Dokumentenprüfung
}

// ─── Unveränderliche Definitionen ─────────────────────────────────────────────

class CheckItemDef {
  final String id;
  final String label;
  final bool isCritical;
  final CheckType checkType;

  const CheckItemDef({
    required this.id,
    required this.label,
    this.isCritical = false,
    this.checkType = CheckType.visual,
  });
}

class CheckCategoryDef {
  final String title;
  final List<CheckItemDef> items;

  const CheckCategoryDef({
    required this.title,
    required this.items,
  });
}

// ─── Checkliste ───────────────────────────────────────────────────────────────

List<CheckCategoryDef> buildChecklist() {
  return const [

    // ── 1. Kennzeichnung ────────────────────────────────────────────────────
    CheckCategoryDef(title: 'Kennzeichnung', items: [
      CheckItemDef(
        id: 'kenn_1',
        label: 'Kennzeichnung (z.B. DIN EN 469 / Prüfnummer) lesbar?',
        isCritical: true,
        checkType: CheckType.document,
      ),
      CheckItemDef(
        id: 'kenn_2',
        label: 'Pflegeanleitung lesbar?',
        isCritical: true,
        checkType: CheckType.document,
      ),
      CheckItemDef(
        id: 'kenn_3',
        label: 'Herstellerinformationen vorhanden & vollständig?',
        checkType: CheckType.document,
      ),
    ]),

    // ── 2. Oberstoff ────────────────────────────────────────────────────────
    CheckCategoryDef(title: 'Oberstoff', items: [
      CheckItemDef(
        id: 'ober_1',
        label: 'Keine Löcher vorhanden',
        isCritical: true,
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'ober_2',
        label: 'Keine sicherheitsrelevanten Verschmutzungen',
        isCritical: true,
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'ober_3',
        label: 'Keine thermischen Schädigungen / Kräuselungen',
        isCritical: true,
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'ober_4',
        label: 'Laminat: Keine Ablösung Oberstoff – Laminat',
        checkType: CheckType.visual,
      ),
    ]),

    // ── 3. Nahtverbindungen ─────────────────────────────────────────────────
    CheckCategoryDef(title: 'Nahtverbindungen', items: [
      CheckItemDef(
        id: 'naht_1',
        label: 'Nähte unbeschädigt',
        isCritical: true,
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'naht_2',
        label: 'Abklebungen vollständig',
        checkType: CheckType.visual,
      ),
    ]),

    // ── 4. Isolationsfutter ─────────────────────────────────────────────────
    CheckCategoryDef(title: 'Isolationsfutter', items: [
      CheckItemDef(
        id: 'iso_1',
        label: 'Keine Beschädigung sichtbar',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'iso_2',
        label: 'Reißverschluss: Leichtgängig & unbeschädigt',
        isCritical: true,
        checkType: CheckType.function,
      ),
    ]),

    // ── 5. Innenfutter ──────────────────────────────────────────────────────
    CheckCategoryDef(title: 'Innenfutter', items: [
      CheckItemDef(
        id: 'inn_1',
        label: 'Keine Löcher vorhanden',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'inn_2',
        label: 'Keine sicherheitsrelevanten Verschmutzungen',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'inn_3',
        label: 'Keine thermischen Schädigungen / Kräuselungen',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'inn_4',
        label: 'Nähte unbeschädigt',
        checkType: CheckType.visual,
      ),
    ]),

    // ── 6. Reißverschluss ───────────────────────────────────────────────────
    CheckCategoryDef(title: 'Reißverschluss', items: [
      CheckItemDef(
        id: 'reiss_1',
        label: 'Vollständige Schließung möglich',
        isCritical: true,
        checkType: CheckType.function,
      ),
      CheckItemDef(
        id: 'reiss_2',
        label: 'Keine Beschädigung',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'reiss_3',
        label: 'Leichtgängig',
        checkType: CheckType.function,
      ),
    ]),

    // ── 7. Taschen / Überlappungen ──────────────────────────────────────────
    CheckCategoryDef(title: 'Taschen / Überlappungen', items: [
      CheckItemDef(
        id: 'tasch_1',
        label: 'Taschenpatten überdecken vollständig',
        isCritical: true,
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'tasch_2',
        label: 'Knöpfe / Klett vollständig & sauber',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'tasch_3',
        label: 'Klettverschluss schließt korrekt',
        checkType: CheckType.function,
      ),
    ]),

    // ── 8. Aufhänger ────────────────────────────────────────────────────────
    CheckCategoryDef(title: 'Aufhänger', items: [
      CheckItemDef(
        id: 'aufh_1',
        label: 'Vorhanden & unbeschädigt',
        checkType: CheckType.visual,
      ),
    ]),

    // ── 9. Karabiner ────────────────────────────────────────────────────────
    CheckCategoryDef(title: 'Karabiner', items: [
      CheckItemDef(
        id: 'kara_1',
        label: 'Vorhanden & unbeschädigt',
        checkType: CheckType.visual,
      ),
    ]),

    // ── 10. Klettverschlüsse ────────────────────────────────────────────────
    CheckCategoryDef(title: 'Klettverschlüsse', items: [
      CheckItemDef(
        id: 'klett_1',
        label: 'Keine Beschädigung / Verschmutzung',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'klett_2',
        label: 'Schließt sachgerecht',
        checkType: CheckType.function,
      ),
    ]),

    // ── 11. Reflexstreifen ──────────────────────────────────────────────────
    CheckCategoryDef(title: 'Reflexstreifen', items: [
      CheckItemDef(
        id: 'reflex_1',
        label: 'Nahtverbindungen fest, kein Ablösen',
        isCritical: true,
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'reflex_2',
        label: 'Keine Beschädigung / Verschmutzung',
        checkType: CheckType.visual,
      ),
      CheckItemDef(
        id: 'reflex_3',
        label: 'Reflektionswirkung vorhanden (Lampentest)',
        isCritical: true,
        checkType: CheckType.function,
      ),
    ]),

  ];
}
