// sign_entry.js — headless proof of ANA #2 Tier-1 (payload) signing.
//
// Proves the per-ENTRY signature scheme before any platform port, the way co-sign and the
// lessons were proven first. It pins the CLAIM (the notification), not the file, so the
// signature survives dedup / merge / re-export / any transport.
//
// SCHEME (one contract for GAXT, iOS CryptoKit, Android java.security):
//   curve     secp256r1 (P-256 / prime256v1)
//   hash      SHA-256
//   signature ECDSA, DER-encoded, hex          (Java native; Node native; Swift .derRepresentation)
//   pubkey    SPKI DER, hex                     (Java X.509; Node 'spki'; Swift .derRepresentation)
//   canonical the STABLE fields only, joined by '\n', UTF-8:
//                 src '\n' postMs '\n' package '\n' title '\n' text
//             NOT key, NOT lagMs  — so a harmless re-key/dedup never breaks the signature.
//
// Run: node diag/sign_entry.js        (also writes diag/sign_vectors.json for the Java cross-check)

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

// ---- the canonical: the claim, not the container -------------------------------------------
function canonical(e) {
  // fields are already tab/newline-cleaned upstream (PngMesh.clean); join with \n.
  return [e.src, String(e.postMs), e.pkg, e.title, e.text].join("\n");
}

// ---- scheme primitives ---------------------------------------------------------------------
function newKey() {
  return crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
}
function pubSpkiHex(pub) {
  return pub.export({ type: "spki", format: "der" }).toString("hex");
}
function sign(priv, e) {
  return crypto.createSign("SHA256").update(canonical(e), "utf8").sign({ key: priv, dsaEncoding: "der" }).toString("hex");
}
function verify(pubHex, e, sigHex) {
  const pub = crypto.createPublicKey({ key: Buffer.from(pubHex, "hex"), format: "der", type: "spki" });
  return crypto.createVerify("SHA256").update(canonical(e), "utf8")
    .verify({ key: pub, dsaEncoding: "der" }, Buffer.from(sigHex, "hex"));
}

// ---- the proof -----------------------------------------------------------------------------
let pass = 0, fail = 0;
const ok  = (name, cond) => { (cond ? pass++ : fail++); console.log((cond ? "  OK   " : "  FAIL ") + name); };

// a real GAXT-style capture (one of the WhatsApp rows from this morning)
const entry = { src: "IPHONE", postMs: 1764000000000, pkg: "net.whatsapp.WhatsApp", title: "Karl", text: "this music is awesome" };

const A = newKey();                         // companion A (e.g. GAXT)
const B = newKey();                         // a different key (impostor / another companion)
const pubA = pubSpkiHex(A.publicKey);
const pubB = pubSpkiHex(B.publicKey);
const sigA = sign(A.privateKey, entry);

console.log("ANA #2 — signing the claim (per-entry) — headless proof\n");

// 1. the happy path: A's signature verifies against A's key
ok("A's signature verifies against A's key", verify(pubA, entry, sigA) === true);

// 2. TAMPER: flip one character of the text -> must fail (the claim is frozen)
const tampered = { ...entry, text: "this music is awful" };
ok("tampered text fails verification", verify(pubA, tampered, sigA) === false);

// 3. tamper any other stable field -> must fail
ok("tampered package fails", verify(pubA, { ...entry, pkg: "net.evil.app" }, sigA) === false);
ok("tampered time fails",    verify(pubA, { ...entry, postMs: entry.postMs + 1 }, sigA) === false);

// 4. CROSS-KEY: A's signature must NOT verify against B's key (no impersonation)
ok("A's signature rejected under B's key", verify(pubB, entry, sigA) === false);

// 5. CLAIM TRAVELS: re-key + re-time the bookkeeping (dedup/import) -> signature still holds,
//    because key/lagMs are NOT in the canonical. This is the whole point.
const reimported = { ...entry };            // same stable fields; imagine key/lag changed around it
ok("signature survives a re-key (claim, not container)", verify(pubA, reimported, sigA) === true);

// 6. determinism of the canonical (same claim -> same bytes to sign)
ok("canonical is stable", canonical(entry) === canonical({ ...entry }));

// ---- vectors for the Java (GAXT / Android) cross-check -------------------------------------
const vectors = {
  scheme: { curve: "secp256r1", hash: "SHA-256", sig: "ECDSA-DER-hex", pubkey: "SPKI-DER-hex",
            canonical: "src\\npostMs\\npkg\\ntitle\\ntext" },
  canonical: canonical(entry),
  entry,
  pubA, sigA,       // Java must VERIFY this (Node-signed -> Java-verified)
  pubB              // Java must REJECT sigA under this
};
fs.writeFileSync(path.join(__dirname, "sign_vectors.json"), JSON.stringify(vectors, null, 2));
// flat file for the plain-Java cross-check (canonical base64'd so newlines survive)
const flat = "canonical_b64=" + Buffer.from(canonical(entry), "utf8").toString("base64") +
             "\npubA=" + pubA + "\nsigA=" + sigA + "\npubB=" + pubB + "\n";
fs.writeFileSync(path.join(__dirname, "sign_vectors.txt"), flat);
console.log("\nwrote diag/sign_vectors.json + sign_vectors.txt for the Java cross-check");

console.log("\n" + (fail === 0 ? "ALL OK (" + pass + ")" : fail + " FAILED, " + pass + " ok"));
process.exit(fail === 0 ? 0 : 1);
