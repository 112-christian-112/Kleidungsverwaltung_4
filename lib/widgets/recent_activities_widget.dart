// widgets/recent_activities_widget.dart
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/activity_model.dart';
import '../services/activity_service.dart';
import '../services/activity_navigation_service.dart';
import '../widgets/activity_action_sheet.dart';

class RecentActivitiesWidget extends StatefulWidget {
  final int limit;

  const RecentActivitiesWidget({
    Key? key,
    this.limit = 3,
  }) : super(key: key);

  @override
  State<RecentActivitiesWidget> createState() => _RecentActivitiesWidgetState();
}

class _RecentActivitiesWidgetState extends State<RecentActivitiesWidget> {
  final ActivityService _activityService = ActivityService();
  List<ActivityModel> _cachedActivities = [];
  bool _isInitialLoad = true;
  DateTime? _lastUpdateTime;

  @override
  void initState() {
    super.initState();
    _initializeTimeago();
  }

  void _initializeTimeago() {
    try {
      timeago.setLocaleMessages('de', timeago.DeMessages());
      timeago.setDefaultLocale('de');
    } catch (e) {
      print('Fehler bei Timeago-Konfiguration: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityModel>>(
      stream: _activityService.getRecentActivities(limit: widget.limit),
      builder: (context, snapshot) {
        // Während der ersten Ladung
        if (_isInitialLoad && snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }

        // Bei Fehlern
        if (snapshot.hasError) {
          return _buildErrorCard(context, snapshot.error.toString());
        }

        // Neue Daten verfügbar
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          _cachedActivities = snapshot.data!;
          _isInitialLoad = false;
          _lastUpdateTime = DateTime.now();
        }

        // Keine Daten (auch nach dem Laden)
        if (_cachedActivities.isEmpty && !_isInitialLoad) {
          return _buildEmptyCard();
        }

        // Daten anzeigen (aus Cache oder frisch geladen)
        return _buildActivitiesCard(context, _cachedActivities);
      },
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text(
              'Lade Aktivitäten...',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Fehler beim Laden',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Zeige gespeicherte Daten',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 32,
              color: Colors.grey,
            ),
            SizedBox(height: 12),
            Text(
              'Keine Aktivitäten',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Aktivitäten erscheinen hier nach Prüfungen, Änderungen oder Einsätzen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitiesCard(BuildContext context, List<ActivityModel> activities) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Optional: Update-Indikator
          if (_lastUpdateTime != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.update, color: Colors.green, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Aktualisiert ${_formatTimeAgo(_lastUpdateTime!)}',
                    style: const TextStyle(fontSize: 10, color: Colors.green),
                  ),
                ],
              ),
            ),

          // Aktivitätenliste
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activities.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withOpacity(0.3),
            ),
            itemBuilder: (context, index) {
              final activity = activities[index];
              return _buildCompactActivityItem(context, activity);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActivityItem(BuildContext context, ActivityModel activity) {
    return InkWell(
        onTap: () => _navigateToDetails(context, activity),
    onLongPress: () => ActivityActionSheet.show(context, activity), // Long-Press für mehr Optionen
    borderRadius: BorderRadius.circular(8),
    child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
    children: [
    // Icon
    Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
    color: activity.color.withOpacity(0.1),
    shape: BoxShape.circle,
    ),
    child: Icon(
    activity.icon,
    color: activity.color,
    size: 16,
    ),
    ),

    const SizedBox(width: 12),

    // Content
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // Titel und Typ-Badge
    Row(
    children: [
    Expanded(
    child: Text(
    activity.title,
    style: const TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 13,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    ),
    ),
    Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
    color: activity.color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
    _getTypeDisplayName(activity.type),
    style: TextStyle(
    fontSize: 9,
    color: activity.color,
    fontWeight: FontWeight.bold,
    ),
    ),
    ),
    ],
    ),

    const SizedBox(height: 2),

    // Beschreibung
    Text(
    activity.description,
    style: TextStyle(
    fontSize: 12,
    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    ),

    const SizedBox(height: 4),

    // Benutzer und Zeit
    Row(
    children: [
    Icon(
    Icons.person,
    size: 10,
    color: Theme.of(context).colorScheme.secondary,
    ),
    const SizedBox(width: 2),
    Expanded(
    child: Text(
    activity.performedBy,
    style: TextStyle(
    fontSize: 10,
    color: Theme.of(context).colorScheme.secondary,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    ),
    ),
    const SizedBox(width: 8),
    Text(
    _formatTimeAgo(activity.timestamp),
    style: TextStyle(
    fontSize: 10,
    color: Theme.of(context).colorScheme.secondary,
    ),
    ),
    ],
    ),
    ],
    ),
    ),

    // Pfeil mit Menü-Indikator
    Column(
    children: [
    Icon(
    Icons.chevron_right,
    size: 16,
    color: Theme.of(context).colorScheme.secondary.withOpacity(0.5),
    ),
    Container(
    width: 2,
    height: 2,
    margin: const EdgeInsets.only(top: 2),
    decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
    shape: BoxShape.circle,
    ),
    ),
    ],
    ),
    ],
    ),
    ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    try {
      return timeago.format(timestamp);
    } catch (e) {
      final difference = DateTime.now().difference(timestamp);
      if (difference.inDays > 0) {
        return 'vor ${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return 'vor ${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return 'vor ${difference.inMinutes}m';
      } else {
        return 'jetzt';
      }
    }
  }

  String _getTypeDisplayName(ActivityType type) {
    switch (type) {
      case ActivityType.inspection:
        return 'Prüfung';
      case ActivityType.statusChange:
        return 'Status';
      case ActivityType.mission:
        return 'Einsatz';
      case ActivityType.creation:
        return 'Neu';
      case ActivityType.update:
        return 'Update';
      case ActivityType.deletion:
        return 'Gelöscht';
      default:
        return 'Andere';
    }
  }

  void _navigateToDetails(BuildContext context, ActivityModel activity) {
    // Verwende den ActivityNavigationService für intelligente Navigation
    ActivityNavigationService.navigateToActivity(context, activity);
  }

  @override
  void dispose() {
    // Cache beim Dispose leeren
    _activityService.clearCache();
    super.dispose();
  }
}