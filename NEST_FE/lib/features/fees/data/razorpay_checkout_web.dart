// ignore_for_file: non_constant_identifier_names
// Razorpay's JS API dictates these snake_case option and response names.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:nest_fe/features/fees/data/razorpay_checkout_types.dart';

export 'package:nest_fe/features/fees/data/razorpay_checkout_types.dart';

@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external _Razorpay(_Options options);
  external void open();
}

extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({
    String key,
    String order_id,
    int amount,
    String currency,
    String name,
    String description,
    _Method method,
    _Modal modal,
    JSFunction handler,
  });
}

extension type _Method._(JSObject _) implements JSObject {
  external factory _Method({bool upi, bool card, bool netbanking, bool wallet, bool emi, bool paylater});
}

extension type _Modal._(JSObject _) implements JSObject {
  external factory _Modal({JSFunction ondismiss});
}

extension type _Success._(JSObject _) implements JSObject {
  external String get razorpay_order_id;
  external String get razorpay_payment_id;
  external String get razorpay_signature;
}

/// Web: Razorpay's `checkout.js`, loaded by `web/index.html`. On a desktop browser the checkout
/// shows a UPI QR to scan; on a phone it offers the installed UPI apps.
Future<CheckoutResult> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
}) async {
  final done = Completer<CheckoutResult>();

  if (!globalContext.has('Razorpay')) {
    throw const CheckoutFailed("Couldn't load the payment window. Check your connection and try again.");
  }

  final rzp = _Razorpay(_Options(
    key: keyId,
    order_id: orderId,
    amount: amountPaise,
    currency: 'INR',
    name: name,
    description: description,
    method: _Method(upi: true, card: false, netbanking: false, wallet: false, emi: false, paylater: false),
    modal: _Modal(
      ondismiss: (() {
        if (!done.isCompleted) done.completeError(const CheckoutCancelled());
      }).toJS,
    ),
    handler: ((_Success r) {
      if (!done.isCompleted) {
        done.complete(CheckoutResult(
          orderId: r.razorpay_order_id,
          paymentId: r.razorpay_payment_id,
          signature: r.razorpay_signature,
        ));
      }
    }).toJS,
  ));
  // A failed attempt leaves the window open so the student can retry; only a dismiss ends it.
  rzp.open();
  return done.future;
}
