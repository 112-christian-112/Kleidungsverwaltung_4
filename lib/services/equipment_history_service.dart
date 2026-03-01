// services/equipment_history_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/equipment_history_model.dart';
import '../models/equipment_model.dart';
import 'permission_service.dart';

class EquipmentHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionService _permissionService = PermissionService();

  /// Fügt einen Historien-Eintrag hinzu.
  /// Nutzt PermissionService statt direktem Firestore-Read für den Benutzernamen.
  Future<DocumentReference> addHistoryEntry({
    required String equipmentId,
    required String action,
    required String field,
    dynamic oldValue,
    dynamic newValue,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('Kein Benutzer angemeldet');
      }

      // Benutzername über PermissionService holen (kein extra Firestore-Read)
      final userModel = await _permissionService.getCurrentUser();
      final userName = userModel?.name.isNotEmpty == true
          ? userModel!.name
          : currentUser.email ?? 'Unbekannt';

      final historyEntry = EquipmentHistoryModel(
        id: '',
        equipmentId: equipmentId,
        action: action,
        field: field,
        oldValue: oldValue,
        newValue: newValue,
        timestamp: DateTime.now(),
        performedBy: currentUser.uid,
        performedByName: userName,
      );

      return await _firestore
          .collection('equipment_history')
          .add(historyEntry.toMap());
    } catch (e) {
      throw Exception('Fehler beim Hinzufügen des Historien-Eintrags: $e');
    }
  }

  Stream<List<EquipmentHistoryModel>> getEquipmentHistory(String equipmentId) {
    return _firestore
        .collection('equipment_history')
        .where('equipmentId', isEqualTo: equipmentId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentHistoryModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  Future<void> recordEquipmentCreation(EquipmentModel equipment) async {
    try {
      await addHistoryEntry(
        equipmentId: equipment.id,
        action: HistoryAction.created,
        field: 'Einsatzkleidung',
        newValue: '${equipment.article} (${equipment.type}, ${equipment.size})',
      );
    } catch (e) {
      print('Fehler beim Aufzeichnen der Ausrüstungserstellung: $e');
    }
  }

  Future<void> recordFieldUpdate({
    required String equipmentId,
    required String field,
    required dynamic oldValue,
    required dynamic newValue,
  }) async {
    try {
      await addHistoryEntry(
        equipmentId: equipmentId,
        action: HistoryAction.updated,
        field: field,
        oldValue: oldValue,
        newValue: newValue,
      );
    } catch (e) {
      print('Fehler beim Aufzeichnen der Feldaktualisierung: $e');
    }
  }

  Future<void> recordEquipmentDeletion(EquipmentModel equipment) async {
    try {
      await addHistoryEntry(
        equipmentId: equipment.id,
        action: HistoryAction.deleted,
        field: 'Einsatzkleidung',
        oldValue: '${equipment.article} (${equipment.type}, ${equipment.size})',
      );
    } catch (e) {
      print('Fehler beim Aufzeichnen der Ausrüstungslöschung: $e');
    }
  }
}
