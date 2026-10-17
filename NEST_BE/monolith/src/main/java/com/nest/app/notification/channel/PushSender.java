package com.nest.app.notification.channel;

import java.util.Map;

/** Delivers a push to one device token. Swap the bean, not the call sites, to change provider. */
public interface PushSender {
    boolean isConfigured();

    ChannelResult send(String deviceToken, String title, String body, Map<String, String> data);
}
