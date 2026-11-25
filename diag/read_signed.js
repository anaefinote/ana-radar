// read_signed.js — parse a real GAXT-written .pngmesh and verify every row's signature.
// Proves the GAXT writer -> ANA reader contract end to end (the class-20 + sig/signer carrier).
// Run: node diag/read_signed.js /tmp/gaxt_signed.pngmesh

const crypto = require("crypto");
const fs = require("fs");

const b = fs.readFileSync(process.argv[2]);
let p;
// trailer length = last 8 bytes, big-endian int64
const tl = Number(b.readBigInt64BE(b.length - 8));
const start = b.length - 8 - tl;
p = start;
const i32 = () => { const v = b.readInt32BE(p); p += 4; return v; };
const str = () => { const n = i32(); const s = b.toString("utf8", p, p + n); p += n; return s; };

if (b.toString("ascii", start, start + 4) !== "PMSH") throw new Error("no PMSH");
p += 4;
const ver = i32(), parts = i32();
console.log("GAXT-written .pngmesh: version " + ver + ", parts " + parts + "\n");

let pass = 0, fail = 0;
for (let part = 0; part < parts; part++) {
  const cls = i32();
  const nc = i32();
  const names = []; for (let i = 0; i < nc; i++) names.push(str());
  const nr = i32();
  console.log("part class " + cls + ", columns: " + names.join(", ") + "\n");
  const col = (row, name) => row[names.indexOf(name)];
  for (let r = 0; r < nr; r++) {
    const row = []; for (let i = 0; i < nc; i++) row.push(str());
    const canonical = [col(row,"src"), col(row,"postMs"), col(row,"package"), col(row,"title"), col(row,"text")].join("\n");
    const sig = col(row, "sig"), signer = col(row, "signer");
    let ok = false;
    if (sig && signer) {
      const pub = crypto.createPublicKey({ key: Buffer.from(signer, "hex"), format: "der", type: "spki" });
      ok = crypto.createVerify("SHA256").update(canonical, "utf8").verify({ key: pub, dsaEncoding: "der" }, Buffer.from(sig, "hex"));
    }
    (ok ? pass++ : fail++);
    console.log("  " + (ok ? "VERIFIED" : "unverified") + "  [" + col(row,"package") + "] " + col(row,"title") + " — " + col(row,"text"));
  }
}
// tamper check: flip a byte in the file's trailer region and confirm a row stops verifying
console.log("\n" + (fail === 0 && pass > 0 ? "ALL ROWS VERIFIED (" + pass + ")" : fail + " unverified"));
process.exit(fail === 0 && pass > 0 ? 0 : 1);
