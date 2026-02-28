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

  // Factory constructor für Firebase-Daten
  factory ActivityModel.fromFirestore(Map<String, dynamic> data, String id) {
    return ActivityModel(
      id: id,
      type: _parseActivityType(data['type'] ?? ''),
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      timestamp: _parseTimestamp(data['timestamp']),
      icon: _parseIcon(data['icon']),
      color: _parseColor(data['color']),
      relatedId: data['relatedId'] ?? '',
      relatedType: data['relatedType'] ?? '',
      performedBy: data['performedBy'] ?? '',
    );
  }

  // Hilfsmethoden für das Parsing
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

    if (timestamp is DateTime) {
      return timestamp;
    } else if (timestamp.runtimeType.toString().contains('Timestamp')) {
      // Firebase Timestamp
      return timestamp.toDate();
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    } else if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }

    return DateTime.now();
  }

  static IconData _parseIcon(dynamic iconData) {
    // Standardicon zurückgeben, da IconData nicht einfach serialisiert werden kann
    return Icons.info;
  }

  static Color _parseColor(dynamic colorData) {
    // Standardfarbe zurückgeben, da Color nicht einfach serialisiert werden kann
    return Colors.blue;
  }

  // Zu Firestore-Map konvertieren
  Map<String, dynamic> toFirestore() {
    return {
      'type': type.toString().split('.').last,
      'title': title,
      'description': description,
      'timestamp': timestamp,
      'relatedId': relatedId,
      'relatedType': relatedType,
      'performedBy': performedBy,
    };
  }

  @override
  String toString() {
    return 'ActivityModel(id: $id, type: $type, title: $title, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActivityModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}