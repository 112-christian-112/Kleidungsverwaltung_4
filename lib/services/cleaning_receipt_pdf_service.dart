// services/cleaning_receipt_pdf_service.dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'dart:typed_data';
import '../models/mission_model.dart';
import '../models/equipment_model.dart';

class CleaningReceiptPdfService {
  static const int _itemsPerPage = 25; // Anpassbar je nach Bedarf

  /// Generiert einen Wäschereischein-PDF für die angegebene Ausrüstung
  static Future<Uint8List> generateCleaningReceiptPdf({
    required MissionModel mission,
    required List<EquipmentModel> equipmentList,
    String? customTitle,
  }) async {
    if (equipmentList.isEmpty) {
      throw Exception('Keine Ausrüstung für PDF-Generierung angegeben');
    }

    final pdf = pw.Document();

    // Datum und Zeit formatieren
    final missionDateFormatted = DateFormat('dd.MM.yyyy').format(mission.startTime);
    final missionTimeFormatted = DateFormat('HH:mm').format(mission.startTime);
    final now = DateTime.now();
    final currentDateFormatted = DateFormat('dd.MM.yyyy').format(now);

    // Einsatztyp übersetzen
    final missionTypeText = _getMissionTypeText(mission.type);

    // Jacken und Hosen zählen
    final counts = _countEquipmentTypes(equipmentList);

    // Berechne Seitenanzahl
    final totalItems = equipmentList.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();

    // Erste Seite mit Header-Informationen
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Titel
              _buildTitle(customTitle ?? 'Wäschereischein'),
              pw.SizedBox(height: 10),
              _buildSubtitle('Feuerwehr ${mission.fireStation}'),
              pw.SizedBox(height: 20),

              // Einsatzdetails
              _buildMissionDetailsSection(
                mission: mission,
                missionDateFormatted: missionDateFormatted,
                missionTimeFormatted: missionTimeFormatted,
                missionTypeText: missionTypeText,
              ),
              pw.SizedBox(height: 20),

              // Zusammenfassung
              _buildSummarySection(counts),
              pw.SizedBox(height: 20),

              // Info über mehrseitige Liste
              if (totalPages > 1)
                _buildMultiPageInfo(totalPages),

              pw.Spacer(),

              // Unterschriftszeile auf erster Seite
              _buildSignatureSection(),
              pw.SizedBox(height: 20),

              // Fußzeile
              _buildFooter(currentDateFormatted, 1, totalPages + 1),
            ],
          );
        },
      ),
    );

    // Zusätzliche Seiten für die detaillierte Liste
    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final pageItems = _getPageItems(equipmentList, pageIndex);
      final startIndex = pageIndex * _itemsPerPage + 1;
      final endIndex = startIndex + pageItems.length - 1;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header für Folgeseiten
                _buildPageHeader(mission.name, pageIndex + 2, totalPages + 1),
                pw.SizedBox(height: 10),

                // Info über aktuellen Seitenbereich
                _buildRangeInfo(startIndex, endIndex, totalItems),
                pw.SizedBox(height: 15),

                // Tabelle mit den Kleidungsstücken
                _buildEquipmentTable(pageItems),

                pw.Spacer(),

                // Fußzeile
                _buildSimpleFooter(mission.fireStation, currentDateFormatted),
              ],
            );
          },
        ),
      );
    }

    return await pdf.save();
  }

  /// Generiert eine Kopie eines bereits existierenden Wäschereischeins
  static Future<Uint8List> generateCleaningReceiptCopy({
    required MissionModel mission,
    required List<EquipmentModel> equipmentList,
  }) async {
    return generateCleaningReceiptPdf(
      mission: mission,
      equipmentList: equipmentList,
      customTitle: 'Wäschereischein (Kopie)',
    );
  }

  // Private Hilfsmethoden

  static String _getMissionTypeText(String type) {
    switch (type) {
      case 'fire':
        return 'Brandeinsatz';
      case 'technical':
        return 'Technische Hilfeleistung';
      case 'hazmat':
        return 'Gefahrguteinsatz';
      case 'water':
        return 'Wasser/Hochwasser';
      case 'training':
        return 'Übung';
      default:
        return 'Sonstiger Einsatz';
    }
  }

  static EquipmentCounts _countEquipmentTypes(List<EquipmentModel> equipmentList) {
    int jacketCount = 0;
    int pantsCount = 0;
    int otherCount = 0;

    for (var item in equipmentList) {
      switch (item.type.toLowerCase()) {
        case 'jacke':
          jacketCount++;
          break;
        case 'hose':
          pantsCount++;
          break;
        default:
          otherCount++;
          break;
      }
    }

    return EquipmentCounts(
      jackets: jacketCount,
      pants: pantsCount,
      other: otherCount,
    );
  }

  static List<EquipmentModel> _getPageItems(List<EquipmentModel> equipmentList, int pageIndex) {
    final startIndex = pageIndex * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage > equipmentList.length)
        ? equipmentList.length
        : startIndex + _itemsPerPage;

    return equipmentList.sublist(startIndex, endIndex);
  }

  // Widget-Builder Methoden

  static pw.Widget _buildTitle(String title) {
    return pw.Center(
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 24,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildSubtitle(String subtitle) {
    return pw.Center(
      child: pw.Text(
        subtitle,
        style: pw.TextStyle(
          fontSize: 18,
        ),
      ),
    );
  }

  static pw.Widget _buildMissionDetailsSection({
    required MissionModel mission,
    required String missionDateFormatted,
    required String missionTimeFormatted,
    required String missionTypeText,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Einsatzdetails:',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          _buildInfoRow('Einsatzname:', mission.name),
          _buildInfoRow('Einsatztyp:', missionTypeText),
          _buildInfoRow('Datum:', missionDateFormatted),
          _buildInfoRow('Uhrzeit:', '$missionTimeFormatted Uhr'),
          _buildInfoRow('Ort:', mission.location),
        ],
      ),
    );
  }

  static pw.Widget _buildSummarySection(EquipmentCounts counts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Zusammenfassung:',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          _buildSummaryRow('Anzahl Jacken:', '${counts.jackets}'),
          pw.SizedBox(height: 5),
          _buildSummaryRow('Anzahl Hosen:', '${counts.pants}'),
          if (counts.other > 0) ...[
            pw.SizedBox(height: 5),
            _buildSummaryRow('Sonstige:', '${counts.other}'),
          ],
          pw.SizedBox(height: 5),
          _buildSummaryRow('Gesamtzahl:', '${counts.total}'),
        ],
      ),
    );
  }

  static pw.Widget _buildMultiPageInfo(int totalPages) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Text(
        'Die detaillierte Liste der Ausrüstung ist auf $totalPages Seiten aufgeteilt.',
        style: pw.TextStyle(
          fontSize: 12,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    );
  }

  static pw.Widget _buildPageHeader(String missionName, int currentPage, int totalPages) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(
            'Detaillierte Liste - $missionName',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          'Seite $currentPage von $totalPages',
          style: pw.TextStyle(
            fontSize: 12,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildRangeInfo(int startIndex, int endIndex, int totalItems) {
    return pw.Text(
      'Einträge $startIndex bis $endIndex von $totalItems',
      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
    );
  }

  static pw.Widget _buildEquipmentTable(List<EquipmentModel> equipmentList) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(1.5),
      },
      children: [
        // Tabellenkopf
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildTableHeader('Typ'),
            _buildTableHeader('Artikel'),
            _buildTableHeader('Größe'),
            _buildTableHeader('Besitzer'),
            _buildTableHeader('Barcode'),
          ],
        ),
        // Tabellenzeilen
        ...equipmentList.map((equipment) {
          return pw.TableRow(
            children: [
              _buildTableCell(equipment.type),
              _buildTableCell(equipment.article),
              _buildTableCell(equipment.size),
              _buildTableCell(equipment.owner),
              _buildTableCell(equipment.barcode ?? 'N/A'),
            ],
          );
        }).toList(),
      ],
    );
  }

  static pw.Widget _buildSignatureSection() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _buildSignatureField('Datum, Unterschrift (Übergabe)'),
        _buildSignatureField('Datum, Unterschrift (Annahme)'),
      ],
    );
  }

  static pw.Widget _buildSignatureField(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 200,
          height: 1,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 14),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _buildTableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }

  static pw.Widget _buildFooter(String date, int currentPage, int totalPages) {
    return pw.Center(
      child: pw.Text(
        'Generiert am $date - Seite $currentPage von $totalPages',
        style: const pw.TextStyle(
          fontSize: 10,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  static pw.Widget _buildSimpleFooter(String fireStation, String date) {
    return pw.Center(
      child: pw.Text(
        'Feuerwehr $fireStation - $date',
        style: const pw.TextStyle(
          fontSize: 10,
          color: PdfColors.grey700,
        ),
      ),
    );
  }
}

/// Hilfsklasse für Ausrüstungszählung
class EquipmentCounts {
  final int jackets;
  final int pants;
  final int other;

  const EquipmentCounts({
    required this.jackets,
    required this.pants,
    required this.other,
  });

  int get total => jackets + pants + other;
}

