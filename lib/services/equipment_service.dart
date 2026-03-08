// services/equipment_service.dart
import 'dart:async';
import 'package:async/async.dart';
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
      if (user == null) {
        yield [];
        return;
      }

      if (!user.isAdmin && !user.permissions.equipmentView) {
        yield [];
        return;
      }

      if (user.isAdmin || user.permissions.visibleFireStations.contains('*')) {
        yield* getAllEquipment();
        return;
      }

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

  /// Einmaligen Abruf eines einzelnen Equipment-Dokuments (kein Stream).
  Future<EquipmentModel?> getEquipmentByIdFuture(String equipmentId) async {
    final doc = await _firestore.collection('equipment').doc(equipmentId).get();
    if (!doc.exists) return null;
    return EquipmentModel.fromMap(doc.data()!, doc.id);
  }

  /// Live-Stream für ein einzelnes Equipment-Dokument.
  Stream<EquipmentModel?> getEquipmentById(String equipmentId) {
    return _firestore
        .collection('equipment')
        .doc(equipmentId)
        .snapshots()
        .map((doc) =>
            doc.exists ? EquipmentModel.fromMap(doc.data()!, doc.id) : null);
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

  /// FIX: Firestore erlaubt max. 10 Werte pro whereIn-Abfrage.
  /// Diese Methode teilt [fireStations] in Chunks à 10 auf,
  /// fragt jeden Chunk separat ab und führt die Streams zusammen.
  Stream<List<EquipmentModel>> getEquipmentByMultipleFireStations(
      List<String> fireStations) {
    if (fireStations.isEmpty) return Stream.value([]);
    if (fireStations.contains('Alle')) return getAllEquipment();
    if (fireStations.length == 1) {
      return getEquipmentByFireStation(fireStations.first);
    }
    return _getEquipmentByStationsBatched(fireStations);
  }

  /// Privater Helfer: teilt eine beliebig lange Stationsliste in Batches
  /// à 10 auf, erstellt pro Batch einen eigenen Firestore-Stream und
  /// führt alle Streams zu einem gemeinsamen Stream zusammen.
  /// Bei jedem Update eines Teilstreams wird die Gesamtliste neu zusammengesetzt.
  Stream<List<EquipmentModel>> _getEquipmentByStationsBatched(
      List<String> fireStations) {
    const int batchSize = 10;

    final List<List<String>> batches = [];
    for (int i = 0; i < fireStations.length; i += batchSize) {
      final end = (i + batchSize < fireStations.length)
          ? i + batchSize
          : fireStations.length;
      batches.add(fireStations.sublist(i, end));
    }

    final List<Stream<MapEntry<int, List<EquipmentModel>>>> indexedStreams =
        batches.asMap().entries.map((entry) {
      final index = entry.key;
      final batch = entry.value;
      return _firestore
          .collection('equipment')
          .where('fireStation', whereIn: batch)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => MapEntry(
                index,
                snapshot.docs
                    .map((doc) => EquipmentModel.fromMap(doc.data(), doc.id))
                    .toList(),
              ));
    }).toList();

    final Map<int, List<EquipmentModel>> latestValues = {};

    return StreamGroup.merge(indexedStreams).map((entry) {
      latestValues[entry.key] = entry.value;
      final combined = latestValues.values.expand((list) => list).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return combined;
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

  /// FIX: getEquipmentByCheckDate — auch hier whereIn-Limit beachtet.
  /// Bei mehreren Stationen wird clientseitig nach Datum gefiltert,
  /// da Firestore kein whereIn + weiteres where-Feld ohne Composite Index erlaubt.
  Stream<List<EquipmentModel>> getEquipmentByCheckDate(
      DateTime startDate, DateTime endDate) async* {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) {
        yield [];
        return;
      }
      if (!user.isAdmin && !user.permissions.equipmentView) {
        yield [];
        return;
      }

      // Admin oder '*': einfache Abfrage ohne Stationsfilter
      if (user.isAdmin ||
          user.permissions.visibleFireStations.contains('*')) {
        yield* _firestore
            .collection('equipment')
            .where('checkDate',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
            .where('checkDate',
                isLessThanOrEqualTo: Timestamp.fromDate(endDate))
            .orderBy('checkDate')
            .snapshots()
            .map((snapshot) => snapshot.docs
                .map((doc) => EquipmentModel.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id))
                .toList());
        return;
      }

      final stations = <String>{user.fireStation};
      stations.addAll(user.permissions.visibleFireStations);
      final stationList = stations.toList();

      if (stationList.length == 1) {
        yield* _firestore
            .collection('equipment')
            .where('fireStation', isEqualTo: stationList.first)
            .where('checkDate',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
            .where('checkDate',
                isLessThanOrEqualTo: Timestamp.fromDate(endDate))
            .orderBy('checkDate')
            .snapshots()
            .map((snapshot) => snapshot.docs
                .map((doc) => EquipmentModel.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id))
                .toList());
      } else {
        // Mehrere Stationen: gebatcht laden + clientseitig nach Datum filtern
        yield* _getEquipmentByStationsBatched(stationList).map((list) => list
            .where((e) =>
                !e.checkDate.isBefore(startDate) &&
                !e.checkDate.isAfter(endDate))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate)));
      }
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

  Future<bool> hasAccessToEquipment(String equipmentId) async {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) return false;
      if (user.isAdmin ||
          user.permissions.visibleFireStations.contains('*')) {
        return true;
      }

      final doc =
          await _firestore.collection('equipment').doc(equipmentId).get();
      if (!doc.exists) return false;

      final equipment = EquipmentModel.fromMap(doc.data()!, doc.id);
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
    if (user == null ||
        (!user.isAdmin && !user.permissions.equipmentDelete)) {
      throw Exception('Keine Berechtigung zum Löschen von Ausrüstung');
    }
    await _firestore.collection('equipment').doc(equipmentId).delete();
  }

  /// Status-Update: benötigt equipmentEdit- ODER inspectionPerform-Recht.
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

    String oldStatus = '';
    if (writeHistory) {
      final doc =
          await _firestore.collection('equipment').doc(equipmentId).get();
      oldStatus = (doc.data()?['status'] as String?) ?? '';
    }

    await _firestore.collection('equipment').doc(equipmentId).update({
      'status': newStatus,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });

    if (writeHistory) {
      try {
        await _historyService.recordFieldUpdate(
          equipmentId: equipmentId,
          field: 'Status',
          oldValue: oldStatus,
          newValue: newStatus,
        );
      } catch (e) {
        print('History-Fehler (nicht kritisch): $e');
      }
    }
  }

  Future<void> updateWashCycles(String equipmentId, int newCount) async {
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
      'washCycles': newCount,
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  /// Batch-Status-Update für mehrere Ausrüstungsgegenstände gleichzeitig.
  /// Nutzt einen Firestore-Batch-Write — alle Änderungen in einem einzigen Commit.
  /// Benötigt equipmentEdit-Recht.
  Future<void> updateStatusBatch(
      List<String> equipmentIds, String newStatus) async {
    if (equipmentIds.isEmpty) return;

    final user = await _permissionService.getCurrentUser();
    if (user == null || (!user.isAdmin && !user.permissions.equipmentEdit)) {
      throw Exception('Keine Berechtigung zum Batch-Update des Status');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    // Firestore Batch-Writes sind auf 500 Operationen begrenzt.
    // Bei sehr großen Listen in Chunks à 400 aufteilen (Puffer für Sicherheit).
    const int batchLimit = 400;
    for (int i = 0; i < equipmentIds.length; i += batchLimit) {
      final end = (i + batchLimit < equipmentIds.length)
          ? i + batchLimit
          : equipmentIds.length;
      final chunk = equipmentIds.sublist(i, end);

      final batch = _firestore.batch();
      for (final id in chunk) {
        batch.update(_firestore.collection('equipment').doc(id), {
          'status': newStatus,
          'updatedAt': Timestamp.now(),
          'updatedBy': currentUser.uid,
        });
      }
      await batch.commit();
    }
  }

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
