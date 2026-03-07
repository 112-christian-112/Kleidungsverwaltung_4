// lib/screens/about_screen.dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Unbekannt',
    packageName: 'Unbekannt',
    version: 'Unbekannt',
    buildNumber: 'Unbekannt',
    buildSignature: 'Unbekannt',
  );

  bool _loadingVersions = false;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _packageInfo = info);
  }

  Future<void> _openVersionPicker() async {
    setState(() => _loadingVersions = true);
    try {
      final versions = await UpdateService.loadVersions();
      if (!mounted) return;
      if (versions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Versionsliste nicht verfügbar'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      UpdateService.showVersionPicker(
        context,
        UpdateInfo(
          latestVersion: versions.first.version,
          currentVersion: _packageInfo.version,
          apkUrl: versions.first.apkUrl,
          versions: versions,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingVersions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Über'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── App-Logo und Name ──────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.local_fire_department,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Einsatzkleidung',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version ${_packageInfo.version} (${_packageInfo.buildNumber})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── App-Version & Update ───────────────────────────────────────
            _buildSectionTitle(context, 'App-Version'),
            const SizedBox(height: 8),
            _buildCard(
              context,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: const Text('Installierte Version'),
                    subtitle: Text(
                        '${_packageInfo.version} (Build ${_packageInfo.buildNumber})'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _loadingVersions
                          ? Padding(
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            )
                          : Icon(
                              Icons.history,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                    ),
                    title: const Text('Frühere Versionen'),
                    subtitle:
                        const Text('Ältere App-Versionen herunterladen'),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _loadingVersions ? null : _openVersionPicker,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Über die App ───────────────────────────────────────────────
            _buildSectionTitle(context, 'Über die App'),
            const SizedBox(height: 8),
            _buildCard(
              context,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diese App wurde für die Verwaltung von Einsatzkleidung '
                    'der Feuerwehr entwickelt. Sie ermöglicht die Überwachung, '
                    'Inspektion und Verfolgung von Feuerwehrausrüstung mit NFC-Tags.',
                    style: TextStyle(fontSize: 14, height: 1.5),
                  ),
                  SizedBox(height: 12),
                  BulletPoint(text: 'Verwaltung von Einsatzkleidung'),
                  BulletPoint(
                      text: 'NFC-Integration für Ausrüstungsidentifikation'),
                  BulletPoint(
                      text:
                          'Barcode-Scanning für alternative Identifikation'),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Hilfsmethoden ──────────────────────────────────────────────────────────

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildCard(BuildContext context, {required Widget child}) {
    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

// ── BulletPoint Helper ────────────────────────────────────────────────────────

class BulletPoint extends StatelessWidget {
  final String text;
  const BulletPoint({Key? key, required this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14)),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
