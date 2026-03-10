import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/equipment_model.dart';
import '../models/mission_model.dart';
import '../services/cleaning_receipt_pdf_service.dart';

class CleaningReceiptPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final MissionModel mission;
  final List<EquipmentModel> equipmentList;
  final bool isRegenerated;
  final VoidCallback? onComplete;

  const CleaningReceiptPreviewScreen({
    Key? key,
    required this.pdfBytes,
    required this.mission,
    required this.equipmentList,
    this.isRegenerated = false,
    this.onComplete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Zähle Ausrüstung
    final counts = _countEquipmentTypes(equipmentList);

    return Scaffold(
      appBar: AppBar(
        title: Text(isRegenerated ? 'Wäschereischein (Archiv)' : 'Wäschereischein'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _sharePdf(),
            tooltip: 'Teilen',
          ),
        ],
      ),
      body: Column(
        children: [
          // Hinweis bei regenerierten Scheinen
          if (isRegenerated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dies ist eine Kopie des Wäschereischeins für bereits in der Reinigung befindliche Ausrüstung.',
                      style: TextStyle(color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),

          // Zusammenfassung
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Zusammenfassung',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Einsatz:', mission.name),
                  _buildInfoRow('Datum:', DateFormat('dd.MM.yyyy').format(mission.startTime)),
                  _buildInfoRow('Jacken:', '${counts.jackets}'),
                  _buildInfoRow('Hosen:', '${counts.pants}'),
                  if (counts.other > 0)
                    _buildInfoRow('Sonstige:', '${counts.other}'),
                  _buildInfoRow('Gesamt:', '${counts.total}'),
                ],
              ),
            ),
          ),

          // PDF-Vorschau
          Expanded(
            child: PdfPreview(
              build: (format) async => pdfBytes,
              allowPrinting: true,
              allowSharing: kIsWeb ? false : true,
              initialPageFormat: PdfPageFormat.a4,
              pdfFileName: 'reinigung_${DateFormat('yyyyMMdd').format(mission.startTime)}.pdf',
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _printPdf(),
                icon: const Icon(Icons.print),
                label: const Text('Drucken'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (onComplete != null) {
                    onComplete!();
                  } else {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.check),
                label: Text(isRegenerated ? 'Schließen' : 'Fertig'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  EquipmentCounts _countEquipmentTypes(List<EquipmentModel> equipmentList) {
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

  void _sharePdf() async {
    try {
      if (kIsWeb) {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'reinigung_${DateFormat('yyyyMMdd').format(mission.startTime)}.pdf',
        );
      } else {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'reinigung_${DateFormat('yyyyMMdd').format(mission.startTime)}.pdf',
        );
      }
    } catch (e) {
      print('Fehler beim Teilen: $e');
      await _printPdf();
    }
  }

  Future<void> _printPdf() async {
    await Printing.layoutPdf(
      onLayout: (format) => pdfBytes,
      name: 'Wäschereischein für ${mission.name}',
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}