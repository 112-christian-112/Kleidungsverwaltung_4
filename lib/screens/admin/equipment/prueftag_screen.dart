// screens/admin/equipment/prueftag_screen.dart
//
// Dedizierter Screen für den Prüftag-Workflow.
// Zeigt dauerhaft die Liste bereits geprüfter Kleidungsstücke dieser Session.
// NFC-Scan läuft als BottomSheet — der Screen bleibt immer sichtbar.
//
// Einstieg: von EquipmentScanScreen per Navigator.push starten.
// Verlassen: Zurück-Button → Abschluss-Dialog mit Zusammenfassung.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../services/equipment_service.dart';
import 'equipment_inspection_form_screen.dart';
import '../../../widgets/nfc_scan_sheet.dart';

// ─── Datenklasse für einen Prüftag-Eintrag ────────────────────────────────────

class _PrueftagEintrag {
  final EquipmentModel equipment;
  final InspectionResult result;
  final DateTime zeitpunkt;

  _PrueftagEintrag({
    required this.equipment,
    required this.result,
    required this.zeitpunkt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRUEFTAG SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class PrueftagScreen extends StatefulWidget {
  const PrueftagScreen({Key? key}) : super(key: key);

  @override
  State<PrueftagScreen> createState() => _PrueftagScreenState();
}

class _PrueftagScreenState extends State<PrueftagScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final ScrollController _scrollController = ScrollController();

  // Session-Daten
  final List<_PrueftagEintrag> _geprueft = [];
  bool _sessionLaeuft = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    // Ersten Scan automatisch starten
    WidgetsBinding.instance.addPostFrameCallback((_) => _naechstenScanStarten());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (_geprueft.isEmpty) return true;
    return await _zeigeAbschlussDialog() ?? false;
  }

  Future<bool?> _zeigeAbschlussDialog() {
    final bestanden = _geprueft
        .where((e) => e.result == InspectionResult.passed)
        .length;
    final bedingt = _geprueft
        .where((e) => e.result == InspectionResult.conditionalPass)
        .length;
    final nichtBestanden = _geprueft
        .where((e) => e.result == InspectionResult.failed)
        .length;

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.assignment_turned_in,
            color: Colors.green, size: 48),
        title: const Text('Prüftag beenden?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_geprueft.length} Kleidungsstücke wurden geprüft.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            _StatZeile(
              icon: Icons.check_circle,
              farbe: Colors.green,
              label: 'Bestanden',
              wert: bestanden,
            ),
            if (bedingt > 0)
              _StatZeile(
                icon: Icons.warning,
                farbe: Colors.orange,
                label: 'Bedingt bestanden',
                wert: bedingt,
              ),
            if (nichtBestanden > 0)
              _StatZeile(
                icon: Icons.cancel,
                farbe: Colors.red,
                label: 'Nicht bestanden',
                wert: nichtBestanden,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Weitermachen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Prüftag abschließen',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Scan-Loop ──────────────────────────────────────────────────────────────

  void _naechstenScanStarten() {
    if (!mounted) return;
    setState(() {
      _fehler = null;
      _sessionLaeuft = true;
    });
    _zeigeNfcSheet();
  }

  Future<void> _zeigeNfcSheet() async {
    if (!mounted) return;

    final gescannteId = await NfcScanSheet.zeigen(
      context,
      hinweisText: _geprueft.isEmpty
          ? 'Ersten NFC-Tag scannen'
          : 'Nächsten NFC-Tag scannen',
    );

    if (!mounted) return;

    if (gescannteId == null || gescannteId!.isEmpty) {
      // Sheet manuell geschlossen → Session pausiert, kein automatischer Neustart
      setState(() => _sessionLaeuft = false);
      return;
    }

    // Equipment per NFC-ID suchen
    await _verarbeiteTag(gescannteId!);
  }

  Future<void> _verarbeiteTag(String nfcId) async {
    setState(() => _fehler = null);

    EquipmentModel? equipment;
    try {
      equipment = await _equipmentService.getEquipmentByNfcTag(nfcId);
    } catch (e) {
      setState(() {
        _fehler = 'Fehler beim Suchen: $e';
        _sessionLaeuft = false;
      });
      return;
    }

    if (!mounted) return;

    if (equipment == null) {
      setState(() {
        _fehler = 'Keine Einsatzkleidung mit diesem NFC-Tag gefunden.\n(Tag: $nfcId)';
        _sessionLaeuft = false;
      });
      // Nach kurzer Pause nächsten Scan anbieten
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _naechstenScanStarten();
      return;
    }

    // Prüfformular öffnen
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EquipmentInspectionFormScreen(equipment: equipment!),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      // Prüfung gespeichert → zur Liste hinzufügen
      HapticFeedback.lightImpact();

      // Ergebnis aus dem Formular rekonstruieren
      // (Das Formular gibt nur true/false zurück, nicht das Ergebnis selbst.
      // Wir lesen den aktualisierten Status des Equipments aus Firestore.)
      InspectionResult inspResult = InspectionResult.passed;
      try {
        final aktuell = await _equipmentService.getEquipmentByIdFuture(equipment.id);
        if (aktuell != null) {
          if (aktuell.status == EquipmentStatus.repair) {
            inspResult = InspectionResult.failed;
          }
        }
      } catch (_) {}

      setState(() {
        _geprueft.add(_PrueftagEintrag(
          equipment: equipment!,
          result: inspResult,
          zeitpunkt: DateTime.now(),
        ));
        _sessionLaeuft = true;
      });

      // Liste ans Ende scrollen damit neue Einträge sichtbar sind
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });

      // Sofort nächsten Scan starten
      _naechstenScanStarten();
    } else {
      // Formular abgebrochen → nächsten Scan anbieten
      setState(() => _sessionLaeuft = false);
      if (mounted) _naechstenScanStarten();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              const Icon(Icons.playlist_add_check, size: 20),
              const SizedBox(width: 8),
              const Text('Prüftag'),
            ],
          ),
          actions: [
            // Zähler
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_geprueft.length} geprüft',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            // Prüftag beenden
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Prüftag beenden',
              onPressed: () async {
                final beenden = await _zeigeAbschlussDialog();
                if (beenden == true && mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            // ── Fehler-Banner ──────────────────────────────────────────
            if (_fehler != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_fehler!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13)),
                    ),
                  ],
                ),
              ),

            // ── Hauptinhalt ────────────────────────────────────────────
            Expanded(
              child: _geprueft.isEmpty
                  ? _buildLeerZustand()
                  : _buildListe(),
            ),

            // ── Bottom-Bar: Nächsten Scan starten ─────────────────────
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildLeerZustand() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.nfc, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Noch keine Prüfungen',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade500,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Halte das Gerät an den NFC-Tag\nder ersten Einsatzkleidung.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildListe() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _geprueft.length,
      itemBuilder: (ctx, i) {
        final eintrag = _geprueft[i];
        final isLast = i == _geprueft.length - 1;
        return _PrueftagListTile(
          eintrag: eintrag,
          laufendeNummer: i + 1,
          isLast: isLast,
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sessionLaeuft ? null : _naechstenScanStarten,
            icon: const Icon(Icons.nfc),
            label: Text(
              _sessionLaeuft
                  ? 'Scan läuft...'
                  : _geprueft.isEmpty
                      ? 'Ersten NFC-Tag scannen'
                      : 'Nächsten NFC-Tag scannen',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIST TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _PrueftagListTile extends StatelessWidget {
  final _PrueftagEintrag eintrag;
  final int laufendeNummer;
  final bool isLast;

  const _PrueftagListTile({
    required this.eintrag,
    required this.laufendeNummer,
    required this.isLast,
  });

  Color get _resultFarbe {
    switch (eintrag.result) {
      case InspectionResult.passed:
        return Colors.green;
      case InspectionResult.conditionalPass:
        return Colors.orange;
      case InspectionResult.failed:
        return Colors.red;
    }
  }

  IconData get _resultIcon {
    switch (eintrag.result) {
      case InspectionResult.passed:
        return Icons.check_circle;
      case InspectionResult.conditionalPass:
        return Icons.warning;
      case InspectionResult.failed:
        return Icons.cancel;
    }
  }

  String get _resultText {
    switch (eintrag.result) {
      case InspectionResult.passed:
        return 'Bestanden';
      case InspectionResult.conditionalPass:
        return 'Bedingt bestanden';
      case InspectionResult.failed:
        return 'Nicht bestanden';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isLast
            ? _resultFarbe.withOpacity(0.08)
            : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: isLast
            ? Border.all(color: _resultFarbe.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Laufende Nummer
            SizedBox(
              width: 28,
              child: Text(
                '$laufendeNummer.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                  fontSize: 13,
                ),
              ),
            ),

            // Typ-Icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: eintrag.equipment.type == 'Jacke'
                    ? Colors.blue.shade50
                    : Colors.orange.shade50,
              ),
              child: Icon(
                eintrag.equipment.type == 'Jacke'
                    ? Icons.accessibility_new
                    : Icons.airline_seat_legroom_normal,
                size: 20,
                color: eintrag.equipment.type == 'Jacke'
                    ? Colors.blue
                    : Colors.orange,
              ),
            ),

            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eintrag.equipment.owner,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${eintrag.equipment.article} · Gr. ${eintrag.equipment.size}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Ergebnis-Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(_resultIcon, color: _resultFarbe, size: 22),
                const SizedBox(height: 2),
                Text(
                  _resultText,
                  style: TextStyle(
                      fontSize: 11,
                      color: _resultFarbe,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NFC BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════════════════════════
// HILFS-WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class _StatZeile extends StatelessWidget {
  final IconData icon;
  final Color farbe;
  final String label;
  final int wert;

  const _StatZeile({
    required this.icon,
    required this.farbe,
    required this.label,
    required this.wert,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: farbe, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            '$wert',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: farbe, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
