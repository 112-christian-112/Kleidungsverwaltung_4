// screens/all_activities_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/activity_model.dart';
import '../services/activity_service.dart';

class AllActivitiesScreen extends StatefulWidget {
  const AllActivitiesScreen({Key? key}) : super(key: key);

  @override
  State<AllActivitiesScreen> createState() => _AllActivitiesScreenState();
}

class _AllActivitiesScreenState extends State<AllActivitiesScreen> {
  final ActivityService _activityService = ActivityService();
  String _selectedFilter = 'Alle';

  final List<String> _filters = [
    'Alle',
    'Prüfungen',
    'Statusänderungen',
    'Einsätze',
    'Sonstiges'
  ];

  @override
  void initState() {
    super.initState();
    // Deutsch für Timeago konfigurieren
    timeago.setLocaleMessages('de', timeago.DeMessages());
    timeago.setDefaultLocale('de');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktivitäten'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtern',
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => _filters
                .map((filter) => PopupMenuItem<String>(
              value: filter,
              child: Row(
                children: [
                  if (_selectedFilter == filter)
                    Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 18,
                    ),
                  if (_selectedFilter == filter) const SizedBox(width: 8),
                  Text(filter),
                ],
              ),
            ))
                .toList(),
          ),
        ],
      ),
      body: StreamBuilder<List<ActivityModel>>(
        stream: _activityService.getRecentActivities(limit: 50),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Fehler beim Laden der Aktivitäten: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }

          List<ActivityModel> activities = snapshot.data ?? [];

          // Aktivitäten nach dem ausgewählten Filter filtern
          if (_selectedFilter != 'Alle') {
            activities = activities.where((activity) {
              switch (_selectedFilter) {
                case 'Prüfungen':
                  return activity.type == ActivityType.inspection;
                case 'Statusänderungen':
                  return activity.type == ActivityType.statusChange;
                case 'Einsätze':
                  return activity.type == ActivityType.mission;
                case 'Sonstiges':
                  return activity.type != ActivityType.inspection &&
                      activity.type != ActivityType.statusChange &&
                      activity.type != ActivityType.mission;
                default:
                  return true;
              }
            }).toList();
          }

          if (activities.isEmpty) {
            return const Center(
              child: Text('Keine Aktivitäten gefunden'),
            );
          }

          // Aktivitäten nach Datum gruppieren
          Map<String, List<ActivityModel>> groupedActivities = {};
          final dateFormat = DateFormat('dd.MM.yyyy');

          for (var activity in activities) {
            final dateString = dateFormat.format(activity.timestamp);
            if (!groupedActivities.containsKey(dateString)) {
              groupedActivities[dateString] = [];
            }
            groupedActivities[dateString]!.add(activity);
          }

          // Daten nach Datum sortieren (neueste zuerst)
          final sortedDates = groupedActivities.keys.toList()
            ..sort((a, b) {
              final dateA = dateFormat.parse(a);
              final dateB = dateFormat.parse(b);
              return dateB.compareTo(dateA);
            });

          return ListView.builder(
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              final date = sortedDates[index];
              final dateActivities = groupedActivities[date]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Text(
                      _formatDateHeader(date),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dateActivities.length,
                    itemBuilder: (context, activityIndex) {
                      return _buildActivityItem(
                          context, dateActivities[activityIndex]);
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _formatDateHeader(String dateString) {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    final date = DateFormat('dd.MM.yyyy').parse(dateString);

    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Heute';
    } else if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Gestern';
    } else {
      return dateString;
    }
  }

  Widget _buildActivityItem(BuildContext context, ActivityModel activity) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16.0),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: activity.color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            activity.icon,
            color: activity.color,
          ),
        ),
        title: Text(
          activity.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(activity.description),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 14,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  activity.performedBy,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('HH:mm').format(activity.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () {
          // Zur Detailseite navigieren (vereinfacht)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Navigation zu: ${activity.title}'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}