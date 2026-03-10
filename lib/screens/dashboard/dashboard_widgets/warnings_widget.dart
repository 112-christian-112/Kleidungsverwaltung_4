// screens/dashboard/dashboard_widgets/warnings_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';

class WarningsWidget extends StatelessWidget {
  final bool isAdmin;
  final String userFireStation;

  const WarningsWidget({
    Key? key,
    required this.isAdmin,
    required this.userFireStation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final EquipmentService equipmentService = EquipmentService();
    final now = DateTime.now();
    final soon = DateTime(now.year, now.month, now.day + 30);

    return StreamBuilder<List<EquipmentModel>>(
      stream: isAdmin
          ? equipmentService.getAllEquipment()
          : equipmentService.getEquipmentByFireStation(userFireStation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return _errorCard(context, snapshot.error.toString());
        }

        final list = snapshot.data ?? [];

        final overdue = list
            .where((e) => e.checkDate.isBefore(now))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

        final upcoming = list
            .where((e) => e.checkDate.isAfter(now) && e.checkDate.isBefore(soon))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

        final notReady = list
            .where((e) => e.status != EquipmentStatus.ready)
            .toList();

        if (overdue.isEmpty && upcoming.isEmpty && notReady.isEmpty) {
          return _emptyCard(context);
        }

        return Column(
          children: [
            if (overdue.isNotEmpty)
              _warningSection(
                context: context,
                title: 'Überfällige Prüfungen',
                count: overdue.length,
                icon: Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                items: overdue,
                trailingBuilder: (e) =>
                    DateFormat('dd.MM.yy').format(e.checkDate),
                subtitleBuilder: (e) => e.owner,
              ),

            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 10),
              _warningSection(
                context: context,
                title: 'Bald fällig (30 Tage)',
                count: upcoming.length,
                icon: Icons.event_outlined,
                color: Colors.orange,
                items: upcoming,
                trailingBuilder: (e) =>
                    DateFormat('dd.MM.yy').format(e.checkDate),
                subtitleBuilder: (e) => e.owner,
              ),
            ],

            if (notReady.isNotEmpty) ...[
              const SizedBox(height: 10),
              _warningSection(
                context: context,
                title: 'Nicht einsatzbereit',
                count: notReady.length,
                icon: Icons.handyman_outlined,
                color: Colors.blue,
                items: notReady,
                trailingBuilder: (e) => e.status,
                subtitleBuilder: (e) => e.owner,
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Kachel-Variante: kompakter Header + max 3 Zeilen ─────────────────────

  Widget _warningSection({
    required BuildContext context,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required List<EquipmentModel> items,
    required String Function(EquipmentModel) trailingBuilder,
    required String Function(EquipmentModel) subtitleBuilder,
  }) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shown  = items.take(3).toList();

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(color: cs.outlineVariant)
            : BorderSide(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.18 : 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // ── Einträge ─────────────────────────────────────────────────────
          ...shown.map((e) => _equipmentRow(
                context: context,
                equipment: e,
                trailing: trailingBuilder(e),
                subtitle: subtitleBuilder(e),
                color: color,
              )),

          // ── „… weitere" ──────────────────────────────────────────────────
          if (count > 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Text(
                '+ ${count - 3} weitere',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _equipmentRow({
    required BuildContext context,
    required EquipmentModel equipment,
    required String trailing,
    required String subtitle,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              equipment.type == 'Jacke'
                  ? Icons.accessibility_new
                  : Icons.airline_seat_legroom_normal,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  equipment.article,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green.shade400, size: 28),
            const SizedBox(width: 12),
            Text(
              'Keine Warnungen — alles in Ordnung',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
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
}
