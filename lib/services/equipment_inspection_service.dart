// services/equipment_inspection_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/equipment_inspection_model.dart';
import '../models/equipment_model.dart';
import 'equipment_history_service.dart';
import 'permission_service.dart';

class EquipmentInspectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EquipmentHistoryService _historyService = EquipmentHistoryService();
  final PermissionService _permissionService = PermissionService();

  // ── Schreib-Methoden ──────────────────────────────────────────────────────

  /// Neue Prüfung speichern + Equipment-Status und Prüfdatum in einem
  /// einzigen Batch-Write aktualisieren (Android-kompatibel).
  Future<DocumentReference> addInspection(
      EquipmentInspectionModel inspection) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    // 1. Einmalige Berechtigungs- und Zustandsprüfung
    final user = await _permissionService.getCurrentUser();
    if (user == null ||
        (!user.isAdmin && !user.permissions.inspectionPerform)) {
      throw Exception('Keine Berechtigung zum Durchführen von Prüfungen');
    }

    // 2. Aktuellen Equipment-Zustand lesen (einmalig)
    final equipmentRef =
        _firestore.collection('equipment').doc(inspection.equipmentId);
    final equipmentDoc = await equipmentRef.get();
    final currentStatus =
        (equipmentDoc.data()?['status'] as String?) ?? '';
    final currentWashCycles =
        (equipmentDoc.data()?['washCycles'] as int?) ?? 0;
    final fromCleaning = currentStatus == EquipmentStatus.cleaning;

    // 3. Prüfungs-Dokument anlegen (außerhalb Batch, da wir die Ref brauchen)
    final inspectionRef = await _firestore
        .collection('equipment_inspections')
        .add(inspection.toMap());

    // 4. Alle Equipment-Updates in einem einzigen Batch
    final newStatus = _statusFromResult(inspection.result);
    final batch = _firestore.batch();

    final equipmentUpdate = <String, dynamic>{
      'status': newStatus,
      'checkDate': Timestamp.fromDate(inspection.nextInspectionDate),
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    };

    // Waschzyklen nur hochzählen wenn aus Reinigung
    if (fromCleaning) {
      equipmentUpdate['washCycles'] = currentWashCycles + 1;
    }

    batch.update(equipmentRef, equipmentUpdate);
    await batch.commit();

    // 5. History best-effort (Fehler nicht weiterwerfen)
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

    return inspectionRef;
  }

  /// Bestehende Prüfung aktualisieren + Equipment-Status und Prüfdatum
  /// in einem einzigen Batch-Write synchron halten.
  Future<void> updateInspection(EquipmentInspectionModel inspection) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    final user = await _permissionService.getCurrentUser();
    if (user == null ||
        (!user.isAdmin && !user.permissions.inspectionPerform)) {
      throw Exception('Keine Berechtigung zum Bearbeiten von Prüfungen');
    }

    // Einmalig alten Status lesen
    final equipmentRef =
        _firestore.collection('equipment').doc(inspection.equipmentId);
    final equipmentDoc = await equipmentRef.get();
    final oldStatus = (equipmentDoc.data()?['status'] as String?) ?? '';

    // Batch: Prüfung + Equipment in einem Commit
    final newStatus = _statusFromResult(inspection.result);
    final batch = _firestore.batch();

    batch.update(
      _firestore.collection('equipment_inspections').doc(inspection.id),
      inspection.toMap(),
    );

    batch.update(equipmentRef, {
      'status': newStatus,
      'checkDate': Timestamp.fromDate(inspection.nextInspectionDate),
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });

    await batch.commit();

    // History best-effort
    try {
      await _historyService.recordFieldUpdate(
        equipmentId: inspection.equipmentId,
        field: 'Prüfung',
        oldValue: oldStatus,
        newValue: 'Prüfung bearbeitet — ${_resultText(inspection.result)}',
      );
    } catch (e) {
      print('History-Fehler (nicht kritisch): $e');
    }
  }

  /// Prüfung löschen.
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

  /// Alle Prüfungen einmalig abrufen (kein Stream → kein "already listened")
  Future<List<EquipmentInspectionModel>> getAllInspectionsFuture() async {
    try {
      final snapshot = await _firestore
          .collection('equipment_inspections')
          .orderBy('inspectionDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => EquipmentInspectionModel.fromMap(
          doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      print('Fehler beim Abrufen aller Prüfungen: $e');
      return [];
    }
  }

  /// Alle Prüfungen für eine bestimmte Ausrüstung einmalig abrufen
  Future<List<EquipmentInspectionModel>> getInspectionsForEquipmentFuture(
      String equipmentId) async {
    try {
      final snapshot = await _firestore
          .collection('equipment_inspections')
          .where('equipmentId', isEqualTo: equipmentId)
          .orderBy('inspectionDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => EquipmentInspectionModel.fromMap(
          doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      print('Fehler beim Abrufen der Prüfungen für $equipmentId: $e');
      return [];
    }
  }

}

