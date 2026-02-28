// widgets/activity_action_sheet.dart
import 'package:flutter/material.dart';
import '../models/activity_model.dart';
import '../services/activity_navigation_service.dart';

class ActivityActionSheet {
  static void show(BuildContext context, ActivityModel activity) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Titel mit Icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: activity.color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      activity.icon,
                      color: activity.color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          activity.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Aktions-Buttons
            _buildActionButtons(context, activity),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static Widget _buildActionButtons(BuildContext context, ActivityModel activity) {
    List<Widget> actions = [];

    // Hauptaktion basierend auf Aktivitätstyp
    switch (activity.type) {
      case ActivityType.inspection:
        actions.addAll([
          _buildActionTile(
            context: context,
            icon: Icons.visibility,
            title: 'Prüfungsdetails anzeigen',
            subtitle: 'Equipment und Prüfungsergebnis',
            onTap: () {
              Navigator.pop(context);
              ActivityNavigationService.navigateToActivity(context, activity);
            },
          ),
          _buildActionTile(
            context: context,
            icon: Icons.inventory_2,
            title: 'Equipment anzeigen',
            subtitle: 'Zur Ausrüstungsübersicht',
            onTap: () {
              Navigator.pop(context);
              _navigateToEquipmentList(context, activity.relatedId);
            },
          ),
        ]);
        break;

      case ActivityType.statusChange:
      case ActivityType.update:
        actions.addAll([
          _buildActionTile(
            context: context,
            icon: Icons.history,
            title: 'Änderungsverlauf anzeigen',
            subtitle: 'Alle Änderungen zu diesem Equipment',
            onTap: () {
              Navigator.pop(context);
              ActivityNavigationService.navigateToActivity(context, activity);
            },
          ),
          _buildActionTile(
            context: context,
            icon: Icons.inventory_2,
            title: 'Equipment anzeigen',
            subtitle: 'Zur Ausrüstungsübersicht',
            onTap: () {
              Navigator.pop(context);
              _navigateToEquipmentList(context, activity.relatedId);
            },
          ),
        ]);
        break;

      case ActivityType.mission:
        actions.addAll([
          _buildActionTile(
            context: context,
            icon: Icons.local_fire_department,
            title: 'Einsatzdetails anzeigen',
            subtitle: 'Vollständige Einsatzinformationen',
            onTap: () {
              Navigator.pop(context);
              ActivityNavigationService.navigateToActivity(context, activity);
            },
          ),
          _buildActionTile(
            context: context,
            icon: Icons.list,
            title: 'Alle Einsätze anzeigen',
            subtitle: 'Zur Einsatzübersicht',
            onTap: () {
              Navigator.pop(context);
              _navigateToMissionsList(context, activity.relatedId);
            },
          ),
        ]);
        break;

      default:
        actions.add(
          _buildActionTile(
            context: context,
            icon: Icons.info,
            title: 'Details anzeigen',
            subtitle: 'Vollständige Informationen',
            onTap: () {
              Navigator.pop(context);
              ActivityNavigationService.navigateToActivity(context, activity);
            },
          ),
        );
    }

    // Allgemeine Aktionen
    actions.addAll([
      const Divider(),
      _buildActionTile(
        context: context,
        icon: Icons.share,
        title: 'Aktivität teilen',
        subtitle: 'Als Text oder Screenshot',
        onTap: () {
          Navigator.pop(context);
          _shareActivity(context, activity);
        },
      ),
      _buildActionTile(
        context: context,
        icon: Icons.copy,
        title: 'ID kopieren',
        subtitle: activity.relatedId.isNotEmpty ? activity.relatedId : activity.id,
        onTap: () {
          Navigator.pop(context);
          _copyToClipboard(context, activity);
        },
      ),
    ]);

    return Column(children: actions);
  }

  static Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }

  // Hilfsmethoden
  static void _navigateToEquipmentList(BuildContext context, String equipmentId) {
    try {
      Navigator.pushNamed(
        context,
        '/admin-equipment',
        arguments: {'highlightId': equipmentId},
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equipment-ID: $equipmentId'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
  }

  static void _navigateToMissionsList(BuildContext context, String missionId) {
    try {
      Navigator.pushNamed(
        context,
        '/missions',
        arguments: {'highlightId': missionId},
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Einsatz-ID: $missionId'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
  }

  static void _shareActivity(BuildContext context, ActivityModel activity) {
    final String shareText = '''
Aktivität: ${activity.title}
Details: ${activity.description}
Durchgeführt von: ${activity.performedBy}
Zeitpunkt: ${_formatDateTime(activity.timestamp)}
${activity.relatedId.isNotEmpty ? 'ID: ${activity.relatedId}' : ''}
''';

    // Hier könntest du ein Share-Plugin verwenden
    // Für jetzt: Kopiere in die Zwischenablage
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aktivitätsdetails wurden kopiert'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static void _copyToClipboard(BuildContext context, ActivityModel activity) {
    final String idToCopy = activity.relatedId.isNotEmpty ? activity.relatedId : activity.id;

    // Hier könntest du Clipboard.setData verwenden
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ID kopiert: $idToCopy'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

// Verwendung im RecentActivitiesWidget:
// Für Long-Press oder alternativen Zugang zu mehr Optionen