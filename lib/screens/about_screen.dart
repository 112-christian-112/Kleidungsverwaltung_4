// screens/about_screen.dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../changelog.dart';

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

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
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
            // App-Logo und Name
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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

            // App-Beschreibung
            _buildSectionTitle(context, 'Über die App'),
            const SizedBox(height: 8),
            _buildCard(
              context,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diese App wurde für die Verwaltung von Einsatzkleidung der Feuerwehr entwickelt. Sie ermöglicht die Überwachung, Inspektion und Verfolgung von Feuerwehrausrüstung mit NFC-Tags.',
                    style: TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Entwickler
            _buildSectionTitle(context, 'Entwickler'),
            const SizedBox(height: 8),
            _buildCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Christian Greve',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Kontakt: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      GestureDetector(
                        onTap: () => _launchEmail('zeugwart.wol@gmail.com'),
                        child: Text(
                          'zeugwart.wol@gmail.com',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Technische Informationen
            _buildSectionTitle(context, 'Technische Informationen'),
            const SizedBox(height: 8),
            _buildCard(
              context,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diese App wurde mit folgenden Technologien entwickelt:',
                    style: TextStyle(height: 1.5),
                  ),
                  SizedBox(height: 8),
                  BulletPoint(text: 'Flutter Framework'),
                  BulletPoint(text: 'Firebase (Authentifizierung, Firestore, Cloud Functions)'),
                  BulletPoint(text: 'NFC-Integration für Ausrüstungsidentifikation'),
                  BulletPoint(text: 'Barcode-Scanning für alternative Identifikation'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Changelog ─────────────────────────────────────────────────────
            _buildSectionTitle(context, 'Changelog'),
            const SizedBox(height: 8),
            _buildChangelogSection(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Changelog ──────────────────────────────────────────────────────────────

  Widget _buildChangelogSection(BuildContext context) {
    return Column(
      children: changelog.asMap().entries.map((entry) {
        final isLatest = entry.key == 0;
        return _buildVersionCard(context, entry.value, isLatest: isLatest);
      }).toList(),
    );
  }

  Widget _buildVersionCard(BuildContext context, ChangelogEntry entry,
      {bool isLatest = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isLatest ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isLatest
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isLatest,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: isLatest
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            child: Icon(
              Icons.rocket_launch,
              size: 16,
              color: isLatest ? Colors.white : Colors.grey.shade600,
            ),
          ),
          title: Row(
            children: [
              Text(
                'v${entry.version}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isLatest
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              if (isLatest) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Aktuell',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            entry.date,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          children: entry.changes
              .map((item) => _buildChangeItem(context, item))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildChangeItem(BuildContext context, ChangelogItem item) {
    Color chipColor;
    IconData chipIcon;
    String chipLabel;

    switch (item.type) {
      case 'new':
        chipColor = Colors.green;
        chipIcon = Icons.add_circle_outline;
        chipLabel = 'Neu';
        break;
      case 'fix':
        chipColor = Colors.orange;
        chipIcon = Icons.bug_report_outlined;
        chipLabel = 'Fix';
        break;
      case 'improvement':
        chipColor = Colors.blue;
        chipIcon = Icons.trending_up;
        chipLabel = 'Verbesserung';
        break;
      case 'breaking':
        chipColor = Colors.red;
        chipIcon = Icons.warning_amber_outlined;
        chipLabel = 'Wichtig';
        break;
      default:
        chipColor = Colors.grey;
        chipIcon = Icons.info_outline;
        chipLabel = 'Info';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: chipColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chipColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chipIcon, size: 11, color: chipColor),
                const SizedBox(width: 3),
                Text(
                  chipLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: chipColor,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hilfsmethoden ──────────────────────────────────────────────────────────

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildCard(BuildContext context, {required Widget child}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
