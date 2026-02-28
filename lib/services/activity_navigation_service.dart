// services/activity_navigation_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/activity_model.dart';
import '../models/equipment_model.dart';
import '../screens/admin/equipment/equipment_detail_screen.dart';
import '../screens/missions/mission_detail_screen.dart';

class ActivityNavigationService {
  // Konfiguration
  static const bool _preferDetailDialogs = false; // Route-Navigation bevorzugen
  static const bool _showEquipmentListFallback = true;
  static const bool _showMissionListFallback = true;
  static const bool _debugMode = false;

  // Hauptnavigation basierend auf Aktivitätstyp
  static void navigateToActivity(BuildContext context, ActivityModel activity) {
    switch (activity.type) {
      case ActivityType.inspection:
      case ActivityType.statusChange:
      case ActivityType.creation:
      case ActivityType.update:
      case ActivityType.deletion:
        _handleEquipmentNavigation(context, activity);
        break;
      case ActivityType.mission:
        _handleMissionNavigation(context, activity);
        break;
      default:
        _showActivityDetailsDialog(context, activity);
    }
  }

  // Equipment-Navigation handhaben
  static void _handleEquipmentNavigation(BuildContext context, ActivityModel activity) {
    if (_preferDetailDialogs) {
      _showEquipmentDetailsDialog(context, activity);
    } else {
      // Lade Equipment-Daten und navigiere zu deiner existierenden Detail-Seite
      _loadEquipmentAndNavigate(context, activity);
    }
  }

  // Equipment laden und zu existierender Detail-Seite navigieren
  static Future<void> _loadEquipmentAndNavigate(BuildContext context, ActivityModel activity) async {
    try {
      // Zeige Loading-Indikator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Equipment-Daten aus Firestore laden
      DocumentSnapshot equipmentDoc = await FirebaseFirestore.instance
          .collection('equipment')
          .doc(activity.relatedId)
          .get();

      // Loading-Dialog schließen
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (equipmentDoc.exists && context.mounted) {
        Map<String, dynamic> data = equipmentDoc.data() as Map<String, dynamic>;

        // EquipmentModel erstellen
        EquipmentModel equipment = EquipmentModel(
          id: equipmentDoc.id,
          article: data['article'] ?? '',
          type: data['type'] ?? '',
          size: data['size'] ?? '',
          fireStation: data['fireStation'] ?? '',
          owner: data['owner'] ?? '',
          nfcTag: data['nfcTag'] ?? '',
          barcode: data['barcode'],
          status: data['status'] ?? 'Verfügbar',
          washCycles: data['washCycles'] ?? 0,
          checkDate: (data['checkDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          createdBy: data['createdBy'] ?? '',
        );

        // Zu deiner existierenden Equipment-Detail-Seite navigieren
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EquipmentDetailScreen(
              equipment: equipment,
            ),
          ),
        );

        // Zeige Toast basierend auf Aktivitätstyp
        _showActivityToast(context, activity);
      } else {
        // Equipment nicht gefunden - Fallback
        if (context.mounted) {
          _handleEquipmentNotFound(context, activity);
        }
      }
    } catch (e) {
      if (_debugMode) {
        print('Fehler beim Laden des Equipment: $e');
      }

      // Loading-Dialog schließen falls noch offen
      if (context.mounted) {
        Navigator.of(context).pop();
        _handleEquipmentNotFound(context, activity);
      }
    }
  }

  // Toast-Nachricht basierend auf Aktivitätstyp anzeigen
  static void _showActivityToast(BuildContext context, ActivityModel activity) {
    String message = '';
    Color color = Colors.blue;

    switch (activity.type) {
      case ActivityType.inspection:
        message = 'Equipment von Prüfungsaktivität geöffnet';
        color = Colors.green;
        break;
      case ActivityType.statusChange:
        message = 'Equipment von Statusänderung geöffnet';
        color = Colors.orange;
        break;
      case ActivityType.creation:
        message = 'Equipment von Erstellungsaktivität geöffnet';
        color = Colors.blue;
        break;
      case ActivityType.update:
        message = 'Equipment von Änderungsaktivität geöffnet';
        color = Colors.blue;
        break;
      case ActivityType.deletion:
        message = 'Equipment von Löschungsaktivität geöffnet';
        color = Colors.red;
        break;
      default:
        message = 'Equipment geöffnet';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(activity.icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Fallback wenn Equipment nicht gefunden wurde
  static void _handleEquipmentNotFound(BuildContext context, ActivityModel activity) {
    if (_showEquipmentListFallback && _tryNavigateToEquipmentList(context, activity.relatedId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equipment nicht gefunden. Suche in der Liste nach: ${activity.relatedId}'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      _showEquipmentDetailsDialog(context, activity);
    }
  }

  // Einsatz-Navigation handhaben
  static void _handleMissionNavigation(BuildContext context, ActivityModel activity) {
    if (_preferDetailDialogs) {
      _showMissionDetailsDialog(context, activity);
    } else {
      // Navigiere direkt zu deiner existierenden Mission-Detail-Seite
      _navigateToExistingMissionDetail(context, activity);
    }
  }

  // Versuche Navigation zu Equipment-Liste
  static bool _tryNavigateToEquipmentList(BuildContext context, String equipmentId) {
    try {
      Navigator.pushNamed(
        context,
        '/admin-equipment',
        arguments: {
          'searchQuery': equipmentId,
          'highlightId': equipmentId,
        },
      );
      return true;
    } catch (e) {
      if (_debugMode) {
        print('Equipment-Liste Route nicht verfügbar: $e');
      }
      return false;
    }
  }

  // Navigiere zu existierender Mission-Detail-Seite
  static void _navigateToExistingMissionDetail(BuildContext context, ActivityModel activity) {
    try {
      // Zu deiner existierenden Mission-Detail-Seite navigieren
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MissionDetailScreen(
            missionId: activity.relatedId,
          ),
        ),
      );

      // Toast-Nachricht für Mission-Navigation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(activity.icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text('Einsatz von Aktivität geöffnet'),
            ],
          ),
          backgroundColor: activity.color,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (_debugMode) {
        print('Fehler beim Öffnen der Mission-Detail-Seite: $e');
      }

      // Fallback zu Mission-Liste oder Dialog
      if (_showMissionListFallback && _tryNavigateToMissionsList(context, activity.relatedId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mission direkt nicht verfügbar. Suche in der Liste nach: ${activity.relatedId}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        _showMissionDetailsDialog(context, activity);
      }
    }
  }

  // Versuche Navigation zu Einsätze-Liste
  static bool _tryNavigateToMissionsList(BuildContext context, String missionId) {
    try {
      Navigator.pushNamed(
        context,
        '/missions',
        arguments: {
          'highlightId': missionId,
        },
      );
      return true;
    } catch (e) {
      if (_debugMode) {
        print('Missions-Liste Route nicht verfügbar: $e');
      }
      return false;
    }
  }

  // Equipment-Details Dialog (Fallback)
  static void _showEquipmentDetailsDialog(BuildContext context, ActivityModel activity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activity.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(activity.icon, color: activity.color),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Equipment-Aktivität')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Aktivität:', activity.title),
            _buildDetailRow('Details:', activity.description),
            _buildDetailRow('Durchgeführt von:', activity.performedBy),
            _buildDetailRow('Zeitpunkt:', _formatDateTime(activity.timestamp)),
            _buildDetailRow('Equipment-ID:', activity.relatedId),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _loadEquipmentAndNavigate(context, activity);
                    },
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Equipment laden'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (!_tryNavigateToEquipmentList(context, activity.relatedId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Equipment-ID: ${activity.relatedId}'),
                            action: SnackBarAction(label: 'OK', onPressed: () {}),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.list, size: 16),
                    label: const Text('Zur Liste'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  // Einsatzdetails Dialog (Fallback)
  static void _showMissionDetailsDialog(BuildContext context, ActivityModel activity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activity.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(activity.icon, color: activity.color),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Einsatzdetails')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Einsatz:', activity.title),
            _buildDetailRow('Details:', activity.description),
            _buildDetailRow('Erstellt von:', activity.performedBy),
            _buildDetailRow('Zeitpunkt:', _formatDateTime(activity.timestamp)),
            _buildDetailRow('Einsatz-ID:', activity.relatedId),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _navigateToExistingMissionDetail(context, activity);
                    },
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Einsatz öffnen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (!_tryNavigateToMissionsList(context, activity.relatedId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Einsatz-ID: ${activity.relatedId}'),
                            action: SnackBarAction(label: 'OK', onPressed: () {}),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.list, size: 16),
                    label: const Text('Zur Liste'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  // Allgemeine Aktivitätsdetails Dialog
  static void _showActivityDetailsDialog(BuildContext context, ActivityModel activity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activity.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(activity.icon, color: activity.color),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Aktivitätsdetails')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Aktivität:', activity.title),
            _buildDetailRow('Beschreibung:', activity.description),
            _buildDetailRow('Durchgeführt von:', activity.performedBy),
            _buildDetailRow('Zeitpunkt:', _formatDateTime(activity.timestamp)),
            _buildDetailRow('Typ:', _getTypeDisplayName(activity.type)),
            if (activity.relatedId.isNotEmpty)
              _buildDetailRow('Referenz-ID:', activity.relatedId),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  // Hilfsmethoden
  static Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  static String _getTypeDisplayName(ActivityType type) {
    switch (type) {
      case ActivityType.inspection:
        return 'Prüfung';
      case ActivityType.statusChange:
        return 'Statusänderung';
      case ActivityType.mission:
        return 'Einsatz';
      case ActivityType.creation:
        return 'Erstellung';
      case ActivityType.update:
        return 'Aktualisierung';
      case ActivityType.deletion:
        return 'Löschung';
      default:
        return 'Sonstige';
    }
  }
}