-- Per-user UI language, stored alongside theme_preference so a preference follows the person
-- across devices rather than living only on whichever phone they set it on.
--
-- A BCP 47 tag ('en', 'hi', 'pt-BR') rather than an enum: the set of shipped languages will change
-- as translations land, and adding one shouldn't need a schema migration and a backend deploy.
-- The client validates it against the locales it actually bundles and falls back to English for
-- anything it doesn't recognise, so an unknown value here degrades rather than breaks.
ALTER TABLE users ADD COLUMN language_preference VARCHAR(10) NOT NULL DEFAULT 'en';
