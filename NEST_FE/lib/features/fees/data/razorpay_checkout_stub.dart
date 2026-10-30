import 'package:nest_fe/features/fees/data/razorpay_checkout_types.dart';

export 'package:nest_fe/features/fees/data/razorpay_checkout_types.dart';

Future<CheckoutResult> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
  bool allMethods = false,
}) {
  throw const CheckoutFailed('Online payment is not supported on this platform.');
}
