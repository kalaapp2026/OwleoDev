package com.nest.app.curriculum.entity;

/** What kind of file (if any) a SyllabusUnit's referenceMaterialUrl points to, so the frontend
 * knows whether to render an image preview or a PDF icon+open link without sniffing content. */
public enum ReferenceMaterialType {
    NONE,
    IMAGE,
    PDF
}
