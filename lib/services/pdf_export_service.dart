// lib/services/pdf_export_service.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/people_count.dart';

class PdfExportService {
  /// Generates a premium PDF and opens a preview window to save or print it.
  static Future<void> generateAndPreviewReport({
    required String reportType, // e.g., "Daily Report", "Monthly Report"
    required String dateRangeText, // e.g., "Jan 26, 2026 - Jan 27, 2026"
    required String cameraName,
    required List<PeopleCount> data,
    required int totalIn,
    required int totalOut,
    required String peakHour,
    String? customFileName, // NEW: Allows passing a nice name!
  }) async {
    // 1. Create a new PDF document
    final pdf = pw.Document(
      title: 'Traffic Analytics Report - $reportType',
      author: 'Retail Intelligence System',
    );

    // 2. Define our premium corporate colors
    final PdfColor primaryColor = PdfColor.fromHex('#0B0F19'); // Slate Dark
    final PdfColor accentColor = PdfColor.fromHex('#00E5FF'); // Cyan
    final PdfColor textLight = PdfColor.fromHex('#FFFFFF');
    final PdfColor textDark = PdfColor.fromHex('#333333');

    // 3. Build the PDF pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),

        // --- HEADER ---
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('RETAIL INTELLIGENCE', style: pw.TextStyle(color: accentColor, fontSize: 10, letterSpacing: 2, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Traffic Analytics Report', style: pw.TextStyle(color: primaryColor, fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(color: primaryColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                    child: pw.Text(cameraName.toUpperCase(), style: pw.TextStyle(color: textLight, fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text('Report Period: $reportType ($dateRangeText)', style: pw.TextStyle(color: PdfColors.grey700, fontSize: 12)),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 20),
            ],
          );
        },

        // --- FOOTER ---
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 20),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}  |  Generated on ${DateTime.now().toString().split('.')[0]}',
              style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 10),
            ),
          );
        },

        // --- BODY CONTENT ---
        build: (pw.Context context) {
          // Calculate the true total visitors
          int totalVisitors = (totalIn + totalOut) ~/ 2;

          return [
            // SUMMARY CARDS ROW
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfSummaryCard('TOTAL IN', totalIn.toString(), primaryColor, textLight),
                _buildPdfSummaryCard('TOTAL OUT', totalOut.toString(), primaryColor, textLight),
                _buildPdfSummaryCard('TOTAL VISITORS', totalVisitors.toString(), primaryColor, accentColor),
                _buildPdfSummaryCard('PEAK HOUR', peakHour, primaryColor, textLight),
              ],
            ),
            pw.SizedBox(height: 30),

            // DATA TABLE TITLE
            pw.Text('Detailed Traffic Breakdown', style: pw.TextStyle(color: primaryColor, fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),

            // THE DATA TABLE
            pw.TableHelper.fromTextArray(
              context: context,
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              headerStyle: pw.TextStyle(color: textLight, fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: pw.TextStyle(color: textDark, fontSize: 10),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
              // UPDATED HEADER: Changed "Total Activity" to "Total Visitors"
              headers: ['Date', 'Time', 'Door/Camera', 'Entrances (IN)', 'Exits (OUT)', 'Total Visitors'],
              data: data.map((item) {
                // THE MATH FIX: (IN + OUT) / 2
                int visitors = (item.inCount + item.outCount) ~/ 2;

                return [
                  item.date,
                  item.time,
                  item.doorName,
                  item.inCount.toString(),
                  item.outCount.toString(),
                  visitors.toString(), // Passes the corrected number!
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    // 4. Open the interactive Preview & Save Window
    // Use the custom name, or fallback to the timestamp
    String finalFileName = customFileName ?? 'Traffic_Report_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: finalFileName,
    );
  }

  // Helper widget to draw the premium summary boxes in the PDF
  static pw.Widget _buildPdfSummaryCard(String title, String value, PdfColor bgColor, PdfColor textColor) {
    return pw.Container(
      width: 110,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(color: PdfColors.grey400, fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(value, style: pw.TextStyle(color: textColor, fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}