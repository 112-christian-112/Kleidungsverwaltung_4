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

  /// Stream der letzten [limit] Aktivitäten.
  ///
  /// FIX: Vorher wurden alle Quellen ohne Limit per Future.wait geladen.
  /// Jetzt gilt [limit] pro Quelle — nie mehr als nötig aus Firestore lesen.
  Stream<List<ActivityModel>> getRecentActivities({int limit = 10}) async* {
    try {
      if (_auth.currentUser == null) { yield []; return; }

      final user = await _permissionService.getCurrentUser();
      if (user == null) { yield []; return; }

      yield* _buildActivityStream(user: user, limit: limit);
    } catch (e) {
      assert(() { print('Fehler getRecentActivities: $e'); return true; }());
      yield [];
    }
  }

  /// Paginierte Aktivitäten — für "Alle anzeigen"-Screens.
  ///
  /// [startAfterTimestamp]: letzter Zeitstempel der vorherigen Seite (Cursor).
  /// Null = erste Seite.
  Future<List<ActivityModel>> getActivitiesPaginated({
    required UserModel user,
    int limit = 20,
    DateTime? startAfterTimestamp,
  }) async {
    try {
      final bool showAll = user.isAdmin ||
          user.permissions.visibleFireStations.contains('*');

      final stations = <String>{user.fireStation};
      if (!showAll) stations.addAll(user.permissions.visibleFireStations);

      final results = await Future.wait([
        if (showAll || user.permissions.equipmentView)
          _loadInspectionsAll(limit,
              startAfter: startAfterTimestamp),
        if (showAll || user.permissions.equipmentView)
          _loadHistoryAll(limit,
              startAfter: startAfterTimestamp),
        if (showAll || user.permissions.missionView)
          _loadMissionsAll(limit,
              startAfter: startAfterTimestamp),
      ]);

      var all = <ActivityModel>[];
      for (final r in results) {
        all.addAll(r);
      }

      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (all.length > limit) all = all.sublist(0, limit);
      return all;
    } catch (e) {
      assert(() { print('Fehler getActivitiesPaginated: $e'); return true; }());
      return [];
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

      final stations = <String>{user.fireStation};
      if (!showAll) stations.addAll(user.permissions.visibleFireStations);

      List<ActivityModel> all = [];

      if (showAll) {
        // Admin: alle Quellen parallel abfragen
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
      assert(() { print('Fehler _buildActivityStream: $e'); return true; }());
      yield [];
    }
  }

  // ── Lade-Methoden ─────────────────────────────────────────────────────────

  /// FIX: [startAfter] ermöglicht Cursor-basierte Pagination.
  /// FIX: Equipment-Infos werden parallel abgerufen statt sequenziell.
  Future<List<ActivityModel>> _loadInspectionsAll(
    int limit, {
    DateTime? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('equipment_inspections')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfter([Timestamp.fromDate(startAfter)]);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) return [];

      // FIX: Equipment-IDs sammeln und alle parallel abrufen
      final equipmentIds = snap.docs
          .map((d) => (d.data() as Map<String, dynamic>)['equipmentId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      await _prefetchEquipmentInfos(equipmentIds);

      final List<ActivityModel> activities = [];
      for (final doc in snap.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final equipmentId = data['equipmentId'] as String? ?? '';
          if (equipmentId.isEmpty) continue;

          final equipmentInfo = await _getEquipmentInfo(equipmentId);
          activities.add(ActivityModel(
            id: doc.id,
            type: ActivityType.inspection,
            title: 'Prüfung durchgeführt',
            description: '$equipmentInfo — ${_getResultText(data['result'])}',
            timestamp: _parseTimestamp(data['createdAt']),
            icon: Icons.check_circle,
            color: Colors.green,
            relatedId: equipmentId,
            relatedType: 'equipment',
            performedBy: data['createdBy'] as String? ?? 'Unbekannt',
          ));
        } catch (_) {}
      }
      return activities;
    } catch (e) {
      assert(() { print('Fehler _loadInspectionsAll: $e'); return true; }());
      return [];
    }
  }

  Future<List<ActivityModel>> _loadHistoryAll(
    int limit, {
    DateTime? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('equipment_history')
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfter([Timestamp.fromDate(startAfter)]);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) return [];

      // Parallel prefetch
      final equipmentIds = snap.docs
          .map((d) => (d.data() as Map<String, dynamic>)['equipmentId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      await _prefetchEquipmentInfos(equipmentIds);

      final List<ActivityModel> activities = [];
      for (final doc in snap.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final equipmentId = data['equipmentId'] as String? ?? '';
          if (equipmentId.isEmpty) continue;

          final equipmentInfo = await _getEquipmentInfo(equipmentId);
          final details = _getActivityDetails(
              data['action'] as String? ?? '',
              data['field'] as String? ?? '',
              data,
              equipmentInfo);

          activities.add(ActivityModel(
            id: doc.id,
            type: details['type'] as ActivityType,
            title: details['title'] as String,
            description: details['description'] as String,
            timestamp: _parseTimestamp(data['timestamp']),
            icon: details['icon'] as IconData,
            color: details['color'] as Color,
            relatedId: equipmentId,
            relatedType: 'equipment',
            performedBy: data['performedByName'] as String? ?? 'Unbekannt',
          ));
        } catch (_) {}
      }
      return activities;
    } catch (e) {
      assert(() { print('Fehler _loadHistoryAll: $e'); return true; }());
      return [];
    }
  }

  Future<List<ActivityModel>> _loadMissionsAll(
    int limit, {
    DateTime? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('missions')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfter([Timestamp.fromDate(startAfter)]);
      }

      final snap = await query.get();
      return _processMissionDocs(snap.docs);
    } catch (e) {
      assert(() { print('Fehler _loadMissionsAll: $e'); return true; }());
      return [];
    }
  }

  Future<List<ActivityModel>> _loadActivitiesForStation(
      String station, int limit) async {
    try {
      final equipSnap = await _firestore
          .collection('equipment')
          .where('fireStation', isEqualTo: station)
          .get();

      final ids = equipSnap.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return [];

      // Equipment-Infos vorab in Cache laden
      await _prefetchEquipmentInfos(ids);

      final List<ActivityModel> activities = [];

      for (int i = 0; i < ids.length; i += 10) {
        final batch = ids.sublist(i, (i + 10).clamp(0, ids.length));

        try {
          final inspSnap = await _firestore
              .collection('equipment_inspections')
              .where('equipmentId', whereIn: batch)
              .orderBy('createdAt', descending: true)
              .limit(limit ~/ 2)
              .get();

          for (final doc in inspSnap.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final equipmentId = data['equipmentId'] as String? ?? '';
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
                performedBy: data['createdBy'] as String? ?? 'Unbekannt',
              ));
            } catch (_) {}
          }
        } catch (_) {}
      }

      return activities;
    } catch (e) {
      assert(() { print('Fehler _loadActivitiesForStation: $e'); return true; }());
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
      assert(() { print('Fehler _loadMissionsForStations: $e'); return true; }());
      return [];
    }
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  List<ActivityModel> _processMissionDocs(List<QueryDocumentSnapshot> docs) {
    final List<ActivityModel> activities = [];
    for (final doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final type = data['type'] as String? ?? '';

        final typeMap = {
          'fire':     ('Brandeinsatz',           Icons.local_fire_department, Colors.red),
          'technical':('Technische Hilfeleistung',Icons.build,                Colors.blue),
          'hazmat':   ('Gefahrguteinsatz',        Icons.dangerous,            Colors.orange),
          'water':    ('Wassereinsatz',            Icons.water,                Colors.lightBlue),
          'training': ('Übung',                   Icons.school,               Colors.green),
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
          performedBy: data['createdBy'] as String? ?? 'Unbekannt',
        ));
      } catch (_) {}
    }
    return activities;
  }

  // ── Equipment-Cache ────────────────────────────────────────────────────────

  final Map<String, String> _equipmentCache = {};

  void clearCache() => _equipmentCache.clear();

  /// FIX: Alle IDs die noch nicht im Cache sind parallel fetchen.
  /// Vorher: sequenzielle await-Aufrufe pro Item = N serielle Firestore-Reads.
  /// Jetzt: alle uncached IDs in einem Future.wait → 1 Runde statt N.
  Future<void> _prefetchEquipmentInfos(List<String> ids) async {
    final uncached = ids.where((id) => !_equipmentCache.containsKey(id)).toList();
    if (uncached.isEmpty) return;

    await Future.wait(uncached.map(_fetchAndCacheEquipmentInfo));
  }

  Future<void> _fetchAndCacheEquipmentInfo(String equipmentId) async {
    try {
      final doc = await _firestore.collection('equipment').doc(equipmentId).get();
      if (!doc.exists) {
        _equipmentCache[equipmentId] = 'Unbekannte Ausrüstung';
        return;
      }
      final data = doc.data()!;
      _equipmentCache[equipmentId] =
          '${data['article'] ?? 'Unbekannt'} (${data['owner'] ?? 'Unbekannt'})';
    } catch (_) {
      _equipmentCache[equipmentId] = 'Unbekannte Ausrüstung';
    }
  }

  Future<String> _getEquipmentInfo(String equipmentId) async {
    if (_equipmentCache.containsKey(equipmentId)) {
      return _equipmentCache[equipmentId]!;
    }
    await _fetchAndCacheEquipmentInfo(equipmentId);
    return _equipmentCache[equipmentId] ?? 'Unbekannte Ausrüstung';
  }

  // ── Detail-Mapping ────────────────────────────────────────────────────────

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
      case 'passed':        return 'Bestanden ✓';
      case 'conditionalPass': return 'Bedingt bestanden ⚠';
      case 'failed':        return 'Durchgefallen ✗';
      default: return result?.toString() ?? 'Unbekannt';
    }
  }
}
