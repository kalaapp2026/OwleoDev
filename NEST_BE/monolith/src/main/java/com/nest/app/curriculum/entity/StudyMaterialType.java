package com.nest.app.curriculum.entity;

import java.util.Locale;
import java.util.Set;

/**
 * What kind of file a study material is, so the list can group and filter without sniffing every
 * file, and the viewer knows which preview to render.
 *
 * <p>Derived from the extension at upload time rather than the browser-supplied content type:
 * content types are inconsistent across platforms (an mp3 arrives as audio/mpeg, audio/mp3 or
 * application/octet-stream depending on the client), while the extension is what the person
 * actually chose.
 */
public enum StudyMaterialType {
    NOTES,
    AUDIO,
    IMAGE;

    private static final Set<String> AUDIO_EXTENSIONS = Set.of("mp3", "wav", "m4a", "aac", "ogg");
    private static final Set<String> IMAGE_EXTENSIONS = Set.of("jpg", "jpeg", "png", "gif", "webp");

    /** Anything not recognised as audio or an image is treated as a document - the widest and
     * least surprising bucket, and the one whose preview degrades most gracefully. */
    public static StudyMaterialType fromFileName(String fileName) {
        if (fileName == null) {
            return NOTES;
        }
        int dot = fileName.lastIndexOf('.');
        if (dot < 0 || dot == fileName.length() - 1) {
            return NOTES;
        }
        String extension = fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
        if (AUDIO_EXTENSIONS.contains(extension)) {
            return AUDIO;
        }
        if (IMAGE_EXTENSIONS.contains(extension)) {
            return IMAGE;
        }
        return NOTES;
    }
}
