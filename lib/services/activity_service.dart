// services/activity_service.dart - Korrigierte Version mit Firestore-Berechtigungen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/activity_model.dart';

class ActivityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Neueste Aktivitäten abrufen (für die Home-Seite)
  Stream<List<ActivityModel>> getRecentActivities({int limit = 10}) async* {
    try {
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        yield [];
        return;
      }

      // Benutzerinformationen einmalig abrufen
      final userInfo = await _getUserInfo(currentUser.uid);
      if (userInfo == null) {
        yield [];
        return;
      }

      // Stream mit optimierten Abfragen
      yield* _getDirectActivitiesStream(
        isAdmin: userInfo['isAdmin'],
        userFireStation: userInfo['fireStation'],
        limit: limit,
      );

    } catch (e) {
      print('Fehler beim Abrufen der Aktivitäten: $e');
      yield [];
    }
  }

  // Benutzerinformationen einmalig abrufen
  Future<Map<String, dynamic>?> _getUserInfo(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return null;

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      String userFireStation = userData['fireStation'] ?? '';
      bool isAdmin = userData['role'] == 'Gemeindebrandmeister' ||
          userData['role'] == 'Stv. Gemeindebrandmeister' ||
          userData['role'] == 'Gemeindezeugwart';

      return {
        'isAdmin': isAdmin,
        'fireStation': userFireStation,
        'userData': userData,
      };
    } catch (e) {
      print('Fehler beim Laden der Benutzerinfo: $e');
      return null;
    }
  }

  // Direkter kombinierter Stream
  Stream<List<ActivityModel>> _getDirectActivitiesStream({
    required bool isAdmin,
    required String userFireStation,
    int limit = 10,
  }) async* {
    try {
      List<ActivityModel> allActivities = [];

      if (isAdmin) {
        // Admin: Alle Aktivitäten laden
        final results = await Future.wait([
          _loadInspectionsAdmin(limit),
          _loadHistoryAdmin(limit),
          _loadMissionsAdmin(limit),
        ]);

        allActivities.addAll(results[0] as List<ActivityModel>);
        allActivities.addAll(results[1] as List<ActivityModel>);
        allActivities.addAll(results[2] as List<ActivityModel>);
      } else {
        // Normale User: Nur über Equipment der eigenen Feuerwehr
        final results = await Future.wait([
          _loadActivitiesViaEquipment(userFireStation, limit),
          _loadMissionsForUser(userFireStation, limit),
        ]);

        allActivities.addAll(results[0] as List<ActivityModel>);
        allActivities.addAll(results[1] as List<ActivityModel>);
      }

      // Nach Datum sortieren und limitieren
      allActivities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (allActivities.length > limit) {
        allActivities = allActivities.sublist(0, limit);
      }

      yield allActivities;

    } catch (e) {
      print('Fehler beim Erstellen des direkten Streams: $e');
      yield [];
    }
  }

  // Für Admins: Direkte Abfrage aller Prüfungen
  Future<List<ActivityModel>> _loadInspectionsAdmin(int limit) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('equipment_inspections')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      List<ActivityModel> activities = [];

      for (var doc in snapshot.docs) {
        try {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String equipmentId = data['equipmentId'] ?? '';

          if (equipmentId.isEmpty) continue;

          String equipmentInfo = await _getEquipmentInfoDirect(equipmentId);
          String resultText = _getResultText(data['result']);
          DateTime timestamp = _parseTimestamp(data['createdAt']);

          activities.add(ActivityModel(
            id: doc.id,
            type: ActivityType.inspection,
            title: 'Prüfung durchgeführt',
            description: '$equipmentInfo - $resultText',
            timestamp: timestamp,
            icon: Icons.check_circle,
            color: Colors.green,
            relatedId: equipmentId,
            relatedType: 'equipment',
            performedBy: data['createdBy'] ?? 'Unbekannt',
          ));
        } catch (e) {
          print('Fehler bei Prüfung ${doc.id}: $e');
          continue;
        }
      }

      return activities;
    } catch (e) {
      print('Fehler beim Laden der Prüfungsaktivitäten (Admin): $e');
      return [];
    }
  }

  // Für Admins: Direkte Abfrage aller Historie-Einträge
  Future<List<ActivityModel>> _loadHistoryAdmin(int limit) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('equipment_history')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      List<ActivityModel> activities = [];

      for (var doc in snapshot.docs) {
        try {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String equipmentId = data['equipmentId'] ?? '';
          String action = data['action'] ?? '';
          String field = data['field'] ?? '';

          if (equipmentId.isEmpty) continue;

          String equipmentInfo = await _getEquipmentInfoDirect(equipmentId);
          DateTime timestamp = _parseTimestamp(data['timestamp']);

          // Aktivitätsdetails bestimmen
          var activityDetails = _getActivityDetails(action, field, data, equipmentInfo);

          activities.add(ActivityModel(
            id: doc.id,
            type: activityDetails['type'],
            title: activityDetails['title'],
            description: activityDetails['description'],
            timestamp: timestamp,
            icon: activityDetails['icon'],
            color: activityDetails['color'],
            relatedId: equipmentId,
            relatedType: 'equipment',
            performedBy: data['performedByName'] ?? 'Unbekannt',
          ));
        } catch (e) {
          print('Fehler bei Historie ${doc.id}: $e');
          continue;
        }
      }

      return activities;
    } catch (e) {
      print('Fehler beim Laden der Historie-Aktivitäten (Admin): $e');
      return [];
    }
  }

  // Für Admins: Direkte Abfrage aller Einsätze
  Future<List<ActivityModel>> _loadMissionsAdmin(int limit) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('missions')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return _processMissionDocuments(snapshot.docs);
    } catch (e) {
      print('Fehler beim Laden der Einsatzaktivitäten (Admin): $e');
      return [];
    }
  }

  // Für normale User: Aktivitäten über Equipment der eigenen Feuerwehr laden
  Future<List<ActivityModel>> _loadActivitiesViaEquipment(String userFireStation, int limit) async {
    try {
      // Erst Equipment der eigenen Feuerwehr laden
      QuerySnapshot equipmentSnapshot = await _firestore
          .collection('equipment')
          .where('fireStation', isEqualTo: userFireStation)
          .get();

      List<String> equipmentIds = equipmentSnapshot.docs.map((doc) => doc.id).toList();

      if (equipmentIds.isEmpty) {
        return [];
      }

      List<ActivityModel> allActivities = [];

      // Equipment-IDs in Batches aufteilen (Firestore Limit: 10 per "in" query)
      for (int i = 0; i < equipmentIds.length; i += 10) {
        int end = i + 10;
        if (end > equipmentIds.length) end = equipmentIds.length;
        List<String> batch = equipmentIds.sublist(i, end);

        // Prüfungen für diesen Batch laden
        try {
          QuerySnapshot inspectionsSnapshot = await _firestore
              .collection('equipment_inspections')
              .where('equipmentId', whereIn: batch)
              .orderBy('createdAt', descending: true)
              .limit(limit ~/ 2) // Aufteilen zwischen Prüfungen und Historie
              .get();

          for (var doc in inspectionsSnapshot.docs) {
            try {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              String equipmentId = data['equipmentId'] ?? '';

              String equipmentInfo = await _getEquipmentInfoDirect(equipmentId);
              String resultText = _getResultText(data['result']);
              DateTime timestamp = _parseTimestamp(data['createdAt']);

              allActivities.add(ActivityModel(
                id: doc.id,
                type: ActivityType.inspection,
                title: 'Prüfung durchgeführt',
                description: '$equipmentInfo - $resultText',
                timestamp: timestamp,
                icon: Icons.check_circle,
                color: Colors.green,
                relatedId: equipmentId,
                relatedType: 'equipment',
                performedBy: data['createdBy'] ?? 'Unbekannt',
              ));
            } catch (e) {
              print('Fehler bei Prüfung ${doc.id}: $e');
              continue;
            }
          }
        } catch (e) {
          print('Fehler beim Laden der Prüfungen für Batch: $e');
        }

        // Historie für diesen Batch laden
        try {
          QuerySnapshot historySnapshot = await _firestore
              .collection('equipment_history')
              .where('equipmentId', whereIn: batch)
              .orderBy('timestamp', descending: true)
              .limit(limit ~/ 2) // Aufteilen zwischen Prüfungen und Historie
              .get();

          for (var doc in historySnapshot.docs) {
            try {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              String equipmentId = data['equipmentId'] ?? '';
              String action = data['action'] ?? '';
              String field = data['field'] ?? '';

              String equipmentInfo = await _getEquipmentInfoDirect(equipmentId);
              DateTime timestamp = _parseTimestamp(data['timestamp']);

              var activityDetails = _getActivityDetails(action, field, data, equipmentInfo);

              allActivities.add(ActivityModel(
                id: doc.id,
                type: activityDetails['type'],
                title: activityDetails['title'],
                description: activityDetails['description'],
                timestamp: timestamp,
                icon: activityDetails['icon'],
                color: activityDetails['color'],
                relatedId: equipmentId,
                relatedType: 'equipment',
                performedBy: data['performedByName'] ?? 'Unbekannt',
              ));
            } catch (e) {
              print('Fehler bei Historie ${doc.id}: $e');
              continue;
            }
          }
        } catch (e) {
          print('Fehler beim Laden der Historie für Batch: $e');
        }
      }

      return allActivities;
    } catch (e) {
      print('Fehler beim Laden der Aktivitäten über Equipment: $e');
      return [];
    }
  }

  // Für normale User: Einsätze laden
  Future<List<ActivityModel>> _loadMissionsForUser(String userFireStation, int limit) async {
    try {
      List<ActivityModel> activities = [];

      // 1. Einsätze wo fireStation = userFireStation
      QuerySnapshot snapshot1 = await _firestore
          .collection('missions')
          .where('fireStation', isEqualTo: userFireStation)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      // 2. Einsätze wo involvedFireStations userFireStation enthält
      QuerySnapshot snapshot2 = await _firestore
          .collection('missions')
          .where('involvedFireStations', arrayContains: userFireStation)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      // Dokumente zusammenführen und doppelte entfernen
      Set<String> processedIds = {};
      List<QueryDocumentSnapshot> allDocs = [];

      for (var doc in snapshot1.docs) {
        if (!processedIds.contains(doc.id)) {
          allDocs.add(doc);
          processedIds.add(doc.id);
        }
      }

      for (var doc in snapshot2.docs) {
        if (!processedIds.contains(doc.id)) {
          allDocs.add(doc);
          processedIds.add(doc.id);
        }
      }

      // Nach Datum sortieren
      allDocs.sort((a, b) {
        DateTime aDate = _parseTimestamp((a.data() as Map<String, dynamic>)['createdAt']);
        DateTime bDate = _parseTimestamp((b.data() as Map<String, dynamic>)['createdAt']);
        return bDate.compareTo(aDate);
      });

      // Auf Limit beschränken
      if (allDocs.length > limit) {
        allDocs = allDocs.sublist(0, limit);
      }

      activities = _processMissionDocuments(allDocs);
      return activities;
    } catch (e) {
      print('Fehler beim Laden der Einsätze für User: $e');
      return [];
    }
  }

  // Mission-Dokumente verarbeiten
  List<ActivityModel> _processMissionDocuments(List<QueryDocumentSnapshot> docs) {
    List<ActivityModel> activities = [];

    for (var doc in docs) {
      try {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // Einsatztyp bestimmen
        String type = data['type'] ?? '';
        String typeText = 'Einsatz';
        IconData icon = Icons.assignment;
        Color color = Colors.blue;

        switch (type.toLowerCase()) {
          case 'fire':
            typeText = 'Brandeinsatz';
            icon = Icons.local_fire_department;
            color = Colors.red;
            break;
          case 'technical':
            typeText = 'Technische Hilfeleistung';
            icon = Icons.build;
            color = Colors.blue;
            break;
          case 'hazmat':
            typeText = 'Gefahrguteinsatz';
            icon = Icons.dangerous;
            color = Colors.orange;
            break;
          case 'water':
            typeText = 'Wassereinsatz';
            icon = Icons.water;
            color = Colors.lightBlue;
            break;
          case 'training':
            typeText = 'Übung';
            icon = Icons.school;
            color = Colors.green;
            break;
        }

        DateTime timestamp = _parseTimestamp(data['createdAt']);

        activities.add(ActivityModel(
          id: doc.id,
          type: ActivityType.mission,
          title: 'Neuer $typeText',
          description: '${data['name'] ?? 'Unbekannt'} in ${data['location'] ?? 'Unbekannt'}',
          timestamp: timestamp,
          icon: icon,
          color: color,
          relatedId: doc.id,
          relatedType: 'mission',
          performedBy: data['createdBy'] ?? 'Unbekannt',
        ));
      } catch (e) {
        print('Fehler bei Einsatz ${doc.id}: $e');
        continue;
      }
    }

    return activities;
  }

  // Aktivitätsdetails bestimmen
  Map<String, dynamic> _getActivityDetails(String action, String field, Map<String, dynamic> data, String equipmentInfo) {
    String title, description;
    IconData icon;
    Color color;
    ActivityType type;

    switch (action.toLowerCase()) {
      case 'erstellt':
        title = 'Ausrüstung angelegt';
        description = equipmentInfo;
        icon = Icons.add_circle;
        color = Colors.blue;
        type = ActivityType.creation;
        break;
      case 'aktualisiert':
        if (field.toLowerCase() == 'status') {
          title = 'Status geändert';
          description = '$equipmentInfo - ${data['oldValue'] ?? ''} → ${data['newValue'] ?? ''}';
          icon = Icons.swap_horiz;
          color = Colors.orange;
          type = ActivityType.statusChange;
        } else if (field.toLowerCase() == 'prüfdatum' || field.toLowerCase() == 'checkdate') {
          title = 'Prüfdatum geändert';
          description = '$equipmentInfo - ${_formatDateValue(data['oldValue'])} → ${_formatDateValue(data['newValue'])}';
          icon = Icons.event;
          color = Colors.purple;
          type = ActivityType.update;
        } else {
          title = '$field geändert';
          description = '$equipmentInfo - ${data['oldValue'] ?? ''} → ${data['newValue'] ?? ''}';
          icon = Icons.edit;
          color = Colors.blue;
          type = ActivityType.update;
        }
        break;
      case 'gelöscht':
        title = 'Ausrüstung gelöscht';
        description = data['oldValue'] ?? equipmentInfo;
        icon = Icons.delete;
        color = Colors.red;
        type = ActivityType.deletion;
        break;
      default:
        title = 'Sonstige Aktivität';
        description = '$field - $equipmentInfo';
        icon = Icons.info;
        color = Colors.grey;
        type = ActivityType.other;
    }

    return {
      'title': title,
      'description': description,
      'icon': icon,
      'color': color,
      'type': type,
    };
  }

  // Equipment-Info DIREKT aus Firestore laden
  Future<String> _getEquipmentInfoDirect(String equipmentId) async {
    try {
      DocumentSnapshot equipmentDoc = await _firestore
          .collection('equipment')
          .doc(equipmentId)
          .get();

      if (equipmentDoc.exists) {
        Map<String, dynamic> data = equipmentDoc.data() as Map<String, dynamic>;

        String article = data['article'] ?? 'Unbekannt';
        String owner = data['owner'] ?? 'Unbekannt';
        String fireStation = data['fireStation'] ?? 'Unbekannt';

        return '$article ($owner, $fireStation)';
      } else {
        return 'Equipment: $equipmentId (nicht gefunden)';
      }
    } catch (e) {
      print('Fehler beim Laden von Equipment $equipmentId: $e');
      return 'Equipment: $equipmentId (Fehler)';
    }
  }

  // Hilfsmethoden
  String _getResultText(dynamic result) {
    switch (result) {
      case 'passed':
        return 'Bestanden';
      case 'conditionalPass':
        return 'Bedingt bestanden';
      case 'failed':
        return 'Nicht bestanden';
      default:
        return 'Durchgeführt';
    }
  }

  DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();

    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is DateTime) {
      return timestamp;
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    }

    return DateTime.now();
  }

  String _formatDateValue(dynamic dateValue) {
    if (dateValue == null) return 'Nicht gesetzt';

    try {
      DateTime date;

      if (dateValue is Timestamp) {
        date = dateValue.toDate();
      } else if (dateValue is DateTime) {
        date = dateValue;
      } else if (dateValue is String) {
        date = DateTime.tryParse(dateValue) ?? DateTime.now();
      } else {
        return dateValue.toString();
      }

      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      print('Fehler beim Formatieren des Datumswerts: $e');
      return dateValue.toString();
    }
  }

  // Cache leeren (für Kompatibilität)
  void clearCache() {
    // Kein Cache mehr vorhanden
  }

  // Testaktivitäten für Fallbacks
  List<ActivityModel> getTestActivities() {
    return [
      ActivityModel(
        id: 'test_1',
        type: ActivityType.inspection,
        title: 'Prüfung durchgeführt',
        description: 'Einsatzjacke (Max Mustermann, Ihrhove) - Bestanden',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
        icon: Icons.check_circle,
        color: Colors.green,
        relatedId: 'test_equipment_1',
        relatedType: 'equipment',
        performedBy: 'Test User',
      ),
      ActivityModel(
        id: 'test_2',
        type: ActivityType.statusChange,
        title: 'Status geändert',
        description: 'Einsatzhose (Anna Schmidt, Westrhauderfehn) - Verfügbar → In Reinigung',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        icon: Icons.swap_horiz,
        color: Colors.orange,
        relatedId: 'test_equipment_2',
        relatedType: 'equipment',
        performedBy: 'Test User',
      ),
      ActivityModel(
        id: 'test_3',
        type: ActivityType.mission,
        title: 'Neuer Brandeinsatz',
        description: 'Brandeinsatz in Ihrhove Hauptstraße',
        timestamp: DateTime.now().subtract(const Duration(hours: 6)),
        icon: Icons.local_fire_department,
        color: Colors.red,
        relatedId: 'test_mission_1',
        relatedType: 'mission',
        performedBy: 'Test User',
      ),
      ActivityModel(
        id: 'test_4',
        type: ActivityType.update,
        title: 'Prüfdatum geändert',
        description: 'Einsatzstiefel (Peter Müller, Ihrhove) - 15.03.2024 → 15.03.2025',
        timestamp: DateTime.now().subtract(const Duration(hours: 8)),
        icon: Icons.event,
        color: Colors.purple,
        relatedId: 'test_equipment_3',
        relatedType: 'equipment',
        performedBy: 'Test User',
      ),
    ];
  }
}