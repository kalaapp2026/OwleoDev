// Adds a batch of keys to every locale's ARB file at once.
//
// Written as a script rather than hand-editing 13 JSON files per batch because the failure mode
// of doing it by hand is a key present in some locales and missing in others - which gen_l10n
// reports, but only after the fact. This keeps every locale in lockstep by construction.
//
// Usage: node tool/add_l10n_keys.mjs <batch-file.json>
// The batch file is { "keyName": { "en": "...", "hi": "...", ... }, ... }

import { readFileSync, writeFileSync } from 'node:fs';

const LOCALES = ['en', 'hi', 'ta', 'te', 'bn', 'mr', 'kn', 'gu', 'ml', 'es', 'ar', 'pt'];
// pt_BR reuses the pt strings - Brazilian wording is what was written, and having both keeps
// gen_l10n happy (a region locale needs its base locale to exist as a fallback).
const FILES = Object.fromEntries([...LOCALES.map((l) => [l, `lib/l10n/app_${l}.arb`]), ['pt_BR', 'lib/l10n/app_pt_BR.arb']]);

const batch = JSON.parse(readFileSync(process.argv[2], 'utf8'));

// Fail before writing anything rather than leaving locales half-updated.
for (const [key, values] of Object.entries(batch)) {
  const missing = LOCALES.filter((l) => typeof values[l] !== 'string' || values[l].length === 0);
  if (missing.length) {
    console.error(`FAIL: "${key}" is missing translations for: ${missing.join(', ')}`);
    process.exit(1);
  }
}

for (const [locale, file] of Object.entries(FILES)) {
  const source = locale === 'pt_BR' ? 'pt' : locale;
  const data = JSON.parse(readFileSync(file, 'utf8'));
  let added = 0;
  for (const [key, values] of Object.entries(batch)) {
    if (!(key in data)) {
      data[key] = values[source];
      added++;
    }
  }
  writeFileSync(file, JSON.stringify(data, null, 2) + '\n', 'utf8');
  console.log(`${file.padEnd(28)} +${added}`);
}
