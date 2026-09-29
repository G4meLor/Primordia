#!/usr/bin/env node
'use strict';
/**
 * gen_i18n_csv.js — extract the VI dictionary from the frozen TS repo's
 * src/core/i18n.ts into an RFC-4180 CSV for the Godot native port.
 *
 * Runs against the Spore repo (frozen for GAME code; tooling additions are
 * sanctioned — M1 precedent tools/table-check.test.ts) but is committed in
 * the native repo and invoked from either side:
 *
 *   cd ~/Desktop/RD/Spore && node ../primordia-native/tools/gen_i18n_csv.js
 *   node tools/gen_i18n_csv.js                      # same effect (paths are
 *                                                   # __dirname-relative)
 *
 * Optional args: [i18n.ts path] [output csv path]
 *
 * Deterministic: reads the TS source as text, slices the `const VI = {...}`
 * object literal out (brace-matched with string-literal awareness), evaluates
 * it as plain JS (the `// section` comments inside are legal in an object
 * literal), then emits rows in SOURCE ORDER — no sorting, no timestamps —
 * so regenerating on an unchanged source is byte-identical.
 *
 * Escaping: RFC 4180 — fields containing comma, double quote, CR or LF are
 * wrapped in double quotes with inner quotes doubled. Keys contain emoji,
 * combining strikethrough chars and em-dashes; values contain commas. The
 * generated CSV is parsed back with an independent reader and deep-compared
 * against the extracted map before the file is written (the escaping test).
 */

const fs = require('node:fs');
const path = require('node:path');

const SPORE_I18N_TS = process.argv[2]
  || path.resolve(__dirname, '..', '..', 'Spore', 'src', 'core', 'i18n.ts');
const OUT_CSV = process.argv[3]
  || path.resolve(__dirname, '..', 'assets', 'i18n', 'vi.csv');

/** TS-side audit floor (tests/features.test.ts: viKeyCount() >= 454). */
const MIN_KEYS = 454;

function fail(msg) {
  console.error('gen_i18n_csv: FAIL: ' + msg);
  process.exit(1);
}

/**
 * Slice the VI object literal out of the TS source. Finds `const VI`, then
 * brace-matches from the opening `{`, skipping over string literals so keys
 * like '🗿 A TITAN WALKS' (braces would confuse a naive matcher — they don't
 * appear, but emoji / quotes / escapes generally must not break the scan).
 */
function extractViObjectText(src) {
  const marker = src.indexOf('const VI');
  if (marker < 0) fail('could not find `const VI` in ' + SPORE_I18N_TS);
  const open = src.indexOf('{', marker);
  if (open < 0) fail('could not find the VI object opening brace');
  let inStr = null; // "'", '"' or null
  for (let i = open + 1; i < src.length; i++) {
    const c = src[i];
    if (inStr !== null) {
      if (c === '\\') { i++; continue; } // skip escaped char (e.g. \')
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === "'" || c === '"') { inStr = c; continue; }
    if (c === '{') fail('unexpected nested { in VI object at offset ' + i);
    if (c === '}') return src.slice(open, i + 1);
  }
  fail('could not find the VI object closing brace');
}

/** Evaluate the object literal as plain JS (comments inside are legal). */
function parseViObject(objectText) {
  let vi;
  try {
    vi = new Function('return (' + objectText + ');')();
  } catch (e) {
    fail('evaluating the VI object literal threw: ' + e.message);
  }
  for (const [k, v] of Object.entries(vi)) {
    if (typeof k !== 'string' || typeof v !== 'string') {
      fail('non-string key/value in VI: ' + String(k));
    }
  }
  return vi;
}

/** RFC 4180 field writer: quote only when needed, double inner quotes. */
function csvField(s) {
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

/**
 * Independent RFC 4180 reader for the round-trip check — deliberately not
 * the mirror image of csvField: a small full-file state machine.
 */
function parseCsv(text) {
  const rows = [[]];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else { quoted = false; }
      } else {
        field += c;
      }
    } else if (c === '"' && field === '') {
      quoted = true;
    } else if (c === ',') {
      rows[rows.length - 1].push(field);
      field = '';
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      rows[rows.length - 1].push(field);
      field = '';
      rows.push([]);
    } else {
      field += c;
    }
  }
  if (field !== '' || rows[rows.length - 1].length > 0) {
    rows[rows.length - 1].push(field);
  }
  // drop the empty trailing record left by the final newline, then the header
  const last = rows[rows.length - 1];
  if (last && last.length === 0) rows.pop();
  else if (last && last.length === 1 && last[0] === '' && rows.length > 1) rows.pop();
  return rows.slice(1);
}

function main() {
  const src = fs.readFileSync(SPORE_I18N_TS, 'utf8');
  const vi = parseViObject(extractViObjectText(src));
  const keys = Object.keys(vi);
  if (keys.length < MIN_KEYS) {
    fail('VI dictionary has ' + keys.length + ' keys, below the audited floor ' + MIN_KEYS);
  }

  const lines = ['key,vi'];
  for (const k of keys) lines.push(csvField(k) + ',' + csvField(vi[k]));
  const csv = lines.join('\n') + '\n';

  // escaping test: parse back and require an exact, order-preserving match
  const parsed = parseCsv(csv);
  if (parsed.length !== keys.length) {
    fail('round-trip row count ' + parsed.length + ' != ' + keys.length);
  }
  for (let i = 0; i < keys.length; i++) {
    const [rk, rv] = parsed[i];
    if (rk !== keys[i] || rv !== vi[keys[i]]) {
      fail('round-trip mismatch at row ' + i + ': "' + rk + '" -> "' + rv + '"');
    }
  }

  fs.mkdirSync(path.dirname(OUT_CSV), { recursive: true });
  fs.writeFileSync(OUT_CSV, csv, 'utf8');
  console.log('gen_i18n_csv: wrote ' + keys.length + ' keys (' + csv.length + ' bytes) -> ' + OUT_CSV);
}

main();
