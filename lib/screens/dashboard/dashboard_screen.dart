// screens/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_models.dart';
import '../../services/permission_service.dart';
import 'dashboard_widgets/dashboard_metrics_widget.dart';
import 'dashboard_widgets/inspection_calender_widget.dart';
import 'dashboard_widgets/warnings_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (mounted) setState(() { _currentUser = user; _isLoading = false; });
    } catch (e) {
      print('Fehler beim Laden: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Begrüßung ─────────────────────────────────────────
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentUser != null
                                  ? 'Willkommen${_currentUser!.fireStation.isNotEmpty ? ' — ${_currentUser!.fireStation}' : ''}'
                                  : 'Willkommen',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Heute ist ${DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(DateTime.now())}',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Metriken (kein isAdmin-Parameter mehr) ────────────
                    if (_currentUser?.isAdmin == true ||
                        _currentUser?.permissions.equipmentView == true) ...[
                      const DashboardMetricsWidget(),
                      const SizedBox(height: 24),
                    ],

                    // ── Warnungen ─────────────────────────────────────────
                    if (_currentUser?.isAdmin == true ||
                        _currentUser?.permissions.equipmentView == true) ...[
                      const Text('Warnungen & Benachrichtigungen',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      WarningsWidget(
                        isAdmin: _currentUser?.isAdmin ?? false,
                        userFireStation:
                            _currentUser?.fireStation ?? '',
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Prüfungskalender ──────────────────────────────────
                    if (_currentUser?.isAdmin == true ||
                        _currentUser?.permissions.inspectionView == true) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Anstehende Prüfungen',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(
                                context, '/overdue-inspections'),
                            child: const Text('Alle anzeigen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InspectionCalendarWidget(
                        isAdmin: _currentUser?.isAdmin ?? false,
                        userFireStation:
                            _currentUser?.fireStation ?? '',
                      ),
                      const SizedBox(height: 32),
                    ],

                    // ── Keine Rechte ──────────────────────────────────────
                    if (_currentUser != null &&
                        !_currentUser!.isAdmin &&
                        !_currentUser!.permissions.equipmentView &&
                        !_currentUser!.permissions.inspectionView)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Keine Berechtigungen zugewiesen.\nBitte wende dich an deinen Administrator.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
