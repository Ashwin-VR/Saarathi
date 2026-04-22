import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final class IncidentPdfService {
  // ── Unicode sanitizer ──────────────────────────────────────────────────────
  /// Replaces Unicode symbols that the default PDF Helvetica font cannot render
  /// (it only supports Latin-1 / ISO 8859-1).  Missing glyphs show as blank
  /// or cause layout artifacts.  Call this on every string before passing it
  /// to pw.Text().
  static String _sanitize(String text) {
    return text
        .replaceAll('\u2022', '-')    // • bullet point
        .replaceAll('\u2026', '...')  // … horizontal ellipsis
        .replaceAll('\u2265', '>=')  // ≥ greater-than-or-equal
        .replaceAll('\u2264', '<=')  // ≤ less-than-or-equal
        .replaceAll('\u00b0', ' deg') // ° degree sign
        .replaceAll('\u2013', '-')   // – en dash
        .replaceAll('\u2014', '--')  // — em dash
        .replaceAll('\u2018', "'")   // ' left single quotation mark
        .replaceAll('\u2019', "'")   // ' right single quotation mark
        .replaceAll('\u201c', '"')   // " left double quotation mark
        .replaceAll('\u201d', '"')   // " right double quotation mark
        // Strip any remaining non-Latin-1 characters (emoji, CJK, etc.)
        .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');
  }

  // ── Basic text export (legacy) ─────────────────────────────────────────────
  Future<String> exportPdf(String reportText) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Text(_sanitize(reportText)),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/incident-report.pdf');
    // Yield to the UI thread before the heavy serialization step.
    await Future.delayed(Duration.zero);
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  // ── Rich SOS report PDF ────────────────────────────────────────────────────
  Future<String> generateSosPdf({
    // Profile
    String? userName,
    String? gender,
    String? age,
    String? bloodGroup,
    String? sos1,
    String? sos2,
    // Event
    DateTime? eventTime,
    double? lat,
    double? lng,
    double? peakG,
    String? gClassification,
    String? severity,
    String? trigger,
  }) async {
    final doc = pw.Document();
    final now = eventTime ?? DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final mapsLink = (lat != null && lng != null)
        ? 'https://www.google.com/maps?q=$lat,$lng'
        : 'N/A';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red800,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      _sanitize('EMERGENCY SOS INCIDENT REPORT'),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _sanitize(dateStr),
                      style: pw.TextStyle(
                        color: PdfColors.grey200,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Profile section
              _pdfSectionHeader('PROFILE'),
              pw.SizedBox(height: 8),
              _pdfTable([
                ['Name', userName ?? 'Not set'],
                ['Gender', gender ?? 'Not set'],
                ['Age', age ?? 'Not set'],
                ['Blood Group', bloodGroup ?? 'Not set'],
                ['SOS Contact 1', sos1 ?? 'Not set'],
                ['SOS Contact 2', sos2 ?? 'Not set'],
              ]),
              pw.SizedBox(height: 16),

              // Event details
              _pdfSectionHeader('INCIDENT DETAILS'),
              pw.SizedBox(height: 8),
              _pdfTable([
                ['Date / Time', dateStr],
                [
                  'Latitude',
                  lat != null ? lat.toStringAsFixed(6) : 'Not available'
                ],
                [
                  'Longitude',
                  lng != null ? lng.toStringAsFixed(6) : 'Not available'
                ],
                ['Google Maps', mapsLink],
                ['Trigger', trigger ?? 'Manual'],
                ['Severity', severity ?? 'Unknown'],
              ]),
              pw.SizedBox(height: 16),

              // G-force
              _pdfSectionHeader('G-FORCE ANALYSIS'),
              pw.SizedBox(height: 8),
              _pdfTable([
                [
                  'Peak G-force',
                  peakG != null
                      ? '${peakG.toStringAsFixed(2)} G'
                      : 'Not recorded'
                ],
                ['Classification', gClassification ?? 'Not classified'],
                [
                  'Threshold',
                  '>= 2.5G = possible vehicular accident'
                ],
              ]),
              pw.SizedBox(height: 24),

              // Footer
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text(
                _sanitize('Generated by Emergency SOS App - $dateStr'),
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/sos_report_${now.millisecondsSinceEpoch}.pdf');
    // Yield to the UI thread before the heavy serialization step.
    await Future.delayed(Duration.zero);
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  // ── Extended SOS report PDF (with triage, sensors, AI narrative) ────────────
  Future<String> generateSosPdfExtended({
    // Profile
    String? userName,
    String? gender,
    String? age,
    String? bloodGroup,
    String? sos1,
    String? sos2,
    // Event
    DateTime? eventTime,
    double? lat,
    double? lng,
    double? peakG,
    String? gClassification,
    String? severity,
    String? trigger,
    // Extended sensor data
    String? durationMs,
    String? stillnessRatio,
    String? speedKmh,
    // Gemini triage
    String? triageSummary,
    int? triageRiskPercent,
    // AI narrative
    String? aiNarrative,
  }) async {
    final doc = pw.Document();
    final now = eventTime ?? DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final mapsLink = (lat != null && lng != null)
        ? 'https://www.google.com/maps?q=$lat,$lng'
        : 'N/A';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return [
            // ── Header ───────────────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.red800,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _sanitize('EMERGENCY SOS INCIDENT REPORT'),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _sanitize(dateStr),
                    style: const pw.TextStyle(
                      color: PdfColors.grey200,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // ── Profile ───────────────────────────────────────────────────────
            _pdfSectionHeader('PROFILE'),
            pw.SizedBox(height: 8),
            _pdfTable([
              ['Name', userName ?? 'Not set'],
              ['Gender', gender ?? 'Not set'],
              ['Age', age ?? 'Not set'],
              ['Blood Group', bloodGroup ?? 'Not set'],
              ['SOS Contact 1', sos1 ?? 'Not set'],
              ['SOS Contact 2', sos2 ?? 'Not set'],
            ]),
            pw.SizedBox(height: 16),

            // ── Incident details ─────────────────────────────────────────────
            _pdfSectionHeader('INCIDENT DETAILS'),
            pw.SizedBox(height: 8),
            _pdfTable([
              ['Date / Time', dateStr],
              [
                'Latitude',
                lat != null ? lat.toStringAsFixed(6) : 'Not available'
              ],
              [
                'Longitude',
                lng != null ? lng.toStringAsFixed(6) : 'Not available'
              ],
              ['Google Maps', mapsLink],
              ['Trigger', trigger ?? 'Manual'],
              ['Severity / Type', severity ?? 'Unknown'],
            ]),
            pw.SizedBox(height: 16),

            // ── G-force & sensor signals ─────────────────────────────────────
            _pdfSectionHeader('SENSOR SIGNALS'),
            pw.SizedBox(height: 8),
            _pdfTable([
              [
                'Peak G-force',
                peakG != null
                    ? '${peakG.toStringAsFixed(2)} G'
                    : 'Not recorded'
              ],
              ['G Classification', gClassification ?? 'Not classified'],
              ['Impact Duration', durationMs ?? 'N/A'],
              ['Stillness Ratio', stillnessRatio ?? 'N/A'],
              ['Speed at Event', speedKmh ?? 'N/A'],
              ['Threshold', '>= 2.5 G = possible vehicular accident'], // ASCII only
            ]),
            pw.SizedBox(height: 16),

            // ── Gemini triage ─────────────────────────────────────────────────
            if (triageSummary != null || triageRiskPercent != null) ...[
              _pdfSectionHeader('AI TRIAGE (Gemini 2.0 Flash)'),
              pw.SizedBox(height: 8),
              _pdfTable([
                ['Triage Summary', triageSummary ?? 'N/A'],
                [
                  'Injury Risk',
                  triageRiskPercent != null
                      ? '$triageRiskPercent%'
                      : 'N/A'
                ],
              ]),
              pw.SizedBox(height: 16),
            ],

            // ── AI narrative ──────────────────────────────────────────────────
            if (aiNarrative != null && aiNarrative.isNotEmpty) ...[
              _pdfSectionHeader('AI INCIDENT NARRATIVE'),
              pw.SizedBox(height: 8),
              // pw.Border(left:...) is broken in pdf ^3.12 — use a Row accent instead.
              pw.Container(
                color: PdfColors.grey100,
                padding: const pw.EdgeInsets.all(0),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left accent bar
                    pw.Container(
                      width: 4,
                      color: PdfColors.red800,
                      padding: const pw.EdgeInsets.symmetric(vertical: 12),
                      child: pw.SizedBox(),
                    ),
                    // Narrative text
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(10),
                        child: pw.Text(
                          _sanitize(aiNarrative),
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // ── Footer ────────────────────────────────────────────────────────
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
              _sanitize('Generated by Emergency SOS App - $dateStr'),
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey600,
              ),
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/sos_report_ext_${now.millisecondsSinceEpoch}.pdf');
    // Yield to the UI thread before the heavy serialization step.
    await Future.delayed(Duration.zero);
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  pw.Widget _pdfSectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        _sanitize(title),
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blueGrey800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  pw.Widget _pdfTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(2),
      },
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                _sanitize(row[0]),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                _sanitize(row[1]),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── Save PDF to user-accessible external storage ─────────────────────────
  /// Copies [sourcePath] to Downloads (Android) or Documents (iOS/other).
  /// Returns the new file path on success, null on failure.
  Future<String?> savePdfToExternalStorage(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      Directory destDir;
      if (Platform.isAndroid) {
        // Try the standard Downloads folder first
        destDir = Directory('/storage/emulated/0/Download');
        if (!destDir.existsSync()) {
          // Fallback to getExternalStorageDirectory
          destDir = await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory();
        }
      } else {
        destDir = await getApplicationDocumentsDirectory();
      }

      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      final fileName =
          'sos_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final destPath = '${destDir.path}/$fileName';
      await sourceFile.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  // ── Legacy save to downloads (kept for backward compat) ───────────────────
  Future<String?> savePdfToDownloads(String sourcePath) async {
    return savePdfToExternalStorage(sourcePath);
  }

  // ── Open a PDF file with the native viewer ────────────────────────────────
  static Future<void> openPdf(String filePath) async {
    await OpenFile.open(filePath);
  }
}
