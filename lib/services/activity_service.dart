// services/activity_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/activity_model.dart';
import '../models/user_models.dart';
import 'permission_service.dart';

class ActivityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionService _permissionService = PermissionService();

  // ── Öffentliche API ───────────────────────────────────────────────────────

  Stream<List<ActivityModel>> getRecentActivities({int limit = 10}) async* {
    try {
      if (_auth.currentUser == null) { yield []; return; }

      // Einmaliger User-Abruf — kein rollenbasiertes Lookup mehr
      final user = await _permissionService.getCurrentUser();
      if (user == null) { yield []; return; }

      yield* _buildActivityStream(user: user, limit: limit);
    } catch (e) {
      print('Fehler getRecentActivities: $e');
      yield [];
    }
  }

  // ── Interner Stream-Aufbau ────────────────────────────────────────────────

  Stream<List<ActivityModel>> _buildActivityStream({
    required UserModel user,
    required int limit,
  }) async* {
    try {
      final bool showAll = user.isAdmin ||
          user.permissions.visibleFireStations.contains('*');

      // Sichtbare Stationen ermitteln
      final stations = <String>{user.fireStation};
      if (!showAll) stations.addAll(user.permissions.visibleFireStations);

      List<ActivityModel> all = [];

      if (showAll) {
        // Admin: alle Quellen direkt abfragen
        final results = await Future.wait([
          if (user.isAdmin || user.permissions.equipmentView)
            _loadInspectionsAll(limit),
          if (user.isAdmin || user.permissions.equipmentView)
            _loadHistoryAll(limit),
          if (user.isAdmin || user.permissions.missionView)
            _loadMissionsAll(limit),
        ]);
        for (final r in results) {
          all.addAll(r);
        }
      } else {
        // User mit eingeschränkten Stationen
        final futures = <Future<List<ActivityModel>>>[];

        if (user.permissions.equipmentView) {
          for (final station in stations) {
            futures.add(_loadActivitiesForStation(station, limit));
          }
        }

        if (user.permissions.missionView) {
          futures.add(_loadMissionsForStations(stations.toList(), limit));
        }

        final results = await Future.wait(futures);
        for (final r in results) {
          all.addAll(r);
        }
      }

      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (all.length > limit) all = all.sublist(0, limit);

      yield all;
    } catch (e) {
      print('Fehler _buildActivityStream: $e');
      yield [];
    }
  }

  // ── Lade-Methoden ─────────────────────────────────────────────────────────

  Future<List<ActivityModel>> _loadInspectionsAll(int limit) async {
    try {
      final snap = await _firestore
          .collection('equipment_inspections')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final List<ActivityModel> activities = [];
      for (final doc in snap.docs) {
        try {
          final data = doc.data();
          final equipmentId = data['equipmentId'] ?? '';
          if (equipmentId.isEmpty) continue;

          final equipmentInfo = await _getEquipmentInfo(equipmentId);
          activities.add(ActivityModel(
            id: doc.id,
            type: ActivityType.inspection,
            title: 'Prüfung durchgeführt',
            description:
                '$equipmentInfo — ${_getResultText(data['result'])}',
            timestamp: _parseTimestamp(data['createdAt']),
            icon: Icons.check_circle,
            color: Colors.green,
            relatedId: equipmentId,
            relatedType: 'equipment',
            performedBy: data['createdBy'] ?? 'Unbekannt',
          ));
        } catch (_) {}
      }
      return activities;
    } catch (e) {
      print('Fehler _loadInspectionsAll: $e');
      return [];
    }
  }

  Future<List<ActivityModel>> _loadHistoryAll(int limit) async {
    try {
      final snap = await _firestore
          .collection('equipment_history')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      final List<ActivityModel> activities = [];
      for (final doc in snap.docs) {
        try {
          final data = doc.data();
          final equipmentId = data['equipmentId'] ?? '';
          if (equipmentId.isEmpty) continue;

          final equipmentInfo = await _getEquipmentInfo(equipmentId);
          final details = _getActivityDetails(
              data['action'] ?? '', data['field'] ?? '', data, equipmentInfo);

          activities.add(ActivityModel(
            id: doc.id,
            type: details['type'],
            title: details['title'],
            description: details['description'],
            timestamp: _parseTimestamp(data['timestamp']),
            icon: details['icon'],
            color: details['color'],
            relatedId: equipmentId,
            relatedType: 'equipment',
            performedBy: data['performedByName'] ?? 'Unbekannt',
          ));
        } catch (_) {}
      }
      return activities;
    } catch (e) {
      print('Fehler _loadHistoryAll: $e');
      return [];
    }
  }

  Future<List<ActivityModel>> _loadMissionsAll(int limit) async {
    try {
      final snap = await _firestore
          .collection('missions')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return _processMissionDocs(snap.docs);
    } catch (e) {
      print('Fehler _loadMissionsAll: $e');
      return [];
    }
  }

  // Aktivitäten für eine bestimmte Station via Equipment-IDs
  Future<List<ActivityModel>> _loadActivitiesForStation(
      String station, int limit) async {
    try {
      final equipSnap = await _firestore
          .collection('equipment')
          .where('fireStation', isEqualTo: station)
          .get();

      final ids = equipSnap.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return [];

      final List<ActivityModel> activities = [];

      // In Batches à 10 (Firestore whereIn-Limit)
      for (int i = 0; i < ids.length; i += 10) {
        final batch = ids.sublist(
            i, i + 10 > ids.length ? ids.length : i + 10);

        try {
          final inspSnap = await _firestore
              .collection('equipment_inspections')
              .where('equipmentId', whereIn: batch)
              .orderBy('createdAt', descending: true)
              .limit(limit ~/ 2)
              .get();

          for (final doc in inspSnap.docs) {
            try {
              final data = doc.data();
              final equipmentId = data['equipmentId'] ?? '';
              final info = await _getEquipmentInfo(equipmentId);

              activities.add(ActivityModel(
                id: doc.id,
                type: ActivityType.inspection,
                title: 'Prüfung durchgeführt',
                description: '$info — ${_getResultText(data['result'])}',
                timestamp: _parseTimestamp(data['createdAt']),
                icon: Icons.check_circle,
                color: Colors.green,
                relatedId: equipmentId,
                relatedType: 'equipment',
                performedBy: data['createdBy'] ?? 'Unbekannt',
              ));
            } catch (_) {}
          }
        } catch (_) {}
      }

      return activities;
    } catch (e) {
      print('Fehler _loadActivitiesForStation: $e');
      return [];
    }
  }

  Future<List<ActivityModel>> _loadMissionsForStations(
      List<String> stations, int limit) async {
    try {
      final snap = await _firestore
          .collection('missions')
          .where('involvedFireStations', arrayContainsAny: stations)
          .orderBy('startTime', descending: true)
          .limit(limit)
          .get();
      return _processMissionDocs(snap.docs);
    } catch (e) {
      print('Fehler _loadMissionsForStations: $e');
      return [];
    }
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  List<ActivityModel> _processMissionDocs(
      List<QueryDocumentSnapshot> docs) {
    final List<ActivityModel> activities = [];
    for (final doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final type = data['type'] ?? '';

        final typeMap = {
          'fire': ('Brandeinsatz', Icons.local_fire_department, Colors.red),
          'technical': ('Technische Hilfeleistung', Icons.build, Colors.blue),
          'hazmat': ('Gefahrguteinsatz', Icons.dangerous, Colors.orange),
          'water': ('Wassereinsatz', Icons.water, Colors.lightBlue),
          'training': ('Übung', Icons.school, Colors.green),
        };

        final (typeText, icon, color) =
            typeMap[type] ?? ('Einsatz', Icons.assignment, Colors.grey);

        activities.add(ActivityModel(
          id: doc.id,
          type: ActivityType.mission,
          title: 'Neuer $typeText',
          description:
              '${data['name'] ?? 'Unbekannt'} in ${data['location'] ?? 'Unbekannt'}',
          timestamp: _parseTimestamp(data['createdAt']),
          icon: icon,
          color: color,
          relatedId: doc.id,
          relatedType: 'mission',
          performedBy: data['createdBy'] ?? 'Unbekannt',
        ));
      } catch (_) {}
    }
    return activities;
  }

  // Equipment-Info aus Cache oder Firestore
  final Map<String, String> _equipmentCache = {};

  void clearCache() => _equipmentCache.clear();

  Future<String> _getEquipmentInfo(String equipmentId) async {
    if (_equipmentCache.containsKey(equipmentId)) {
      return _equipmentCache[equipmentId]!;
    }
    try {
      final doc = await _firestore
          .collection('equipment')
          .doc(equipmentId)
          .get();
      if (!doc.exists) return 'Unbekannte Ausrüstung';
      final data = doc.data()!;
      final info =
          '${data['article'] ?? 'Unbekannt'} (${data['owner'] ?? 'Unbekannt'})';
      _equipmentCache[equipmentId] = info;
      return info;
    } catch (e) {
      return 'Unbekannte Ausrüstung';
    }
  }

  Map<String, dynamic> _getActivityDetails(String action, String field,
      Map<String, dynamic> data, String equipmentInfo) {
    switch (action.toLowerCase()) {
      case 'erstellt':
        return {
          'type': ActivityType.creation,
          'title': 'Ausrüstung angelegt',
          'description': equipmentInfo,
          'icon': Icons.add_circle,
          'color': Colors.blue,
        };
      case 'aktualisiert':
        if (field.toLowerCase() == 'status') {
          return {
            'type': ActivityType.statusChange,
            'title': 'Status geändert',
            'description':
                '$equipmentInfo — ${data['oldValue'] ?? ''} → ${data['newValue'] ?? ''}',
            'icon': Icons.swap_horiz,
            'color': Colors.orange,
          };
        }
        return {
          'type': ActivityType.update,
          'title': '$field geändert',
          'description':
              '$equipmentInfo — ${data['oldValue'] ?? ''} → ${data['newValue'] ?? ''}',
          'icon': Icons.edit,
          'color': Colors.purple,
        };
      default:
        return {
          'type': ActivityType.update,
          'title': 'Änderung',
          'description': equipmentInfo,
          'icon': Icons.info,
          'color': Colors.grey,
        };
    }
  }

  DateTime _parseTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return DateTime.now();
  }

  String _getResultText(dynamic result) {
    switch (result?.toString()) {
      case 'passed':
        return 'Bestanden ✓';
      case 'conditionalPass':
        return 'Bedingt bestanden ⚠';
      case 'failed':
        return 'Durchgefallen ✗';
      default:
        return result?.toString() ?? 'Unbekannt';
    }
  }
}
