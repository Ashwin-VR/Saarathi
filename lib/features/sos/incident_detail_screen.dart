import 'package:accident_app/shared/models/incident_record.dart';
import 'package:accident_app/shared/services/incident_pdf_service.dart';
import 'package:accident_app/shared/services/profile_service.dart';
import 'package:accident_app/shared/utils/maps_launcher.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Incident detail screen — generates a rich PDF report from local data only.
/// No Gemini / network required. Profile data is loaded from SharedPreferences.
class IncidentDetailScreen extends StatefulWidget {
  final IncidentRecord incident;

  const IncidentDetailScreen({super.key, required this.incident});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  final _pdfService = IncidentPdfService();
  final _profileService = ProfileService();

  String? _pdfPath; // set once PDF is generated
  bool _generating = false;
  bool _sharing = false;
  bool _downloading = false;

  // ── Generate a rich local PDF (NO Gemini) ────────────────────────────────

  Future<void> _generateReport() async {
    setState(() => _generating = true);
    try {
      // 1. Load stored user profile (name, age, blood group, contacts, etc.)
      final profile = await _profileService.load();

      // 2. Extract sensor event data from the incident record
      final sensorEvent = widget.incident.sensorEvents.isNotEmpty
          ? widget.incident.sensorEvents.first
          : null;
      final trigger = sensorEvent?['trigger'] as String? ?? 'manual';
      final severity = sensorEvent?['severity'] as String?;
      final peakG = sensorEvent?['peak_g'] as double?;
      final gClass = sensorEvent?['g_class'] as String?;

      // 3. Derive duration string
      final durationMs = widget.incident.endTime
          .difference(widget.incident.startTime)
          .inSeconds;
      final durationLabel = '${durationMs}s';

      // 4. Build severity/type label
      final severityLabel =
          [trigger.toUpperCase(), if (severity != null) '/ $severity']
              .join(' ');

      // 5. Generate fully local structured PDF with all profile + sensor data
      // Future.microtask keeps this off the UI frame pipeline
      final path = await Future.microtask(() => _pdfService.generateSosPdfExtended(
            // ── Profile ──────────────────────────────────────────────────────
            userName: profile.name,
            gender: profile.gender,
            age: profile.age,
            bloodGroup: profile.bloodGroup,
            sos1: profile.sos1,
            sos2: profile.sos2,
            // ── Event ────────────────────────────────────────────────────────
            eventTime: widget.incident.startTime,
            lat: widget.incident.lat,
            lng: widget.incident.lng,
            trigger: trigger,
            severity: severityLabel,
            // ── Sensor signals ───────────────────────────────────────────────
            peakG: peakG,
            gClassification: gClass,
            durationMs: durationLabel,
            // No Gemini triage — leave null so the section is omitted cleanly
            triageSummary: null,
            triageRiskPercent: null,
            aiNarrative: null,
          ));

      if (!mounted) return;
      setState(() {
        _pdfPath = path;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate PDF: $e')),
      );
    }
  }

  // ── Share PDF ─────────────────────────────────────────────────────────────

  Future<void> _shareReport() async {
    if (_pdfPath == null) return;
    setState(() => _sharing = true);
    try {
      await Share.shareXFiles(
        [XFile(_pdfPath!)],
        text: 'Emergency SOS Incident Report',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Save to Downloads / external storage ─────────────────────────────────

  Future<void> _downloadReport() async {
    if (_pdfPath == null) return;
    setState(() => _downloading = true);
    try {
      final savedPath =
          await _pdfService.savePdfToExternalStorage(_pdfPath!);
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report saved to Downloads')),
        );
        try {
          await IncidentPdfService.openPdf(savedPath);
        } catch (_) {}
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save report file')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lat = widget.incident.lat;
    final lng = widget.incident.lng;

    final sensorEvent = widget.incident.sensorEvents.isNotEmpty
        ? widget.incident.sensorEvents.first
        : null;
    final trigger = sensorEvent?['trigger'] as String? ?? 'manual';
    final severity = sensorEvent?['severity'] as String?;

    final cs = Theme.of(context).colorScheme;
    final pdfReady = _pdfPath != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Incident Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Incident ID card ────────────────────────────────────────────
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Incident ID',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.incident.incidentId,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Timing card ──────────────────────────────────────────────────
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _rowLabel('Start',
                      widget.incident.startTime.toLocal().toString()),
                  const SizedBox(height: 4),
                  _rowLabel(
                      'End', widget.incident.endTime.toLocal().toString()),
                  const SizedBox(height: 4),
                  _rowLabel('Trigger', trigger),
                  if (severity != null) ...[
                    const SizedBox(height: 4),
                    _rowLabel('Severity', severity),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── View location button ─────────────────────────────────────────
          if (lat != null && lng != null)
            OutlinedButton.icon(
              onPressed: () => openInGoogleMaps(lat, lng),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('View Location on Map'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          const SizedBox(height: 16),

          // ── Generate PDF button ──────────────────────────────────────────
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor:
                  pdfReady ? Colors.green.shade700 : cs.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _generating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(pdfReady
                    ? Icons.check_circle_outline
                    : Icons.picture_as_pdf_outlined),
            label: Text(
              _generating
                  ? 'Generating PDF...'
                  : pdfReady
                      ? 'Report Ready - Regenerate'
                      : 'Generate Report PDF',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: _generating ? null : _generateReport,
          ),

          // ── Actions (shown after PDF is ready) ───────────────────────────
          if (pdfReady) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'PDF generated with profile + incident data',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),

            // Open PDF
            OutlinedButton.icon(
              onPressed: () => IncidentPdfService.openPdf(_pdfPath!),
              icon: const Icon(Icons.open_in_new_outlined),
              label: const Text('Open PDF'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),

            // Share + Download row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sharing ? null : _shareReport,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(
                        _sharing ? 'Sharing...' : 'Share PDF',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _downloading ? null : _downloadReport,
                    icon: const Icon(Icons.download),
                    label: Text(
                        _downloading ? 'Saving...' : 'Save to Downloads',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _rowLabel(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
