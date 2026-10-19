import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/export/report_export.dart';

void main() {
  const table = ReportTable(
    title: 'Attendance History — Asha',
    subtitle: 'Bharatanatyam · Morning batch',
    meta: [('Amount paid', '₹1,500')],
    headers: ['Date', 'Status'],
    rows: [
      ['12 Oct 2026', 'Present'],
      ['5 Oct 2026', 'Absent & away'],
    ],
    totalLabel: 'Attendance in range',
    totalValue: '50%',
    fileStem: 'asha_attendance',
    sheetName: 'Attendance',
  );

  test('the PDF is a real PDF document', () async {
    final bytes = await buildReportBytes(table, ReportFormat.pdf);
    expect(utf8.decode(bytes.sublist(0, 5), allowMalformed: true), '%PDF-');
  });

  test('the spreadsheet is a zip holding the sheet, with the rows and escaped text', () async {
    final bytes = await buildReportBytes(table, ReportFormat.excel);
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml']));
    final sheet = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('12 Oct 2026'));
    expect(sheet, contains('Absent &amp; away'));
    expect(sheet, contains('Attendance in range'));
  });
}
