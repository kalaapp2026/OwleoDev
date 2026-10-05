-- Academy Profile rebuild: the address splits into line / area / city / state / pin code (line
-- stays in the existing `address` column), and the cover banner and logo tile get a preset look
-- used whenever no photo is uploaded. Both presets are theme keys, not hex values, so they follow
-- light/dark mode.
ALTER TABLE academies ADD COLUMN area VARCHAR(200);
ALTER TABLE academies ADD COLUMN pin_code VARCHAR(10);
ALTER TABLE academies ADD COLUMN cover_style VARCHAR(20);
ALTER TABLE academies ADD COLUMN logo_color VARCHAR(20);

-- Social / maps links the Admin has switched off. Kept separate from the URL columns so hiding a
-- link and turning it back on later doesn't lose what was typed. Comma-separated keys
-- (instagram, x, facebook, youtube, website, maps).
ALTER TABLE academies ADD COLUMN hidden_links VARCHAR(100);
