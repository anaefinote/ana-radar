#!/usr/bin/env node
// ANA #2 1b slice 3 — DETAIN PEN test fixtures.
// Mints two authority capsules (class 30) that ANA must DETAIN, not run, not drop:
//   A) a validly-signed lesson from an UNTRUSTED key  -> verdict UNKNOWN_KEY
//   B) a structurally malformed capsule (illegal section) -> verdict BAD_FORMAT
// Both are real .pngmesh files (PMSH trailer) with matching .sha256 sidecars, so the
// ANA importer pairs and routes them exactly like a genuine lesson. Node-only; no ANA code.
//
// Capsule layout (from AnaRule.parseSigned / AnaMesh.looksLikePngmesh / Lessons.classOf):
//   [PNG filler] [PMSH trailer] [8-byte big-endian trailer length]
//   trailer = "PMSH" u32(version=1) u32(parts=1) u32(cls) u32(cols=3) "section" "key" "value"
//             u32(nrows) nrows*(str section, str key, str value)
//   last two rows MUST be  sig|key_id|<64hex>  and  sig|value|<128hex>
//   signed body = trailer bytes from 0 up to the START of the last row (sig|value)
//   message = "ANA-PMSH1|<cls>|" + SHA256(body)   (ECDSA P-256, raw r||s, low-S)

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, 'bad_capsules');
fs.mkdirSync(OUT, { recursive: true });

const N = BigInt('0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551'); // secp256r1 order
const SPKI_P256_PREFIX = Buffer.from('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
// minimal 1x1 PNG — front filler only; the lesson path never decodes it
const PNG = Buffer.from(
  '89504e470d0a1a0a0000000d494844520000000100000001080600000' +
  '01f15c4890000000d49444154789c6360000002000154a24f5e0000000049454e44ae426082', 'hex');

const u32 = n => { const b = Buffer.alloc(4); b.writeUInt32BE(n >>> 0, 0); return b; };
const u64 = n => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n), 0); return b; };
const str = s => { const u = Buffer.from(s, 'utf8'); return Buffer.concat([u32(u.length), u]); };
const sha256 = buf => crypto.createHash('sha256').update(buf).digest();
const hex = buf => buf.toString('hex');

// build the PMSH trailer and report the offset where the LAST row starts (= end of signed body)
function buildTrailer(cls, rows) {
  const head = Buffer.concat([
    Buffer.from('PMSH', 'ascii'),
    u32(1), u32(1), u32(cls),
    u32(3), str('section'), str('key'), str('value'),
    u32(rows.length),
  ]);
  const rowBufs = rows.map(r => Buffer.concat([str(r[0]), str(r[1]), str(r[2])]));
  let bodyEnd = head.length;
  for (let i = 0; i < rowBufs.length - 1; i++) bodyEnd += rowBufs[i].length;
  return { trailer: Buffer.concat([head, ...rowBufs]), bodyEnd };
}

function assemble(cls, rows) {
  const { trailer, bodyEnd } = buildTrailer(cls, rows);
  const file = Buffer.concat([PNG, trailer, u64(trailer.length)]);
  return { file, trailer, bodyEnd };
}

// low-S normalise a raw 64-byte (r||s) signature
function lowS(sig) {
  const r = sig.subarray(0, 32);
  let s = BigInt('0x' + hex(sig.subarray(32, 64)));
  if (s > N / 2n) s = N - s;
  return Buffer.concat([r, Buffer.from(s.toString(16).padStart(64, '0'), 'hex')]);
}

function writeCapsule(base, file, note) {
  const p = path.join(OUT, base + '.pngmesh');
  fs.writeFileSync(p, file);
  fs.writeFileSync(p + '.sha256', hex(sha256(file)) + '\n');
  console.log(`  ${base}.pngmesh  (${file.length} bytes)  sha256 ${hex(sha256(file)).slice(0, 16)}…  -> ${note}`);
}

// ---- Capsule A: validly-signed lesson from an untrusted key -> UNKNOWN_KEY ----
const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const spki = publicKey.export({ type: 'spki', format: 'der' });
const pubRaw = spki.subarray(spki.length - 65);           // 0x04 || X || Y
const keyId = hex(sha256(pubRaw));

const rowsA = [
  ['lesson', 'id', 'bad-unknown-key'],
  ['sig', 'key_id', keyId],
  ['sig', 'value', '00'.repeat(64)],                       // placeholder; sig value is OUTSIDE the body
];
let A = assemble(30, rowsA);
const bodyA = A.trailer.subarray(0, A.bodyEnd);
const msgA = Buffer.concat([Buffer.from('ANA-PMSH1|30|', 'utf8'), sha256(bodyA)]);
const sigA = lowS(crypto.sign('sha256', msgA, { key: privateKey, dsaEncoding: 'ieee-p1363' }));
rowsA[2][2] = hex(sigA);                                   // same length (128 hex) -> body unchanged
A = assemble(30, rowsA);

// self-check: the signature really verifies against its own (untrusted) key
const pubKeyObj = crypto.createPublicKey({
  key: Buffer.concat([SPKI_P256_PREFIX, pubRaw]), format: 'der', type: 'spki',
});
const sigOk = crypto.verify('sha256', msgA, { key: pubKeyObj, dsaEncoding: 'ieee-p1363' }, sigA);

// ---- Capsule B: malformed capsule (illegal section) -> BAD_FORMAT ----
const rowsB = [
  ['bogus', 'x', 'y'],                                     // "bogus" is not an allowed section
  ['sig', 'key_id', 'ab'.repeat(32)],
  ['sig', 'value', 'cd'.repeat(64)],
];
const B = assemble(30, rowsB);

console.log('Minting detain-pen test capsules into diag/bad_capsules/ …');
writeCapsule('lesson_bad_unknownkey', A.file, 'expect DETAINED (UNKNOWN_KEY)');
writeCapsule('lesson_bad_malformed', B.file, 'expect DETAINED (BAD_FORMAT)');
console.log('');
console.log(`Capsule A signature self-verifies against its untrusted key: ${sigOk ? 'YES ✓' : 'NO ✗'}`);
console.log(`Capsule A key_id (sha256 of its pubkey): ${keyId.slice(0, 24)}…`);
console.log(`Both files report class ${classOfLocal(A.file)} / ${classOfLocal(B.file)} (30 = authority tier).`);
console.log('');
console.log('On the iPhone: Lessons sheet → Import a lesson… → import BOTH files of a pair');
console.log('(the .pngmesh and its .sha256). Each should toast "Detained — …" and appear in');
console.log('"Detain pen". Import the same pair twice to see the hit-count bump (dedup).');

// mirror of Lessons.classOf — reads cls at trailer offset 12, independent of the rows
function classOfLocal(buf) {
  const b = buf;
  const tl = Number(b.readBigUInt64BE(b.length - 8));
  const st = b.length - 8 - tl;
  return (b[st + 12] << 24) | (b[st + 13] << 16) | (b[st + 14] << 8) | b[st + 15];
}
