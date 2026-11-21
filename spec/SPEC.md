# ANA Rule v1: lessons, the root chain, keys and verdicts

Every ANA build (LITE and STATIA on Android, ORBIT and STATIA on iOS) runs the same rule on the same bytes and must reach the same verdict. A verdict depends only on the file bytes, the build, and what this phone has already accepted: no clock, no network, no randomness. The test files in `vectors/` are the referee: a build ships only when it reproduces every expected verdict.

Built from the Lesson Maker homework (its pngmesh rows, readers and lint stay) and ANA MESH RULE v1 (its key format, low-S signatures, body hash and verdict style).

## 1. Keys (one format everywhere)

| Thing | Format |
|---|---|
| Public key | 65 raw bytes: `04 ‖ X ‖ Y` (P-256), written as 130 lowercase hex characters |
| Key id | SHA-256 of the 65 raw bytes, 64 lowercase hex characters. People see the first 16 |
| Signature | 64 raw bytes `r ‖ s`, ECDSA P-256 with SHA-256, **low-S only** (`s ≤ n/2`), written as 128 lowercase hex characters. A high-S signature is refused, never normalised by the reader |

Trusted keys built into every app: the Novvera **root** key and the **spare** key (made by the ANA Key Ceremony tool). Both may sign root-chain files and lessons. Licensee keys are trusted only through a permission (section 5).

## 2. The pngmesh container (unchanged)

`file = PNG bytes ‖ trailer ‖ u64 big-endian trailer length`. Trailer = `"PMSH"`, `u32 version = 1`, `u32 parts = 1`, `u32 class`, `u32 ncols = 3`, the column names `section`, `key`, `value`, `u32 nrows`, then each cell as `u32 length ‖ UTF-8 bytes`. No bytes may follow the last row. Every file travels with a `.sha256` sidecar whose first line is the lowercase hex SHA-256 of the whole file.

## 3. Class registry

| Class | Holds |
|---|---|
| 3 | 3D shapes |
| 20 | ANA log entries |
| 21 | GST packs |
| 22 | Mesh Rule chains (FLEX ledger, GST ledger) |
| 23 | IFAX messages |
| 30 | Lessons (any hive) |
| 31 | Licensee permissions (root chain) |
| 32 | Revokes (root chain) |
| 40 / 41 / 42 | ana.work job / result / assembly |

A number is never reused.

## 4. Signing a class 30, 31 or 32 file

The last two rows are always `sig | key_id | <64 hex>` then `sig | value | <128 hex>`.

* **Body** = the trailer bytes up to (not including) the final `sig | value` row. **Body hash** = SHA-256(body). The signature is not in the body, so re-encoding a signature can never give one file two identities.
* **Signed message** = the ASCII bytes `"ANA-PMSH1|" ‖ <class as decimal> ‖ "|"` followed by the 32 raw bytes of the body hash. Including the class means a signature on a lesson can never be replayed as a permission or a revoke.
* A lesson signed by a licensee also carries, before the `sig` rows, one row `permit | file | <base64 of the permission's whole pngmesh file>`, so the lesson can be checked on its own anywhere (personal import or GST).

## 5. The root chain (classes 31 and 32)

Permissions and revokes form one chain signed only by the root or spare key. Each carries `chain | seq | <n>` (starting at 1) and `chain | prev | <body hash of file n-1, or 64 zeros for n = 1>`.

**Permission (31)** rows, in this order: `chain|seq`, `chain|prev`, `permit|name` (the licensee, shown to people), `permit|key` (130 hex raw public key), `permit|tiers` (`ana` or `ana,statia`), `permit|hives` (comma list), `permit|tickers` (comma list, or `*`), `permit|until_seq` (the licence ends when this phone has accepted root-chain file number `until_seq`), then the `sig` rows.

**Revoke (32)** rows: `chain|seq`, `chain|prev`, `revoke|keys` (comma list of key ids), `revoke|reason`, then the `sig` rows. A revoked key and everything it signed stop working, including lessons already installed.

Expiry uses no clock: publishing root-chain file `until_seq` without a renewal ends the licence on every phone that has received it. A phone may warn by calendar date, but the verdict never uses one.

## 6. Lessons (class 30)

Rows, in section order `lesson`, `coin`, `address`, `reader`, `server`, `param`, `test`, then `permit` if any, then `sig`:

| Row | Rule |
|---|---|
| `lesson|id` | 2 to 32 of `a-z 0-9 _ -`, starting with a letter or digit |
| `lesson|version` | whole number 1 to 1,000,000 |
| `lesson|needs_reader` | whole number 1 to 1,000. This rule is reader level **1** |
| `lesson|hive` | `watch`, `efinote`, `clipnote`, `pacenote`, `hivenote` or `flex` |
| `lesson|tier` | `ana` or `statia` |
| `coin|…`, `address|…`, `reader|…`, `server|…`, `param|…`, `test|…` | as in the Lesson Maker homework (watch hive) |

At reader level 1 only the **watch** hive has its rows defined. A lesson for any other hive asks for `needs_reader ≥ 2` until that hive's rows are written into this Spec.

Watch rows (the homework's lint, enforced again on the phone): `coin|name`, `coin|ticker` (1 to 10 of `A-Z 0-9`), `coin|decimals` (0 to 30), `coin|display_decimals` (0 to 18), `coin|price_id` (CoinGecko id); one or more address forms `address|formN.kind` (`base58check`, `bech32` or `hex_evm`) with `.pattern`, and `.hrp` (bech32) or `.versions` (base58check); `reader|name` (`esplora`, `evm` or `json`); `server|1…` (https only, no user or password, no key-like query); for `json`: `param|method`, `param|balance_path`, `param|balance_type`, and `{address}` in the body or URL; for `evm`: `param|chain_id`. At least one `test|good.N` that passes an address form and one `test|bad.N` that passes none. No value outside `test` may look like a secret.

## 7. Verdicts

| Verdict | Phone says |
|---|---|
| `ACCEPT` | Added |
| `DUPLICATE` | You already have this |
| `HOLE` | Something earlier is missing; waiting for it (root chain) |
| `UPDATE_FIRST` | Update ANA to read this (never "invalid") |
| `BAD_SIDECAR` | This file is damaged (it doesn't match its .sha256) |
| `BAD_FORMAT` | This file is damaged |
| `HIGH_S` | This file was changed after signing |
| `BAD_SIGNATURE` | This file was changed after signing |
| `UNKNOWN_KEY` | Signed by someone ANA doesn't trust |
| `REVOKED` | This signer was switched off |
| `EXPIRED` | This signer's licence has ended |
| `NOT_PERMITTED` | This signer isn't licensed for this |
| `WRONG_TIER` | Part of ANA : STATIA, ANA's big sister |
| `WRONG_HIVE` | This lesson is for a hive this app doesn't have |
| `OLDER` | You have a newer version |
| `BAD_RULES` | This lesson breaks a safety rule (and names which) |
| `FORK` | Two different files claim the same place |
| `FROZEN` | This signer is frozen after a fork |

## 8. Checking a file, in this exact order (first failure is the verdict)

A phone's state: its build (`reader` level, `tier` = `ana` or `statia`, the `hives` it has), the root chain (`seq`, `head` hash, revoked key ids, frozen key ids, permissions by key id), and installed lessons (by id: version and body hash).

1. Sidecar missing or not matching the file: `BAD_SIDECAR`.
2. Container unreadable, wrong class, wrong columns, extra bytes, missing or malformed `sig` rows, or a malformed key or signature hex: `BAD_FORMAT`.
3. High-S signature: `HIGH_S`.
4. Find the signer. Root-chain files (31, 32): only root or spare, else `UNKNOWN_KEY`. Lessons: root or spare; else a `permit|file` row whose permission (checked by steps 1 to 6 as a class 31 file, without a sidecar) is signed by root or spare and whose `permit|key` has the lesson's `key_id`; else `UNKNOWN_KEY`.
5. Root-chain files only: signer frozen: `FROZEN`. Any file: signer revoked, or (for a lesson) the root or spare that signed its permission revoked: `REVOKED`.
6. Signature does not verify: `BAD_SIGNATURE`.
7. Root-chain files only: `seq` already accepted with the same body hash: `DUPLICATE`; same `seq`, different body: `FORK` (both signers frozen for root-chain purposes); `seq` more than one ahead: `HOLE`; `prev` not equal to this phone's head: `FORK`. Otherwise `ACCEPT`: a revoke adds its keys to the revoked set; a permission is stored by its key id.
8. Lessons only, in order: `needs_reader` not a whole number: `BAD_RULES`. `needs_reader` above this build's reader level, or a known hive this Spec level does not define yet: `UPDATE_FIRST` (a hive name that is not in the list at all: `BAD_RULES`). Licensee checks: permission not in force here (`chain seq` of this phone ≥ `until_seq`): `EXPIRED`; lesson's tier not in `permit|tiers`, hive not in `permit|hives`, or ticker not in `permit|tickers`: `NOT_PERMITTED`. Hive defined but not in this build: `WRONG_HIVE`. Tier `statia` on an `ana` build: `WRONG_TIER`. Same id installed: lower version `OLDER`; same version and body `DUPLICATE`; same version, different body `FORK`. Lint failure: `BAD_RULES` with the reasons. Otherwise `ACCEPT`.

After a root-chain `ACCEPT`, the phone re-checks installed lessons: any whose signer is now revoked or whose licence has expired is switched off, with the verdict shown.

## 9. ANA MESH RULE v2 (one change from v1)

The witness payload's amount becomes `u8 length ‖ ASCII decimal digits` (no leading zeros except `"0"`, length 1 to 78), replacing the u64 that topped out near 18.4 ETH in wei. The rule version field becomes 2; a v1 phone answers `UPDATE_FIRST` to v2 entries. Everything else in v1 is unchanged.

## 10. What is verified

`vectors/` holds 31 test files and 47 expected verdicts in 11 scenarios, covering all 18 verdicts. They are made by `py/anarule.py` with fixed TEST keys (never the real root or spare). `java/AnaRule.java` is an independent implementation built on the Lesson Maker's Engine. `run_all.sh` remakes the files, checks both reach every expected verdict, then plants five bugs in the Java (no high-S check, prev link ignored, no tier gate, expiry off by one, a revoked root behind a permit ignored) and confirms the vectors catch every one.
