import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'booking_receipt.dart';

// The receipt as a one-page A4 PDF, built from the server's receipt
// (booking_receipt.dart) so it shows exactly what was saved at payment.
// Plain ASCII text only: the built-in PDF font has no emoji or special
// dashes.

const _blue = PdfColor.fromInt(0xFF356AE6);
const _ink = PdfColor.fromInt(0xFF17233D);
const _muted = PdfColor.fromInt(0xFF6B7385);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _tint = PdfColor.fromInt(0xFFF2F4FB);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "2026-11-20" -> "20 Nov 2026"
String receiptDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "2026-11-16 21:32" -> "16 Nov 2026, 21:32"
String receiptDateTime(String value) {
  final parts = value.split(' ');
  return parts.length == 2
      ? '${receiptDate(parts[0])}, ${parts[1]}'
      : receiptDate(value);
}

/// The file name the student saves: "TheoTutoring-receipt-TT-000016.pdf".
String receiptFileName(BookingReceipt r) =>
    'TheoTutoring-receipt-${r.receiptNumber}.pdf';

/// Builds the receipt PDF.
Future<Uint8List> buildReceiptPdf(BookingReceipt r) {
  final doc = pw.Document(
    title: 'TheoTutoring receipt ${r.receiptNumber}',
    author: 'TheoTutoring',
  );

  pw.TextStyle style({
    double size = 10,
    PdfColor color = _ink,
    bool bold = false,
  }) => pw.TextStyle(
    fontSize: size,
    color: color,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );

  pw.Widget labelValue(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 110,
          child: pw.Text(label, style: style(color: _muted)),
        ),
        pw.Expanded(child: pw.Text(value, style: style())),
      ],
    ),
  );

  pw.Widget moneyRow(String label, String value, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: style(bold: bold, size: bold ? 11 : 10),
              ),
            ),
            pw.Text(
              value,
              style: style(bold: bold, size: bold ? 11 : 10),
            ),
          ],
        ),
      );

  final hasDiscount = r.discountPercent > 0;
  final lessonLabel = r.lessonCount == 1 ? 'lesson' : 'lessons';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TheoTutoring',
                      style: style(size: 20, color: _blue, bold: true),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Payment receipt',
                      style: style(size: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Receipt ${r.receiptNumber}',
                    style: style(size: 11, bold: true),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Paid ${receiptDateTime(r.paidAt)} (SAST)',
                    style: style(color: _muted),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _tint,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      r.purchaseStatus.toUpperCase(),
                      style: style(size: 9, color: _blue, bold: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Divider(color: _line),
          pw.SizedBox(height: 12),

          // ── Who and what ──
          labelValue(
            'Billed to',
            r.studentEmail.isEmpty
                ? r.studentName
                : '${r.studentName} (${r.studentEmail})',
          ),
          labelValue('Tutor', r.tutorName),
          labelValue('Subject', r.subject),
          labelValue(
            'Booking',
            '${r.purchaseType == 'Package' ? 'Package' : 'Single lesson'}'
                ' - ${r.lessonCount} $lessonLabel (booking #${r.purchaseId})',
          ),
          labelValue(
            'Payment method',
            r.isDemo ? '${r.paymentMethod} (demo payment)' : r.paymentMethod,
          ),
          if (r.paymentReference != null)
            labelValue('Reference', r.paymentReference!),
          pw.SizedBox(height: 16),

          // ── Lessons ──
          pw.Text('Lessons', style: style(size: 12, bold: true)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Date', 'Time', 'Status', 'Price'],
            data: [
              for (final l in r.lessons)
                [
                  '${l.lessonNumber ?? ''}',
                  receiptDate(l.date),
                  '${l.startTime} - ${l.endTime}',
                  l.status,
                  'R${l.price}',
                ],
            ],
            headerStyle: style(size: 9, color: PdfColors.white, bold: true),
            headerDecoration: const pw.BoxDecoration(color: _blue),
            cellStyle: style(size: 9),
            cellAlignments: {4: pw.Alignment.centerRight},
            border: pw.TableBorder.all(color: _line, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
          ),
          pw.SizedBox(height: 16),

          // ── Money ──
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: pw.Column(
                children: [
                  moneyRow(
                    'Rate (${r.lessonCount} x R${r.ratePerLesson})',
                    'R${r.subtotal}',
                  ),
                  if (hasDiscount)
                    moneyRow(
                      'Package discount (${r.discountPercent}%)',
                      '-R${r.discountAmount}',
                    ),
                  moneyRow('Total', 'R${r.total}'),
                  pw.Divider(color: _line),
                  moneyRow('Amount paid', 'R${r.amountPaid}', bold: true),
                  for (final refund in r.refunds)
                    moneyRow(
                      'Refund ${refund.percentage}% (${refund.status})',
                      '-R${refund.amount}',
                    ),
                ],
              ),
            ),
          ),
          pw.Spacer(),

          // ── Footer ──
          pw.Divider(color: _line),
          pw.SizedBox(height: 6),
          if (r.isDemo)
            pw.Text(
              'This was a demo payment: no real money was charged.',
              style: style(size: 9, color: _muted),
            ),
          pw.Text(
            'Amounts are in South African rand (ZAR). Lesson times are '
            'South African time and show each lesson as it is now.',
            style: style(size: 9, color: _muted),
          ),
          pw.Text(
            'Thank you for learning with TheoTutoring.',
            style: style(size: 9, color: _muted),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
