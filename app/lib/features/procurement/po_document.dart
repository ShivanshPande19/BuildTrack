import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/models.dart';

/// Builds a proper, office-level Purchase Order document from a [PoDocData]
/// bundle and hands it to the OS print / share sheet.
///
/// It is a GST-style Indian PO: buyer + supplier with GSTIN, a line-item table
/// with HSN/SAC + rate, the CGST/SGST (same state) or IGST (inter-state) split,
/// the grand total in words, terms, and an authorised-signatory block filled in
/// from the approval trail (who prepared / signed / approved it, and when).
///
/// Fonts: the built-in Helvetica is used (no network needed to print) and money
/// is written "Rs 1,00,000.00" so it renders on every device — the rupee glyph
/// is missing from the standard PDF fonts.

final _money = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs ', decimalDigits: 2);
final _date = DateFormat('d MMM yyyy');

const _ink = PdfColor.fromInt(0xFF1A1A17);
const _mut = PdfColor.fromInt(0xFF6B6B60);
const _line = PdfColor.fromInt(0xFFD9D6CC);
const _band = PdfColor.fromInt(0xFFF2EFE7);

/// Open the OS print / share preview for this PO.
Future<void> printPoDocument(PoDocData d) =>
    Printing.layoutPdf(onLayout: (format) => _build(d, format), name: '${d.detail.po.poNumber}.pdf');

Future<Uint8List> _build(PoDocData d, PdfPageFormat format) async {
  final po = d.detail.po;
  final items = d.detail.items;
  final company = d.company;
  final vendor = d.vendor;

  // CGST + SGST when buyer and supplier are in the same state; IGST otherwise.
  // If we can't tell (a state is missing) fall back to a single GST line.
  final bs = company.state?.trim().toLowerCase();
  final vs = vendor?.state?.trim().toLowerCase();
  final intra = bs != null && bs.isNotEmpty && vs != null && vs.isNotEmpty && bs == vs;
  final inter = bs != null && bs.isNotEmpty && vs != null && vs.isNotEmpty && bs != vs;

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 30),
    build: (ctx) => [
      _header(company, po),
      pw.SizedBox(height: 16),
      _parties(company, vendor, po),
      pw.SizedBox(height: 14),
      _meta(po),
      pw.SizedBox(height: 14),
      _itemsTable(items),
      pw.SizedBox(height: 12),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _leftNotes(po)),
          pw.SizedBox(width: 18),
          _totals(po, intra: intra, inter: inter),
        ],
      ),
      pw.SizedBox(height: 8),
      _amountWords(po.amount),
      pw.SizedBox(height: 26),
      _signatories(d.detail.events, company),
      pw.SizedBox(height: 18),
      _footer(),
    ],
  ));
  return doc.save();
}

pw.Widget _header(CompanySettings c, PurchaseOrder po) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(c.name, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _ink)),
      if ((c.address ?? '').isNotEmpty) _small(c.address!),
      if ((c.gstin ?? '').isNotEmpty) _small('GSTIN: ${c.gstin}'),
      if ([c.phone, c.email].any((e) => (e ?? '').isNotEmpty))
        _small([if ((c.phone ?? '').isNotEmpty) c.phone, if ((c.email ?? '').isNotEmpty) c.email].join('  ·  ')),
    ])),
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Text('PURCHASE ORDER', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink, letterSpacing: 1.5)),
      pw.SizedBox(height: 4),
      pw.Text(po.poNumber, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _mut)),
      if (po.orderDate != null) _small('Date: ${_date.format(po.orderDate!)}'),
    ]),
  ],
);

pw.Widget _parties(CompanySettings c, VendorRow? v, PurchaseOrder po) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Expanded(child: _box('SUPPLIER', [
      pw.Text(v?.name ?? 'Vendor', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _ink)),
      if ((v?.address ?? '').isNotEmpty) _small(v!.address!),
      if ((v?.gstin ?? '').isNotEmpty) _small('GSTIN: ${v!.gstin}'),
      if ((v?.state ?? '').isNotEmpty) _small('State: ${v!.state}'),
      if ((v?.email ?? '').isNotEmpty) _small(v!.email!),
    ])),
    pw.SizedBox(width: 14),
    pw.Expanded(child: _box('DELIVER TO', [
      pw.Text(c.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _ink)),
      if ((po.shipTo ?? '').isNotEmpty) _small(po.shipTo!)
      else if ((c.address ?? '').isNotEmpty) _small(c.address!),
      if ((c.gstin ?? '').isNotEmpty) _small('GSTIN: ${c.gstin}'),
      if ((c.state ?? '').isNotEmpty) _small('State: ${c.state}'),
    ])),
  ],
);

pw.Widget _meta(PurchaseOrder po) {
  final cells = <pw.Widget>[
    _metaCell('PO Date', po.orderDate == null ? '—' : _date.format(po.orderDate!)),
    _metaCell('Expected delivery', po.deliveryDate == null ? '—' : _date.format(po.deliveryDate!)),
    _metaCell('Payment terms', (po.paymentTerms ?? '').isEmpty ? '—' : po.paymentTerms!),
  ];
  return pw.Container(
    decoration: const pw.BoxDecoration(color: _band, borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: pw.Row(children: [
      for (int i = 0; i < cells.length; i++) ...[
        pw.Expanded(child: cells[i]),
        if (i != cells.length - 1) pw.Container(width: 1, height: 26, color: _line),
      ],
    ]),
  );
}

pw.Widget _metaCell(String label, String value) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(label.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, color: _mut, letterSpacing: 0.5, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 3),
    pw.Text(value, style: const pw.TextStyle(fontSize: 10, color: _ink)),
  ],
);

pw.Widget _itemsTable(List<PoLineItem> items) => pw.TableHelper.fromTextArray(
  headers: ['#', 'Description', 'HSN/SAC', 'Qty', 'Rate', 'Amount'],
  data: [
    for (int i = 0; i < items.length; i++)
      [
        '${i + 1}',
        items[i].description?.isNotEmpty == true ? items[i].description! : items[i].name,
        (items[i].hsnCode ?? '').isEmpty ? '—' : items[i].hsnCode!,
        '${items[i].qty}',
        _money.format(items[i].unitPrice),
        _money.format(items[i].lineTotal),
      ],
  ],
  border: pw.TableBorder.all(color: _line, width: 0.5),
  headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
  headerDecoration: const pw.BoxDecoration(color: _ink),
  headerHeight: 24,
  cellStyle: const pw.TextStyle(fontSize: 9.5, color: _ink),
  cellHeight: 22,
  cellAlignments: {
    0: pw.Alignment.center,
    1: pw.Alignment.centerLeft,
    2: pw.Alignment.center,
    3: pw.Alignment.center,
    4: pw.Alignment.centerRight,
    5: pw.Alignment.centerRight,
  },
  columnWidths: {
    0: const pw.FixedColumnWidth(24),
    1: const pw.FlexColumnWidth(4),
    2: const pw.FlexColumnWidth(1.6),
    3: const pw.FixedColumnWidth(40),
    4: const pw.FlexColumnWidth(1.6),
    5: const pw.FlexColumnWidth(1.8),
  },
);

pw.Widget _leftNotes(PurchaseOrder po) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    if ((po.notes ?? '').isNotEmpty) ...[
      pw.Text('NOTES', style: pw.TextStyle(fontSize: 8, color: _mut, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
      pw.SizedBox(height: 3),
      pw.Text(po.notes!, style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
    ],
  ],
);

pw.Widget _totals(PurchaseOrder po, {required bool intra, required bool inter}) {
  final rows = <pw.Widget>[_totalRow('Subtotal', _money.format(po.subtotal))];
  if (intra) {
    rows.add(_totalRow('CGST', _money.format(po.taxTotal / 2)));
    rows.add(_totalRow('SGST', _money.format(po.taxTotal / 2)));
  } else if (inter) {
    rows.add(_totalRow('IGST', _money.format(po.taxTotal)));
  } else {
    rows.add(_totalRow('GST', _money.format(po.taxTotal)));
  }
  rows.add(pw.Divider(color: _line, height: 12));
  rows.add(_totalRow('Grand Total', _money.format(po.amount), bold: true));
  return pw.Container(
    width: 220,
    child: pw.Column(children: rows),
  );
}

pw.Widget _totalRow(String label, String value, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
    pw.Text(label, style: pw.TextStyle(fontSize: bold ? 11 : 9.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: bold ? _ink : _mut)),
    pw.Text(value, style: pw.TextStyle(fontSize: bold ? 12 : 9.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: _ink)),
  ]),
);

pw.Widget _amountWords(double amount) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: const pw.BoxDecoration(color: _band, borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
  child: pw.Text('Amount in words: ${rupeesInWords(amount)}',
    style: pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic, color: _ink)),
);

pw.Widget _signatories(List<PoApprovalEvent> events, CompanySettings c) {
  PoApprovalEvent? last(String type) {
    PoApprovalEvent? found;
    for (final e in events) { if (e.event == type) found = e; }
    return found;
  }
  final prepared = last('created');
  final signed = last('pm_signed');
  final approved = last('final_signed');

  pw.Widget block(String role, PoApprovalEvent? e) => pw.Expanded(child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(height: 30),
      pw.Container(height: 0.8, color: _line),
      pw.SizedBox(height: 4),
      pw.Text(role, style: pw.TextStyle(fontSize: 8, color: _mut, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
      pw.Text(e?.actorName ?? '—', style: pw.TextStyle(fontSize: 10, color: _ink, fontWeight: pw.FontWeight.bold)),
      if (e?.at != null) pw.Text(_date.format(e!.at!), style: const pw.TextStyle(fontSize: 8, color: _mut)),
    ],
  ));

  return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    block('PREPARED BY', prepared),
    pw.SizedBox(width: 20),
    block('CHECKED (PM)', signed),
    pw.SizedBox(width: 20),
    block('APPROVED', approved),
  ]);
}

pw.Widget _footer() => pw.Column(children: [
  pw.Divider(color: _line, height: 1),
  pw.SizedBox(height: 6),
  pw.Text('This is a system-generated purchase order and is valid without a physical signature.',
    style: const pw.TextStyle(fontSize: 7.5, color: _mut)),
]);

pw.Widget _small(String t) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 2),
  child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5, color: _mut)),
);

pw.Widget _box(String title, List<pw.Widget> children) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _line, width: 0.6),
    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
  ),
  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text(title, style: pw.TextStyle(fontSize: 8, color: _mut, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
    pw.SizedBox(height: 5),
    ...children,
  ]),
);

/// Indian-system amount in words: "Rupees One Lakh Twenty Thousand Only".
/// Paise are rounded into the rupee amount to keep the document clean.
String rupeesInWords(double amount) {
  final n = amount.round();
  if (n == 0) return 'Rupees Zero Only';
  final words = _numberToWords(n);
  return 'Rupees $words Only';
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
  'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _twoDigits(int n) {
  if (n < 20) return _ones[n];
  final t = _tens[n ~/ 10];
  final o = n % 10;
  return o == 0 ? t : '$t ${_ones[o]}';
}

String _threeDigits(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  final parts = <String>[];
  if (h > 0) parts.add('${_ones[h]} Hundred');
  if (r > 0) parts.add(_twoDigits(r));
  return parts.join(' ');
}

String _numberToWords(int n) {
  if (n < 0) return 'Minus ${_numberToWords(-n)}';
  final parts = <String>[];
  final crore = n ~/ 10000000; n %= 10000000;
  final lakh = n ~/ 100000; n %= 100000;
  final thousand = n ~/ 1000; n %= 1000;
  final rest = n;
  if (crore > 0) parts.add('${_numberToWords(crore)} Crore');
  if (lakh > 0) parts.add('${_twoDigits(lakh)} Lakh');
  if (thousand > 0) parts.add('${_twoDigits(thousand)} Thousand');
  if (rest > 0) parts.add(_threeDigits(rest));
  return parts.join(' ');
}
