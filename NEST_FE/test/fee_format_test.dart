import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';

void main() {
  group('money', () {
    test('groups Indian-style: last three, then twos', () {
      // The reason this is not toStringAsFixed with a comma every three digits. A first attempt at
      // this function grouped the thousands correctly and everything above it wrong.
      expect(money(500), '₹500');
      expect(money(1000), '₹1,000');
      expect(money(12345), '₹12,345');
      expect(money(123456), '₹1,23,456');
      expect(money(1234567), '₹12,34,567');
      expect(money(12345678), '₹1,23,45,678');
    });

    test('handles the boundaries', () {
      expect(money(0), '₹0');
      expect(money(999), '₹999');
      expect(money(1), '₹1');
    });

    test('keeps the sign outside the symbol', () {
      // A reversal is a negative amount, and "-₹500" reads as money owed back; "₹-500" reads as a
      // rendering bug.
      expect(money(-500), '-₹500');
      expect(money(-123456), '-₹1,23,456');
    });

    test('rounds rather than truncating', () {
      expect(money(1000.6), '₹1,001');
    });
  });

  group('formatDateSectionLabel', () {
    test('uses relative labels only for the two most recent days', () {
      final now = DateTime.now();
      expect(formatDateSectionLabel(now), 'Today');
      expect(formatDateSectionLabel(now.subtract(const Duration(days: 1))), 'Yesterday');
      // Past that a relative label makes the reader do arithmetic.
      expect(formatDateSectionLabel(DateTime(2026, 8, 4)), '4 August 2026');
    });

    test('names the no-payment case rather than showing an empty heading', () {
      expect(formatDateSectionLabel(null), 'No payment yet');
    });

    test('is not fooled by a time-of-day difference on the same date', () {
      // A payment recorded at 23:00 and "now" at 01:00 are 2 hours apart but different days; one
      // recorded this morning is the same day. Comparing instants rather than dates gets both wrong.
      final now = DateTime.now();
      final earlierToday = DateTime(now.year, now.month, now.day);
      expect(formatDateSectionLabel(earlierToday), 'Today');
    });
  });

  group('statusLabel', () {
    test('names where the money is, not merely that it arrived', () {
      // "Cash/UPI" vs "Gateway" is the distinction an admin acts on - whether to expect it in the
      // cash box or on the gateway statement.
      expect(statusLabel(PaymentStatus.paidManual), 'Cash/UPI');
      expect(statusLabel(PaymentStatus.paidGateway), 'Gateway');
      expect(statusLabel(PaymentStatus.notPaid), 'Not Paid');
      expect(statusLabel(PaymentStatus.due), 'Due');
      expect(statusLabel(PaymentStatus.partial), 'Partial');
    });
  });

  group('periodOf', () {
    test('zero-pads the month to match the API key', () {
      expect(periodOf(DateTime(2026, 8)), '2026-08');
      expect(periodOf(DateTime(2026, 12)), '2026-12');
    });
  });

  group('PaymentStatus', () {
    test('unknown wire values degrade instead of throwing', () {
      // A server that grows a new status must not blank out an admin's whole roster.
      expect(PaymentStatus.fromWire('SOMETHING_NEW'), PaymentStatus.notPaid);
      expect(PaymentStatus.fromWire(null), PaymentStatus.notPaid);
      expect(PaymentStatus.fromWire('PAID_GATEWAY'), PaymentStatus.paidGateway);
    });

    test('closed counts as settled - the period is done, not outstanding', () {
      expect(PaymentStatus.closed.isSettled, isTrue);
      expect(PaymentStatus.paidManual.isSettled, isTrue);
      expect(PaymentStatus.partial.isSettled, isFalse);
      expect(PaymentStatus.due.isSettled, isFalse);
    });
  });

  group('FeeRosterEntry.fromJson', () {
    test('reads the payment date and mode the row displays', () {
      final entry = FeeRosterEntry.fromJson({
        'membershipId': 'm1',
        'studentName': 'Savish Holla',
        'agreedFee': 1000,
        'totalPaid': 1000,
        'balance': 0,
        'status': 'PAID_MANUAL',
        'lastPaymentId': 't1',
        'lastPaidOn': '2026-08-03',
        'lastPaymentMode': 'CASH',
      });
      expect(entry.lastPaidOn, DateTime(2026, 8, 3));
      expect(entry.lastPaymentMode, 'CASH');
      expect(entry.canUndo, isTrue);
    });

    test('an unpaid row has no payment to undo', () {
      final entry = FeeRosterEntry.fromJson({
        'membershipId': 'm2',
        'studentName': 'Arjun Kumar',
        'agreedFee': 1000,
        'totalPaid': 0,
        'balance': 1000,
        'status': 'NOT_PAID',
      });
      expect(entry.lastPaidOn, isNull);
      expect(entry.canUndo, isFalse);
    });
  });
}
