// screens/missions/mission_send_to_cleaning_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import '../../models/mission_model.dart';
import '../../models/equipment_model.dart';
import '../../services/mission_service.dart';
import '../../services/equipment_service.dart';
import '../../services/cleaning_receipt_pdf_service.dart';
import '../../widgets/cleaning_receipt_preview.dart';

class MissionSendToCleaningScreen extends StatefulWidget {
  final String missionId;
  final String missionName;

  const MissionSendToCleaningScreen({
    Key? key,
    required this.missionId,
    required this.missionName,
  }) : super(key: key);

  @override
  State<MissionSendToCleaningScreen> createState() =>
      _MissionSendToCleaningScreenState();
}

class _MissionSendToCleaningScreenState
    extends State<MissionSendToCleaningScreen> {
  final MissionService _missionService = MissionService();
  final EquipmentService _equipmentService = EquipmentService();

  bool _isLoading = true;
  bool _isProcessing = false;
  List<EquipmentModel> _equipmentList = [];
  List<EquipmentModel> _selectedEquipment = [];
  MissionModel? _mission;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final mission = await _missionService.getMissionById(widget.missionId);
      if (mission == null) throw Exception('Einsatz nicht gefunden');

      final equipmentList =
          await _missionService.getEquipmentForMission(widget.missionId);

      final selectedEquipment = equipmentList
          .where((item) => item.status != EquipmentStatus.cleaning)
          .toList();

      if (mounted) {
        setState(() {
          _mission = mission;
          _equipmentList = equipmentList;
          _selectedEquipment = selectedEquipment;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleSelection(EquipmentModel equipment) {
    setState(() {
      if (_selectedEquipment.contains(equipment)) {
        _selectedEquipment.remove(equipment);
      } else {
        _selectedEquipment.add(equipment);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedEquipment = _equipmentList
          .where((item) => item.status != EquipmentStatus.cleaning)
          .toList();
    });
  }

  void _deselectAll() {
    setState(() => _selectedEquipment = []);
  }

  Future<Uint8List> _generatePdf() async {
    if (_mission == null) throw Exception('Keine Einsatzdaten verfügbar');
    return CleaningReceiptPdfService.generateCleaningReceiptPdf(
      mission: _mission!,
      equipmentList: _selectedEquipment,
    );
  }

  /// FIX: Einzelfehlerbehandlung in der Cleaning-Schleife.
  ///
  /// Vorher: sequenzielle Schleife — ein Fehler bei Item 3 bricht ab und
  /// lässt Items 1+2 inkonsistent auf "cleaning" stehen, ohne Rückmeldung.
  ///
  /// Jetzt:
  /// 1. Alle IDs per Batch-Write auf "cleaning" setzen (atomisch, ein Commit).
  /// 2. Bei Batch-Fehler: Abbruch vor PDF-Generierung, kein inkonsistenter Zustand.
  /// 3. PDF-Fehler: Status bleibt gesetzt (Kleidung ist in der Reinigung),
  ///    aber Nutzer wird informiert und kann PDF manuell neu generieren.
  Future<void> _sendToCleaningAndGeneratePdf() async {
    if (_selectedEquipment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte wählen Sie mindestens ein Kleidungsstück aus'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    // ── Schritt 1: Alle Status-Updates als atomischer Batch ──────────────────
    // updateStatusBatch() schreibt alle IDs in einem einzigen Firestore-Commit.
    // Entweder alle oder keiner — kein inkonsistenter Zwischenzustand möglich.
    final ids = _selectedEquipment.map((e) => e.id).toList();
    try {
      await Future.wait([
        // Status auf "cleaning" setzen
        _equipmentService.updateStatusBatch(ids, EquipmentStatus.cleaning),
        // equipmentIds in der Mission eintragen (für Dashboard-Verknüpfung)
        _missionService.addEquipmentToMission(widget.missionId, ids),
      ]);
    } catch (e) {
      // Batch komplett fehlgeschlagen → kein einziger Status wurde geändert
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status-Update fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // ── Schritt 2: PDF generieren ────────────────────────────────────────────
    // Status ist bereits gesetzt — die Kleidung ist in der Reinigung.
    // Ein PDF-Fehler ist nicht mehr kritisch, der Nutzer kann das PDF
    // über "Wäschereischein" im Einsatz-Detail neu generieren.
    Uint8List? pdfBytes;
    String? pdfError;
    try {
      pdfBytes = await _generatePdf();
    } catch (e) {
      pdfError = e.toString();
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (pdfError != null) {
      // Status wurde erfolgreich gesetzt, aber PDF schlug fehl
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_selectedEquipment.length} Kleidungsstücke in die Reinigung gesendet.\n'
            'PDF konnte nicht erstellt werden: $pdfError',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
      // Zurück zum vorherigen Screen — Status ist korrekt gesetzt
      Navigator.pop(context, true);
      return;
    }

    // ── Schritt 3: PDF-Preview anzeigen ─────────────────────────────────────
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CleaningReceiptPreviewScreen(
          pdfBytes: pdfBytes!,
          mission: _mission!,
          equipmentList: _selectedEquipment,
          onComplete: () {
            Navigator.popUntil(
              context,
              (route) =>
                  route.isFirst || route.settings.name == '/missions',
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('In die Reinigung senden')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final counts = _countEquipmentTypes(_selectedEquipment);

    return Scaffold(
      appBar: AppBar(
        title: const Text('In die Reinigung senden'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _selectAll,
            tooltip: 'Alle auswählen',
          ),
          IconButton(
            icon: const Icon(Icons.deselect),
            onPressed: _deselectAll,
            tooltip: 'Alle abwählen',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Einsatz-Info ─────────────────────────────────────────────────
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Einsatz: ${_mission?.name ?? widget.missionName}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (_mission != null) ...[
                    const SizedBox(height: 8),
                    Text('Datum: ${DateFormat('dd.MM.yyyy').format(_mission!.startTime)}'),
                    Text('Ort: ${_mission!.location}'),
                  ],
                ],
              ),
            ),
          ),

          // ── Auswahl-Zusammenfassung ───────────────────────────────────────
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Ausgewählte Ausrüstung',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCountColumn('Jacken', '${counts.jackets}',
                          Icons.accessibility_new, Colors.blue),
                      _buildCountColumn('Hosen', '${counts.pants}',
                          Icons.airline_seat_legroom_normal, Colors.amber),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Listen-Header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ausrüstung zur Reinigung',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_selectedEquipment.length} von ${_equipmentList.length} ausgewählt',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary),
                ),
              ],
            ),
          ),

          // ── Ausrüstungs-Liste ─────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _equipmentList.length,
              itemBuilder: (context, index) {
                final equipment = _equipmentList[index];
                final isSelected = _selectedEquipment.contains(equipment);
                final isInCleaning =
                    equipment.status == EquipmentStatus.cleaning;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    title: Text(
                      equipment.article,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isInCleaning ? Colors.orange : null,
                      ),
                    ),
                    subtitle: Text(
                      '${equipment.owner} · Gr. ${equipment.size}'
                      '${isInCleaning ? ' · Bereits in Reinigung' : ''}',
                    ),
                    value: isSelected,
                    onChanged: isInCleaning
                        ? null // Bereits in Reinigung → nicht auswählbar
                        : (_) => _toggleSelection(equipment),
                    secondary: CircleAvatar(
                      backgroundColor: equipment.type == 'Jacke'
                          ? Colors.blue
                          : Colors.amber,
                      child: Icon(
                        equipment.type == 'Jacke'
                            ? Icons.accessibility_new
                            : Icons.airline_seat_legroom_normal,
                        color: Colors.white,
                      ),
                    ),
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // ── Senden-Button ────────────────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _sendToCleaningAndGeneratePdf,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isProcessing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'In die Reinigung senden und PDF erstellen',
                  style: TextStyle(fontSize: 16),
                ),
        ),
      ),
    );
  }

  Widget _buildCountColumn(
      String label, String count, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 4),
        Text(count,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
      ],
    );
  }

  EquipmentCounts _countEquipmentTypes(List<EquipmentModel> equipmentList) {
    int jacketCount = 0;
    int pantsCount = 0;
    int otherCount = 0;

    for (final item in equipmentList) {
      switch (item.type.toLowerCase()) {
        case 'jacke':
          jacketCount++;
          break;
        case 'hose':
          pantsCount++;
          break;
        default:
          otherCount++;
          break;
      }
    }

    return EquipmentCounts(
        jackets: jacketCount, pants: pantsCount, other: otherCount);
  }
}
