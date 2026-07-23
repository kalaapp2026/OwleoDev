CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE academies (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(200) NOT NULL,
    category       VARCHAR(30)  NOT NULL,
    logo_url       VARCHAR(500),
    address        VARCHAR(500) NOT NULL,
    city           VARCHAR(100) NOT NULL,
    state          VARCHAR(100) NOT NULL,
    contact_number VARCHAR(30)  NOT NULL,
    email          VARCHAR(200),
    plan           VARCHAR(50)  NOT NULL DEFAULT 'STANDARD',
    status         VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ,
    CONSTRAINT uq_academies_name_city UNIQUE (name, city)
);
