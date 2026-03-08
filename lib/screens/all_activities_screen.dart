// screens/all_activities_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/activity_model.dart';
import '../models/user_models.dart';
import '../services/activity_service.dart';
import '../services/permission_service.dart';

class AllActivitiesScreen extends StatefulWidget {
  const AllActivitiesScreen({Key? key}) : super(key: key);

  @override
  State<AllActivitiesScreen> createState() => _AllActivitiesScreenState();
}

class _AllActivitiesScreenState extends State<AllActivitiesScreen> {
  final ActivityService _activityService = ActivityService();
  final PermissionService _permissionService = PermissionService();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 20;

  UserModel? _user;
  List<ActivityModel> _activities = [];
  String _selectedFilter = 'Alle';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  final List<String> _filters = [
    'Alle',
    'Prüfungen',
    'Statusänderungen',
    'Einsätze',
    'Sonstiges',
  ];

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('de', timeago.DeMessages());
    timeago.setDefaultLocale('de');
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _activityService.clearCache();
    super.dispose();
  }

  // ── Laden ─────────────────────────────────────────────────────────────────

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _activities = [];
      _hasMore = true;
    });

    try {
      _user = await _permissionService.getCurrentUser();
      if (_user == null) {
        setState(() { _isLoading = false; });
        return;
      }
      await _loadPage();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadPage() async {
    if (_user == null || _isLoadingMore) return;

    // Cursor = Timestamp des letzten geladenen Elements
    final cursor = _activities.isNotEmpty ? _activities.last.timestamp : null;

    final isFirstPage = cursor == null;
    if (isFirstPage) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final page = await _activityService.getActivitiesPaginated(
        user: _user!,
        limit: _pageSize,
        startAfterTimestamp: cursor,
      );

      if (mounted) {
        setState(() {
          _activities.addAll(page);
          _hasMore = page.length >= _pageSize;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    // 200px vor dem Ende → nächste Seite laden
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadPage();
    }
  }

  // ── Filter ────────────────────────────────────────────────────────────────

  List<ActivityModel> get _filteredActivities {
    if (_selectedFilter == 'Alle') return _activities;
    return _activities.where((a) {
      switch (_selectedFilter) {
        case 'Prüfungen':
          return a.type == ActivityType.inspection;
        case 'Statusänderungen':
          return a.type == ActivityType.statusChange;
        case 'Einsätze':
          return a.type == ActivityType.mission;
        case 'Sonstiges':
          return a.type != ActivityType.inspection &&
              a.type != ActivityType.statusChange &&
              a.type != ActivityType.mission;
        default:
          return true;
      }
    }).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktivitäten'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtern',
            onSelected: (value) => setState(() => _selectedFilter = value),
            itemBuilder: (context) => _filters
                .map((filter) => PopupMenuItem<String>(
                      value: filter,
                      child: Row(
                        children: [
                          if (_selectedFilter == filter) ...[
                            Icon(Icons.check,
                                color:
                                    Theme.of(context).colorScheme.primary,
                                size: 18),
                            const SizedBox(width: 8),
                          ],
                          Text(filter),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Fehler beim Laden',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }

    final activities = _filteredActivities;

    if (activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Keine Aktivitäten gefunden'),
            if (_selectedFilter != 'Alle') ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _selectedFilter = 'Alle'),
                child: const Text('Filter zurücksetzen'),
              ),
            ],
          ],
        ),
      );
    }

    // Nach Datum gruppieren
    final grouped = <String, List<ActivityModel>>{};
    final dateFormat = DateFormat('dd.MM.yyyy');
    for (final a in activities) {
      final key = dateFormat.format(a.timestamp);
      grouped.putIfAbsent(key, () => []).add(a);
    }
    final sortedDates = grouped.keys.toList()
      ..sort((a, b) => dateFormat.parse(b).compareTo(dateFormat.parse(a)));

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView.builder(
        controller: _scrollController,
        // +1 für den Lade-Indikator am Ende
        itemCount: sortedDates.length + (_isLoadingMore || _hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Letztes Element: Lade-Indikator oder "Alle geladen"-Hinweis
          if (index == sortedDates.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!_hasMore && _activities.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Alle ${_activities.length} Aktivitäten geladen',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final date = sortedDates[index];
          final dateActivities = grouped[date]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                itemBuilder: (_, i) =>
                    _buildActivityItem(context, dateActivities[i]),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  String _formatDateHeader(String dateString) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateFormat('dd.MM.yyyy').parse(dateString);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) return 'Heute';
    if (dateOnly == yesterday) return 'Gestern';
    return dateString;
  }

  Widget _buildActivityItem(BuildContext context, ActivityModel activity) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: activity.color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(activity.icon, color: activity.color),
        ),
        title: Text(activity.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(activity.description),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    activity.performedBy,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  timeago.format(activity.timestamp, locale: 'de'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
