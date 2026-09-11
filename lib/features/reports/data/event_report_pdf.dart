import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../events/domain/event_summary.dart';
import '../domain/event_report.dart';

Future<Uint8List> buildEventReportPdf(EventReport report) async {
  final document = pw.Document(
    title: '${report.summary.title} report',
    author: 'Oslava Events',
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          report.summary.title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text('${report.summary.eventType} at ${report.summary.venueName}'),
        pw.Text(
          'Reporting: ${formatKolkataDateTime12h(report.summary.reportingAt)}',
        ),
        pw.SizedBox(height: 12),
        pw.Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _metric(
              'Workers',
              '${report.summary.confirmedWorkerCount}/${report.summary.requiredWorkerCount}',
            ),
            _metric(
              'Attendance',
              'P ${report.summary.attendancePresent} L ${report.summary.attendanceLate} A ${report.summary.attendanceAbsent} Open ${report.summary.attendanceNotMarked}',
            ),
            _metric(
              'Display pay',
              '${report.summary.currencyCode} ${report.summary.totalWorkerPayDisplay.toStringAsFixed(0)}',
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Confirmed staffing',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Category',
            'Worker ID',
            'Name',
            'Phone',
            'Attendance',
            'Display pay',
          ],
          data: [
            for (final row in report.staffing)
              [
                row.categoryAtConfirmation.databaseValue,
                row.workerNumber?.toString() ?? '-',
                row.fullName,
                row.phoneE164,
                row.attendanceStatus.label,
                '${row.currencyCode} ${row.totalPayDisplay.toStringAsFixed(0)}',
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: const {
            0: pw.FixedColumnWidth(48),
            1: pw.FixedColumnWidth(54),
            4: pw.FixedColumnWidth(70),
            5: pw.FixedColumnWidth(70),
          },
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Recent history',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        for (final row in report.auditHistory.take(20))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              '${formatKolkataDateTime12h(row.createdAt)}  ${row.action}  ${row.historySource}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _metric(String label, String value) {
  return pw.Container(
    width: 150,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}
