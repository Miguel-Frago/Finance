import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'settings.dart';

/// Shared look for every printed report: fonts that include the peso sign,
/// company header with logo, signature lines and page numbers.
/// The logo and signature are temporary placeholders until the company
/// uploads real ones in Settings.
class ReportKit {
  final pw.Font base, bold;
  final pw.MemoryImage? logo, signature;
  final String company, address;
  ReportKit._(this.base, this.bold, this.logo, this.signature, this.company, this.address);

  static Future<ReportKit> load() async {
    final reg = await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf');
    final bld = await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf');
    pw.MemoryImage? img(String key) {
      try {
        final p = Settings.get('${key}_path');
        if (p.isEmpty || !File(p).existsSync()) return null;
        return pw.MemoryImage(File(p).readAsBytesSync());
      } catch (_) {
        return null; // unsupported image type: fall back to the placeholder
      }
    }

    return ReportKit._(
      pw.Font.ttf(reg),
      pw.Font.ttf(bld),
      img('logo'),
      img('signature'),
      Settings.get('company_name', 'Your Company'),
      Settings.get('company_address'),
    );
  }

  pw.Document newDoc() => pw.Document(
        theme: pw.ThemeData.withFont(
            base: base, bold: bold, italic: base, boldItalic: bold),
      );

  pw.Widget _logoBox() => logo != null
      ? pw.SizedBox(width: 64, height: 42, child: pw.Image(logo!, fit: pw.BoxFit.contain))
      : pw.Container(
          width: 64,
          height: 42,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.6)),
          child: pw.Text('LOGO', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        );

  pw.Widget header(String title, String subtitle) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            _logoBox(),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(company, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 8.5)),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(title, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text(subtitle, style: const pw.TextStyle(fontSize: 8.5)),
            ]),
          ]),
          pw.Divider(thickness: 0.8),
        ],
      );

  pw.Widget sigLine(String label, {bool withImage = false, double width = 150}) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        withImage && signature != null
            ? pw.SizedBox(height: 26, child: pw.Image(signature!, fit: pw.BoxFit.contain))
            : pw.SizedBox(height: 26),
        pw.Container(width: width, height: 0.6, color: PdfColors.grey700),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        if (signature == null || !withImage)
          pw.Text('(name / signature placeholder)',
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
      ]);

  pw.Widget footer(pw.Context ctx) => pw.Column(children: [
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            sigLine('Prepared by'),
            sigLine('Approved by', withImage: true),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ]);

  pw.Widget table(List<String> headers, List<List<String>> data,
      {Set<int> right = const {}, Map<int, pw.TableColumnWidth>? widths}) {
    final align = {
      for (var i = 0; i < headers.length; i++)
        i: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft
    };
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignments: align,
      headerAlignments: align,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      border: const pw.TableBorder(
        bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.6),
        horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.3),
      ),
      columnWidths: widths,
    );
  }
}
