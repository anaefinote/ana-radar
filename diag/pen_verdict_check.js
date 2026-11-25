#!/usr/bin/env node
// Headless proof that the two minted fixtures resolve to DETAIN-worthy verdicts.
// Faithful mirror of AnaRule.parseSigned + the empty-trust branch of AnaRule.check
// (trusted set empty, as on a fresh install). No ANA code imported.

const fs = require('fs');
const path = require('path');
const DIR = path.join(__dirname, 'bad_capsules');

const OK_SECTIONS = ['lesson', 'coin', 'address', 'reader', 'server', 'param', 'test', 'permit', 'chain', 'revoke'];
const isHex = (s, n) => new RegExp(`^[0-9a-f]{${n}}$`).test(s);

function parseSigned(buf) {
  const b = buf;
  if (b.length < 20) throw new Error('too small');
  const tl = Number(b.readBigUInt64BE(b.length - 8));
  if (tl < 12 || tl > b.length - 8) throw new Error('no trailer');
  const t = b.subarray(b.length - 8 - tl, b.length - 8);
  if (!(t[0] === 0x50 && t[1] === 0x4d && t[2] === 0x53 && t[3] === 0x48)) throw new Error('magic');
  let p = 4;
  const u32 = () => { if (p + 4 > t.length) throw new Error('short'); const v = t.readUInt32BE(p); p += 4; return v; };
  const str = () => { const n = u32(); if (p + n > t.length) throw new Error('bad string'); const s = t.subarray(p, p + n).toString('utf8'); p += n; return s; };
  if (u32() !== 1 || u32() !== 1) throw new Error('version or parts');
  const cls = u32();
  if (u32() !== 3 || str() !== 'section' || str() !== 'key' || str() !== 'value') throw new Error('columns');
  const nr = u32();
  if (nr < 3 || nr > 100000) throw new Error('rows');
  const rows = []; let lastAt = 0;
  for (let i = 0; i < nr; i++) { if (i === nr - 1) lastAt = p; rows.push([str(), str(), str()]); }
  if (p !== t.length) throw new Error('extra bytes');
  const kid = rows[nr - 2], sg = rows[nr - 1];
  if (kid[0] !== 'sig' || kid[1] !== 'key_id' || sg[0] !== 'sig' || sg[1] !== 'value') throw new Error('sig rows');
  if (!isHex(kid[2], 64) || !isHex(sg[2], 128)) throw new Error('sig hex');
  const kv = {}; const seen = new Set();
  for (let i = 0; i < nr - 2; i++) {
    if (!OK_SECTIONS.includes(rows[i][0])) throw new Error('section ' + rows[i][0]);
    const k = rows[i][0] + '|' + rows[i][1];
    if (seen.has(k)) throw new Error('duplicate row ' + k);
    seen.add(k); kv[k] = rows[i][2];
  }
  return { cls, kv, keyId: kid[2] };
}

// empty-trust branch of check(): lesson with no trusted key and no permit -> UNKNOWN_KEY
function verdict(buf) {
  let s;
  try { s = parseSigned(buf); } catch (e) { return ['BAD_FORMAT', e.message]; }
  if (![30, 31, 32].includes(s.cls)) return ['BAD_FORMAT', 'class'];
  const trusted = {};                       // fresh install: nothing trusted
  if (s.cls !== 30) return trusted[s.keyId] ? ['OK?', ''] : ['UNKNOWN_KEY', ''];
  if (trusted[s.keyId]) return ['NEEDS_FULL_ENGINE', ''];
  if (!('permit|file' in s.kv)) return ['UNKNOWN_KEY', ''];
  return ['NEEDS_FULL_ENGINE', 'permit present'];
}

const cases = [
  ['lesson_bad_unknownkey.pngmesh', 'UNKNOWN_KEY'],
  ['lesson_bad_malformed.pngmesh', 'BAD_FORMAT'],
];
let pass = 0;
console.log('Detain-pen verdict proof (empty-trust / fresh install):\n');
for (const [name, want] of cases) {
  const v = verdict(fs.readFileSync(path.join(DIR, name)));
  const ok = v[0] === want;
  pass += ok ? 1 : 0;
  // penShouldDetain: anything not ACCEPT/DUPLICATE/OLDER/UPDATE_FIRST is held
  const detained = !['ACCEPT', 'DUPLICATE', 'OLDER', 'UPDATE_FIRST'].includes(v[0]);
  console.log(`  ${ok ? '✓' : '✗'} ${name}`);
  console.log(`      verdict ${v[0]}${v[1] ? ' (' + v[1] + ')' : ''}  ·  want ${want}  ·  pen detains: ${detained ? 'YES' : 'no'}`);
}
console.log(`\n${pass}/${cases.length} fixtures resolve to the expected DETAIN verdict.`);
process.exit(pass === cases.length ? 0 : 1);
