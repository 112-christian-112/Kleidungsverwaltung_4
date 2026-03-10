// screens/dashboard/dashboard_tiles_widget.dart
import 'package:flutter/material.dart';

class DashboardTilesWidget extends StatelessWidget {
  final bool isAdmin;
  final String userFireStation;

  const DashboardTilesWidget({
    Key? key,
    required this.isAdmin,
    required this.userFireStation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tiles = [
      _TileData('Ausrüstung suchen',  Icons.search,                cs.primary,       '/admin-equipment'),
      _TileData('Neue Prüfung',       Icons.check_circle_outline,  Colors.green,      '/equipment-scan'),
      _TileData('Überfällig',         Icons.warning_amber_rounded, Colors.red,        '/overdue-inspections'),
      _TileData('Statusübersicht',    Icons.bar_chart_rounded,     Colors.deepOrange, '/equipment-status'),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.35,
      children: tiles.map((t) => _tile(context, t, isDark, cs)).toList(),
    );
  }

  Widget _tile(BuildContext context, _TileData t, bool isDark, ColorScheme cs) {
    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, t.route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.color.withOpacity(isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(t.icon, color: t.color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                t.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileData {
  final String label;
  final IconData icon;
  final Color color;
  final String route;
  const _TileData(this.label, this.icon, this.color, this.route);
}
