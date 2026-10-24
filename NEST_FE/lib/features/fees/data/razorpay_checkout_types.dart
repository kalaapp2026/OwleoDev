/// What Razorpay's checkout hands back after a successful payment. The three values are what the
/// server needs to check the signature; the app never decides a payment succeeded on its own.
class CheckoutResult {
  const CheckoutResult({required this.orderId, required this.paymentId, required this.signature});
  final String orderId;
  final String paymentId;
  final String signature;
}

/// The student closed the checkout without paying. Not an error worth shouting about.
class CheckoutCancelled implements Exception {
  const CheckoutCancelled();
  @override
  String toString() => 'Payment cancelled';
}

/// The checkout opened and the payment failed (declined, timed out, UPI app refused).
class CheckoutFailed implements Exception {
  const CheckoutFailed(this.message);
  final String message;
  @override
  String toString() => message;
}
