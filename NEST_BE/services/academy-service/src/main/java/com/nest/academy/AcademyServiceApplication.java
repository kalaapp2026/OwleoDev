package com.nest.academy;

import com.nest.academy.config.IdentityServiceProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(IdentityServiceProperties.class)
public class AcademyServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(AcademyServiceApplication.class, args);
    }
}
