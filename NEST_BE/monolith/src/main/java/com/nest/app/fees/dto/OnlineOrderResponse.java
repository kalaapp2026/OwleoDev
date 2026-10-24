package com.nest.app.fees.dto;

import java.math.BigDecimal;

/** What the app needs to open the gateway's checkout. {@code keyId} is the public half of the key. */
public record OnlineOrderResponse(String orderId, String keyId, long amountPaise, BigDecimal amount, String currency) {
}
