package com.nest.app.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.nio.file.Path;

/** Serves whatever {@link com.nest.app.storage.FileStorageService} saved back out as plain URLs -
 * e.g. a profile picture saved to {@code <uploadDir>/profile-images/xyz.jpg} is reachable at
 * {@code /uploads/profile-images/xyz.jpg}. Public (see SecurityConfig's PUBLIC_PATHS) since these
 * are just avatars, not sensitive documents. */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final String uploadDir;

    public WebConfig(@Value("${nest.upload.dir}") String uploadDir) {
        this.uploadDir = uploadDir;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        String location = Path.of(uploadDir).toAbsolutePath().normalize().toUri().toString();
        registry.addResourceHandler("/uploads/**").addResourceLocations(location);
    }
}
