/// Opens Razorpay's UPI checkout and reports how it went.
///
/// One call, three implementations picked at compile time: the Android/iOS plugin on devices,
/// Razorpay's `checkout.js` (loaded in `web/index.html`) in the browser, and a stub anywhere else.
/// Nothing here marks a fee paid - it only returns the signed values the server must verify.
library;

export 'razorpay_checkout_stub.dart'
    if (dart.library.js_interop) 'razorpay_checkout_web.dart'
    if (dart.library.io) 'razorpay_checkout_mobile.dart';
