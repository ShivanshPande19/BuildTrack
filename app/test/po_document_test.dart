// The money on a GST purchase order.
//
// This is the one document in the app that leaves the building and is read by
// an accountant, so the figures on it have to agree with each other: the
// rate-wise breakup has to sum to the tax, CGST + SGST has to equal the tax,
// the grand total has to equal subtotal + tax, and the amount in words has to
// equal the amount in figures. None of it was covered before, and two of those
// four were wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:buildtrack/data/models.dart';
import 'package:buildtrack/features/procurement/po_document.dart';

PoLineItem line({required int qty, required double price, required double rate}) =>
    PoLineItem(name: 'Item', qty: qty, receivedQty: 0, unitPrice: price, taxRate: rate);

/// A PO header whose stored totals deliberately disagree with the lines, so a
/// test can tell which of the two the document actually used.
PurchaseOrder header({double subtotal = 0, double tax = 0, double amount = 0}) =>
    PurchaseOrder(id: 'po1', poNumber: 'PO-00001', status: 'ordered',
        approvalStatus: 'approved', subtotal: subtotal, taxTotal: tax, amount: amount);

void main() {
  group('paise rounding', () {
    test('money is rounded to whole paise, because that is what prints', () {
      expect(toPaise(100.004), 100.0);
      expect(toPaise(100.005), 100.01);
      expect(toPaise(1234.5678), 1234.57);
    });

    test('a repeating value never leaks a third decimal', () {
      // 1/3 of a rupee prints as 0.33, and three of them are 0.99 — not
      // 0.9999999. That one-paisa shortfall is real and is exactly why the
      // document adds up the *rounded* group figures rather than rounding the
      // sum: whatever it prints is what its own rows add to.
      final third = toPaise(1 / 3);
      expect(third, 0.33);
      expect(toPaise(third * 3), 0.99);
    });
  });

  group('rate-wise tax breakup', () {
    test('one row per GST rate, lowest first', () {
      final items = [
        line(qty: 2, price: 1000, rate: 18),
        line(qty: 1, price: 500, rate: 5),
        line(qty: 3, price: 100, rate: 18),
      ];
      final groups = poTaxBreakup(items);
      expect(groups.map((g) => g.rate).toList(), [5, 18]);
      expect(groups.first.taxable, 500);
      expect(groups.last.taxable, 2300);   // 2000 + 300
      expect(groups.first.tax, 25);        // 5% of 500
      expect(groups.last.tax, 414);        // 18% of 2300
    });

    test('the breakup sums to the grand total the document prints', () {
      final items = [line(qty: 7, price: 333.33, rate: 18), line(qty: 1, price: 99.99, rate: 5)];
      final groups = poTaxBreakup(items);
      final subtotal = toPaise(groups.fold<double>(0, (s, g) => s + g.taxable));
      final tax = toPaise(groups.fold<double>(0, (s, g) => s + g.tax));
      expect(poGrandTotal(items, header()), toPaise(subtotal + tax));
    });

    test('a PO with no lines falls back to its stored header amount', () {
      expect(poGrandTotal([], header(amount: 4130)), 4130);
      expect(poTaxBreakup([]), isEmpty);
    });
  });

  group('CGST / SGST split', () {
    test('the two halves add up to the tax exactly, odd paise included', () {
      // A tax of 100.05 printed as 50.03 + 50.03 = 100.06 — a rupee document
      // whose own rows did not add up.
      const tax = 100.05;
      final half = toPaise(tax / 2);
      final other = toPaise(tax - half);
      expect(toPaise(half + other), tax);
      expect(half == other, isFalse, reason: 'the odd paisa has to land somewhere');
    });

    test('an even tax splits evenly', () {
      const tax = 630.0;
      final half = toPaise(tax / 2);
      expect(half, 315);
      expect(toPaise(half + toPaise(tax - half)), tax);
    });
  });

  group('GST rate labels', () {
    test('a whole slab has no decimals', () {
      expect(poPct(0), '0%');
      expect(poPct(18), '18%');
      expect(poPct(28), '28%');
    });

    test('a fractional rate keeps its decimals (toInt() made 7.5% read "7%")', () {
      expect(poPct(7.5), '7.5%');
      expect(poPct(1.25), '1.25%');
    });
  });

  group('amount in words', () {
    test('the Indian system: lakh and crore, not million', () {
      expect(rupeesInWords(120000), 'Rupees One Lakh Twenty Thousand Only');
      expect(rupeesInWords(10000000), 'Rupees One Crore Only');
      expect(rupeesInWords(12345678),
          'Rupees One Crore Twenty Three Lakh Forty Five Thousand Six Hundred Seventy Eight Only');
    });

    test('paise are spelled out, so the words match the figure', () {
      expect(rupeesInWords(1234.56),
          'Rupees One Thousand Two Hundred Thirty Four and Fifty Six Paise Only');
      expect(rupeesInWords(0.05), 'Rupees Zero and Five Paise Only');
    });

    test('the teens and the round tens read correctly', () {
      expect(rupeesInWords(11), 'Rupees Eleven Only');
      expect(rupeesInWords(19), 'Rupees Nineteen Only');
      expect(rupeesInWords(20), 'Rupees Twenty Only');
      expect(rupeesInWords(100), 'Rupees One Hundred Only');
      expect(rupeesInWords(101), 'Rupees One Hundred One Only');
    });

    test('zero, and a float that should not drift', () {
      expect(rupeesInWords(0), 'Rupees Zero Only');
      // 0.1 + 0.2 = 0.30000000000000004 in binary floating point.
      expect(rupeesInWords(0.1 + 0.2), 'Rupees Zero and Thirty Paise Only');
    });
  });
}
