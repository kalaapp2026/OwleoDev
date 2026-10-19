import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// A small table-shaped report - a title, a few key/value lines, rows, and a total - that can be
/// handed over as a PDF or an Excel sheet. Attendance history and the fee statement both build one
/// and let the person pick the format.
class ReportTable {
  const ReportTable({
    required this.title,
    this.subtitle,
    this.meta = const [],
    required this.headers,
    required this.rows,
    this.totalLabel,
    this.totalValue,
    required this.fileStem,
    this.sheetName = 'Report',
  });

  final String title;
  final String? subtitle;
  final List<(String, String)> meta;
  final List<String> headers;
  final List<List<String>> rows;
  final String? totalLabel;
  final String? totalValue;

  /// File name without extension; made safe for a file system.
  final String fileStem;
  final String sheetName;

  String get _safeStem => fileStem.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
}

enum ReportFormat { pdf, excel }

/// Builds [table] in [format] and opens the platform's save/share flow: the browser's download on
/// web, the native share sheet on a phone.
/// The file's bytes, without handing them to the platform - what [shareReport] shares.
Future<Uint8List> buildReportBytes(ReportTable table, ReportFormat format) async =>
    format == ReportFormat.pdf ? await _buildPdf(table) : _buildXlsx(table);

Future<void> shareReport(ReportTable table, ReportFormat format) async {
  final isPdf = format == ReportFormat.pdf;
  final bytes = await buildReportBytes(table, format);
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: '${table._safeStem}.${isPdf ? 'pdf' : 'xlsx'}',
        mimeType: isPdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    ],
    text: table.title,
  );
}

/// The PDF's built-in font has no rupee sign, so amounts are written "Rs. 1,800" there, and dashes are plain hyphens.
String _pdf(String v) => v.replaceAll('₹', 'Rs. ').replaceAll('—', '-').replaceAll('–', '-');

Future<Uint8List> _buildPdf(ReportTable t) async {
  final doc = pw.Document();
  const gold = PdfColor.fromInt(0xFFA6690F);
  const grey = PdfColor.fromInt(0xFF6E6250);
  const line = PdfColor.fromInt(0xFFE4D9C3);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text('OWLEO N.E.S.T.',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: gold, letterSpacing: 1)),
        pw.SizedBox(height: 6),
        pw.Text(_pdf(t.title), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        if (t.subtitle != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(_pdf(t.subtitle!), style: const pw.TextStyle(fontSize: 11, color: grey)),
        ],
        pw.SizedBox(height: 14),
        for (final m in t.meta)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(children: [
              pw.SizedBox(width: 150, child: pw.Text(_pdf(m.$1), style: const pw.TextStyle(fontSize: 10, color: grey))),
              pw.Text(_pdf(m.$2), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        pw.SizedBox(height: 12),
        if (t.rows.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: t.headers.map(_pdf).toList(),
            data: [for (final r in t.rows) r.map(_pdf).toList()],
            headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2EADA)),
            border: pw.TableBorder.all(color: line, width: 0.6),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          )
        else
          pw.Text('Nothing to show for this range.', style: const pw.TextStyle(fontSize: 11, color: grey)),
        if (t.totalLabel != null) ...[
          pw.SizedBox(height: 14),
          pw.Divider(color: line),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text(t.totalLabel!, style: const pw.TextStyle(fontSize: 11, color: grey)),
            pw.SizedBox(width: 10),
            pw.Text(_pdf(t.totalValue ?? ''), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ]),
        ],
      ],
    ),
  );
  return doc.save();
}

/// A minimal but valid .xlsx: one sheet of inline strings. Written by hand because the usual Excel
/// packages pull in an `archive` version that clashes with the PDF viewer already in the app.
Uint8List _buildXlsx(ReportTable t) {
  String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  String col(int i) => String.fromCharCode(65 + i);

  final sheet = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
  var r = 1;
  void row(List<String> cells, {bool bold = false}) {
    sheet.write('<row r="$r">');
    for (var c = 0; c < cells.length; c++) {
      sheet.write('<c r="${col(c)}$r" t="inlineStr"${bold ? ' s="1"' : ''}><is><t xml:space="preserve">${esc(cells[c])}</t></is></c>');
    }
    sheet.write('</row>');
    r++;
  }

  row([t.title], bold: true);
  if (t.subtitle != null) row([t.subtitle!]);
  for (final m in t.meta) {
    row([m.$1, m.$2]);
  }
  r++;
  row(t.headers, bold: true);
  for (final cells in t.rows) {
    row(cells);
  }
  if (t.totalLabel != null) {
    r++;
    row([t.totalLabel!, t.totalValue ?? ''], bold: true);
  }
  sheet.write('</sheetData></worksheet>');

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
  final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="${esc(t.sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>';
  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
      '</styleSheet>';

  final archive = Archive();
  void add(String path, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(path, data.length, data));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rootRels);
  add('xl/workbook.xml', workbook);
  add('xl/_rels/workbook.xml.rels', workbookRels);
  add('xl/styles.xml', styles);
  add('xl/worksheets/sheet1.xml', sheet.toString());
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The prototype's "Download as" sheet: PDF Document / Excel Spreadsheet. Returns the choice, or
/// null if dismissed.
Future<ReportFormat?> showDownloadFormatSheet(BuildContext context, {String title = 'Download as'}) {
  return showModalBottomSheet<ReportFormat>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      Widget option(ReportFormat f, IconData icon, String label, String hint) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              onTap: () => Navigator.of(sheetContext).pop(f),
              borderRadius: AppRadii.all(13),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(13),
                  border: Border.all(color: palette.border),
                ),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: palette.primarySoft, borderRadius: AppRadii.all(AppRadii.md)),
                    child: Icon(icon, size: 16, color: palette.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.text)),
                      const SizedBox(height: 1),
                      Text(hint, style: TextStyle(fontSize: 10, color: palette.textFaint)),
                    ]),
                  ),
                ]),
              ),
            ),
          );
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text)),
                Pressable(
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: palette.bg,
                      borderRadius: AppRadii.all(AppRadii.sm),
                      border: Border.all(color: palette.border),
                    ),
                    child: Icon(Icons.close, size: 13, color: palette.textMuted),
                  ),
                ),
              ]),
            ),
            option(ReportFormat.pdf, Icons.description_outlined, 'PDF Document', 'Saves a .pdf you can print or share'),
            option(ReportFormat.excel, Icons.table_chart_outlined, 'Excel Spreadsheet', 'Downloads a .xlsx file instantly'),
          ]),
        ),
      );
    },
  );
}
