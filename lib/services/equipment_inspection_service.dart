// 2. Service für die Prüfungen
// services/equipment_inspection_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/equipment_inspection_model.dart';
import '../models/equipment_model.dart';
import 'equipment_service.dart';

class EquipmentInspectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EquipmentService _equipmentService = EquipmentService();

  // Neue Prüfung hinzufügen
  Future<DocumentReference> addInspection(EquipmentInspectionModel inspection) async {
    User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    // Prüfung in Firestore speichern
    DocumentReference docRef = await _firestore.collection('equipment_inspections').add(inspection.toMap());

    // Prüfdatum in der Einsatzkleidung aktualisieren
    await _equipmentService.updateCheckDate(inspection.equipmentId, inspection.nextInspectionDate);

    // Bei Durchfall den Status der Einsatzkleidung auf "In Reparatur" oder "Ausgemustert" setzen
    if (inspection.result == InspectionResult.failed) {
      await _equipmentService.updateStatus(inspection.equipmentId, EquipmentStatus.repair);
    }
    else if (inspection.result == InspectionResult.passed) {
      await _equipmentService.updateStatus(inspection.equipmentId, EquipmentStatus.ready);
    }
    else if (inspection.result == InspectionResult.conditionalPass) {
      await _equipmentService.updateStatus(inspection.equipmentId, EquipmentStatus.ready);
    }

    return docRef;
  }

  // Prüfungen für ein bestimmtes Equipment abrufen
  Stream<List<EquipmentInspectionModel>> getInspectionsForEquipment(String equipmentId) {
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

  // Alle Prüfungen abrufen (für Admin-Übersicht)
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

  // Nächste anstehende Prüfungen abrufen
  Stream<List<EquipmentInspectionModel>> getUpcomingInspections() {
    final DateTime now = DateTime.now();
    final DateTime threeMonthsFromNow = now.add(const Duration(days: 90));

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

  // Prüfung aktualisieren
  Future<void> updateInspection(EquipmentInspectionModel inspection) async {
    await _firestore
        .collection('equipment_inspections')
        .doc(inspection.id)
        .update(inspection.toMap());
  }

  // Prüfung löschen
  Future<void> deleteInspection(String inspectionId) async {
    await _firestore.collection('equipment_inspections').doc(inspectionId).delete();
  }


  // PRIVATE HILFSMETHODE: Status basierend auf Prüfergebnis bestimmen
  String _getNewStatusFromResult(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return 'Einsatzbereit'; // Bestanden = Einsatzbereit
      case InspectionResult.conditionalPass:
        return 'Einsatzbereit'; // Bedingt bestanden = auch Einsatzbereit
      case InspectionResult.failed:
        return 'In Reparatur'; // Durchgefallen = In Reparatur
    }
  }
}

