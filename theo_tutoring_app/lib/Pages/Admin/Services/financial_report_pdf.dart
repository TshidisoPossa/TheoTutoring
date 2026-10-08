import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/financial_models.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _change(double? v) => v == null ? '-' : signedPercent(v);

class FinancialReportPdf {
  static Future<void> export({
    required FinancialOverview overview,
    required List<SubjectRevenue> subjects,
    required String rangeLabel,
    required String periodLabel,
  }) async {
    final now = DateTime.now();
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
            'Theo Admin - Revenue & Payouts',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Period: $rangeLabel. Generated ${DateFormat('d MMM yyyy, HH:mm').format(now)} by ${overview.adminName}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          heading('Summary'),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Value', 'Change'],
            data: [
              [
                'Total Gross Revenue',
                formatRandFull(overview.grossRevenue),
                _change(overview.grossRevenueChange),
              ],
              [
                'Net Profit (Post-Payout)',
                formatRandFull(overview.netProfit),
                _change(overview.netProfitChange),
              ],
              ['Pending Payouts', formatRandFull(overview.pendingPayouts), ''],
              ['Tutors awaiting payout', '${overview.pendingPayoutTutors}', ''],
            ],
          ),
          heading('Revenue by Subject ($periodLabel)'),
          if (subjects.isEmpty)
            pw.Text('No data for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Subject', 'Revenue'],
              data: [
                for (final s in subjects)
                  [s.subject, formatRandFull(s.revenue)],
              ],
            ),
          heading('Payout Queue'),
          if (overview.payoutQueue.isEmpty)
            pw.Text('No payouts in the queue.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Tutor', 'Subject', 'Amount', 'Status'],
              data: [
                for (final p in overview.payoutQueue)
                  [
                    p.tutorName,
                    p.subject,
                    formatRandFull(p.amount),
                    _cap(p.status),
                  ],
              ],
            ),
          heading('Recent Transactions'),
          if (overview.transactions.isEmpty)
            pw.Text('No transactions for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'ID',
                'Date',
                'Student',
                'Tutor / Subject',
                'Amount',
                'Status',
              ],
              data: [
                for (final t in overview.transactions)
                  [
                    t.id,
                    DateFormat('d MMM yyyy, HH:mm').format(t.date.toLocal()),
                    t.studentName,
                    '${t.tutorName} / ${t.subject}',
                    formatRandFull(t.amount),
                    _cap(t.status),
                  ],
              ],
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'theo-revenue-payouts-${DateFormat('yyyyMMdd').format(now)}.pdf',
    );
  }
}

