// widgets/fire_station_selector.dart
import 'package:flutter/material.dart';

import '../Lists/fire_stations.dart';

class FireStationSelector extends StatefulWidget {
  final List<String> selectedStations;
  final String? userFireStation;
  final bool allowMultipleSelection;
  final bool showFullNames;
  final String title;
  final String? helpText;
  final Function(List<String>) onSelectionChanged;

  const FireStationSelector({
    Key? key,
    required this.selectedStations,
    required this.onSelectionChanged,
    this.userFireStation,
    this.allowMultipleSelection = true,
    this.showFullNames = false,
    this.title = 'Ortswehren auswählen',
    this.helpText,
  }) : super(key: key);

  @override
  State<FireStationSelector> createState() => _FireStationSelectorState();
}

class _FireStationSelectorState extends State<FireStationSelector> {
  late List<String> _tempSelectedStations;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tempSelectedStations = List.from(widget.selectedStations);
  }

  List<String> get _filteredStations {
    if (_searchQuery.isEmpty) {
      return FireStations.getAllStations();
    }
    return FireStations.searchStations(_searchQuery);
  }

  void _toggleStation(String station) {
    setState(() {
      if (_tempSelectedStations.contains(station)) {
        _tempSelectedStations.remove(station);
      } else {
        if (widget.allowMultipleSelection) {
          _tempSelectedStations.add(station);
        } else {
          _tempSelectedStations = [station];
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      _tempSelectedStations = List.from(FireStations.getAllStations());
    });
  }

  void _clearAll() {
    setState(() {
      _tempSelectedStations.clear();
      // Eigene Feuerwehr immer beibehalten
      if (widget.userFireStation != null) {
        _tempSelectedStations.add(widget.userFireStation!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.helpText != null) ...[
              Text(
                widget.helpText!,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
            ],

            // Suchfeld
            TextField(
              decoration: InputDecoration(
                labelText: 'Suchen',
                hintText: 'Nach Ortswehr suchen...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Aktionsbuttons (nur bei Mehrfachauswahl)
            if (widget.allowMultipleSelection) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.select_all, size: 16),
                    label: const Text('Alle'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Keine'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Auswahl-Anzeige
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_tempSelectedStations.length} ${widget.allowMultipleSelection ? "Ortswehren" : "Ortswehr"} ausgewählt',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Liste der Ortswehren
            Expanded(
              child: ListView.builder(
                itemCount: _filteredStations.length,
                itemBuilder: (context, index) {
                  final station = _filteredStations[index];
                  final isSelected = _tempSelectedStations.contains(station);
                  final isOwnStation = station == widget.userFireStation;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: widget.allowMultipleSelection
                        ? CheckboxListTile(
                      title: Text(
                        widget.showFullNames
                            ? FireStations.getFullName(station)
                            : station,
                        style: TextStyle(
                          fontWeight: isOwnStation ? FontWeight.bold : FontWeight.normal,
                          color: isOwnStation ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isOwnStation)
                            Text(
                              'Eigene Feuerwehr',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          if (widget.showFullNames)
                            Text(
                              station,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                      value: isSelected,
                      onChanged: isOwnStation ? null : (bool? value) {
                        _toggleStation(station);
                      },
                      secondary: Icon(
                        FireStations.getIcon(station),
                        color: isOwnStation
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[600],
                      ),
                    )
                        : RadioListTile<String>(
                      title: Text(
                        widget.showFullNames
                            ? FireStations.getFullName(station)
                            : station,
                        style: TextStyle(
                          fontWeight: isOwnStation ? FontWeight.bold : FontWeight.normal,
                          color: isOwnStation ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                      subtitle: isOwnStation
                          ? Text(
                        'Eigene Feuerwehr',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                          : null,
                      value: station,
                      groupValue: _tempSelectedStations.isNotEmpty ? _tempSelectedStations.first : null,
                      onChanged: (String? value) {
                        if (value != null) {
                          _toggleStation(value);
                        }
                      },
                      secondary: Icon(
                        FireStations.getIcon(station),
                        color: isOwnStation
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[600],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSelectionChanged(_tempSelectedStations);
            Navigator.of(context).pop();
          },
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

// Hilfsfunktion für einfache Verwendung
Future<List<String>?> showFireStationSelector({
  required BuildContext context,
  required List<String> selectedStations,
  String? userFireStation,
  bool allowMultipleSelection = true,
  bool showFullNames = false,
  String title = 'Ortswehren auswählen',
  String? helpText,
}) async {
  List<String>? result;

  await showDialog(
    context: context,
    builder: (context) => FireStationSelector(
      selectedStations: selectedStations,
      userFireStation: userFireStation,
      allowMultipleSelection: allowMultipleSelection,
      showFullNames: showFullNames,
      title: title,
      helpText: helpText,
      onSelectionChanged: (selection) {
        result = selection;
      },
    ),
  );

  return result;
}