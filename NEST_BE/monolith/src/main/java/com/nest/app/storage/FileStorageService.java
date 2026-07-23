package com.nest.app.storage;

import com.nest.common.exception.BadRequestException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

/**
 * Dev-stage local-disk storage for uploaded files (profile pictures, course-material PDFs/images,
 * song attachments) - saved under {@code nest.upload.dir} on the backend's own filesystem and
 * served back out at {@code /uploads/**} by {@link com.nest.app.config.WebConfig}. Good enough
 * while there's a single backend instance; swapping this for real object storage (S3 etc.) later
 * only needs to change this one class, since every caller only ever sees the returned URL path.
 *
 * <p>Every caller supplies its own allowed content-type set and size cap - a profile picture and
 * a course PDF have nothing in common validation-wise, so there's no one shared "allowed types"
 * list to hide a bug behind.
 */
@Service
public class FileStorageService {

    private final Path uploadRoot;

    public FileStorageService(@Value("${nest.upload.dir}") String uploadDir) {
        this.uploadRoot = Path.of(uploadDir).toAbsolutePath().normalize();
        try {
            Files.createDirectories(uploadRoot);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not create upload directory: " + uploadRoot, e);
        }
    }

    /** Saves under a random filename (never the caller-supplied one, beyond its extension) in a
     * {@code subDir} bucket, returning the public-facing "/uploads/..." path to store on the
     * owning row. {@code maxBytes} and {@code allowedContentTypes} are the caller's own rules -
     * a profile picture and a song attachment don't share a size cap or a MIME whitelist. */
    public String store(MultipartFile file, String subDir, Set<String> allowedContentTypes, long maxBytes) {
        if (file == null || file.isEmpty()) {
            throw new BadRequestException("No file was uploaded");
        }
        if (file.getSize() > maxBytes) {
            throw new BadRequestException("File must be " + (maxBytes / (1024 * 1024)) + "MB or smaller");
        }
        String contentType = file.getContentType();
        if (contentType == null || !allowedContentTypes.contains(contentType.toLowerCase(Locale.ROOT))) {
            throw new BadRequestException("Unsupported file type: " + contentType);
        }

        String filename = UUID.randomUUID() + extensionOf(file.getOriginalFilename());

        try {
            Path targetDir = uploadRoot.resolve(subDir).normalize();
            Files.createDirectories(targetDir);
            Path target = targetDir.resolve(filename);
            file.transferTo(target);
            return "/uploads/" + subDir + "/" + filename;
        } catch (IOException e) {
            throw new UncheckedIOException("Could not save uploaded file", e);
        }
    }

    /** Only ever trusts the extension, never the rest of the caller-supplied filename (which
     * becomes a random UUID) - a short alphanumeric suffix is safe to keep, anything else
     * (path separators, no extension at all) is dropped rather than reproduced verbatim. */
    private String extensionOf(String originalFilename) {
        if (originalFilename == null) {
            return "";
        }
        int dot = originalFilename.lastIndexOf('.');
        if (dot < 0 || dot == originalFilename.length() - 1) {
            return "";
        }
        String extension = originalFilename.substring(dot).toLowerCase(Locale.ROOT);
        return extension.matches("\\.[a-z0-9]{1,5}") ? extension : "";
    }
}
