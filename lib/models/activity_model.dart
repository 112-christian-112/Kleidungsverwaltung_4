// models/activity_model.dart
import 'package:flutter/material.dart';

enum ActivityType {
  inspection,
  statusChange,
  mission,
  creation,
  update,
  deletion,
  other,
}

class ActivityModel {
  final String id;
  final ActivityType type;
  final String title;
  final String description;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String relatedId;
  final String relatedType;
  final String performedBy;

  ActivityModel({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.relatedId,
    required this.relatedType,
    required this.performedBy,
  });

  /// Factory constructor für Firestore-Daten.
  ///
  /// FIX: Icon und Farbe werden nicht aus Firestore gelesen (IconData/Color
  /// sind nicht serialisierbar), sondern aus dem ActivityType abgeleitet.
  /// Vorher gaben _parseIcon() und _parseColor() immer Icons.info / Colors.blue
  /// zurück — unabhängig vom tatsächlichen Aktivitätstyp.
  ///
  /// Ausnahme: Einsatz-Aktivitäten haben typ-spezifische Icons (Feuer, Wasser
  /// etc.) die der ActivityService beim Erstellen setzt. Diese werden über das
  /// optionale [iconCodePoint]-Feld aus Firestore wiederhergestellt, falls
  /// vorhanden — andernfalls greift der Typ-Fallback.
  factory ActivityModel.fromFirestore(Map<String, dynamic> data, String id) {
    final type = _parseActivityType(data['type'] ?? '');

    // Icon: gespeicherter codePoint hat Vorrang, sonst Typ-Fallback
    final iconCodePoint = data['iconCodePoint'] as int?;
    final iconFontFamily = data['iconFontFamily'] as String?;
    final IconData icon = iconCodePoint != null
        ? IconData(iconCodePoint,
            fontFamily: iconFontFamily ?? 'MaterialIcons')
        : _iconForType(type);

    // Farbe: gespeicherter ARGB-Wert hat Vorrang, sonst Typ-Fallback
    final colorValue = data['colorValue'] as int?;
    final Color color =
        colorValue != null ? Color(colorValue) : _colorForType(type);

    return ActivityModel(
      id: id,
      type: type,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      timestamp: _parseTimestamp(data['timestamp']),
      icon: icon,
      color: color,
      relatedId: data['relatedId'] ?? '',
      relatedType: data['relatedType'] ?? '',
      performedBy: data['performedBy'] ?? '',
    );
  }

  /// Zu Firestore-Map konvertieren.
  ///
  /// FIX: iconCodePoint und colorValue werden jetzt mitgespeichert,
  /// damit typ-spezifische Icons (z.B. Einsatztypen) beim Lesen
  /// korrekt wiederhergestellt werden können.
  Map<String, dynamic> toFirestore() {
    return {
      'type': type.toString().split('.').last,
      'title': title,
      'description': description,
      'timestamp': timestamp,
      'relatedId': relatedId,
      'relatedType': relatedType,
      'performedBy': performedBy,
      // Icon als codePoint serialisieren
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      // Farbe als ARGB-Integer serialisieren
      'colorValue': color.value,
    };
  }

  // ── Typ-Ableitungen ────────────────────────────────────────────────────────

  /// Standardicon pro ActivityType — Fallback wenn kein gespeicherter codePoint.
  static IconData _iconForType(ActivityType type) {
    switch (type) {
      case ActivityType.inspection:
        return Icons.check_circle;
      case ActivityType.statusChange:
        return Icons.swap_horiz;
      case ActivityType.mission:
        return Icons.local_fire_department;
      case ActivityType.creation:
        return Icons.add_circle;
      case ActivityType.update:
        return Icons.edit;
      case ActivityType.deletion:
        return Icons.delete;
      case ActivityType.other:
        return Icons.info;
    }
  }

  /// Standardfarbe pro ActivityType — Fallback wenn kein gespeicherter colorValue.
  static Color _colorForType(ActivityType type) {
    switch (type) {
      case ActivityType.inspection:
        return Colors.green;
      case ActivityType.statusChange:
        return Colors.orange;
      case ActivityType.mission:
        return Colors.red;
      case ActivityType.creation:
        return Colors.blue;
      case ActivityType.update:
        return Colors.indigo;
      case ActivityType.deletion:
        return Colors.red.shade700;
      case ActivityType.other:
        return Colors.grey;
    }
  }

  // ── Parsing-Hilfsmethoden ──────────────────────────────────────────────────

  static ActivityType _parseActivityType(String type) {
    switch (type.toLowerCase()) {
      case 'inspection':
        return ActivityType.inspection;
      case 'statuschange':
        return ActivityType.statusChange;
      case 'mission':
        return ActivityType.mission;
      case 'creation':
        return ActivityType.creation;
      case 'update':
        return ActivityType.update;
      case 'deletion':
        return ActivityType.deletion;
      default:
        return ActivityType.other;
    }
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    if (timestamp is DateTime) return timestamp;
    if (timestamp.runtimeType.toString().contains('Timestamp')) {
      return timestamp.toDate();
    }
    if (timestamp is String) return DateTime.tryParse(timestamp) ?? DateTime.now();
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now();
  }

  // ── Gleichheit ─────────────────────────────────────────────────────────────

  @override
  String toString() =>
      'ActivityModel(id: $id, type: $type, title: $title, timestamp: $timestamp)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActivityModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
