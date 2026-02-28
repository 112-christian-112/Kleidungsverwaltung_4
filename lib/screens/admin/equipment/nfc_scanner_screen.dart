// screens/admin/equipment/nfc_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'dart:async';

class NfcScannerScreen extends StatefulWidget {
  const NfcScannerScreen({Key? key}) : super(key: key);

  @override
  State<NfcScannerScreen> createState() => _NfcScannerScreenState();
}

class _NfcScannerScreenState extends State<NfcScannerScreen> {
  bool _isScanning = true;
  String _nfcId = '';
  bool _nfcAvailable = false;
  String _errorMessage = '';
  bool _sessionActive = false;
  bool _continuousMode = true;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _checkNfcAvailability();
  }

  @override
  void dispose() {
    // Timer stoppen
    _resetTimer?.cancel();
    // NFC-Session stoppen, wenn Screen verlassen wird
    _stopNfcSession();
    super.dispose();
  }

  // Prüfen, ob NFC auf dem Gerät verfügbar ist
  Future<void> _checkNfcAvailability() async {
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      setState(() {
        _nfcAvailable = isAvailable;
        if (!isAvailable) {
          _errorMessage = 'NFC ist auf diesem Gerät nicht verfügbar.';
          _isScanning = false;
        } else {
          _startContinuousNfcSession();
        }
      });
    } catch (e) {
      setState(() {
        _nfcAvailable = false;
        _errorMessage = 'Fehler beim Prüfen der NFC-Verfügbarkeit: $e';
        _isScanning = false;
      });
    }
  }

  // Kontinuierliche NFC-Session - wird nur einmal gestartet
  void _startContinuousNfcSession() {
    if (_sessionActive) return;

    setState(() {
      _isScanning = true;
      _nfcId = '';
      _errorMessage = '';
      _sessionActive = true;
    });

    // Einmalige Session die kontinuierlich läuft
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          // Tag-ID extrahieren ohne Session zu stoppen
          var tagId = _extractTagIdFast(tag);

          if (tagId.isNotEmpty) {
            // UI aktualisieren aber Session NICHT stoppen
            if (mounted) {
              setState(() {
                _nfcId = tagId;
                _isScanning = false;
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _errorMessage = 'Konnte keine Tag-ID lesen. Bitte versuchen Sie es erneut.';
              });
              // Fehler nach 2 Sekunden zurücksetzen
              _resetTimer?.cancel();
              _resetTimer = Timer(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _errorMessage = '';
                    _isScanning = true;
                  });
                }
              });
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Fehler beim Lesen des NFC-Tags: $e';
            });
            // Fehler nach 3 Sekunden zurücksetzen
            _resetTimer?.cancel();
            _resetTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _errorMessage = '';
                  _isScanning = true;
                });
              }
            });
          }
        }
      },
      onError: (error) async {
        if (mounted) {
          setState(() {
            _errorMessage = 'NFC-Fehler: $error';
            _sessionActive = false;
          });
        }
      },
      // Erweiterte Polling-Optionen für bessere Kontrolle
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
    );
  }

  // Optimierte Tag-ID-Extraktion für schnellere Verarbeitung
  String _extractTagIdFast(NfcTag tag) {
    try {
      // Direkter Zugriff auf die häufigsten Tag-Typen für maximale Geschwindigkeit

      // NFC-A (ISO 14443-3A) - häufigster Typ zuerst
      if (tag.data.containsKey('nfca')) {
        final nfcA = tag.data['nfca']['identifier'];
        if (nfcA != null) {
          return _bytesToHex(nfcA);
        }
      }

      // NDEF-Format
      if (tag.data.containsKey('ndef')) {
        final ndefTag = tag.data['ndef']['identifier'];
        if (ndefTag != null) {
          return _bytesToHex(ndefTag);
        }
      }

      // NFC-B (ISO 14443-3B)
      if (tag.data.containsKey('nfcb')) {
        final nfcB = tag.data['nfcb']['applicationData'];
        if (nfcB != null) {
          return _bytesToHex(nfcB);
        }
      }

      // NFC-F (JIS 6319-4)
      if (tag.data.containsKey('nfcf')) {
        final nfcF = tag.data['nfcf']['identifier'];
        if (nfcF != null) {
          return _bytesToHex(nfcF);
        }
      }

      // NFC-V (ISO 15693)
      if (tag.data.containsKey('nfcv')) {
        final nfcV = tag.data['nfcv']['identifier'];
        if (nfcV != null) {
          return _bytesToHex(nfcV);
        }
      }

      // Schneller Fallback ohne aufwendige Suche
      for (final key in tag.data.keys) {
        final tagData = tag.data[key];
        if (tagData != null && tagData['identifier'] != null) {
          return _bytesToHex(tagData['identifier']);
        }
      }
    } catch (e) {
      print('Fehler bei schneller Tag-ID-Extraktion: $e');
    }

    return '';
  }

  // NFC-Session stoppen
  Future<void> _stopNfcSession() async {
    try {
      _resetTimer?.cancel();
      _sessionActive = false;
      await NfcManager.instance.stopSession();
    } catch (e) {
      // Fehler beim Stoppen ignorieren
      print('Fehler beim Stoppen der NFC-Session: $e');
    }
  }

  // Optimierte Bytes-zu-Hex Konvertierung
  String _bytesToHex(List<int> bytes) {
    if (bytes.isEmpty) return '';

    // Direkte String-Erstellung für bessere Performance
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      if (i > 0) buffer.write(':');
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }

  // Für neuen Scan - Session läuft weiter, nur UI wird zurückgesetzt
  void _resetForNewScan() {
    _resetTimer?.cancel();
    setState(() {
      _isScanning = true;
      _nfcId = '';
      _errorMessage = '';
    });
    // Session läuft kontinuierlich weiter - keine neue Meldung!
  }

  // Komplett neustarten (falls Session Probleme hat)
  void _restartSession() {
    _stopNfcSession().then((_) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _startContinuousNfcSession();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC-Tag scannen'),
        actions: [
          // Toggle für kontinuierlichen Modus
          IconButton(
            icon: Icon(_continuousMode ? Icons.loop : Icons.loop_outlined),
            onPressed: () {
              setState(() {
                _continuousMode = !_continuousMode;
              });
              if (_continuousMode && !_sessionActive) {
                _startContinuousNfcSession();
              }
            },
          ),
          // Info-Button für Benutzerhinweise
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('NFC-Scan Hinweise'),
                  content: const Text(
                      'Optimierter Scan-Modus:\n\n'
                          '• Die erste Android-Meldung erscheint beim App-Start\n'
                          '• Weitere Scans erfolgen OHNE neue Meldungen\n'
                          '• Halten Sie das NFC-Tag fest an die Rückseite\n'
                          '• Der kontinuierliche Modus ist standardmäßig aktiviert\n'
                          '• Bei Problemen: Loop-Symbol zum Neustarten antippen'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status-Indikator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _sessionActive ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _sessionActive ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _sessionActive ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                      size: 16,
                      color: _sessionActive ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sessionActive ? 'NFC Session aktiv' : 'NFC Session gestoppt',
                      style: TextStyle(
                        fontSize: 12,
                        color: _sessionActive ? Colors.green[800] : Colors.red[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_isScanning && _nfcAvailable)
                Column(
                  children: [
                    // Animierte NFC-Icon
                    TweenAnimationBuilder(
                      tween: Tween<double>(begin: 0.8, end: 1.2),
                      duration: const Duration(seconds: 1),
                      builder: (context, double scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: const Icon(
                            Icons.nfc,
                            size: 80,
                            color: Colors.blue,
                          ),
                        );
                      },
                      onEnd: () {
                        // Animation wiederholen während des Scannens
                        if (_isScanning && mounted) {
                          setState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Bereit zum Scannen',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Halten Sie den NFC-Tag an die Rückseite Ihres Smartphones',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _continuousMode
                          ? 'Kontinuierlicher Scan-Modus: Keine weiteren Meldungen'
                          : 'Einzelscan-Modus: Android-Meldung kann erscheinen',
                      style: TextStyle(
                          fontSize: 14,
                          color: _continuousMode ? Colors.green[600] : Colors.orange[600],
                          fontStyle: FontStyle.italic
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                )
              else if (!_isScanning && _nfcId.isNotEmpty)
                Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 80,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'NFC-Tag erfolgreich erkannt',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'NFC-ID:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _nfcId,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _resetForNewScan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Weiter scannen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context, _nfcId);
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Übernehmen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else if (_errorMessage.isNotEmpty)
                  Column(
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        size: 80,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Scan-Problem',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Versuchen Sie es erneut oder starten Sie die Session neu',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_nfcAvailable)
                            ElevatedButton.icon(
                              onPressed: _restartSession,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Session neustarten'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.cancel),
                            label: const Text('Abbrechen'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}