// lib/services/pdf_export_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // 🚀 For kIsWeb
import 'package:printing/printing.dart';  // 🚀 For web PDF sharing
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/people_count.dart';

class PdfExportService {
  /// Generates a premium PDF and saves it directly to the local disk (or downloads on Web).
  static Future<void> generateAndSaveReport({
    required String reportType,
    required String dateRangeText,
    required String cameraName,
    required List<PeopleCount> data,
    required int totalIn,
    required int totalOut,
    required String peakHour,
    required String outputPath,
    // 🚀 STORE PROFILE PARAMETERS
    required String storeName,
    required String storeLocation,
    String? storeLogoPath,
    // 🚀 POS PARAMETERS
    required double revenue,
    required int clients,
    required double conversionRate,
    required double avgBasket,
    required double upt,
    // 🚀 NEW: MALL VS RETAIL MODE FLAG
    required bool enablePosFeatures,
  }) async {
    // 1. Create a new PDF document
    final pdf = pw.Document(
      title: 'Traffic Analytics Report - $reportType',
      author: storeName, // Updated to use the dynamic store name
    );

    // 2. Define our premium corporate colors
    final PdfColor primaryColor = PdfColor.fromHex('#0B0F19'); // Slate Dark
    final PdfColor accentColor = PdfColor.fromHex('#00E5FF'); // Cyan
    final PdfColor textLight = PdfColor.fromHex('#FFFFFF');
    final PdfColor textDark = PdfColor.fromHex('#333333');

    // 🚀 3. Load the Store Logo if it exists
    pw.MemoryImage? logoImage;
    // 🌐 WEB SAFETY: dart:io File operations crash on the web.
    // We only attempt to load the local logo file if we are NOT on the web.
    if (!kIsWeb && storeLogoPath != null && storeLogoPath.isNotEmpty) {
      final file = File(storeLogoPath);
      if (file.existsSync()) {
        logoImage = pw.MemoryImage(file.readAsBytesSync());
      }
    }

    // 4. Build the PDF pages
    pdf.addPage(
      pw.MultiPage(
        // 🚀 ULTIMATE FIX: Override the default 20-page limit!
        // This allows up to 5000 pages for massive yearly/all-time data exports.
        maxPages: 5000,

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
                  pw.Row(
                    children: [
                      // Render the logo if available
                      if (logoImage != null) ...[
                        pw.Container(
                          width: 50,
                          height: 50,
                          decoration: pw.BoxDecoration(
                            shape: pw.BoxShape.circle,
                            image: pw.DecorationImage(image: logoImage, fit: pw.BoxFit.cover),
                          ),
                        ),
                        pw.SizedBox(width: 16),
                      ],
                      // 🚀 Explicit Client and Location formatting on Top Left!
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                              'CLIENT: ${storeName.toUpperCase()}',
                              style: pw.TextStyle(
                                color: accentColor,
                                fontSize: 14,
                                letterSpacing: 1.5,
                                fontWeight: pw.FontWeight.bold,
                              )
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                              'LOCATION: ${storeLocation.toUpperCase()}',
                              style: pw.TextStyle(
                                color: PdfColors.grey700,
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                              )
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                              'Traffic Analytics Report',
                              style: pw.TextStyle(
                                color: primaryColor,
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                              )
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Camera/Door Badge
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
          int totalVisitors = (totalIn + totalOut) ~/ 2;

          return [
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildPdfSummaryCard('TOTAL IN', totalIn.toString(), primaryColor, textLight),
                _buildPdfSummaryCard('TOTAL OUT', totalOut.toString(), primaryColor, textLight),
                _buildPdfSummaryCard('TOTAL VISITORS', totalVisitors.toString(), primaryColor, accentColor),
                _buildPdfSummaryCard('PEAK HOUR', peakHour, primaryColor, textLight),

                // 🚀 Conditionally add POS cards only if Retail Mode is enabled
                if (enablePosFeatures) ...[
                  _buildPdfSummaryCard('REVENUE', '${revenue.toStringAsFixed(0)} DZD', PdfColor.fromHex('#E8F5E9'), PdfColor.fromHex('#2E7D32')),
                  _buildPdfSummaryCard('CLIENTS', clients.toString(), PdfColor.fromHex('#F3E5F5'), PdfColor.fromHex('#6A1B9A')),
                  _buildPdfSummaryCard('CONV RATE', '${conversionRate.toStringAsFixed(1)}%', PdfColor.fromHex('#FFF3E0'), PdfColor.fromHex('#EF6C00')),
                  _buildPdfSummaryCard('AVG BASKET', '${avgBasket.toStringAsFixed(0)} DZD', PdfColor.fromHex('#E3F2FD'), PdfColor.fromHex('#1565C0')),
                  _buildPdfSummaryCard('UPT', upt.toStringAsFixed(2), PdfColor.fromHex('#FCE4EC'), PdfColor.fromHex('#C2185B')),
                ]
              ],
            ),
            pw.SizedBox(height: 30),

            pw.Text('Detailed Traffic Breakdown', style: pw.TextStyle(color: primaryColor, fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),

            pw.TableHelper.fromTextArray(
              context: context,
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              headerStyle: pw.TextStyle(color: textLight, fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: pw.TextStyle(color: textDark, fontSize: 10),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
              headers: ['Date', 'Time', 'Door/Camera', 'Entrances (IN)', 'Exits (OUT)', 'Total Visitors'],
              data: data.map((item) {
                int visitors = (item.inCount + item.outCount) ~/ 2;
                return [
                  item.date,
                  item.time,
                  item.doorName,
                  item.inCount.toString(),
                  item.outCount.toString(),
                  visitors.toString(),
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    final Uint8List bytes = await pdf.save();

    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Traffic_Analytics_${reportType}_$dateRangeText.pdf',
      );
    } else {
      final File file = File(outputPath);
      await file.writeAsBytes(bytes);
    }
  }

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
          pw.Text(value, style: pw.TextStyle(color: textColor, fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}