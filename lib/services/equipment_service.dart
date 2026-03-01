// services/equipment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/equipment_model.dart';
import '../models/user_models.dart';
import 'permission_service.dart';
import 'equipment_history_service.dart';

class EquipmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionService _permissionService = PermissionService();
  final EquipmentHistoryService _historyService = EquipmentHistoryService();

  // ── Lese-Methoden ─────────────────────────────────────────────────────────

  /// Hauptmethode: Lädt Ausrüstung basierend auf den Berechtigungen des
  /// eingeloggten Benutzers. Einmaliger Firestore-Read für das UserModel,
  /// danach direkter Permission-Zugriff ohne weitere Reads.
  Stream<List<EquipmentModel>> getEquipmentByUserAccess() async* {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) { yield []; return; }

      // Kein Leserecht → sofort leere Liste
      if (!user.isAdmin && !user.permissions.equipmentView) { yield []; return; }

      // Admin oder '*' → alles laden
      if (user.isAdmin || user.permissions.visibleFireStations.contains('*')) {
        yield* getAllEquipment();
        return;
      }

      // Sichtbare Stationen ermitteln (eigene Feuerwehr immer dabei)
      final stations = <String>{user.fireStation};
      stations.addAll(user.permissions.visibleFireStations);
      final stationList = stations.toList();

      if (stationList.length == 1) {
        yield* getEquipmentByFireStation(stationList.first);
      } else {
        yield* getEquipmentByMultipleFireStations(stationList);
      }
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung nach Berechtigung: $e');
      yield [];
    }
  }

  /// Live-Stream für ein einzelnes Equipment-Dokument.
  /// Wird im Detail-Screen genutzt, damit Status und Waschzyklen
  /// nach einer Prüfung sofort aktualisiert werden.
  Stream<EquipmentModel?> getEquipmentById(String equipmentId) {
    return _firestore
        .collection('equipment')
        .doc(equipmentId)
        .snapshots()
        .map((doc) => doc.exists
            ? EquipmentModel.fromMap(doc.data()!, doc.id)
            : null);
  }

  Stream<List<EquipmentModel>> getAllEquipment() {
    return _firestore
        .collection('equipment')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<EquipmentModel>> getEquipmentByFireStation(String fireStation) {
    return _firestore
        .collection('equipment')
        .where('fireStation', isEqualTo: fireStation)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<EquipmentModel>> getEquipmentByMultipleFireStations(
      List<String> fireStations) {
    if (fireStations.isEmpty) return Stream.value([]);
    if (fireStations.contains('Alle')) return getAllEquipment();

    return _firestore
        .collection('equipment')
        .where('fireStation', whereIn: fireStations)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EquipmentModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<EquipmentModel>> getEquipmentByUserFireStation() async* {
    try {
      final userFireStation = await _permissionService.getUserFireStation();
      if (userFireStation.isEmpty) { yield []; return; }
      yield* getEquipmentByFireStation(userFireStation);
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung für Benutzerfeuerwehr: $e');
      yield [];
    }
  }

  /// Ausrüstung nach Prüfdatum-Zeitraum filtern — berücksichtigt sichtbare
  /// Feuerwehren aus dem UserModel (ein einziger Firestore-Read).
  Stream<List<EquipmentModel>> getEquipmentByCheckDate(
      DateTime startDate, DateTime endDate) async* {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) { yield []; return; }

      if (!user.isAdmin && !user.permissions.equipmentView) { yield []; return; }

      Query query = _firestore
          .collection('equipment')
          .where('checkDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('checkDate',
              isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('checkDate');

      // Eingeschränkte Sicht: nur eigene Feuerwehr(en)
      if (!user.isAdmin &&
          !user.permissions.visibleFireStations.contains('*')) {
        final stations = <String>{user.fireStation};
        stations.addAll(user.permissions.visibleFireStations);

        if (stations.length == 1) {
          query =
              query.where('fireStation', isEqualTo: stations.first);
        } else {
          query = query.where('fireStation', whereIn: stations.toList());
        }
      }

      yield* query.snapshots().map((snapshot) => snapshot.docs
          .map((doc) =>
              EquipmentModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList());
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung nach Prüfdatum: $e');
      yield [];
    }
  }

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

  Stream<List<EquipmentModel>> getOverdueEquipmentByFireStation(
      String fireStation) {
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

  /// Prüft ob der aktuelle Benutzer Zugriff auf ein bestimmtes Equipment hat.
  Future<bool> hasAccessToEquipment(String equipmentId) async {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) return false;
      if (user.isAdmin || user.permissions.visibleFireStations.contains('*')) {
        return true;
      }

      final doc =
          await _firestore.collection('equipment').doc(equipmentId).get();
      if (!doc.exists) return false;

      final equipment =
          EquipmentModel.fromMap(doc.data()!, doc.id);
      final stations = <String>{user.fireStation};
      stations.addAll(user.permissions.visibleFireStations);

      return stations.contains(equipment.fireStation);
    } catch (e) {
      print('Fehler beim Prüfen des Ausrüstungszugriffs: $e');
      return false;
    }
  }

  // ── Such-Methoden ─────────────────────────────────────────────────────────

  Future<EquipmentModel?> getEquipmentByNfcTag(String nfcTag) async {
    try {
      final snapshot = await _firestore
          .collection('equipment')
          .where('nfcTag', isEqualTo: nfcTag)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        return EquipmentModel.fromMap(
            snapshot.docs.first.data(), snapshot.docs.first.id);
      }
      return null;
    } catch (e) {
      print('Fehler beim Suchen nach NFC-Tag: $e');
      return null;
    }
  }

  Future<EquipmentModel?> getEquipmentByBarcode(String barcode) async {
    try {
      final snapshot = await _firestore
          .collection('equipment')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        return EquipmentModel.fromMap(
            snapshot.docs.first.data(), snapshot.docs.first.id);
      }
      return null;
    } catch (e) {
      print('Fehler beim Suchen nach Barcode: $e');
      return null;
    }
  }

  Future<List<EquipmentModel>> searchEquipmentByPartialTagOrBarcode(
      String searchString) async {
    try {
      final results = <EquipmentModel>[];

      final nfcQuery = await _firestore
          .collection('equipment')
          .where('nfcTag', isGreaterThanOrEqualTo: searchString)
          .where('nfcTag', isLessThan: '${searchString}z')
          .get();
      for (final doc in nfcQuery.docs) {
        results.add(EquipmentModel.fromMap(doc.data(), doc.id));
      }

      final barcodeQuery = await _firestore
          .collection('equipment')
          .where('barcode', isGreaterThanOrEqualTo: searchString)
          .where('barcode', isLessThan: '${searchString}z')
          .get();
      for (final doc in barcodeQuery.docs) {
        final equipment = EquipmentModel.fromMap(doc.data(), doc.id);
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

  // ── Schreib-Methoden ──────────────────────────────────────────────────────

  Future<DocumentReference> addEquipment(EquipmentModel equipment) async {
    final user = await _permissionService.getCurrentUser();
    if (user == null || (!user.isAdmin && !user.permissions.equipmentAdd)) {
      throw Exception('Keine Berechtigung zum Hinzufügen von Ausrüstung');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    return await _firestore.collection('equipment').add(equipment.toMap());
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
    final user = await _permissionService.getCurrentUser();
    if (user == null || (!user.isAdmin && !user.permissions.equipmentEdit)) {
      throw Exception('Keine Berechtigung zum Bearbeiten von Ausrüstung');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

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
    final user = await _permissionService.getCurrentUser();
    if (user == null || (!user.isAdmin && !user.permissions.equipmentDelete)) {
      throw Exception('Keine Berechtigung zum Löschen von Ausrüstung');
    }
    await _firestore.collection('equipment').doc(equipmentId).delete();
  }

  /// Status-Update: benötigt equipmentEdit- ODER inspectionPerform-Recht.
  /// Schreibt automatisch einen History-Eintrag.
  Future<void> updateStatus(String equipmentId, String newStatus,
      {bool writeHistory = true}) async {
    final user = await _permissionService.getCurrentUser();
    if (user == null ||
        (!user.isAdmin &&
            !user.permissions.equipmentEdit &&
            !user.permissions.inspectionPerform)) {
      throw Exception('Keine Berechtigung zum Aktualisieren des Status');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    // Alten Status für History lesen
    String oldStatus = '';
    if (writeHistory) {
      final doc = await _firestore.collection('equipment').doc(equipmentId).get();
      oldStatus = (doc.data()?['status'] as String?) ?? '';
    }

    await _firestore.collection('equipment').doc(equipmentId).update({
      'status': newStatus,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });

    // History-Eintrag schreiben (best-effort, nur wenn sich Status geändert hat)
    if (writeHistory && oldStatus != newStatus) {
      try {
        await _historyService.recordFieldUpdate(
          equipmentId: equipmentId,
          field: 'Status',
          oldValue: oldStatus,
          newValue: newStatus,
        );
      } catch (e) {
        print('History-Fehler updateStatus (nicht kritisch): $e');
      }
    }
  }

  /// Waschzyklen-Update: benötigt equipmentEdit- ODER inspectionPerform-Recht.
  /// inspectionPerform darf Waschzyklen erhöhen, da dies automatisch nach
  /// einer Prüfung aus der Reinigung heraus passiert.
  Future<void> updateWashCycles(String equipmentId, int newWashCycles) async {
    final user = await _permissionService.getCurrentUser();
    if (user == null ||
        (!user.isAdmin &&
            !user.permissions.equipmentEdit &&
            !user.permissions.inspectionPerform)) {
      throw Exception('Keine Berechtigung zum Aktualisieren der Waschzyklen');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    await _firestore.collection('equipment').doc(equipmentId).update({
      'washCycles': newWashCycles,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  /// Batch-Status-Update: benötigt equipmentEdit-Recht.
  Future<void> updateStatusBatch(
      List<String> equipmentIds, String newStatus) async {
    final user = await _permissionService.getCurrentUser();
    if (user == null || (!user.isAdmin && !user.permissions.equipmentEdit)) {
      throw Exception('Keine Berechtigung zum Batch-Update des Status');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    final batch = _firestore.batch();
    for (final id in equipmentIds) {
      batch.update(_firestore.collection('equipment').doc(id), {
        'status': newStatus,
        'updatedAt': Timestamp.now(),
        'updatedBy': currentUser.uid,
      });
    }
    await batch.commit();
  }

  /// Prüfdatum-Update: benötigt inspectionPerform- oder equipmentEdit-Recht.
  Future<void> updateCheckDate(
      String equipmentId, DateTime newCheckDate) async {
    final user = await _permissionService.getCurrentUser();
    if (user == null ||
        (!user.isAdmin &&
            !user.permissions.inspectionPerform &&
            !user.permissions.equipmentEdit)) {
      throw Exception(
          'Keine Berechtigung zum Aktualisieren des Prüfdatums');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    await _firestore.collection('equipment').doc(equipmentId).update({
      'checkDate': Timestamp.fromDate(newCheckDate),
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }
}
