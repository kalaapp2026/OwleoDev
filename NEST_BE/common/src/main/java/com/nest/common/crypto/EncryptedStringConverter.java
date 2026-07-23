package com.nest.common.crypto;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * Apply to PII fields explicitly: {@code @Convert(converter = EncryptedStringConverter.class)}.
 * Not {@code autoApply} on purpose - encryption must be an opt-in, visible decision per column.
 */
@Converter
public class EncryptedStringConverter implements AttributeConverter<String, String> {

    @Override
    public String convertToDatabaseColumn(String attribute) {
        return PiiEncryptor.instance().encrypt(attribute);
    }

    @Override
    public String convertToEntityAttribute(String dbData) {
        return PiiEncryptor.instance().decrypt(dbData);
    }
}
