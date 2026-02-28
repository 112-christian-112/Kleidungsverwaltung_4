// constants/fire_stations.dart
import 'package:flutter/material.dart';

class FireStations {
  // Private Konstruktor für Utility-Klasse
  FireStations._();

  // Liste aller Ortswehren (alphabetisch sortiert)
  static const List<String> all = [
    'Breinermoor',
    'Esklum',
    'Flachsmeer',
    'Folmhusen',
    'Grotegaste',
    'Großwolde',
    'Ihren',
    'Ihrhove',
    'Steenfelde',
    'Völlen',
    'Völlenerfehn',
    'Völlenerkönigsfehn',
  ];

  // Zusätzliche Informationen zu den Ortswehren (optional)
  static const Map<String, Map<String, dynamic>> details = {
    'Breinermoor': {
      'fullName': 'Freiwillige Feuerwehr Breinermoor',
      'district': 'Westoverledingen',
      'established': 1952,
      'icon': Icons.local_fire_department,
    },
    'Esklum': {
      'fullName': 'Freiwillige Feuerwehr Esklum',
      'district': 'Westoverledingen',
      'established': 1948,
      'icon': Icons.local_fire_department,
    },
    'Flachsmeer': {
      'fullName': 'Freiwillige Feuerwehr Flachsmeer',
      'district': 'Westoverledingen',
      'established': 1955,
      'icon': Icons.local_fire_department,
    },
    'Folmhusen': {
      'fullName': 'Freiwillige Feuerwehr Folmhusen',
      'district': 'Westoverledingen',
      'established': 1950,
      'icon': Icons.local_fire_department,
    },
    'Grotegaste': {
      'fullName': 'Freiwillige Feuerwehr Grotegaste',
      'district': 'Westoverledingen',
      'established': 1949,
      'icon': Icons.local_fire_department,
    },
    'Großwolde': {
      'fullName': 'Freiwillige Feuerwehr Großwolde',
      'district': 'Westoverledingen',
      'established': 1953,
      'icon': Icons.local_fire_department,
    },
    'Ihren': {
      'fullName': 'Freiwillige Feuerwehr Ihren',
      'district': 'Westoverledingen',
      'established': 1947,
      'icon': Icons.local_fire_department,
    },
    'Ihrhove': {
      'fullName': 'Freiwillige Feuerwehr Ihrhove',
      'district': 'Westoverledingen',
      'established': 1945,
      'icon': Icons.local_fire_department,
    },
    'Steenfelde': {
      'fullName': 'Freiwillige Feuerwehr Steenfelde',
      'district': 'Westoverledingen',
      'established': 1951,
      'icon': Icons.local_fire_department,
    },
    'Völlen': {
      'fullName': 'Freiwillige Feuerwehr Völlen',
      'district': 'Westoverledingen',
      'established': 1946,
      'icon': Icons.local_fire_department,
    },
    'Völlenerfehn': {
      'fullName': 'Freiwillige Feuerwehr Völlenerfehn',
      'district': 'Westoverledingen',
      'established': 1954,
      'icon': Icons.local_fire_department,
    },
    'Völlenerkönigsfehn': {
      'fullName': 'Freiwillige Feuerwehr Völlenerkönigsfehn',
      'district': 'Westoverledingen',
      'established': 1956,
      'icon': Icons.local_fire_department,
    },
  };

  // Hilfsmethoden für einfacheren Zugriff
  static List<String> getAllStations() {
    return List.from(all);
  }

  // Sortierte Liste (falls gewünscht)
  static List<String> getAllStationsSorted() {
    final stations = List<String>.from(all);
    stations.sort();
    return stations;
  }

  // Vollständigen Namen einer Ortswehr abrufen
  static String getFullName(String station) {
    return details[station]?['fullName'] ?? 'Freiwillige Feuerwehr $station';
  }

  // Bezirk einer Ortswehr abrufen
  static String getDistrict(String station) {
    return details[station]?['district'] ?? 'Unbekannt';
  }

  // Gründungsjahr einer Ortswehr abrufen
  static int? getEstablishedYear(String station) {
    return details[station]?['established'];
  }

  // Icon für eine Ortswehr abrufen
  static IconData getIcon(String station) {
    return details[station]?['icon'] ?? Icons.local_fire_department;
  }

  // Prüfen ob eine Ortswehr existiert
  static bool isValidStation(String station) {
    return all.contains(station);
  }

  // Suchfunktion für Ortswehren
  static List<String> searchStations(String query) {
    if (query.isEmpty) return getAllStations();

    return all
        .where((station) =>
    station.toLowerCase().contains(query.toLowerCase()) ||
        getFullName(station).toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  // Ortswehren nach Bezirk filtern
  static List<String> getStationsByDistrict(String district) {
    return all
        .where((station) => getDistrict(station) == district)
        .toList();
  }

  // Alle verfügbaren Bezirke abrufen
  static List<String> getAllDistricts() {
    return details.values
        .map((detail) => detail['district'] as String)
        .toSet()
        .toList()
      ..sort();
  }

  // Ortswehren ohne eine bestimmte ausschließen
  static List<String> getAllStationsExcept(String excludeStation) {
    return all.where((station) => station != excludeStation).toList();
  }

  // Ortswehren für Dropdown mit Details
  static List<Map<String, dynamic>> getStationsForDropdown() {
    return all.map((station) => {
      'value': station,
      'name': station,
      'fullName': getFullName(station),
      'district': getDistrict(station),
      'icon': getIcon(station),
    }).toList();
  }

  // Validierung für Formulare
  static String? validateStation(String? value) {
    if (value == null || value.isEmpty) {
      return 'Bitte wählen Sie eine Ortswehr aus';
    }
    if (!isValidStation(value)) {
      return 'Ungültige Ortswehr ausgewählt';
    }
    return null;
  }
}