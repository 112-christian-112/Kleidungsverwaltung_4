// screens/dashboard/dashboard_widgets/inspection_calendar_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';
import '../../admin/equipment/equipment_inspection_form_screen.dart';


class InspectionCalendarWidget extends StatefulWidget {
  final bool isAdmin;
  final String userFireStation;

  const InspectionCalendarWidget({
    Key? key,
    required this.isAdmin,
    required this.userFireStation,
  }) : super(key: key);

  @override
  State<InspectionCalendarWidget> createState() =>
      _InspectionCalendarWidgetState();
}

class _InspectionCalendarWidgetState extends State<InspectionCalendarWidget> {
  final EquipmentService _equipmentService = EquipmentService();
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<EquipmentModel>> _inspectionEvents = {};

  @override
  void initState() {
    super.initState();
    _focusedDay  = DateTime.now();
    _selectedDay = DateTime.now();
    _loadInspectionEvents();
  }

  Future<void> _loadInspectionEvents() async {
    final now             = DateTime.now();
    final threeMonthsLater = DateTime(now.year, now.month + 3, now.day);

    final stream = widget.isAdmin
        ? _equipmentService.getEquipmentByCheckDate(now, threeMonthsLater)
        : _equipmentService.getEquipmentByCheckDateAndFireStation(
            now, threeMonthsLater, widget.userFireStation);

    stream.listen((equipment) {
      final Map<DateTime, List<EquipmentModel>> events = {};
      for (final item in equipment) {
        final d = DateTime(
            item.checkDate.year, item.checkDate.month, item.checkDate.day);
        events.putIfAbsent(d, () => []).add(item);
      }
      if (mounted) setState(() => _inspectionEvents = events);
    });
  }

  List<EquipmentModel> _getEventsForDay(DateTime day) =>
      _inspectionEvents[DateTime(day.year, day.month, day.day)] ?? [];

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final events = _getEventsForDay(_selectedDay);

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Kalender ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: TableCalendar(
              locale: 'de_DE',
              firstDay: DateTime.now().subtract(const Duration(days: 30)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: _calendarFormat,
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay  = focused;
                });
              },
              onFormatChanged: (f) => setState(() => _calendarFormat = f),
              onPageChanged: (f) => _focusedDay = f,
              eventLoader: _getEventsForDay,
              headerStyle: HeaderStyle(
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                formatButtonTextStyle:
                    TextStyle(fontSize: 12, color: cs.onSurface),
                titleCentered: true,
                titleTextStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
                leftChevronIcon:
                    Icon(Icons.chevron_left, color: cs.onSurface),
                rightChevronIcon:
                    Icon(Icons.chevron_right, color: cs.onSurface),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: TextStyle(color: cs.onSurface),
                weekendTextStyle: TextStyle(color: cs.onSurface),
                selectedTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                todayTextStyle: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.bold),
                markerDecoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          Divider(height: 1, color: cs.outlineVariant),

          // ── Tagesliste ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd. MMMM yyyy', 'de_DE').format(_selectedDay),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                ),
                const Spacer(),
                if (events.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${events.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
              child: Text(
                'Keine Prüfungen an diesem Tag',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurfaceVariant),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              itemCount: events.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 42,
                  color: cs.outlineVariant.withOpacity(0.5)),
              itemBuilder: (context, i) =>
                  _eventTile(context, events[i], cs),
            ),
        ],
      ),
    );
  }

  Widget _eventTile(
      BuildContext context, EquipmentModel eq, ColorScheme cs) {
    final isOverdue = eq.checkDate.isBefore(DateTime.now());
    final color     = isOverdue ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              eq.type == 'Jacke'
                  ? Icons.accessibility_new
                  : Icons.airline_seat_legroom_normal,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eq.article,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${eq.owner} · ${eq.fireStation}',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Prüfen-Button
          FilledButton.tonal(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    EquipmentInspectionFormScreen(equipment: eq),
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 0),
              minimumSize: const Size(64, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Prüfen', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
