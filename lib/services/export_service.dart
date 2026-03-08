// lib/services/export_service.dart
//
// Packages in pubspec.yaml:
//   excel: ^4.0.6
//   pdf: ^3.10.8
//   printing: ^5.12.0
//   share_plus: ^9.0.0
//   path_provider: ^2.1.2
//   flutter_file_dialog: ^3.0.1
//   url_launcher: ^6.2.5

import 'cleaning_receipt_pdf_service.dart';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/equipment_inspection_model.dart';
import '../models/equipment_model.dart';
import '../models/mission_model.dart';

class ExportService {
  static final DateFormat _dateFmt = DateFormat('dd.MM.yyyy');
  static final DateFormat _fileDateFmt = DateFormat('yyyyMMdd_HHmmss');

  // ══════════════════════════════════════════════════════════════════════════
  // EINSATZKLEIDUNG
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportToExcel(
    BuildContext context,
    List<EquipmentModel> equipment, {
    String title = 'Einsatzkleidung',
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Einsatzkleidung'];

      final headers = [
        'Artikel', 'Typ', 'Größe', 'Ortswehr', 'Besitzer',
        'NFC-Tag', 'Barcode', 'Status', 'Waschzyklen',
        'Nächste Prüfung', 'Angelegt am', 'Angelegt von',
      ];
      _writeExcelHeader(sheet, headers);

      final evenStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString('#F9F9F9'));

      for (int r = 0; r < equipment.length; r++) {
        final e = equipment[r];
        _writeExcelRow(sheet, r + 1, [
          e.article, e.type, e.size, e.fireStation, e.owner,
          e.nfcTag, e.barcode ?? '', e.status, e.washCycles.toString(),
          _dateFmt.format(e.checkDate),
          _dateFmt.format(e.createdAt),
          e.createdBy,
        ], r % 2 == 1 ? evenStyle : null);
      }

      await _saveExcel(context, excel, title);
    } catch (e) {
      _showError(context, 'Excel-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> exportEquipmentPdf(
    BuildContext context,
    List<EquipmentModel> equipment, {
    String title = 'Einsatzkleidung',
    bool withStatsSummary = false,
  }) async {
    try {
      final pdf = pw.Document();
      final fontRegular = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      const headerColor = PdfColor.fromInt(0xFF1565C0);
      const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
      const darkGrey = PdfColor.fromInt(0xFF424242);

      if (withStatsSummary) {
        pdf.addPage(_buildEquipmentStatsPage(
            equipment, fontBold, fontRegular, headerColor, darkGrey, title));
      }

      const columns = [
        _PdfCol('Artikel',    flex: 3),
        _PdfCol('Typ',        flex: 1),
        _PdfCol('Größe',      flex: 1),
        _PdfCol('Ortswehr',   flex: 2),
        _PdfCol('Besitzer',   flex: 2),
        _PdfCol('NFC-Tag',    flex: 2),
        _PdfCol('Barcode',    flex: 2),
        _PdfCol('Status',     flex: 2),
        _PdfCol('Prüfung',    flex: 1),
        _PdfCol('Wäschen',    flex: 1),
      ];

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) =>
            _pdfHeader(ctx, title, fontBold, fontRegular, headerColor),
        footer: (ctx) => _pdfFooter(ctx, fontRegular),
        build: (ctx) => [
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(
              'Gesamt: ${equipment.length} Einträge  •  '
              'Exportiert am: ${_dateFmt.format(DateTime.now())}',
              style: pw.TextStyle(
                  font: fontRegular, fontSize: 9, color: darkGrey),
            ),
          ),
          // Kopfzeile
          pw.Container(
            color: headerColor,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(
              children: columns
                  .map((c) => pw.Expanded(
                        flex: c.flex,
                        child: pw.Text(c.label,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 8,
                                color: PdfColors.white)),
                      ))
                  .toList(),
            ),
          ),
          // Datenzeilen
          ...equipment.asMap().entries.map((entry) {
            final idx = entry.key;
            final e = entry.value;
            final rowData = [
              e.article,
              e.type,
              e.size,
              e.fireStation,
              e.owner,
              e.nfcTag,
              e.barcode ?? '',
              e.status,
              _dateFmt.format(e.checkDate),
              e.washCycles.toString(),
            ];
            return pw.Container(
              color: idx % 2 == 1 ? lightGrey : PdfColors.white,
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              child: pw.Row(
                children: List.generate(
                  columns.length,
                  (i) => pw.Expanded(
                    flex: columns[i].flex,
                    child: pw.Text(rowData[i],
                        style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 8,
                            color: darkGrey)),
                  ),
                ),
              ),
            );
          }),
        ],
      ));

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          '${title.replaceAll(' ', '_')}_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'PDF-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> emailEquipmentPdf(
    BuildContext context,
    List<EquipmentModel> equipment, {
    String title = 'Einsatzkleidung',
  }) async {
    await exportEquipmentPdf(context, equipment,
        title: title, withStatsSummary: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EINSÄTZE
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportMissionsExcel(
    BuildContext context,
    List<MissionModel> missions, {
    Map<String, EquipmentModel> equipmentById = const {},
    String title = 'Einsätze',
  }) async {
    try {
      final excel = Excel.createExcel();

      // ── Tab 1: Einsatzübersicht ───────────────────────────────────────────
      final overviewSheet = excel['Einsätze'];
      _writeExcelHeader(overviewSheet, [
        'Name', 'Typ', 'Ort', 'Datum', 'Uhrzeit',
        'Ortswehr', 'Beteiligte Wehren',
        'Anzahl Kleidung', 'Angelegt von', 'Angelegt am',
      ]);

      final evenStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString('#F9F9F9'));

      for (int r = 0; r < missions.length; r++) {
        final m = missions[r];
        _writeExcelRow(overviewSheet, r + 1, [
          m.name,
          _missionTypeName(m.type),
          m.location,
          DateFormat('dd.MM.yyyy').format(m.startTime),
          DateFormat('HH:mm').format(m.startTime),
          m.fireStation,
          m.involvedFireStations.join(', '),
          m.equipmentIds.length.toString(),
          m.createdBy,
          _dateFmt.format(m.createdAt),
        ], r % 2 == 1 ? evenStyle : null);
      }

      // ── Tab 2: Kleidung pro Einsatz ───────────────────────────────────────
      final detailSheet = excel['Kleidung je Einsatz'];
      _writeExcelHeader(detailSheet, [
        'Einsatz', 'Datum', 'Typ', 'Ort',
        'Artikel', 'Typ (Kleidung)', 'Größe', 'Besitzer', 'Ortswehr',
        'Barcode', 'NFC-Tag',
      ]);

      int detailRow = 1;
      for (final m in missions) {
        if (m.equipmentIds.isEmpty) continue;
        final date = DateFormat('dd.MM.yyyy').format(m.startTime);
        final mType = _missionTypeName(m.type);
        for (final id in m.equipmentIds) {
          final eq = equipmentById[id];
          _writeExcelRow(detailSheet, detailRow, [
            m.name,
            date,
            mType,
            m.location,
            eq?.article ?? '–',
            eq?.type ?? '–',
            eq?.size ?? '–',
            eq?.owner ?? '–',
            eq?.fireStation ?? '–',
            eq?.barcode ?? '–',
            eq?.nfcTag ?? '–',
          ], detailRow % 2 == 1 ? evenStyle : null);
          detailRow++;
        }
      }

      // Standard-Sheet entfernen
      excel.delete('Sheet1');

      await _saveExcel(context, excel, title);
    } catch (e) {
      _showError(context, 'Excel-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> exportMissionsPdf(
    BuildContext context,
    List<MissionModel> missions, {
    Map<String, EquipmentModel> equipmentById = const {},
    String title = 'Einsätze',
    bool withStatsSummary = false,
  }) async {
    try {
      final pdf = pw.Document();
      final fontRegular = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      const headerColor = PdfColor.fromInt(0xFF1565C0);
      const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
      const darkGrey = PdfColor.fromInt(0xFF424242);
      const accentBlue = PdfColor.fromInt(0xFFE3F2FD);

      if (withStatsSummary) {
        pdf.addPage(_buildMissionStatsPage(
            missions, fontBold, fontRegular, headerColor, darkGrey, title));
      }

      // ── Seite 1+: Einsatzübersicht ────────────────────────────────────────
      final overviewCols = [
        _PdfCol('Name', flex: 3),
        _PdfCol('Typ', flex: 2),
        _PdfCol('Ort', flex: 2),
        _PdfCol('Datum', flex: 1),
        _PdfCol('Ortswehr', flex: 2),
        _PdfCol('Kleidung', flex: 1),
      ];

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) =>
            _pdfHeader(ctx, title, fontBold, fontRegular, headerColor),
        footer: (ctx) => _pdfFooter(ctx, fontRegular),
        build: (ctx) => [
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(
              'Gesamt: ${missions.length} Einsätze  •  '
              'Exportiert am: ${_dateFmt.format(DateTime.now())}',
              style: pw.TextStyle(
                  font: fontRegular, fontSize: 9, color: darkGrey),
            ),
          ),
          // Header-Zeile
          pw.Container(
            color: headerColor,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(
              children: overviewCols
                  .map((c) => pw.Expanded(
                        flex: c.flex,
                        child: pw.Text(c.label,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 8,
                                color: PdfColors.white)),
                      ))
                  .toList(),
            ),
          ),
          // Einsatzzeilen + Kleidungs-Unterblock
          ...missions.asMap().entries.map((entry) {
            final idx = entry.key;
            final m = entry.value;
            final eqList = m.equipmentIds
                .map((id) => equipmentById[id])
                .whereType<EquipmentModel>()
                .toList();

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Haupt-Einsatzzeile
                pw.Container(
                  color: idx % 2 == 1 ? lightGrey : PdfColors.white,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 3, child: pw.Text(m.name, style: pw.TextStyle(font: fontBold, fontSize: 8, color: darkGrey))),
                      pw.Expanded(flex: 2, child: pw.Text(_missionTypeName(m.type), style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                      pw.Expanded(flex: 2, child: pw.Text(m.location, style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                      pw.Expanded(flex: 1, child: pw.Text(DateFormat('dd.MM.yy').format(m.startTime), style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                      pw.Expanded(flex: 2, child: pw.Text(m.fireStation, style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                      pw.Expanded(flex: 1, child: pw.Text('${eqList.length}', style: pw.TextStyle(font: fontBold, fontSize: 8, color: darkGrey))),
                    ],
                  ),
                ),
                // Kleidungs-Unterblock
                if (eqList.isNotEmpty)
                  pw.Container(
                    color: accentBlue,
                    margin: const pw.EdgeInsets.only(left: 16, bottom: 2),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Spaltenüberschriften
                        pw.Row(children: [
                          pw.Expanded(flex: 3, child: pw.Text('Artikel', style: pw.TextStyle(font: fontBold, fontSize: 7, color: headerColor))),
                          pw.Expanded(flex: 2, child: pw.Text('Typ', style: pw.TextStyle(font: fontBold, fontSize: 7, color: headerColor))),
                          pw.Expanded(flex: 1, child: pw.Text('Größe', style: pw.TextStyle(font: fontBold, fontSize: 7, color: headerColor))),
                          pw.Expanded(flex: 2, child: pw.Text('Besitzer', style: pw.TextStyle(font: fontBold, fontSize: 7, color: headerColor))),
                          pw.Expanded(flex: 2, child: pw.Text('Ortswehr', style: pw.TextStyle(font: fontBold, fontSize: 7, color: headerColor))),
                          pw.Expanded(flex: 2, child: pw.Text('Barcode / NFC', style: pw.TextStyle(font: fontBold, fontSize: 7, color: headerColor))),
                        ]),
                        pw.SizedBox(height: 2),
                        // Kleidungszeilen
                        ...eqList.map((eq) => pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Row(children: [
                            pw.Expanded(flex: 3, child: pw.Text(eq.article, style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                            pw.Expanded(flex: 2, child: pw.Text(eq.type, style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                            pw.Expanded(flex: 1, child: pw.Text(eq.size, style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                            pw.Expanded(flex: 2, child: pw.Text(eq.owner, style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                            pw.Expanded(flex: 2, child: pw.Text(eq.fireStation, style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                            pw.Expanded(flex: 2, child: pw.Text(
                              [if (eq.barcode != null && eq.barcode!.isNotEmpty) eq.barcode!, if (eq.nfcTag.isNotEmpty) eq.nfcTag].join(' / '),
                              style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey),
                            )),
                          ]),
                        )),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ],
      ));

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          '${title.replaceAll(' ', '_')}_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'PDF-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> emailMissionsPdf(
    BuildContext context,
    List<MissionModel> missions, {
    String title = 'Einsätze',
  }) async {
    await exportMissionsPdf(context, missions,
        title: title, withStatsSummary: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRÜFUNGSHISTORIE
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportInspectionsExcel(
    BuildContext context,
    List<EquipmentInspectionModel> inspections, {
    String title = 'Prüfungshistorie',
    Map<String, EquipmentModel>? equipmentById,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Prüfungen'];

      final headers = [
        'Artikel', 'Besitzer', 'Ortswehr', 'Barcode', 'NFC-Tag',
        'Prüfdatum', 'Prüfer', 'Ergebnis',
        'Mängel', 'Kommentar', 'Nächste Prüfung',
      ];
      _writeExcelHeader(sheet, headers);

      final evenStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString('#F9F9F9'));

      for (int r = 0; r < inspections.length; r++) {
        final i = inspections[r];
        final eq = equipmentById?[i.equipmentId];
        _writeExcelRow(sheet, r + 1, [
          eq?.article ?? i.equipmentId,
          eq?.owner ?? '',
          eq?.fireStation ?? '',
          eq?.barcode ?? '',
          eq?.nfcTag ?? '',
          _dateFmt.format(i.inspectionDate),
          i.inspector,
          _inspectionResultName(i.result.toString().split('.').last),
          i.issues?.join('; ') ?? '',
          i.comments,
          _dateFmt.format(i.nextInspectionDate),
        ], r % 2 == 1 ? evenStyle : null);
      }

      await _saveExcel(context, excel, title);
    } catch (e) {
      _showError(context, 'Excel-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> exportInspectionsPdf(
    BuildContext context,
    List<EquipmentInspectionModel> inspections, {
    String title = 'Prüfungshistorie',
    bool withStatsSummary = false,
    Map<String, EquipmentModel>? equipmentById,
  }) async {
    try {
      final pdf = pw.Document();
      final fontRegular = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      const headerColor = PdfColor.fromInt(0xFF1565C0);
      const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
      const darkGrey = PdfColor.fromInt(0xFF424242);

      if (withStatsSummary) {
        pdf.addPage(_buildInspectionStatsPage(
            inspections, fontBold, fontRegular, headerColor, darkGrey, title));
      }

      // Pro Prüfung eine Zeile + ggf. Mängel-Block
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) =>
            _pdfHeader(ctx, title, fontBold, fontRegular, headerColor),
        footer: (ctx) => _pdfFooter(ctx, fontRegular),
        build: (ctx) => [
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(
              'Gesamt: ${inspections.length} Prüfungen  •  '
              'Exportiert am: ${_dateFmt.format(DateTime.now())}',
              style: pw.TextStyle(
                  font: fontRegular, fontSize: 9, color: darkGrey),
            ),
          ),
          // Kopfzeile
          pw.Container(
            color: headerColor,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(children: [
              pw.Expanded(flex: 3, child: pw.Text('Artikel / Besitzer',  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Ortswehr',            style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('NFC-Tag',             style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Barcode',             style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Prüfdatum',           style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Prüfer',              style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Ergebnis',            style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Nächste Prüfung',     style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
            ]),
          ),

          // Datenzeilen
          ...inspections.asMap().entries.expand((entry) {
            final idx = entry.key;
            final i = entry.value;
            final eq = equipmentById?[i.equipmentId];
            final resultName = _inspectionResultName(
                i.result.toString().split('.').last);
            final resultColor = i.result == InspectionResult.passed
                ? PdfColors.green700
                : i.result == InspectionResult.conditionalPass
                    ? PdfColors.orange700
                    : PdfColors.red700;
            final hasIssues = i.issues != null && i.issues!.isNotEmpty;
            final rowBg = idx % 2 == 1 ? lightGrey : PdfColors.white;

            return [
              // Hauptzeile
              pw.Container(
                color: rowBg,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(eq?.article ?? i.equipmentId,
                              style: pw.TextStyle(
                                  font: fontBold, fontSize: 8, color: darkGrey)),
                          if (eq != null)
                            pw.Text(eq.owner,
                                style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: 7,
                                    color: PdfColors.grey600)),
                        ],
                      ),
                    ),
                    pw.Expanded(flex: 2, child: pw.Text(eq?.fireStation ?? '',           style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                    pw.Expanded(flex: 2, child: pw.Text(eq?.nfcTag ?? '',                style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                    pw.Expanded(flex: 2, child: pw.Text(eq?.barcode ?? '',               style: pw.TextStyle(font: fontRegular, fontSize: 7, color: darkGrey))),
                    pw.Expanded(flex: 2, child: pw.Text(_dateFmt.format(i.inspectionDate), style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                    pw.Expanded(flex: 2, child: pw.Text(i.inspector,                     style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                    pw.Expanded(flex: 2, child: pw.Text(resultName,                      style: pw.TextStyle(font: fontBold,    fontSize: 8, color: resultColor))),
                    pw.Expanded(flex: 2, child: pw.Text(_dateFmt.format(i.nextInspectionDate), style: pw.TextStyle(font: fontRegular, fontSize: 8, color: darkGrey))),
                  ],
                ),
              ),

              // Mängel-Block (nur wenn vorhanden)
              if (hasIssues)
                pw.Container(
                  color: const PdfColor.fromInt(0xFFFFF3E0),
                  padding: const pw.EdgeInsets.fromLTRB(16, 4, 8, 6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Mängel:',
                          style: pw.TextStyle(
                              font: fontBold, fontSize: 7, color: PdfColors.orange800)),
                      ...i.issues!.map((issue) => pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Row(children: [
                              pw.Text('• ',
                                  style: pw.TextStyle(
                                      font: fontBold, fontSize: 7, color: PdfColors.orange800)),
                              pw.Expanded(
                                child: pw.Text(issue,
                                    style: pw.TextStyle(
                                        font: fontRegular, fontSize: 7, color: PdfColors.orange900)),
                              ),
                            ]),
                          )),
                      if (i.comments.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text('Kommentar: ${i.comments}',
                            style: pw.TextStyle(
                                font: fontRegular, fontSize: 7, color: PdfColors.grey700)),
                      ],
                    ],
                  ),
                ),
            ];
          }),
        ],
      ));

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          '${title.replaceAll(' ', '_')}_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'PDF-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> emailInspectionsPdf(
    BuildContext context,
    List<EquipmentInspectionModel> inspections, {
    String title = 'Prüfungshistorie',
    Map<String, EquipmentModel>? equipmentById,
  }) async {
    await exportInspectionsPdf(context, inspections,
        title: title,
        withStatsSummary: true,
        equipmentById: equipmentById);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STATISTIK-SEITEN
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Page _buildEquipmentStatsPage(
    List<EquipmentModel> equipment,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor headerColor,
    PdfColor darkGrey,
    String title,
  ) {
    final byStatus = <String, int>{};
    final byType = <String, int>{};
    final byStation = <String, int>{};
    int totalWash = 0;

    for (final e in equipment) {
      byStatus[e.status] = (byStatus[e.status] ?? 0) + 1;
      byType[e.type] = (byType[e.type] ?? 0) + 1;
      byStation[e.fireStation] = (byStation[e.fireStation] ?? 0) + 1;
      totalWash += e.washCycles;
    }

    final now = DateTime.now();
    final overdue = equipment.where((e) => e.checkDate.isBefore(now)).length;
    final avgWash = equipment.isNotEmpty
        ? (totalWash / equipment.length).toStringAsFixed(1)
        : '0';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfHeader(ctx, '$title – Zusammenfassung', fontBold, fontRegular,
              headerColor),
          pw.SizedBox(height: 24),

          // Kennzahlen
          pw.Row(children: [
            _statBox('Gesamt', '${equipment.length}', fontBold, fontRegular,
                headerColor),
            pw.SizedBox(width: 12),
            _statBox('Überfällig', '$overdue', fontBold, fontRegular,
                overdue > 0 ? PdfColors.red700 : PdfColors.green700),
            pw.SizedBox(width: 12),
            _statBox('Ø Wäschen', avgWash, fontBold, fontRegular, darkGrey),
          ]),
          pw.SizedBox(height: 20),

          // Status-Verteilung
          _statsTable('Status-Verteilung', byStatus, fontBold, fontRegular,
              darkGrey, headerColor),
          pw.SizedBox(height: 16),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _statsTable('Typ', byType, fontBold, fontRegular,
                    darkGrey, headerColor),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: _statsTable('Ortswehr', byStation, fontBold,
                    fontRegular, darkGrey, headerColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Page _buildMissionStatsPage(
    List<MissionModel> missions,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor headerColor,
    PdfColor darkGrey,
    String title,
  ) {
    final byType = <String, int>{};
    final byStation = <String, int>{};
    int totalEquipment = 0;

    for (final m in missions) {
      byType[_missionTypeName(m.type)] =
          (byType[_missionTypeName(m.type)] ?? 0) + 1;
      byStation[m.fireStation] = (byStation[m.fireStation] ?? 0) + 1;
      totalEquipment += m.equipmentIds.length;
    }

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfHeader(ctx, '$title – Zusammenfassung', fontBold, fontRegular,
              headerColor),
          pw.SizedBox(height: 24),
          pw.Row(children: [
            _statBox('Einsätze gesamt', '${missions.length}', fontBold,
                fontRegular, headerColor),
            pw.SizedBox(width: 12),
            _statBox('Ausrüstung gesamt', '$totalEquipment', fontBold,
                fontRegular, darkGrey),
          ]),
          pw.SizedBox(height: 20),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _statsTable('Einsatztyp', byType, fontBold, fontRegular,
                    darkGrey, headerColor),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: _statsTable('Ortswehr', byStation, fontBold, fontRegular,
                    darkGrey, headerColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Page _buildInspectionStatsPage(
    List<EquipmentInspectionModel> inspections,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor headerColor,
    PdfColor darkGrey,
    String title,
  ) {
    final byResult = <String, int>{};
    for (final i in inspections) {
      final name = _inspectionResultName(i.result.toString().split('.').last);
      byResult[name] = (byResult[name] ?? 0) + 1;
    }

    final passed =
        inspections.where((i) => i.result == InspectionResult.passed).length;
    final passRate = inspections.isNotEmpty
        ? (passed / inspections.length * 100).toStringAsFixed(1)
        : '0';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfHeader(ctx, '$title – Zusammenfassung', fontBold, fontRegular,
              headerColor),
          pw.SizedBox(height: 24),
          pw.Row(children: [
            _statBox('Prüfungen gesamt', '${inspections.length}', fontBold,
                fontRegular, headerColor),
            pw.SizedBox(width: 12),
            _statBox('Bestanden', '$passRate%', fontBold, fontRegular,
                PdfColors.green700),
          ]),
          pw.SizedBox(height: 20),
          _statsTable('Ergebnis-Verteilung', byResult, fontBold, fontRegular,
              darkGrey, headerColor),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // E-MAIL
  // ══════════════════════════════════════════════════════════════════════════


  // ══════════════════════════════════════════════════════════════════════════
  // OUTPUT-HANDLER (Web / Mobil)
  // ══════════════════════════════════════════════════════════════════════════

  /// PDF ausgeben – Context-sichere Variante:
  /// ScaffoldMessenger und Navigator werden VOR dem ersten await extrahiert.
  static Future<void> _handlePdfOutput(
      BuildContext context, Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      downloadFileOnWeb(bytes, fileName, 'application/pdf');
      return;
    }
    if (!context.mounted) return;
    // Referenzen VOR async-Lücken sichern
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await _showMobileOptions(
      context: context,
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
      isPdf: true,
      messenger: messenger,
      navigator: navigator,
    );
  }

  static Future<void> _saveExcel(
      BuildContext context, Excel excel, String title) async {
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Excel konnte nicht kodiert werden.');
    final fileName =
        '${title.replaceAll(' ', '_')}_${_fileDateFmt.format(DateTime.now())}.xlsx';
    const mimeType =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    if (kIsWeb) {
      downloadFileOnWeb(Uint8List.fromList(bytes), fileName, mimeType);
      return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await _showMobileOptions(
      context: context,
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      mimeType: mimeType,
      isPdf: false,
      messenger: messenger,
      navigator: navigator,
    );
  }

  /// Bottom Sheet mit Speichern / Teilen / Drucken.
  /// Nimmt vorextrahierte [messenger] und [navigator] entgegen,
  /// damit nach langen async-Operationen keine "context not mounted"-Fehler auftreten.
  static Future<void> _showMobileOptions({
    required BuildContext context,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required bool isPdf,
    required ScaffoldMessengerState messenger,
    required NavigatorState navigator,
  }) async {
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text(isPdf ? 'PDF speichern' : 'Excel speichern',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Speichern unter…'),
              subtitle: const Text('Ordner selbst auswählen'),
              onTap: () {
                Navigator.pop(ctx);
                // Kein await hier – damit ctx sofort geschlossen ist
                // und wir danach mit den gesicherten Refs weiterarbeiten
                _saveWithSAF(
                  bytes: bytes,
                  fileName: fileName,
                  mimeType: mimeType,
                  messenger: messenger,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Teilen / E-Mail'),
              subtitle: const Text('Per E-Mail, WhatsApp, Drive…'),
              onTap: () {
                Navigator.pop(ctx);
                _shareFile(
                  bytes: bytes,
                  fileName: fileName,
                  mimeType: mimeType,
                  messenger: messenger,
                );
              },
            ),
            if (isPdf)
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Drucken'),
                onTap: () {
                  Navigator.pop(ctx);
                  Printing.layoutPdf(
                      onLayout: (_) async => bytes, name: fileName);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> _saveWithSAF({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required ScaffoldMessengerState messenger,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: tempFile.path,
          fileName: fileName,
          mimeTypesFilter: [mimeType],
        ),
      );

      if (savedPath != null) {
        messenger.showSnackBar(SnackBar(
          content: Text('Gespeichert: $savedPath'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Speichern fehlgeschlagen: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  static Future<void> _shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required ScaffoldMessengerState messenger,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: fileName);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Teilen fehlgeschlagen: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXCEL-HILFSMETHODEN
  // ══════════════════════════════════════════════════════════════════════════

  static void _writeExcelHeader(Sheet sheet, List<String> headers) {
    final style = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = style;
      sheet.setColumnWidth(i, 20.0);
    }
  }

  static void _writeExcelRow(Sheet sheet, int rowIndex, List<String> values,
      CellStyle? style) {
    for (int c = 0; c < values.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
      cell.value = TextCellValue(values[c]);
      if (style != null) cell.cellStyle = style;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PDF-HILFSMETHODEN
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _pdfHeader(
    pw.Context ctx,
    String title,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor headerColor,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      font: fontBold, fontSize: 16, color: headerColor)),
              pw.Text('Kleidungsverwaltung — Feuerwehr',
                  style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 9,
                      color: PdfColors.grey600)),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: pw.BoxDecoration(
                color: headerColor,
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text('EXPORT',
                style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 10,
                    color: PdfColors.white)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooter(pw.Context ctx, pw.Font fontRegular) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
          border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300))),
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Kleidungsverwaltung',
              style: pw.TextStyle(
                  font: fontRegular, fontSize: 7, color: PdfColors.grey)),
          pw.Text('Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
              style: pw.TextStyle(
                  font: fontRegular, fontSize: 7, color: PdfColors.grey)),
        ],
      ),
    );
  }

  static pw.Widget _statBox(String label, String value, pw.Font fontBold,
      pw.Font fontRegular, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: color, width: 1.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    font: fontRegular, fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    font: fontBold, fontSize: 20, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _statsTable(
    String title,
    Map<String, int> data,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor darkGrey,
    PdfColor headerColor,
  ) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = data.values.fold(0, (s, v) => s + v);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style:
                pw.TextStyle(font: fontBold, fontSize: 11, color: headerColor)),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            children: sorted.asMap().entries.map((entry) {
              final idx = entry.key;
              final e = entry.value;
              final pct =
                  total > 0 ? (e.value / total * 100).toStringAsFixed(0) : '0';
              final isLast = idx == sorted.length - 1;
              return pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: idx % 2 == 0
                      ? PdfColors.white
                      : const PdfColor.fromInt(0xFFF5F5F5),
                  border: isLast
                      ? null
                      : const pw.Border(
                          bottom:
                              pw.BorderSide(color: PdfColors.grey200)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                        child: pw.Text(e.key,
                            style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                                color: darkGrey))),
                    pw.Text('${e.value}',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 9,
                            color: darkGrey)),
                    pw.SizedBox(width: 8),
                    pw.Text('($pct%)',
                        style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 8,
                            color: PdfColors.grey600)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HILFSMETHODEN
  // ══════════════════════════════════════════════════════════════════════════

  static String _missionTypeName(String type) {
    const names = {
      'fire': 'Brandeinsatz',
      'technical': 'Techn. Hilfeleistung',
      'hazmat': 'Gefahrgut',
      'water': 'Wasser/Sturm',
      'training': 'Übung',
      'other': 'Sonstiger Einsatz',
    };
    return names[type] ?? type;
  }

  static String _inspectionResultName(String result) {
    const names = {
      'passed': 'Bestanden',
      'conditionalPass': 'Bedingt bestanden',
      'failed': 'Nicht bestanden',
    };
    return names[result] ?? result;
  }

  static void _showError(BuildContext context, String message) {
    // Nur aufrufen wenn context noch mounted – bei langem async ggf. nicht mehr der Fall
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Context-sichere Fehleranzeige via vorextrahiertem Messenger
  static void _showErrorMsg(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }
  // ════════════════════════════════════════════════════════════════════════════
// DIESE METHODEN IN export_service.dart EINFÜGEN
// — direkt vor der letzten schließenden } der ExportService-Klasse
// ════════════════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════
  // PRÜFUNGS-FÄLLIGKEIT
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportDueInspectionsPdf(
      BuildContext context,
      List<EquipmentModel> dueItems,
      Map<String, EquipmentModel> equipmentById, {
        String title = 'Prüfungs-Fälligkeit',
        bool asExcel = false,
      }) async {
    if (asExcel) {
      await _exportDueInspectionsExcel(context, dueItems, title);
      return;
    }
    try {
      final pdf         = pw.Document();
      final fontReg     = await PdfGoogleFonts.notoSansRegular();
      final fontBold    = await PdfGoogleFonts.notoSansBold();
      const headerColor = PdfColor.fromInt(0xFFE65100);
      const darkGrey    = PdfColor.fromInt(0xFF424242);
      const lightGrey   = PdfColor.fromInt(0xFFF5F5F5);
      const redColor    = PdfColor.fromInt(0xFFC62828);
      const orangeColor = PdfColor.fromInt(0xFFEF6C00);

      final now      = DateTime.now();
      final overdue  = dueItems.where((e) => e.checkDate.isBefore(now)).toList();
      final upcoming = dueItems.where((e) => !e.checkDate.isBefore(now)).toList();

      // Statistikseite
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pdfHeader(ctx, '$title – Übersicht', fontBold, fontReg, headerColor),
            pw.SizedBox(height: 24),
            pw.Row(children: [
              _statBox('Überfällig',  '${overdue.length}',  fontBold, fontReg, redColor),
              pw.SizedBox(width: 12),
              _statBox('Bald fällig', '${upcoming.length}', fontBold, fontReg, orangeColor),
              pw.SizedBox(width: 12),
              _statBox('Gesamt',      '${dueItems.length}', fontBold, fontReg, headerColor),
            ]),
            pw.SizedBox(height: 20),
                () {
              final byStation = <String, int>{};
              for (final e in dueItems) {
                byStation[e.fireStation] = (byStation[e.fireStation] ?? 0) + 1;
              }
              return _statsTable('Verteilung nach Ortswehr', byStation,
                  fontBold, fontReg, darkGrey, headerColor);
            }(),
          ],
        ),
      ));

      // Detailseite
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => _pdfHeader(ctx, title, fontBold, fontReg, headerColor),
        footer: (ctx) => _pdfFooter(ctx, fontReg),
        build: (ctx) {
          pw.Widget sectionHdr(String label, PdfColor color) =>
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                    color: color, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text(label,
                    style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.white)),
              );

          pw.Widget dataRow(EquipmentModel e, int idx, bool isOverdue) {
            final days      = e.checkDate.difference(now).inDays;
            final daysLabel = isOverdue ? '${-days} Tage überfällig' : 'in $days Tagen';
            final rowColor  = isOverdue ? redColor : orangeColor;
            return pw.Container(
              color: idx % 2 == 1 ? lightGrey : PdfColors.white,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text(e.article,
                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Text(e.owner,
                    style: pw.TextStyle(font: fontReg, fontSize: 8, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Text(e.fireStation,
                    style: pw.TextStyle(font: fontReg, fontSize: 8, color: darkGrey))),
                pw.Expanded(flex: 1, child: pw.Text(e.size,
                    style: pw.TextStyle(font: fontReg, fontSize: 8, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Text(_dateFmt.format(e.checkDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                      color: rowColor, borderRadius: pw.BorderRadius.circular(3)),
                  child: pw.Text(daysLabel,
                      style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white)),
                )),
              ]),
            );
          }

          return [
            pw.Container(
              color: headerColor,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text('Artikel',   style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Besitzer',  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Ortswehr',  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 1, child: pw.Text('Größe',     style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Prüfdatum', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Fälligkeit',style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              ]),
            ),
            if (overdue.isNotEmpty) ...[
              sectionHdr('ÜBERFÄLLIG (${overdue.length})', redColor),
              ...overdue.asMap().entries.map((e) => dataRow(e.value, e.key, true)),
            ],
            if (upcoming.isNotEmpty) ...[
              sectionHdr('BALD FÄLLIG (${upcoming.length})', orangeColor),
              ...upcoming.asMap().entries.map((e) => dataRow(e.value, e.key, false)),
            ],
          ];
        },
      ));

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          'Pruefungs_Faelligkeit_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'PDF-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> _exportDueInspectionsExcel(
      BuildContext context,
      List<EquipmentModel> items,
      String title,
      ) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Fälligkeit'];
      _writeExcelHeader(sheet, [
        'Artikel', 'Typ', 'Größe', 'Ortswehr', 'Besitzer',
        'NFC-Tag', 'Status', 'Prüfdatum', 'Fälligkeit',
      ]);
      final now       = DateTime.now();
      final evenStyle = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#F9F9F9'));
      for (int r = 0; r < items.length; r++) {
        final e    = items[r];
        final days = e.checkDate.difference(now).inDays;
        _writeExcelRow(sheet, r + 1, [
          e.article, e.type, e.size, e.fireStation, e.owner,
          e.nfcTag, e.status,
          _dateFmt.format(e.checkDate),
          days < 0 ? '${-days} Tage überfällig' : 'in $days Tagen',
        ], r % 2 == 1 ? evenStyle : null);
      }
      excel.delete('Sheet1');
      await _saveExcel(context, excel, title);
    } catch (e) {
      _showError(context, 'Excel-Export fehlgeschlagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BESITZER-ÜBERSICHT
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportOwnerOverviewPdf(
      BuildContext context,
      List<EquipmentModel> allEquipment,
      Map<String, EquipmentModel> equipmentById, {
        String title = 'Besitzer-Übersicht',
      }) async {
    try {
      final pdf         = pw.Document();
      final fontReg     = await PdfGoogleFonts.notoSansRegular();
      final fontBold    = await PdfGoogleFonts.notoSansBold();
      const headerColor = PdfColor.fromInt(0xFF1A237E);
      const darkGrey    = PdfColor.fromInt(0xFF424242);
      const lightGrey   = PdfColor.fromInt(0xFFF5F5F5);

      final byOwner = <String, List<EquipmentModel>>{};
      for (final e in allEquipment) {
        final owner = e.owner.isNotEmpty ? e.owner : '(kein Besitzer)';
        byOwner.putIfAbsent(owner, () => []).add(e);
      }
      final owners = byOwner.keys.toList()..sort();

      // Statistikseite
      final byCount = {for (final o in owners) o: byOwner[o]!.length};
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pdfHeader(ctx, '$title – Übersicht', fontBold, fontReg, headerColor),
            pw.SizedBox(height: 24),
            pw.Row(children: [
              _statBox('Personen',        '${owners.length}',       fontBold, fontReg, headerColor),
              pw.SizedBox(width: 12),
              _statBox('Kleidungsstücke', '${allEquipment.length}', fontBold, fontReg, darkGrey),
            ]),
            pw.SizedBox(height: 20),
            _statsTable('Kleidung pro Person', byCount, fontBold, fontReg, darkGrey, headerColor),
          ],
        ),
      ));

      // Detailseite: Pro Besitzer eine Sektion
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => _pdfHeader(ctx, title, fontBold, fontReg, headerColor),
        footer: (ctx) => _pdfFooter(ctx, fontReg),
        build: (ctx) {
          final widgets = <pw.Widget>[];
          for (final owner in owners) {
            final items = byOwner[owner]!;
            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(top: 14, bottom: 4),
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                  color: headerColor, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(owner, style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white)),
                  pw.Text('${items.length} Stück', style: pw.TextStyle(font: fontReg, fontSize: 9, color: PdfColors.white)),
                ],
              ),
            ));
            widgets.add(pw.Container(
              color: const PdfColor.fromInt(0xFFE8EAF6),
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text('Artikel',         style: pw.TextStyle(font: fontBold, fontSize: 7, color: darkGrey))),
                pw.Expanded(flex: 1, child: pw.Text('Typ',             style: pw.TextStyle(font: fontBold, fontSize: 7, color: darkGrey))),
                pw.Expanded(flex: 1, child: pw.Text('Größe',           style: pw.TextStyle(font: fontBold, fontSize: 7, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Text('Ortswehr',        style: pw.TextStyle(font: fontBold, fontSize: 7, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Text('Status',          style: pw.TextStyle(font: fontBold, fontSize: 7, color: darkGrey))),
                pw.Expanded(flex: 2, child: pw.Text('Nächste Prüfung', style: pw.TextStyle(font: fontBold, fontSize: 7, color: darkGrey))),
              ]),
            ));
            for (int i = 0; i < items.length; i++) {
              final e = items[i];
              widgets.add(pw.Container(
                color: i % 2 == 1 ? lightGrey : PdfColors.white,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pw.Row(children: [
                  pw.Expanded(flex: 3, child: pw.Text(e.article,  style: pw.TextStyle(font: fontReg, fontSize: 7, color: darkGrey))),
                  pw.Expanded(flex: 1, child: pw.Text(e.type,     style: pw.TextStyle(font: fontReg, fontSize: 7, color: darkGrey))),
                  pw.Expanded(flex: 1, child: pw.Text(e.size,     style: pw.TextStyle(font: fontReg, fontSize: 7, color: darkGrey))),
                  pw.Expanded(flex: 2, child: pw.Text(e.fireStation, style: pw.TextStyle(font: fontReg, fontSize: 7, color: darkGrey))),
                  pw.Expanded(flex: 2, child: pw.Text(e.status,   style: pw.TextStyle(font: fontReg, fontSize: 7, color: darkGrey))),
                  pw.Expanded(flex: 2, child: pw.Text(_dateFmt.format(e.checkDate), style: pw.TextStyle(font: fontReg, fontSize: 7, color: darkGrey))),
                ]),
              ));
            }
          }
          return widgets;
        },
      ));

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          'Besitzer_Uebersicht_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'PDF-Export fehlgeschlagen: $e');
    }
  }

  static Future<void> exportOwnerOverviewExcel(
      BuildContext context,
      List<EquipmentModel> allEquipment,
      Map<String, EquipmentModel> equipmentById, {
        String title = 'Besitzer-Übersicht',
      }) async {
    try {
      final excel = Excel.createExcel();

      // Tab 1: Zusammenfassung
      final summarySheet = excel['Übersicht'];
      _writeExcelHeader(summarySheet, ['Besitzer', 'Anzahl', 'Ortswehr(en)', 'Status-Übersicht']);
      final byOwner = <String, List<EquipmentModel>>{};
      for (final e in allEquipment) {
        byOwner.putIfAbsent(e.owner.isNotEmpty ? e.owner : '(kein Besitzer)', () => []).add(e);
      }
      final owners    = byOwner.keys.toList()..sort();
      final evenStyle = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#F9F9F9'));
      for (int r = 0; r < owners.length; r++) {
        final o       = owners[r];
        final items   = byOwner[o]!;
        final stations = items.map((e) => e.fireStation).toSet().join(', ');
        final statusMap = <String, int>{};
        for (final e in items) statusMap[e.status] = (statusMap[e.status] ?? 0) + 1;
        _writeExcelRow(summarySheet, r + 1, [
          o, items.length.toString(), stations,
          statusMap.entries.map((e) => '${e.value}× ${e.key}').join(', '),
        ], r % 2 == 1 ? evenStyle : null);
      }

      // Tab 2: Alle Details sortiert nach Besitzer
      final detailSheet = excel['Details'];
      _writeExcelHeader(detailSheet, [
        'Besitzer', 'Artikel', 'Typ', 'Größe', 'Ortswehr',
        'Status', 'NFC-Tag', 'Barcode', 'Nächste Prüfung', 'Waschzyklen',
      ]);
      final sorted = allEquipment.toList()..sort((a, b) => a.owner.compareTo(b.owner));
      for (int r = 0; r < sorted.length; r++) {
        final e = sorted[r];
        _writeExcelRow(detailSheet, r + 1, [
          e.owner.isNotEmpty ? e.owner : '(kein Besitzer)',
          e.article, e.type, e.size, e.fireStation,
          e.status, e.nfcTag, e.barcode ?? '',
          _dateFmt.format(e.checkDate), e.washCycles.toString(),
        ], r % 2 == 1 ? evenStyle : null);
      }

      excel.delete('Sheet1');
      await _saveExcel(context, excel, title);
    } catch (e) {
      _showError(context, 'Excel-Export fehlgeschlagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // JAHRESBERICHT
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportYearlyReportPdf(
      BuildContext context, {
        required List<EquipmentModel> equipment,
        required List<MissionModel> missions,
        required List<EquipmentInspectionModel> inspections,
        required Map<String, EquipmentModel> equipmentById,
        required int year,
      }) async {
    try {
      final pdf         = pw.Document();
      final fontReg     = await PdfGoogleFonts.notoSansRegular();
      final fontBold    = await PdfGoogleFonts.notoSansBold();
      const headerColor = PdfColor.fromInt(0xFF00695C); // Teal
      const darkGrey    = PdfColor.fromInt(0xFF424242);
      const lightGrey   = PdfColor.fromInt(0xFFF5F5F5);
      const redColor    = PdfColor.fromInt(0xFFC62828);
      const greenColor  = PdfColor.fromInt(0xFF2E7D32);
      const orangeColor = PdfColor.fromInt(0xFFEF6C00);

      final missionsYear    = missions.where((m) => m.startTime.year == year).toList();
      final inspYear        = inspections.where((i) => i.inspectionDate.year == year).toList();
      final now             = DateTime.now();
      final overdue         = equipment.where((e) => e.checkDate.isBefore(now)).toList();
      final passedCount     = inspYear.where((i) => i.result == InspectionResult.passed).length;
      final passRate        = inspYear.isNotEmpty
          ? (passedCount / inspYear.length * 100).toStringAsFixed(1)
          : '–';

      // ── Seite 1: Übersicht ────────────────────────────────────────────────
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) {
          final byStation = <String, int>{};
          for (final e in equipment) {
            byStation[e.fireStation] = (byStation[e.fireStation] ?? 0) + 1;
          }
          final byMissionType = <String, int>{};
          for (final m in missionsYear) {
            final name = _missionTypeName(m.type);
            byMissionType[name] = (byMissionType[name] ?? 0) + 1;
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Titel
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: headerColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('JAHRESBERICHT $year',
                        style: pw.TextStyle(
                            font: fontBold, fontSize: 22, color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                        'Erstellt am ${_dateFmt.format(DateTime.now())} · Kleidungsverwaltung',
                        style: pw.TextStyle(
                            font: fontReg, fontSize: 9, color: const PdfColor.fromInt(0xCCFFFFFF))),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Kennzahlen-Reihe 1
              pw.Row(children: [
                _statBox('Kleidungsstücke', '${equipment.length}',    fontBold, fontReg, headerColor),
                pw.SizedBox(width: 12),
                _statBox('Einsätze $year',  '${missionsYear.length}', fontBold, fontReg, orangeColor),
                pw.SizedBox(width: 12),
                _statBox('Prüfungen $year', '${inspYear.length}',     fontBold, fontReg, const PdfColor.fromInt(0xFF1A237E)),
              ]),
              pw.SizedBox(height: 12),

              // Kennzahlen-Reihe 2
              pw.Row(children: [
                _statBox('Überfällige Prüfungen', '${overdue.length}', fontBold, fontReg,
                    overdue.isNotEmpty ? redColor : greenColor),
                pw.SizedBox(width: 12),
                _statBox('Bestandsquote', '$passRate%', fontBold, fontReg, greenColor),
                pw.SizedBox(width: 12),
                _statBox('Ortswehren', '${byStation.length}', fontBold, fontReg, darkGrey),
              ]),
              pw.SizedBox(height: 24),

              // Tabellen nebeneinander
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: _statsTable('Kleidung je Ortswehr', byStation,
                        fontBold, fontReg, darkGrey, headerColor),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: missionsYear.isEmpty
                        ? pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Einsatztypen $year',
                            style: pw.TextStyle(
                                font: fontBold, fontSize: 11, color: headerColor)),
                        pw.SizedBox(height: 8),
                        pw.Text('Keine Einsätze in $year',
                            style: pw.TextStyle(
                                font: fontReg, fontSize: 9, color: darkGrey)),
                      ],
                    )
                        : _statsTable('Einsatztypen $year', byMissionType,
                        fontBold, fontReg, darkGrey, orangeColor),
                  ),
                ],
              ),
            ],
          );
        },
      ));

      // ── Seite 2: Kleidungsbestand ─────────────────────────────────────────
      pdf.addPage(_buildEquipmentStatsPage(
          equipment, fontBold, fontReg, headerColor, darkGrey,
          'Kleidungsbestand $year'));

      // ── Seite 3: Prüfungen ────────────────────────────────────────────────
      if (inspYear.isNotEmpty) {
        pdf.addPage(_buildInspectionStatsPage(
            inspYear, fontBold, fontReg,
            const PdfColor.fromInt(0xFF1A237E), darkGrey,
            'Prüfungshistorie $year'));
      }

      // ── Seite 4: Überfällige Prüfungen ───────────────────────────────────
      if (overdue.isNotEmpty) {
        pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (ctx) => _pdfHeader(
              ctx, 'Überfällige Prüfungen', fontBold, fontReg, redColor),
          footer: (ctx) => _pdfFooter(ctx, fontReg),
          build: (ctx) => [
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: redColor,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                '${overdue.length} Kleidungsstücke haben eine überfällige Prüfung und benötigen sofortige Aufmerksamkeit.',
                style: pw.TextStyle(font: fontReg, fontSize: 9, color: PdfColors.white),
              ),
            ),
            pw.Container(
              color: redColor,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Row(children: [
                pw.Expanded(flex: 3, child: pw.Text('Artikel',   style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Besitzer',  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Ortswehr',  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 1, child: pw.Text('Größe',     style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Fällig am', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Seit',      style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white))),
              ]),
            ),
            ...overdue.asMap().entries.map((entry) {
              final e    = entry.value;
              final days = now.difference(e.checkDate).inDays;
              return pw.Container(
                color: entry.key % 2 == 1 ? lightGrey : PdfColors.white,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Row(children: [
                  pw.Expanded(flex: 3, child: pw.Text(e.article,
                      style: pw.TextStyle(font: fontBold, fontSize: 8, color: darkGrey))),
                  pw.Expanded(flex: 2, child: pw.Text(e.owner,
                      style: pw.TextStyle(font: fontReg, fontSize: 8, color: darkGrey))),
                  pw.Expanded(flex: 2, child: pw.Text(e.fireStation,
                      style: pw.TextStyle(font: fontReg, fontSize: 8, color: darkGrey))),
                  pw.Expanded(flex: 1, child: pw.Text(e.size,
                      style: pw.TextStyle(font: fontReg, fontSize: 8, color: darkGrey))),
                  pw.Expanded(flex: 2, child: pw.Text(_dateFmt.format(e.checkDate),
                      style: pw.TextStyle(font: fontBold, fontSize: 8, color: redColor))),
                  pw.Expanded(flex: 2, child: pw.Text('$days Tage',
                      style: pw.TextStyle(font: fontBold, fontSize: 8, color: redColor))),
                ]),
              );
            }),
          ],
        ));
      }

      // ── Seite 5: Einsätze ─────────────────────────────────────────────────
      if (missionsYear.isNotEmpty) {
        pdf.addPage(_buildMissionStatsPage(
            missionsYear, fontBold, fontReg, orangeColor, darkGrey,
            'Einsätze $year'));
      }

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          'Jahresbericht_${year}_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'Jahresbericht fehlgeschlagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ETIKETTEN-PDF
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportLabelsPdf(
      BuildContext context,
      List<EquipmentModel> equipment, {
        String title = 'Etiketten',
      }) async {
    try {
      final pdf      = pw.Document();
      final fontReg  = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();
      final fontMono = await PdfGoogleFonts.notoSansMonoRegular();

      const headerColor  = PdfColor.fromInt(0xFF4A148C); // Deep purple
      const darkGrey     = PdfColor.fromInt(0xFF424242);
      const borderColor  = PdfColor.fromInt(0xFFE0E0E0);

      // 4 Etiketten pro Seite (2×2 Grid)
      const cols    = 2;
      const rows    = 4;
      const perPage = cols * rows;

      for (int page = 0; page < (equipment.length / perPage).ceil(); page++) {
        final pageItems = equipment
            .skip(page * perPage)
            .take(perPage)
            .toList();

        // Mit leeren Slots auffüllen
        while (pageItems.length < perPage) {
          // leerer Slot zum Auffüllen
          pageItems.add(EquipmentModel(
            id: '', article: '', type: '', size: '', fireStation: '',
            owner: '', nfcTag: '', barcode: null, status: '',
            washCycles: 0, checkDate: DateTime(2000),
            createdAt: DateTime(2000), createdBy: '',
          ));
        }

        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) {
            final grid = <pw.Widget>[];
            for (int r = 0; r < rows; r++) {
              final rowWidgets = <pw.Widget>[];
              for (int c = 0; c < cols; c++) {
                final idx  = r * cols + c;
                final item = pageItems[idx];
                final isEmpty = item.id.isEmpty;

                rowWidgets.add(pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.all(6),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderColor, width: 1),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: isEmpty
                        ? pw.SizedBox()
                        : pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // QR-Code
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: item.nfcTag.isNotEmpty
                              ? item.nfcTag
                              : item.id,
                          width:  70,
                          height: 70,
                          color:  headerColor,
                        ),
                        pw.SizedBox(width: 10),
                        // Text
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              // Artikel
                              pw.Text(item.article,
                                  style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 10,
                                      color: headerColor),
                                  maxLines: 2),
                              pw.SizedBox(height: 3),
                              // Typ + Größe
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: pw.BoxDecoration(
                                  color: headerColor,
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                                child: pw.Text(
                                    '${item.type} · ${item.size}',
                                    style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 8,
                                        color: PdfColors.white)),
                              ),
                              pw.SizedBox(height: 5),
                              // Besitzer
                              pw.Row(children: [
                                pw.Text('Besitzer: ',
                                    style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 8,
                                        color: darkGrey)),
                                pw.Expanded(
                                  child: pw.Text(item.owner,
                                      style: pw.TextStyle(
                                          font: fontReg,
                                          fontSize: 8,
                                          color: darkGrey),
                                      maxLines: 1),
                                ),
                              ]),
                              // Ortswehr
                              pw.Row(children: [
                                pw.Text('Ortswehr: ',
                                    style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 8,
                                        color: darkGrey)),
                                pw.Expanded(
                                  child: pw.Text(item.fireStation,
                                      style: pw.TextStyle(
                                          font: fontReg,
                                          fontSize: 8,
                                          color: darkGrey),
                                      maxLines: 1),
                                ),
                              ]),
                              pw.SizedBox(height: 5),
                              // NFC-Tag in Monospace
                              if (item.nfcTag.isNotEmpty)
                                pw.Text(item.nfcTag,
                                    style: pw.TextStyle(
                                        font: fontMono,
                                        fontSize: 7,
                                        color: const PdfColor.fromInt(0xFF9E9E9E))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ));
                if (c < cols - 1) {
                  rowWidgets.add(pw.SizedBox(width: 0));
                }
              }
              grid.add(pw.Expanded(
                child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: rowWidgets),
              ));
            }

            return pw.Column(
              children: [
                // Kopfzeile
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('$title · ${equipment.length} Stück',
                          style: pw.TextStyle(
                              font: fontBold, fontSize: 9, color: darkGrey)),
                      pw.Text(
                          'Seite ${ctx.pageNumber} · ${_dateFmt.format(DateTime.now())}',
                          style: pw.TextStyle(
                              font: fontReg, fontSize: 8, color: const PdfColor.fromInt(0xFF9E9E9E))),
                    ],
                  ),
                ),
                pw.Divider(color: borderColor),
                pw.SizedBox(height: 4),
                ...grid,
              ],
            );
          },
        ));
      }

      final bytes = await pdf.save();
      await _handlePdfOutput(context, bytes,
          'Etiketten_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'Etiketten-Export fehlgeschlagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REINIGUNGSSCHEIN (EINSATZUNABHÄNGIG)
  // ══════════════════════════════════════════════════════════════════════════

  /// Erstellt einen Wäschereischein ohne Einsatzbezug — direkt aus dem
  /// Export-Screen mit freier Kleidungsauswahl.
  static Future<void> exportStandaloneCleaningReceiptPdf(
      BuildContext context,
      List<EquipmentModel> equipment, {
        String title = 'Reinigungsschein',
      }) async {
    if (equipment.isEmpty) {
      _showError(context, 'Keine Kleidungsstücke ausgewählt.');
      return;
    }
    try {
      // Dummy-MissionModel bauen — CleaningReceiptPdfService erwartet eines
      final dummyMission = MissionModel(
        id:                    'standalone',
        name:                  'Freie Reinigung',
        startTime:             DateTime.now(),
        type:                  'other',
        location:              '',
        description:           '',
        equipmentIds:          equipment.map((e) => e.id).toList(),
        fireStation:           equipment.first.fireStation,
        involvedFireStations:  equipment.map((e) => e.fireStation).toSet().toList(),
        createdBy:             '',
        createdAt:             DateTime.now(),
      );

      final bytes = await CleaningReceiptPdfService.generateCleaningReceiptPdf(
        mission:       dummyMission,
        equipmentList: equipment,
        customTitle:   title,
      );

      await _handlePdfOutput(context, bytes,
          'Reinigungsschein_${_fileDateFmt.format(DateTime.now())}.pdf');
    } catch (e) {
      _showError(context, 'Reinigungsschein fehlgeschlagen: $e');
    }
  }
}

class _PdfCol {
  final String label;
  final int flex;
  const _PdfCol(this.label, {required this.flex});
}
