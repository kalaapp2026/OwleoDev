package com.nest.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

import java.util.TimeZone;

@SpringBootApplication
@EnableScheduling
public class NestApplication {
    public static void main(String[] args) {
        // Must happen before any DataSource/Flyway connection is opened: pgjdbc derives its
        // startup "TimeZone" GUC from the JVM default zone, and on India-locale Windows hosts
        // that resolves to the legacy alias "Asia/Calcutta", which Postgres's pruned tzdata
        // rejects outright ("FATAL: invalid value for parameter TimeZone"). Pinning to UTC here
        // sidesteps the alias problem entirely and keeps stored timestamps unambiguous.
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
        SpringApplication.run(NestApplication.class, args);
    }
}
