// services/equipment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/equipment_model.dart';
import 'permission_service.dart';

class EquipmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionService _permissionService = PermissionService();

  // ERWEITERTE METHODE: Ausrüstung basierend auf Benutzerberechtigungen abrufen
  Stream<List<EquipmentModel>> getEquipmentByUserAccess() async* {
    try {
      final hasExtendedAccess = await _permissionService.hasExtendedReadAccess();

      if (hasExtendedAccess) {
        // Admin und Hygieneeinheit können alle Ausrüstung sehen
        yield* getAllEquipment();
      } else {
        // Normale Benutzer sehen nur Ausrüstung ihrer Feuerwehr
        yield* getEquipmentByUserFireStation();
      }
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung nach Berechtigung: $e');
      yield [];
    }
  }

  // Bestehende Methoden bleiben erhalten
  Stream<List<EquipmentModel>> getAllEquipment() {
    return _firestore
        .collection('equipment')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return EquipmentModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  Stream<List<EquipmentModel>> getEquipmentByUserFireStation() async* {
    try {
      final userFireStation = await _permissionService.getUserFireStation();
      if (userFireStation.isEmpty) {
        yield [];
        return;
      }

      yield* getEquipmentByFireStation(userFireStation);
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung für Benutzerfeuerwehr: $e');
      yield [];
    }
  }

  Stream<List<EquipmentModel>> getEquipmentByFireStation(String fireStation) {
    return _firestore
        .collection('equipment')
        .where('fireStation', isEqualTo: fireStation)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return EquipmentModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // NEUE METHODE: Ausrüstung für mehrere Feuerwehrstationen abrufen
  Stream<List<EquipmentModel>> getEquipmentByMultipleFireStations(List<String> fireStations) {
    if (fireStations.isEmpty) {
      return Stream.value([]);
    }

    // Wenn "Alle" in der Liste ist, alle Ausrüstung zurückgeben
    if (fireStations.contains('Alle')) {
      return getAllEquipment();
    }

    return _firestore
        .collection('equipment')
        .where('fireStation', whereIn: fireStations)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return EquipmentModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // Methoden mit Berechtigungsprüfung für Schreiboperationen
  Future<DocumentReference> addEquipment(EquipmentModel equipment) async {
    // Prüfung der Schreibberechtigung
    final canEdit = await _permissionService.canEditEquipment();
    if (!canEdit) {
      throw Exception('Keine Berechtigung zum Hinzufügen von Ausrüstung');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    final equipmentData = equipment.toMap();
    return await _firestore.collection('equipment').add(equipmentData);
  }

  Future<void> updateEquipment({
    required String equipmentId,
    required String article,
    required String type,
    required String size,
    required String fireStation,
    required String owner,
    required DateTime checkDate,
    required String status,
  }) async {
    // Prüfung der Schreibberechtigung
    final canEdit = await _permissionService.canEditEquipment();
    if (!canEdit) {
      throw Exception('Keine Berechtigung zum Bearbeiten von Ausrüstung');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    await _firestore.collection('equipment').doc(equipmentId).update({
      'article': article,
      'type': type,
      'size': size,
      'fireStation': fireStation,
      'owner': owner,
      'checkDate': Timestamp.fromDate(checkDate),
      'status': status,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  Future<void> deleteEquipment(String equipmentId) async {
    // Prüfung der Löschberechtigung
    final canEdit = await _permissionService.canEditEquipment();
    if (!canEdit) {
      throw Exception('Keine Berechtigung zum Löschen von Ausrüstung');
    }

    await _firestore.collection('equipment').doc(equipmentId).delete();
  }

  // Status-Update mit flexibleren Berechtigungen
  Future<void> updateStatus(String equipmentId, String newStatus) async {
    // Admins und normale Benutzer können Status aktualisieren
    final canUpdate = await _permissionService.canPerformAction('update_equipment_status');
    if (!canUpdate) {
      throw Exception('Keine Berechtigung zum Aktualisieren des Status');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    await _firestore.collection('equipment').doc(equipmentId).update({
      'status': newStatus,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  // Waschzyklen-Update mit flexibleren Berechtigungen
  Future<void> updateWashCycles(String equipmentId, int newWashCycles) async {
    // Admins und normale Benutzer können Waschzyklen aktualisieren
    final canUpdate = await _permissionService.canPerformAction('update_wash_cycles');
    if (!canUpdate) {
      throw Exception('Keine Berechtigung zum Aktualisieren der Waschzyklen');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    await _firestore.collection('equipment').doc(equipmentId).update({
      'washCycles': newWashCycles,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  // Batch-Status-Update mit Berechtigungsprüfung
  Future<void> updateStatusBatch(List<String> equipmentIds, String newStatus) async {
    final canUpdate = await _permissionService.canPerformAction('update_equipment_status');
    if (!canUpdate) {
      throw Exception('Keine Berechtigung zum Batch-Update des Status');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    WriteBatch batch = _firestore.batch();

    for (String equipmentId in equipmentIds) {
      DocumentReference equipmentRef = _firestore.collection('equipment').doc(equipmentId);
      batch.update(equipmentRef, {
        'status': newStatus,
        'updatedAt': Timestamp.now(),
        'updatedBy': currentUser.uid,
      });
    }

    await batch.commit();
  }

  // Prüfdatum-Update mit Berechtigungsprüfung
  Future<void> updateCheckDate(String equipmentId, DateTime newCheckDate) async {
    final canEdit = await _permissionService.canPerformAction('update_check_date');
    if (!canEdit) {
      throw Exception('Keine Berechtigung zum Aktualisieren des Prüfdatums');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    await _firestore.collection('equipment').doc(equipmentId).update({
      'checkDate': Timestamp.fromDate(newCheckDate),
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  // Lesezugriff-Methoden (für alle mit entsprechenden Berechtigungen verfügbar)
  Future<EquipmentModel?> getEquipmentByNfcTag(String nfcTag) async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('equipment')
          .where('nfcTag', isEqualTo: nfcTag)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return EquipmentModel.fromMap(
          querySnapshot.docs.first.data() as Map<String, dynamic>,
          querySnapshot.docs.first.id,
        );
      }
      return null;
    } catch (e) {
      print('Fehler beim Suchen nach NFC-Tag: $e');
      return null;
    }
  }

  Future<EquipmentModel?> getEquipmentByBarcode(String barcode) async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('equipment')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return EquipmentModel.fromMap(
          querySnapshot.docs.first.data() as Map<String, dynamic>,
          querySnapshot.docs.first.id,
        );
      }
      return null;
    } catch (e) {
      print('Fehler beim Suchen nach Barcode: $e');
      return null;
    }
  }

  Future<List<EquipmentModel>> searchEquipmentByPartialTagOrBarcode(String searchString) async {
    try {
      List<EquipmentModel> results = [];

      // Suche nach NFC-Tags (Teilstring)
      QuerySnapshot nfcQuery = await _firestore
          .collection('equipment')
          .where('nfcTag', isGreaterThanOrEqualTo: searchString)
          .where('nfcTag', isLessThan: searchString + 'z')
          .get();

      for (var doc in nfcQuery.docs) {
        results.add(EquipmentModel.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        ));
      }

      // Suche nach Barcodes (Teilstring)
      QuerySnapshot barcodeQuery = await _firestore
          .collection('equipment')
          .where('barcode', isGreaterThanOrEqualTo: searchString)
          .where('barcode', isLessThan: searchString + 'z')
          .get();

      for (var doc in barcodeQuery.docs) {
        final equipment = EquipmentModel.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );

        // Duplikate vermeiden
        if (!results.any((item) => item.id == equipment.id)) {
          results.add(equipment);
        }
      }

      return results;
    } catch (e) {
      print('Fehler bei der Teilstring-Suche: $e');
      return [];
    }
  }

  // NEUE METHODE: Berechtigungsbasierte Ausrüstungsabfrage für Prüfdaten
  Stream<List<EquipmentModel>> getEquipmentByCheckDate(DateTime startDate, DateTime endDate) async* {
    try {
      final hasExtendedAccess = await _permissionService.hasExtendedReadAccess();

      Query query = _firestore
          .collection('equipment')
          .where('checkDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('checkDate', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('checkDate');

      if (!hasExtendedAccess) {
        // Normale Benutzer sehen nur Ausrüstung ihrer Feuerwehr
        final userFireStation = await _permissionService.getUserFireStation();
        if (userFireStation.isNotEmpty) {
          query = query.where('fireStation', isEqualTo: userFireStation);
        } else {
          yield [];
          return;
        }
      }

      yield* query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          return EquipmentModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }).toList();
      });
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung nach Prüfdatum: $e');
      yield [];
    }
  }

  // NEUE METHODE: Prüft ob Benutzer Zugriff auf bestimmte Ausrüstung hat
  Future<bool> hasAccessToEquipment(String equipmentId) async {
    try {
      final hasExtendedAccess = await _permissionService.hasExtendedReadAccess();
      if (hasExtendedAccess) {
        return true; // Admin und Hygieneeinheit haben Zugriff auf alles
      }

      // Normale Benutzer: Prüfe ob Ausrüstung zur eigenen Feuerwehr gehört
      final doc = await _firestore.collection('equipment').doc(equipmentId).get();
      if (!doc.exists) return false;

      final equipment = EquipmentModel.fromMap(doc.data()!, doc.id);
      final userFireStation = await _permissionService.getUserFireStation();

      return equipment.fireStation == userFireStation;
    } catch (e) {
      print('Fehler beim Prüfen des Ausrüstungszugriffs: $e');
      return false;
    }
  }

  // Einsatzkleidung nach Prüfdatum und Feuerwehrstation filtern
  Stream<List<EquipmentModel>> getEquipmentByCheckDateAndFireStation(
      DateTime startDate, DateTime endDate, String fireStation) {
    return _firestore
        .collection('equipment')
        .where('fireStation', isEqualTo: fireStation)
        .where('checkDate', isGreaterThanOrEqualTo: startDate)
        .where('checkDate', isLessThanOrEqualTo: endDate)
        .orderBy('checkDate')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => EquipmentModel.fromMap(
        doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  // Überfällige Einsatzkleidung abrufen
  Stream<List<EquipmentModel>> getOverdueEquipment() {
    final now = DateTime.now();

    return _firestore
        .collection('equipment')
        .where('checkDate', isLessThan: now)
        .orderBy('checkDate')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => EquipmentModel.fromMap(
        doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  // Überfällige Einsatzkleidung nach Feuerwehrstation abrufen
  Stream<List<EquipmentModel>> getOverdueEquipmentByFireStation(String fireStation) {
    final now = DateTime.now();

    return _firestore
        .collection('equipment')
        .where('fireStation', isEqualTo: fireStation)
        .where('checkDate', isLessThan: now)
        .orderBy('checkDate')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => EquipmentModel.fromMap(
        doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }
}