import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Shows a report as a PDF preview with print, save/share and paper size.
/// [builder] is called again whenever the paper size changes.
class ReportPreviewScreen extends StatelessWidget {
  final String title;
  final String fileName;
  final Future<Uint8List> Function(PdfPageFormat format) builder;
  const ReportPreviewScreen(
      {super.key, required this.title, required this.fileName, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: builder,
        pdfFileName: fileName,
        initialPageFormat: PdfPageFormat.a4,
        pageFormats: const {
          'A4': PdfPageFormat.a4,
          'Letter': PdfPageFormat.letter,
          'Legal': PdfPageFormat.legal,
        },
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: true,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}

/// Opens the preview for [title].
void openReport(BuildContext context,
    {required String title,
    required String fileName,
    required Future<Uint8List> Function(PdfPageFormat) build}) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ReportPreviewScreen(title: title, fileName: fileName, builder: build)));
}
