// screens/dashboard/dashboard_widgets/equipment_stats_widget.dart
import 'package:flutter/material.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';

class EquipmentStatsWidget extends StatelessWidget {
  final bool isAdmin;
  final String userFireStation;

  const EquipmentStatsWidget({
    Key? key,
    required this.isAdmin,
    required this.userFireStation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final EquipmentService equipmentService = EquipmentService();

    return StreamBuilder<List<EquipmentModel>>(
      stream: isAdmin
          ? equipmentService.getAllEquipment()
          : equipmentService.getEquipmentByFireStation(userFireStation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return _errorCard(context, '${snapshot.error}');
        }

        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return _emptyCard(context);
        }

        final typeStats    = _calcBy(list, (e) => e.type);
        final statusStats  = _calcBy(list, (e) => e.status);
        final stationStats = isAdmin ? _calcBy(list, (e) => e.fireStation) : null;

        final cs     = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Column(
          children: [
            // ── Typ + Status nebeneinander ─────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _distCard(context, 'Nach Typ', typeStats,
                    (k) => k == 'Jacke'
                        ? Icons.accessibility_new
                        : Icons.airline_seat_legroom_normal,
                    (k) => k == 'Jacke' ? cs.primary : cs.secondary)),
                const SizedBox(width: 10),
                Expanded(child: _distCard(context, 'Nach Status', statusStats,
                    (k) => EquipmentStatus.getStatusIcon(k),
                    (k) => EquipmentStatus.getStatusColor(k))),
              ],
            ),

            // ── Station (nur Admin) ────────────────────────────────────
            if (stationStats != null) ...[
              const SizedBox(height: 10),
              _stationCard(context, stationStats),
            ],
          ],
        );
      },
    );
  }

  // ── Verteilungs-Karte (Typ / Status) ──────────────────────────────────────
  Widget _distCard(
    BuildContext context,
    String title,
    Map<String, int> stats,
    IconData Function(String) iconFn,
    Color Function(String) colorFn,
  ) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total  = stats.values.fold(0, (s, v) => s + v);
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 12),
            ...sorted.map((e) {
              final pct = total > 0 ? e.value / total : 0.0;
              final color = colorFn(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(iconFn(e.key), size: 14, color: color),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(e.key,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurface),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${e.value}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface)),
                    ]),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: color.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Stationsbalken ─────────────────────────────────────────────────────────
  Widget _stationCard(BuildContext context, Map<String, int> stats) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max    = sorted.isEmpty ? 1 : sorted.first.value;

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nach Ortswehr',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 12),
            ...sorted.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(
                  width: 110,
                  child: Text(e.key,
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / max,
                      minHeight: 8,
                      backgroundColor: cs.primary.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${e.value}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
              ]),
            )),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('Keine Einsatzkleidung vorhanden',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, String error) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.error.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Fehler: $error',
            style: TextStyle(color: cs.error, fontSize: 13)),
      ),
    );
  }

  Map<String, int> _calcBy(
      List<EquipmentModel> list, String Function(EquipmentModel) key) {
    final m = <String, int>{};
    for (final e in list) {
      m[key(e)] = (m[key(e)] ?? 0) + 1;
    }
    return m;
  }
}
