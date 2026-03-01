// services/equipment_inspection_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/equipment_inspection_model.dart';
import '../models/equipment_model.dart';
import 'equipment_service.dart';
import 'equipment_history_service.dart';
import 'permission_service.dart';

class EquipmentInspectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EquipmentService _equipmentService = EquipmentService();
  final EquipmentHistoryService _historyService = EquipmentHistoryService();
  final PermissionService _permissionService = PermissionService();

  // ── Schreib-Methoden ──────────────────────────────────────────────────────

  /// Neue Prüfung speichern + Equipment-Status, Prüfdatum, Waschzyklen
  /// und History aktualisieren.
  Future<DocumentReference> addInspection(
      EquipmentInspectionModel inspection) async {
    if (_auth.currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    // 1. Aktuellen Equipment-Zustand lesen (für Waschzyklus- und History-Logik)
    final equipmentDoc = await _firestore
        .collection('equipment')
        .doc(inspection.equipmentId)
        .get();
    final currentStatus =
        (equipmentDoc.data()?['status'] as String?) ?? '';
    final currentWashCycles =
        (equipmentDoc.data()?['washCycles'] as int?) ?? 0;

    // 2. Prüfung speichern
    final docRef = await _firestore
        .collection('equipment_inspections')
        .add(inspection.toMap());

    // 3. Prüfdatum setzen
    await _equipmentService.updateCheckDate(
        inspection.equipmentId, inspection.nextInspectionDate);

    // 4. Status setzen
    final newStatus = _statusFromResult(inspection.result);
    await _equipmentService.updateStatus(inspection.equipmentId, newStatus);

    // 5. Waschzyklen hochzählen wenn Kleidungsstück aus Reinigung kam
    final fromCleaning = currentStatus == EquipmentStatus.cleaning;
    if (fromCleaning) {
      await _equipmentService.updateWashCycles(
          inspection.equipmentId, currentWashCycles + 1);
    }

    // 6. History-Einträge schreiben (best-effort, Fehler nicht weiterwerfen)
    try {
      await _historyService.recordFieldUpdate(
        equipmentId: inspection.equipmentId,
        field: 'Prüfung',
        oldValue: null,
        newValue: 'Prüfung durchgeführt — ${_resultText(inspection.result)}',
      );
      if (fromCleaning) {
        await _historyService.recordFieldUpdate(
          equipmentId: inspection.equipmentId,
          field: 'Waschzyklen',
          oldValue: currentWashCycles,
          newValue: currentWashCycles + 1,
        );
      }
    } catch (e) {
      print('History-Fehler (nicht kritisch): $e');
    }

    return docRef;
  }

  /// Bestehende Prüfung aktualisieren + Equipment-Status, Prüfdatum
  /// und History synchron halten.
  Future<void> updateInspection(EquipmentInspectionModel inspection) async {
    if (_auth.currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    // Alten Status für History lesen
    final equipmentDoc = await _firestore
        .collection('equipment')
        .doc(inspection.equipmentId)
        .get();
    final oldStatus = (equipmentDoc.data()?['status'] as String?) ?? '';

    // 1. Prüfungsdokument aktualisieren
    await _firestore
        .collection('equipment_inspections')
        .doc(inspection.id)
        .update(inspection.toMap());

    // 2. Prüfdatum aktualisieren
    await _equipmentService.updateCheckDate(
        inspection.equipmentId, inspection.nextInspectionDate);

    // 3. Status aktualisieren
    final newStatus = _statusFromResult(inspection.result);
    await _equipmentService.updateStatus(inspection.equipmentId, newStatus);

    // 4. History-Einträge schreiben (best-effort)
    try {
      await _historyService.recordFieldUpdate(
        equipmentId: inspection.equipmentId,
        field: 'Prüfung',
        oldValue: null,
        newValue: 'Prüfung bearbeitet — ${_resultText(inspection.result)}',
      );
    } catch (e) {
      print('History-Fehler (nicht kritisch): $e');
    }
  }

  /// Prüfung löschen.
  /// Equipment-Status wird nicht zurückgesetzt — muss manuell geprüft werden.
  Future<void> deleteInspection(String inspectionId) async {
    await _firestore
        .collection('equipment_inspections')
        .doc(inspectionId)
        .delete();
  }

  // ── Lese-Methoden ─────────────────────────────────────────────────────────

  Stream<List<EquipmentInspectionModel>> getInspectionsForEquipment(
      String equipmentId) {
    return _firestore
        .collection('equipment_inspections')
        .where('equipmentId', isEqualTo: equipmentId)
        .orderBy('inspectionDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentInspectionModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  Stream<List<EquipmentInspectionModel>> getAllInspections() {
    return _firestore
        .collection('equipment_inspections')
        .orderBy('inspectionDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentInspectionModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  Stream<List<EquipmentInspectionModel>> getUpcomingInspections() {
    final now = DateTime.now();
    final threeMonthsFromNow = now.add(const Duration(days: 90));

    return _firestore
        .collection('equipment_inspections')
        .where('nextInspectionDate', isGreaterThanOrEqualTo: now)
        .where('nextInspectionDate', isLessThanOrEqualTo: threeMonthsFromNow)
        .orderBy('nextInspectionDate')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentInspectionModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  String _statusFromResult(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return EquipmentStatus.ready;
      case InspectionResult.conditionalPass:
        return EquipmentStatus.ready;
      case InspectionResult.failed:
        return EquipmentStatus.repair;
    }
  }

  String _resultText(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return 'Bestanden';
      case InspectionResult.conditionalPass:
        return 'Bedingt bestanden';
      case InspectionResult.failed:
        return 'Durchgefallen';
    }
  }
}
