import 'dart:async';

import 'package:nest_fe/features/fees/data/razorpay_checkout_types.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

export 'package:nest_fe/features/fees/data/razorpay_checkout_types.dart';

/// Android / iOS: the Razorpay plugin. `method.upi` is the only one switched on, so the sheet shows
/// the phone's UPI apps (Google Pay, PhonePe, Paytm...) and nothing else.
Future<CheckoutResult> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
  bool allMethods = false,
}) {
  final done = Completer<CheckoutResult>();
  final razorpay = Razorpay();

  void finish() => razorpay.clear();

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
    if (!done.isCompleted) {
      done.complete(CheckoutResult(
        orderId: r.orderId ?? orderId,
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      ));
    }
    finish();
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
    if (!done.isCompleted) {
      // Code 0 is "the user backed out"; anything else is a real failure worth showing.
      done.completeError(r.code == Razorpay.PAYMENT_CANCELLED
          ? const CheckoutCancelled()
          : CheckoutFailed(r.message ?? 'The payment did not go through.'));
    }
    finish();
  });
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

  razorpay.open({
    'key': keyId,
    'order_id': orderId,
    'amount': amountPaise,
    'currency': 'INR',
    'name': name,
    'description': description,
    // A student's fee is UPI only. Owleo's own bill is paid by a business, which may use a card or net banking too.
    'method': {
      'upi': true,
      'card': allMethods,
      'netbanking': allMethods,
      'wallet': false,
      'emi': false,
      'paylater': false,
    },
    'retry': {'enabled': true, 'max_count': 2},
  });
  return done.future;
}
