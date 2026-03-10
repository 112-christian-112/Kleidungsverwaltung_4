// services/mission_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/mission_model.dart';
import '../models/equipment_model.dart';
import '../models/user_models.dart';
import 'permission_service.dart';

class MissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionService _permissionService = PermissionService();

  // ── Lese-Methoden ─────────────────────────────────────────────────────────

  /// Einsätze basierend auf UserModel-Permissions laden.
  /// Akzeptiert nullable UserModel — bei null wird der alte PermissionService
  /// als Fallback genutzt (Rückwärtskompatibilität).
  Stream<List<MissionModel>> getMissionsForCurrentUser([UserModel? user]) async* {
    try {
      if (user == null) {
        final canViewAll = await _permissionService.canViewAllMissions();
        if (canViewAll) {
          yield* getAllMissions();
        } else {
          yield* getMissionsForUserFireStation();
        }
        return;
      }

      if (!user.isAdmin && user.permissions.missionView != true) {
        yield [];
        return;
      }

      if (user.isAdmin ||
          user.permissions.visibleFireStations.contains('*')) {
        yield* getAllMissions();
        return;
      }

      final stations = <String>{user.fireStation};
      stations.addAll(user.permissions.visibleFireStations);

      yield* _firestore
          .collection('missions')
          .orderBy('startTime', descending: true)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => MissionModel.fromMap(d.data(), d.id))
              .where((m) =>
                  stations.contains(m.fireStation) ||
                  m.involvedFireStations.any((s) => stations.contains(s)))
              .toList());
    } catch (e) {
      print('Fehler getMissionsForCurrentUser: $e');
      yield [];
    }
  }

  Stream<List<MissionModel>> getAllMissions() {
    return _firestore
        .collection('missions')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MissionModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<MissionModel>> getMissionsForUserFireStation() async* {
    try {
      final userFireStation = await _permissionService.getUserFireStation();
      if (userFireStation.isEmpty) {
        yield [];
        return;
      }
      yield* _firestore
          .collection('missions')
          .where('involvedFireStations', arrayContains: userFireStation)
          .orderBy('startTime', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => MissionModel.fromMap(doc.data(), doc.id))
              .toList());
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze für Benutzerfeuerwehr: $e');
      yield [];
    }
  }

  Stream<List<MissionModel>> getMissionsByFireStation(String fireStation) {
    return _firestore
        .collection('missions')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                MissionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .where((mission) =>
                mission.fireStation == fireStation ||
                mission.involvedFireStations.contains(fireStation))
            .toList());
  }

  Stream<List<MissionModel>> getMissionsByFireStations(
      List<String> fireStations) async* {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();

      if (canViewAll && fireStations.contains('Alle')) {
        yield* getAllMissions();
        return;
      }

      if (fireStations.isEmpty) {
        yield [];
        return;
      }

      yield* _firestore
          .collection('missions')
          .where('involvedFireStations', arrayContainsAny: fireStations)
          .orderBy('startTime', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => MissionModel.fromMap(doc.data(), doc.id))
              .toList());
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze nach Feuerwehrstationen: $e');
      yield [];
    }
  }

  Stream<List<MissionModel>> getMissionsByDateRange(
      DateTime startDate, DateTime endDate) async* {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();

      Query query = _firestore
          .collection('missions')
          .where('startTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('startTime', descending: true);

      if (!canViewAll) {
        final userFireStation = await _permissionService.getUserFireStation();
        if (userFireStation.isEmpty) {
          yield [];
          return;
        }
        query = query.where('involvedFireStations',
            arrayContains: userFireStation);
      }

      yield* query.snapshots().map((snapshot) => snapshot.docs
          .map((doc) =>
              MissionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList());
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze nach Zeitraum: $e');
      yield [];
    }
  }

  Future<MissionModel?> getMissionById(String missionId) async {
    try {
      final doc =
          await _firestore.collection('missions').doc(missionId).get();
      if (!doc.exists) return null;

      final mission =
          MissionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);

      final hasAccess = await hasAccessToMission(mission);
      if (!hasAccess) {
        throw Exception('Keine Berechtigung zum Anzeigen dieses Einsatzes');
      }

      return mission;
    } catch (e) {
      print('Fehler beim Abrufen des Einsatzes: $e');
      return null;
    }
  }

  /// FIX: whereIn ist auf 10 Einträge begrenzt.
  /// Diese Methode lädt Equipment-IDs in Batches à 10,
  /// damit Einsätze mit mehr als 10 Kleidungsstücken korrekt geladen werden.
  Future<List<EquipmentModel>> getEquipmentForMission(String missionId) async {
    try {
      final missionDoc =
          await _firestore.collection('missions').doc(missionId).get();
      if (!missionDoc.exists) return [];

      final mission = MissionModel.fromMap(
          missionDoc.data() as Map<String, dynamic>, missionDoc.id);

      final hasAccess = await hasAccessToMission(mission);
      if (!hasAccess) {
        throw Exception(
            'Keine Berechtigung zum Anzeigen der Ausrüstung für diesen Einsatz');
      }

      if (mission.equipmentIds.isEmpty) return [];

      final ids = mission.equipmentIds;
      const int batchSize = 10; // Firestore whereIn-Limit
      final List<EquipmentModel> allEquipment = [];

      for (int i = 0; i < ids.length; i += batchSize) {
        final end =
            (i + batchSize < ids.length) ? i + batchSize : ids.length;
        final batch = ids.sublist(i, end);

        final snapshot = await _firestore
            .collection('equipment')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        allEquipment.addAll(snapshot.docs.map((doc) =>
            EquipmentModel.fromMap(
                doc.data() as Map<String, dynamic>, doc.id)));
      }

      return allEquipment;
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung für Einsatz: $e');
      return [];
    }
  }

  Future<List<MissionModel>> getMissionsForEquipment(
      String equipmentId) async {
    try {
      final querySnapshot = await _firestore
          .collection('missions')
          .where('equipmentIds', arrayContains: equipmentId)
          .orderBy('startTime', descending: true)
          .get();

      final missions = <MissionModel>[];
      for (final doc in querySnapshot.docs) {
        final mission =
            MissionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        final hasAccess = await hasAccessToMission(mission);
        if (hasAccess) missions.add(mission);
      }

      return missions;
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze für Ausrüstung: $e');
      return [];
    }
  }

  Future<bool> hasAccessToMission(MissionModel mission) async {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();
      if (canViewAll) return true;

      final userFireStation = await _permissionService.getUserFireStation();
      if (userFireStation.isEmpty) return false;

      return mission.involvedFireStations.contains(userFireStation) ||
          mission.fireStation == userFireStation;
    } catch (e) {
      print('Fehler beim Prüfen des Einsatzzugriffs: $e');
      return false;
    }
  }

  Future<bool> canEditMission(MissionModel mission) async {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) return false;
      if (user.isAdmin) return true;
      if (!user.permissions.missionEdit) return false;
      return mission.fireStation == user.fireStation;
    } catch (e) {
      print('Fehler beim Prüfen der Bearbeitungsberechtigung: $e');
      return false;
    }
  }

  // ── Such-Methoden ─────────────────────────────────────────────────────────

  Future<List<MissionModel>> searchMissions(String searchTerm) async {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();
      final results = <MissionModel>[];
      final addedIds = <String>{};

      final nameQuery = await _firestore
          .collection('missions')
          .where('name', isGreaterThanOrEqualTo: searchTerm)
          .where('name', isLessThan: '${searchTerm}z')
          .get();

      final locationQuery = await _firestore
          .collection('missions')
          .where('location', isGreaterThanOrEqualTo: searchTerm)
          .where('location', isLessThan: '${searchTerm}z')
          .get();

      for (final doc in [...nameQuery.docs, ...locationQuery.docs]) {
        if (addedIds.contains(doc.id)) continue;
        final mission =
            MissionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        if (canViewAll || await hasAccessToMission(mission)) {
          results.add(mission);
          addedIds.add(doc.id);
        }
      }

      return results;
    } catch (e) {
      print('Fehler bei der Einsatzsuche: $e');
      return [];
    }
  }

  // ── Schreib-Methoden ──────────────────────────────────────────────────────

  Future<DocumentReference> createMission(MissionModel mission) async {
    final canCreate =
        await _permissionService.canPerformAction('add_missions');
    if (!canCreate) {
      throw Exception('Keine Berechtigung zum Erstellen von Einsätzen');
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    return await _firestore.collection('missions').add(mission.toMap());
  }

  Future<void> updateMission(MissionModel mission) async {
    final canEdit = await _permissionService.canEditMissions();
    if (!canEdit) {
      throw Exception('Keine Berechtigung zum Bearbeiten von Einsätzen');
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    final missionData = mission.toMap();
    missionData['updatedAt'] = Timestamp.now();
    missionData['updatedBy'] = currentUser.uid;

    await _firestore
        .collection('missions')
        .doc(mission.id)
        .update(missionData);
  }

  Future<void> deleteMission(String missionId) async {
    final canDelete = await _permissionService.canDeleteMissions();
    if (!canDelete) {
      throw Exception('Keine Berechtigung zum Löschen von Einsätzen');
    }
    await _firestore.collection('missions').doc(missionId).delete();
  }

  Future<void> addEquipmentToMission(
      String missionId, List<String> equipmentIds) async {
    final canUpdate =
        await _permissionService.canPerformAction('add_missions');
    if (!canUpdate) {
      throw Exception(
          'Keine Berechtigung zum Hinzufügen von Ausrüstung zu Einsätzen');
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

    await _firestore.collection('missions').doc(missionId).update({
      'equipmentIds': FieldValue.arrayUnion(equipmentIds),
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }
}
