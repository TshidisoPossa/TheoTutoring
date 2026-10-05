import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/dashborad_models.dart';

class DashboardReportPdf {
  static Future<void> export({
    required DashboardSummary summary,
    required List<ChartPoint> points,
    required String rangeLabel,
  }) async {
    final now = DateTime.now();
    final money = NumberFormat('#,##0.00');
    final count = NumberFormat.decimalPattern();
    final doc = pw.Document();

    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'Theo Admin - System Overview',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated ${DateFormat('d MMM yyyy, HH:mm').format(now)} by ${summary.adminName}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          heading('Summary'),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Value', 'Change'],
            data: [
              [
                'Total Revenue',
                'R${money.format(summary.totalRevenue)}',
                formatChange(summary.totalRevenueChange),
              ],
              [
                'Active Students',
                count.format(summary.activeStudents),
                formatChange(summary.activeStudentsChange),
              ],
              [
                'Active Tutors',
                count.format(summary.activeTutors),
                formatChange(summary.activeTutorsChange),
              ],
              [
                'Monthly Growth',
                '${summary.monthlyGrowth.toStringAsFixed(1)}%',
                formatChange(summary.monthlyGrowthChange),
              ],
              [
                'Pending Tutor Applications',
                '${summary.pendingApplications}',
                '',
              ],
              ['Pending Refund Requests', '${summary.pendingRefunds}', ''],
            ],
          ),
          heading('Session Volume vs Revenue ($rangeLabel)'),
          if (points.isEmpty)
            pw.Text('No data for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Sessions', 'Revenue'],
              data: [
                for (final p in points)
                  [
                    DateFormat('d MMM yyyy').format(p.date),
                    '${p.sessions}',
                    'R${money.format(p.revenue)}',
                  ],
              ],
            ),
          heading('Recent Activity'),
          if (summary.recentActivity.isEmpty)
            pw.Text('No recent activity.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Type', 'Activity', 'Details', 'Time'],
              data: [
                for (final a in summary.recentActivity)
                  [
                    a.type.replaceAll('_', ' ').toUpperCase(),
                    a.title,
                    a.subtitle,
                    DateFormat('d MMM yyyy, HH:mm')
                        .format(a.createdAt.toLocal()),
                  ],
              ],
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'theo-system-overview-${DateFormat('yyyyMMdd').format(now)}.pdf',
    );
  }
}
