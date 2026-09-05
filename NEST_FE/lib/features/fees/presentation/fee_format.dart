import 'package:nest_fe/features/fees/data/fee_roster.dart';

/// The money/date helpers moved to core once Course Creation needed them too. Re-exported here
/// so every existing Fees call site keeps working against the single shared implementation.
export 'package:nest_fe/core/format/money.dart'
    show money, formatFeeDate, formatDateSectionLabel, periodOf, ordinalDay;

/// The badge wording from the prototype. "Cash/UPI" rather than "Paid" because the distinction an
/// admin cares about is where the money physically is, not merely that it arrived.
String statusLabel(PaymentStatus status) => switch (status) {
      PaymentStatus.notPaid => 'Not Paid',
      PaymentStatus.due => 'Due',
      PaymentStatus.partial => 'Partial',
      PaymentStatus.paidManual => 'Cash/UPI',
      PaymentStatus.paidGateway => 'Gateway',
      PaymentStatus.closed => 'Closed',
    };
