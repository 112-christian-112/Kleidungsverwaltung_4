// services/mission_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/mission_model.dart';
import '../models/equipment_model.dart';
import 'permission_service.dart';

class MissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionService _permissionService = PermissionService();

  // ERWEITERTE METHODE: Einsätze basierend auf Benutzerberechtigungen abrufen
  Stream<List<MissionModel>> getMissionsForCurrentUser() async* {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();

      if (canViewAll) {
        // Admin und Hygieneeinheit können alle Einsätze sehen
        yield* getAllMissions();
      } else {
        // Normale Benutzer sehen nur Einsätze ihrer Feuerwehr
        yield* getMissionsForUserFireStation();
      }
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze für aktuellen Benutzer: $e');
      yield [];
    }
  }

  // Bestehende Methoden bleiben erhalten
  Stream<List<MissionModel>> getAllMissions() {
    return _firestore
        .collection('missions')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MissionModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  Stream<List<MissionModel>> getMissionsForUserFireStation() async* {
    try {
      final userFireStation = await _permissionService.getUserFireStation();
      if (userFireStation.isEmpty) {
        yield [];
        return;
      }

      // Einsätze abrufen, bei denen die Benutzer-Feuerwehr beteiligt ist
      yield* _firestore
          .collection('missions')
          .where('involvedFireStations', arrayContains: userFireStation)
          .orderBy('startTime', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return MissionModel.fromMap(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze für Benutzerfeuerwehr: $e');
      yield [];
    }
  }

  // Methoden mit Berechtigungsprüfung für Schreiboperationen
  Future<DocumentReference> createMission(MissionModel mission) async {
    // Normale Benutzer und Admins können Einsätze erstellen
    final canCreate = await _permissionService.canPerformAction('add_missions');
    if (!canCreate) {
      throw Exception('Keine Berechtigung zum Erstellen von Einsätzen');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    final missionData = mission.toMap();
    return await _firestore.collection('missions').add(missionData);
  }

  Future<void> updateMission(MissionModel mission) async {
    // Nur Admins können Einsätze bearbeiten
    final canEdit = await _permissionService.canEditMissions();
    if (!canEdit) {
      throw Exception('Keine Berechtigung zum Bearbeiten von Einsätzen');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    final missionData = mission.toMap();
    missionData['updatedAt'] = Timestamp.now();
    missionData['updatedBy'] = currentUser.uid;

    await _firestore.collection('missions').doc(mission.id).update(missionData);
  }

  Future<void> deleteMission(String missionId) async {
    // Nur Admins können Einsätze löschen
    final canDelete = await _permissionService.canEditMissions();
    if (!canDelete) {
      throw Exception('Keine Berechtigung zum Löschen von Einsätzen');
    }

    await _firestore.collection('missions').doc(missionId).delete();
  }

  // Ausrüstung zu Einsatz hinzufügen (normale Benutzer und Admins)
  Future<void> addEquipmentToMission(String missionId,
      List<String> equipmentIds) async {
    final canUpdate = await _permissionService.canPerformAction('add_missions');
    if (!canUpdate) {
      throw Exception(
          'Keine Berechtigung zum Hinzufügen von Ausrüstung zu Einsätzen');
    }

    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Kein Benutzer angemeldet');
    }

    await _firestore.collection('missions').doc(missionId).update({
      'equipmentIds': FieldValue.arrayUnion(equipmentIds),
      'updatedAt': Timestamp.now(),
      'updatedBy': currentUser.uid,
    });
  }

  // Lesezugriff-Methoden (für alle mit entsprechenden Berechtigungen verfügbar)
  Future<MissionModel?> getMissionById(String missionId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('missions').doc(
          missionId).get();

      if (!doc.exists) return null;

      final mission = MissionModel.fromMap(
          doc.data() as Map<String, dynamic>, doc.id);

      // Prüfe Zugriffsberechtigung
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

  Future<List<EquipmentModel>> getEquipmentForMission(String missionId) async {
    try {
      DocumentSnapshot missionDoc = await _firestore.collection('missions').doc(
          missionId).get();

      if (!missionDoc.exists) return [];

      final mission = MissionModel.fromMap(
          missionDoc.data() as Map<String, dynamic>, missionDoc.id);

      // Prüfe Zugriffsberechtigung
      final hasAccess = await hasAccessToMission(mission);
      if (!hasAccess) {
        throw Exception(
            'Keine Berechtigung zum Anzeigen der Ausrüstung für diesen Einsatz');
      }

      if (mission.equipmentIds.isEmpty) return [];

      QuerySnapshot equipmentQuery = await _firestore
          .collection('equipment')
          .where(FieldPath.documentId, whereIn: mission.equipmentIds)
          .get();

      return equipmentQuery.docs.map((doc) {
        return EquipmentModel.fromMap(
            doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      print('Fehler beim Abrufen der Ausrüstung für Einsatz: $e');
      return [];
    }
  }

  Future<List<MissionModel>> getMissionsForEquipment(String equipmentId) async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('missions')
          .where('equipmentIds', arrayContains: equipmentId)
          .orderBy('startTime', descending: true)
          .get();

      List<MissionModel> missions = [];

      for (var doc in querySnapshot.docs) {
        final mission = MissionModel.fromMap(
            doc.data() as Map<String, dynamic>, doc.id);

        // Prüfe Zugriffsberechtigung für jeden Einsatz
        final hasAccess = await hasAccessToMission(mission);
        if (hasAccess) {
          missions.add(mission);
        }
      }

      return missions;
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze für Ausrüstung: $e');
      return [];
    }
  }

  // NEUE METHODE: Prüft ob Benutzer Zugriff auf bestimmten Einsatz hat
  Future<bool> hasAccessToMission(MissionModel mission) async {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();
      if (canViewAll) {
        return true; // Admin und Hygieneeinheit haben Zugriff auf alle Einsätze
      }

      // Normale Benutzer: Prüfe ob ihre Feuerwehr beteiligt ist
      final userFireStation = await _permissionService.getUserFireStation();
      if (userFireStation.isEmpty) return false;

      return mission.involvedFireStations.contains(userFireStation) ||
          mission.fireStation == userFireStation;
    } catch (e) {
      print('Fehler beim Prüfen des Einsatzzugriffs: $e');
      return false;
    }
  }

  // NEUE METHODE: Berechtigungsbasierte Einsatzabfrage nach Feuerwehrstationen
  Stream<List<MissionModel>> getMissionsByFireStations(
      List<String> fireStations) async* {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();

      if (canViewAll && fireStations.contains('Alle')) {
        // Admin/Hygieneeinheit kann alle Einsätze sehen
        yield* getAllMissions();
        return;
      }

      if (fireStations.isEmpty) {
        yield [];
        return;
      }

      // Einsätze abrufen, bei denen eine der angegebenen Feuerwehren beteiligt ist
      yield* _firestore
          .collection('missions')
          .where('involvedFireStations', arrayContainsAny: fireStations)
          .orderBy('startTime', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return MissionModel.fromMap(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze nach Feuerwehrstationen: $e');
      yield [];
    }
  }

  // NEUE METHODE: Einsätze nach Zeitraum mit Berechtigungsprüfung
  Stream<List<MissionModel>> getMissionsByDateRange(DateTime startDate,
      DateTime endDate) async* {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();

      Query query = _firestore
          .collection('missions')
          .where(
          'startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('startTime', descending: true);

      if (!canViewAll) {
        // Normale Benutzer sehen nur Einsätze ihrer Feuerwehr
        final userFireStation = await _permissionService.getUserFireStation();
        if (userFireStation.isNotEmpty) {
          query = query.where(
              'involvedFireStations', arrayContains: userFireStation);
        } else {
          yield [];
          return;
        }
      }

      yield* query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          return MissionModel.fromMap(
              doc.data() as Map<String, dynamic>, doc.id);
        }).toList();
      });
    } catch (e) {
      print('Fehler beim Abrufen der Einsätze nach Zeitraum: $e');
      yield [];
    }
  }

  // NEUE METHODE: Statistiken für autorisierte Benutzer
  Future<Map<String, dynamic>> getMissionStatistics() async {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();

      Query query = _firestore.collection('missions');

      if (!canViewAll) {
        final userFireStation = await _permissionService.getUserFireStation();
        if (userFireStation.isEmpty) {
          return {
            'total': 0,
            'byType': <String, int>{},
            'byMonth': <String, int>{},
          };
        }
        query =
            query.where('involvedFireStations', arrayContains: userFireStation);
      }

      QuerySnapshot snapshot = await query.get();

      Map<String, int> byType = {};
      Map<String, int> byMonth = {};

      for (var doc in snapshot.docs) {
        final mission = MissionModel.fromMap(
            doc.data() as Map<String, dynamic>, doc.id);

        // Nach Typ zählen
        byType[mission.type] = (byType[mission.type] ?? 0) + 1;

        // Nach Monat zählen
        final monthKey = DateFormat('yyyy-MM').format(mission.startTime);
        byMonth[monthKey] = (byMonth[monthKey] ?? 0) + 1;
      }

      return {
        'total': snapshot.docs.length,
        'byType': byType,
        'byMonth': byMonth,
      };
    } catch (e) {
      print('Fehler beim Abrufen der Einsatzstatistiken: $e');
      return {
        'total': 0,
        'byType': <String, int>{},
        'byMonth': <String, int>{},
      };
    }
  }

  // NEUE METHODE: Prüft ob Benutzer Einsatz bearbeiten kann
  Future<bool> canEditMission(String missionId) async {
    try {
      final isAdmin = await _permissionService.isAdmin();
      if (isAdmin) return true;

      // Weitere Logik könnte hier hinzugefügt werden, z.B.
      // ob der Benutzer der Ersteller des Einsatzes ist
      return false;
    } catch (e) {
      print('Fehler beim Prüfen der Bearbeitungsberechtigung: $e');
      return false;
    }
  }

  // NEUE METHODE: Suche nach Einsätzen mit Berechtigungsprüfung
  Future<List<MissionModel>> searchMissions(String searchTerm) async {
    try {
      final canViewAll = await _permissionService.canViewAllMissions();
      List<MissionModel> results = [];

      // Suche nach Namen
      QuerySnapshot nameQuery = await _firestore
          .collection('missions')
          .where('name', isGreaterThanOrEqualTo: searchTerm)
          .where('name', isLessThan: searchTerm + 'z')
          .get();

      // Suche nach Ort
      QuerySnapshot locationQuery = await _firestore
          .collection('missions')
          .where('location', isGreaterThanOrEqualTo: searchTerm)
          .where('location', isLessThan: searchTerm + 'z')
          .get();

      Set<String> addedIds = {};

      for (var doc in [...nameQuery.docs, ...locationQuery.docs]) {
        if (addedIds.contains(doc.id)) continue;

        final mission = MissionModel.fromMap(
            doc.data() as Map<String, dynamic>, doc.id);

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
  // UPDATED: Einsätze nach Feuerwehr abrufen - berücksichtigt jetzt auch involvedFireStations
  Stream<List<MissionModel>> getMissionsByFireStation(String fireStation) {
    return _firestore
        .collection('missions')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MissionModel.fromMap(
          doc.data() as Map<String, dynamic>, doc.id))
          .where((mission) {
        // Prüfe sowohl das Haupt-fireStation Feld als auch die involvedFireStations Liste
        return mission.fireStation == fireStation ||
            mission.involvedFireStations.contains(fireStation);
      })
          .toList();
    });
  }
}