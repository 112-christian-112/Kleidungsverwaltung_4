// widgets/nfc_scan_sheet.dart
//
// Wiederverwendbares NFC-Scan BottomSheet.
// Kapselt NfcManager-Session vollständig — kein Navigator.push nötig.
// Wird von EquipmentScanScreen (Einzelscan) und PrueftagScreen genutzt.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NfcScanSheet extends StatefulWidget {
  /// Callback wenn Tag erfolgreich erkannt wurde
  final void Function(String tagId) onTagScanned;

  /// Label unter dem Scan-Icon — kontextabhängig
  final String? hinweisText;

  const NfcScanSheet({
    Key? key,
    required this.onTagScanned,
    this.hinweisText,
  }) : super(key: key);

  /// Öffnet das Sheet und gibt die gescannte Tag-ID zurück (oder null bei Abbruch).
  static Future<String?> zeigen(
    BuildContext context, {
    String? hinweisText,
  }) async {
    bool nfcVerfuegbar = false;
    try {
      nfcVerfuegbar = await NfcManager.instance.isAvailable();
    } catch (_) {}

    if (!nfcVerfuegbar || !context.mounted) return null;

    String? scannedId;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => NfcScanSheet(
        hinweisText: hinweisText,
        onTagScanned: (tagId) {
          scannedId = tagId;
          Navigator.of(sheetCtx).pop();
        },
      ),
    );

    try { await NfcManager.instance.stopSession(); } catch (_) {}

    return scannedId;
  }

  @override
  State<NfcScanSheet> createState() => _NfcScanSheetState();
}

class _NfcScanSheetState extends State<NfcScanSheet>
    with SingleTickerProviderStateMixin {
  bool _tagGefunden = false;
  String _fehler = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startSession();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startSession() {
    setState(() { _tagGefunden = false; _fehler = ''; });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final tagId = _extractTagId(tag);
        if (tagId.isEmpty) {
          if (mounted) setState(() => _fehler = 'Tag konnte nicht gelesen werden.');
          return;
        }
        HapticFeedback.heavyImpact();
        if (mounted) setState(() => _tagGefunden = true);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) widget.onTagScanned(tagId);
      },
      onError: (e) async {
        if (mounted) setState(() => _fehler = 'NFC-Fehler: $e');
      },
    );
  }

  String _extractTagId(NfcTag tag) {
    try {
      final rawId = tag.data['nfca']?['identifier'] as List<int>? ??
          tag.data['nfcb']?['applicationData'] as List<int>? ??
          tag.data['nfcf']?['identifier'] as List<int>? ??
          tag.data['nfcv']?['identifier'] as List<int>?;
      if (rawId != null && rawId.isNotEmpty) {
        return rawId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }
      final records = tag.data['ndef']?['cachedMessage']?['records'] as List?;
      if (records != null && records.isNotEmpty) {
        final payload = records.first['payload'] as List<int>?;
        if (payload != null && payload.length > 3) {
          return String.fromCharCodes(payload.skip(3));
        }
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Pulsierendes NFC-Icon
            ScaleTransition(
              scale: _tagGefunden || _fehler.isNotEmpty
                  ? const AlwaysStoppedAnimation(1.0)
                  : _pulseAnimation,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _tagGefunden
                      ? Colors.green.shade100
                      : _fehler.isNotEmpty
                          ? Colors.red.shade50
                          : Colors.indigo.shade50,
                ),
                child: Icon(
                  _tagGefunden
                      ? Icons.check_circle
                      : _fehler.isNotEmpty
                          ? Icons.error_outline
                          : Icons.nfc,
                  size: 52,
                  color: _tagGefunden
                      ? Colors.green.shade700
                      : _fehler.isNotEmpty
                          ? Colors.red.shade400
                          : Colors.indigo.shade400,
                ),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _tagGefunden
                  ? 'Tag erkannt!'
                  : _fehler.isNotEmpty
                      ? 'Fehler beim Lesen'
                      : 'Gerät an NFC-Tag halten',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _tagGefunden
                        ? Colors.green.shade700
                        : _fehler.isNotEmpty
                            ? Colors.red.shade600
                            : null,
                  ),
            ),

            const SizedBox(height: 4),

            Text(
              _fehler.isNotEmpty
                  ? _fehler
                  : widget.hinweisText ?? 'NFC muss auf dem Gerät aktiviert sein',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),

            if (_fehler.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _startSession,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Erneut versuchen'),
              ),
            ],

            const SizedBox(height: 20),

            // Abbrechen
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Abbrechen',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
