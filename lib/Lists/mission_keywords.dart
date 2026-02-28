// constants/mission_keywords.dart
import 'package:flutter/material.dart';

class MissionKeywords {
  // Private Konstruktor für Utility-Klasse
  MissionKeywords._();

  // Einsatzstichwörter nach Kategorien
  static const Map<String, List<String>> keywords = {
    'fire': [
      'BMA',
      'F_Heumessung',
      'F_Erkundung',
      'F_Fahrzeug_klein',
      'F_Fläche_klein',
      'F_klein',
      'F_Schornstein',
      'F_Fahrzeug_mittel',
      'F_Garage',
      'F_Keller',
      'F_mittel',
      'F_Schuppen',
      'F_Zimmmer',
      'F_Betriebsgebäude',
      'F_Wohngebäude',
      'F_Landw_Maschine',
      'F_Schienenfahrzeug',
      'F_Fläche Groß',
      'F_Dachstuhl',
      'F_Fahrzeug BAB',
      'F_Fahrzeug_groß',
      'F_Landw_Gebäude',
      'F_Groß',
      'F_Wald',
      'F_Alten-_Pflegeheim_Y',
      'F_Betriebsgebäude_Y',
      'F_Schiff_Y',
      'F_Schule_Y',
      'F_Krankenhaus_Y',
      'F_Luftfahrzeug_Y',
      'F_groß_Y',
      'F_Bus_Y',
      'F_Wohngebäude_Y',

    ],
    'technical': [
      'TH_klein',
      'TH_ohne_Eile_mitte',
      'TH_Ölschaden_klein',
      'TH_Tierrettung',
      'TH_Tragehilfe_RD',
      'TH_mittel',
      'TH_ohne_Eile_klein',
      'TH_Ölschaden_mittel',
      'TH_nach_VU',
      'TH_groß',
      'TH_ohne_Eile_groß',
      'TH_Ölschaden_groß',
      'TH_Fahrzeg_vor-Zug',
      'TH_Luftnotlage',
      'TH_Eisrettung_Y',
      'TH_MANV_10',
      'TH_MANV_20',
      'TH_MANV_35',
      'TH_MANV_50',
      'TH_Notfalltüröffnung_Y',
      'TH_Person_vor_Zug',
      'TH_VU_EP_Wasser',
      'TH_Menschenrettung_aus_Höhe_Y',
      'TH_Personensuche',
      'TH_VU_Bahn_Y',
      'TH_VU_EP_Bahn',
      'TH_Menschenrettung_aus_Tiefe_Y',
      'TH_Menschenrettung_aus_Wasser_Y',
      'TH_VU_EP_Straße'
    ],
    'hazmat': [
      'F_Gefahrgut',
      'F_Gefahrgut_BAB',
      'TH_Gefahrgut',

    ],
    'water': [
      'TH_Sturmschaden_klein',
      'TH_Wasserschaden_klein',
      'TH_Sturmschaden_mittel',
      'TH_Wasserschaden_mittel',
      'TH_Sturmschaden_groß',
      'TH_Wasserschaden_groß',


    ],
    'training': [
      'Übung - Brandeinsatz',
      'Übung - Technische Hilfeleistung',
      'Übung - Atemschutz',
      'Übung - Verkehrsunfall',
      'Übung - Gefahrgut',
      'Übung - Hochwasser',
      'Gemeinsame Übung',
      'Ausbildung',
      'Fahrzeugkunde',
      'Gerätekunde',
    ],
    'other': [
      'Einsatz unklar',
      'Fehlalarm',
      'Unterstützung Rettungsdienst',
      'Unterstützung Polizei',
      'Sicherheitswache',
      'Brandwache',
      'Absperrdienst',
      'Sonstiger Einsatz',
    ],
  };

  // Kategorienamen für bessere Darstellung
  static const Map<String, String> typeNames = {
    'fire': 'Brandeinsatz',
    'technical': 'Technische Hilfeleistung',
    'hazmat': 'Gefahrgut',
    'water': 'Wasser/Sturm',
    'training': 'Übung',
    'other': 'Sonstiger Einsatz',
  };

  // Icons für die verschiedenen Einsatztypen
  static const Map<String, IconData> typeIcons = {
    'fire': Icons.local_fire_department,
    'technical': Icons.build,
    'hazmat': Icons.dangerous,
    'water': Icons.water,
    'training': Icons.school,
    'other': Icons.more_horiz,
  };

  // Hilfsmethoden für einfacheren Zugriff
  static List<String> getKeywordsForType(String type) {
    return keywords[type] ?? [];
  }

  static List<String> getAllKeywords() {
    return keywords.values.expand((list) => list).toList();
  }

  static List<String> getAllTypes() {
    return keywords.keys.toList();
  }

  static String getTypeName(String type) {
    return typeNames[type] ?? type;
  }

  static IconData getTypeIcon(String type) {
    return typeIcons[type] ?? Icons.help_outline;
  }

  // Suchfunktion für Stichwörter
  static List<String> searchKeywords(String query, {String? type}) {
    final keywordsToSearch = type != null
        ? getKeywordsForType(type)
        : getAllKeywords();

    return keywordsToSearch
        .where((keyword) => keyword.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  // Prüfen ob ein Stichwort zu einem Typ gehört
  static String? getTypeForKeyword(String keyword) {
    for (final entry in keywords.entries) {
      if (entry.value.contains(keyword)) {
        return entry.key;
      }
    }
    return null;
  }
}