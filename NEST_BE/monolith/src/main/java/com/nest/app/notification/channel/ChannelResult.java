package com.nest.app.notification.channel;

import com.nest.app.notification.entity.DeliveryStatus;

/** Outcome of one send. {@code invalidToken} tells the caller to forget a dead push token. */
public record ChannelResult(DeliveryStatus status, String detail, boolean invalidToken) {

    public static ChannelResult sent() {
        return new ChannelResult(DeliveryStatus.SENT, null, false);
    }

    public static ChannelResult skipped(String why) {
        return new ChannelResult(DeliveryStatus.SKIPPED, why, false);
    }

    public static ChannelResult failed(String why) {
        return new ChannelResult(DeliveryStatus.FAILED, truncate(why), false);
    }

    public static ChannelResult deadToken(String why) {
        return new ChannelResult(DeliveryStatus.FAILED, truncate(why), true);
    }

    private static String truncate(String s) {
        return s != null && s.length() > 480 ? s.substring(0, 480) : s;
    }
}
