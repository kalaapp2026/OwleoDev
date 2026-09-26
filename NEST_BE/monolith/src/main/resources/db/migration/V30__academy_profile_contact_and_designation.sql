-- Reference-parity additions to the About-Us page: a WhatsApp number distinct from the phone
-- contact, a generic Website link alongside the existing social URLs, a Google Maps link, and a
-- cover banner image separate from the logo tile. All nullable - identical treatment to the
-- existing optional profile fields (tagline, instagram_url, etc.).
ALTER TABLE academies ADD COLUMN whatsapp VARCHAR(20);
ALTER TABLE academies ADD COLUMN website_url VARCHAR(255);
ALTER TABLE academies ADD COLUMN maps_url VARCHAR(500);
ALTER TABLE academies ADD COLUMN cover_image_url VARCHAR(500);

-- A featured trainer's custom label on the About page (e.g. "Head of Dance & Founder"),
-- overriding whatever the frontend shows by default when set. Null falls back to that default.
ALTER TABLE academy_featured_trainers ADD COLUMN designation VARCHAR(120);
