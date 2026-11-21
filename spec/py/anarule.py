"""ANA Rule v1 - reference implementation in Python (see ../SPEC.md).

Pure: verdicts depend only on file bytes, the build and the phone's accepted state. No clock, no network.
Used to make the test files and to check them. The Java implementation (../java) is written separately.
"""
import base64, hashlib, re, struct
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature
from cryptography.hazmat.primitives import hashes
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
READER_LEVEL = 1
HIVES_ALL = ["watch", "efinote", "clipnote", "pacenote", "hivenote", "flex"]
HIVES_DEFINED = {1: ["watch"]}          # hives whose rows this Spec level defines
SECTIONS = ["lesson", "coin", "address", "reader", "server", "param", "test", "permit", "sig"]
CLASS_LESSON, CLASS_PERMIT, CLASS_REVOKE = 30, 31, 32

# ------------------------------------------------------------------ keys
def raw_pub(priv):
    return priv.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)

def key_id(raw):
    return hashlib.sha256(raw).hexdigest()

def priv_from_seed(text):
    d = int.from_bytes(hashlib.sha256(text.encode()).digest(), "big") % (N - 1) + 1
    return ec.derive_private_key(d, ec.SECP256R1())

def sign_raw(priv, msg):
    r, s = decode_dss_signature(priv.sign(msg, ec.ECDSA(hashes.SHA256(), deterministic_signing=True)))
    if s > N // 2:
        s = N - s
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")

def verify_raw(raw, msg, sig):
    if len(raw) != 65 or raw[0] != 4 or len(sig) != 64:
        return False
    r, s = int.from_bytes(sig[:32], "big"), int.from_bytes(sig[32:], "big")
    if not (0 < r < N and 0 < s <= N // 2):
        return False
    try:
        pub = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)
        pub.verify(encode_dss_signature(r, s), msg, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError):
        return False

# ------------------------------------------------------------------ pngmesh
def _wstr(s):
    b = s.encode("utf-8")
    return struct.pack(">I", len(b)) + b

def trailer_prefix(cls, rows_before_last, total_rows):
    out = b"PMSH" + struct.pack(">III", 1, 1, cls) + struct.pack(">I", 3)
    out += _wstr("section") + _wstr("key") + _wstr("value") + struct.pack(">I", total_rows)
    for r in rows_before_last:
        for c in r:
            out += _wstr(c)
    return out

def wrap(png, trailer):
    return png + trailer + struct.pack(">Q", len(trailer))

class Bad(Exception):
    pass

def parse(f):
    """-> (cls, rows, body). body = trailer bytes before the final row."""
    if len(f) < 20:
        raise Bad("too small")
    tl = struct.unpack(">Q", f[-8:])[0]
    start = len(f) - 8 - tl
    if tl < 12 or start < 0:
        raise Bad("no trailer")
    t = f[start:len(f) - 8]
    p = [0]
    def u32():
        if p[0] + 4 > len(t):
            raise Bad("short")
        v = struct.unpack(">I", t[p[0]:p[0] + 4])[0]; p[0] += 4; return v
    def rstr():
        n = u32()
        if n > 16777216 or p[0] + n > len(t):
            raise Bad("bad string")
        b = t[p[0]:p[0] + n]; p[0] += n
        try:
            return b.decode("utf-8")
        except UnicodeDecodeError:
            raise Bad("bad utf-8")
    if t[:4] != b"PMSH":
        raise Bad("magic")
    p[0] = 4
    if u32() != 1 or u32() != 1:
        raise Bad("version/parts")
    cls = u32()
    if u32() != 3 or [rstr(), rstr(), rstr()] != ["section", "key", "value"]:
        raise Bad("columns")
    nr = u32()
    if nr < 3 or nr > 100000:
        raise Bad("rows")
    rows, last = [], 0
    for i in range(nr):
        if i == nr - 1:
            last = p[0]
        rows.append((rstr(), rstr(), rstr()))
    if p[0] != len(t):
        raise Bad("extra bytes")
    return cls, rows, t[:last]

def signed_message(cls, body):
    return ("ANA-PMSH1|%d|" % cls).encode() + hashlib.sha256(body).digest()

def build(cls, rows, priv, png=b"\x89PNG\r\n\x1a\n-test-", high_s=False):
    kid = key_id(raw_pub(priv))
    before = list(rows) + [("sig", "key_id", kid)]
    body = trailer_prefix(cls, before, len(before) + 1)
    sig = sign_raw(priv, signed_message(cls, body))
    if high_s:
        s = int.from_bytes(sig[32:], "big")
        sig = sig[:32] + (N - s).to_bytes(32, "big")
    return wrap(png, body + _wstr("sig") + _wstr("value") + _wstr(sig.hex()))

def sidecar(f, name="file.pngmesh"):
    return ("%s\n%s\n%d\n" % (hashlib.sha256(f).hexdigest(), name, len(f))).encode()

# ------------------------------------------------------------------ addresses (same checks as the Lesson Maker Engine)
B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
B32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

def b58check_ok(a, versions):
    n = 0
    for ch in a:
        i = B58.find(ch)
        if i < 0:
            return False
        n = n * 58 + i
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big") if n else b""
    zeros = len(a) - len(a.lstrip("1"))
    d = b"\x00" * zeros + raw
    if len(d) != 25 or hashlib.sha256(hashlib.sha256(d[:21]).digest()).digest()[:4] != d[21:]:
        return False
    vs = []
    for v in (versions or "").split(","):
        try:
            vs.append(int(v.strip()))
        except ValueError:
            pass
    return d[0] in vs

def _polymod(v):
    gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    chk = 1
    for x in v:
        top = chk >> 25
        chk = ((chk & 0x1ffffff) << 5) ^ x
        for j in range(5):
            if (top >> j) & 1:
                chk ^= gen[j]
    return chk

def bech32_ok(a, hrp):
    if a is None or len(a) < 8 or (a != a.lower() and a != a.upper()):
        return False
    low = a.lower()
    pos = low.rfind("1")
    if pos < 1 or pos + 7 > len(low):
        return False
    h = low[:pos]
    if hrp and h != hrp.lower():
        return False
    if any(ord(c) < 33 or ord(c) > 126 for c in h):
        return False
    data = []
    for c in low[pos + 1:]:
        i = B32.find(c)
        if i < 0:
            return False
        data.append(i)
    return _polymod([ord(c) >> 5 for c in h] + [0] + [ord(c) & 31 for c in h] + data) in (1, 0x2bc830a3)

def addr_ok(kind, pattern, hrp, versions, a):
    try:
        if pattern and not re.fullmatch(pattern, a):
            return False
    except re.error:
        return False
    if kind == "hex_evm":
        return re.fullmatch(r"0x[0-9a-fA-F]{40}", a) is not None
    if kind == "base58check":
        return b58check_ok(a, versions)
    if kind == "bech32":
        return bech32_ok(a, hrp)
    return False

# ------------------------------------------------------------------ lint (watch hive, reader level 1)
SECRET_URL = re.compile(r".*[?&](api_?key|key|token|secret|project_id|auth|access_token)=.*")
SECRET_ANY = re.compile(r".*(apikey|api_key|api-key|x-api|authorization|bearer |project_id|secret).*")

def lint(kv):
    e = []
    def isint(k, lo, hi):
        try:
            return lo <= int(kv.get(k, "").strip()) <= hi
        except ValueError:
            return False
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,31}", kv.get("lesson|id", "")):
        e.append("lesson|id")
    for k, lo, hi in (("lesson|version", 1, 1000000), ("lesson|needs_reader", 1, 1000), ("coin|decimals", 0, 30), ("coin|display_decimals", 0, 18)):
        if not isint(k, lo, hi):
            e.append(k)
    if kv.get("lesson|tier") not in ("ana", "statia"):
        e.append("lesson|tier")
    if not kv.get("coin|name", "").strip():
        e.append("coin|name")
    if not re.fullmatch(r"[A-Z0-9]{1,10}", kv.get("coin|ticker", "")):
        e.append("coin|ticker")
    if not re.fullmatch(r"[a-z0-9-]{1,60}", kv.get("coin|price_id", "")):
        e.append("coin|price_id")
    forms = []
    for k in kv:
        m = re.fullmatch(r"address\|(form[0-9]+)\.kind", k)
        if m:
            n = m.group(1)
            forms.append((n, kv[k], kv.get("address|%s.pattern" % n, ""), kv.get("address|%s.hrp" % n, ""), kv.get("address|%s.versions" % n, "")))
    if not forms:
        e.append("address forms")
    for n, kind, pat, hrp, vers in forms:
        if kind not in ("base58check", "bech32", "hex_evm"):
            e.append("address|%s.kind" % n)
        try:
            re.compile(pat)
            if not pat:
                e.append("address|%s.pattern" % n)
        except re.error:
            e.append("address|%s.pattern" % n)
        if kind == "bech32" and not re.fullmatch(r"[a-z0-9]{1,20}", hrp):
            e.append("address|%s.hrp" % n)
        if kind == "base58check" and not re.fullmatch(r"[0-9]{1,3}(,[0-9]{1,3})*", vers):
            e.append("address|%s.versions" % n)
    rd = kv.get("reader|name")
    if rd not in ("esplora", "evm", "json"):
        e.append("reader|name")
    servers = [k for k in kv if k.startswith("server|")]
    if not servers:
        e.append("server|1")
    for k in servers:
        u = kv[k]
        if not re.fullmatch(r"[0-9]{1,2}", k[7:]):
            e.append(k)
        if not re.fullmatch(r"https://[^/\s@?#]+(/\S*)?", u):
            e.append(k + " (https only)")
        if SECRET_URL.fullmatch(u.lower()):
            e.append(k + " (looks like a key)")
    for k, v in kv.items():
        if not k.startswith("test|") and not k.startswith("permit|") and SECRET_ANY.fullmatch(v.lower()):
            e.append(k + " (looks like a secret)")
    if rd == "json":
        m = kv.get("param|method")
        if m not in ("GET", "POST"):
            e.append("param|method")
        if not kv.get("param|balance_path", "").strip():
            e.append("param|balance_path")
        if kv.get("param|balance_type") not in ("number", "text_integer"):
            e.append("param|balance_type")
        if m == "POST" and "{address}" not in kv.get("param|body", ""):
            e.append("param|body")
        if m == "GET":
            for k in servers:
                if "{address}" not in kv[k]:
                    e.append(k + " ({address})")
    if rd == "evm" and not isint("param|chain_id", 1, 2147483647):
        e.append("param|chain_id")
    good = [k for k in kv if k.startswith("test|good.")]
    bad = [k for k in kv if k.startswith("test|bad.")]
    any_ok = lambda a: any(addr_ok(f[1], f[2], f[3], f[4], a) for f in forms)
    for k in good:
        if not any_ok(kv[k]):
            e.append(k)
    for k in bad:
        if any_ok(kv[k]):
            e.append(k)
    if not good:
        e.append("test|good.1")
    if not bad:
        e.append("test|bad.1")
    return e

# ------------------------------------------------------------------ the phone
class Phone:
    def __init__(self, build, trusted_raw):
        self.build = build                       # {"reader": 1, "tier": "ana"|"statia", "hives": [...]}
        self.trusted = {key_id(r): r for r in trusted_raw}
        self.seq, self.head = 0, "0" * 64
        self.chain = {}                          # seq -> body hash
        self.revoked, self.frozen = set(), set()
        self.permits = {}                        # licensee key id -> permit kv (+ "_signer")
        self.lessons = {}                        # id -> (version, body hash)

    def check(self, f, sc, commit=True):
        """-> (verdict, detail). Follows SPEC.md section 8 step by step."""
        # 1 sidecar
        want = None
        if sc is not None:
            first = sc.decode("utf-8", "replace").split("\n")[0].strip().lower()
            if re.fullmatch(r"[0-9a-f]{64}", first):
                want = first
        if want is None or want != hashlib.sha256(f).hexdigest():
            return "BAD_SIDECAR", ""
        return self._check_bytes(f, commit)

    def _parse_signed(self, f):
        cls, rows, body = parse(f)
        if len(rows) < 3 or rows[-2][:2] != ("sig", "key_id") or rows[-1][:2] != ("sig", "value"):
            raise Bad("sig rows")
        kid, sighex = rows[-2][2], rows[-1][2]
        if not re.fullmatch(r"[0-9a-f]{64}", kid) or not re.fullmatch(r"[0-9a-f]{128}", sighex):
            raise Bad("sig hex")
        if any(r[0] not in SECTIONS and r[0] not in ("chain", "revoke") for r in rows):
            raise Bad("section")
        kv = {}
        for r in rows[:-2]:
            k = r[0] + "|" + r[1]
            if k in kv:
                raise Bad("duplicate row")
            kv[k] = r[2]
        return cls, kv, body, kid, bytes.fromhex(sighex)

    def _check_bytes(self, f, commit):
        # 2 format
        try:
            cls, kv, body, kid, sig = self._parse_signed(f)
        except (Bad, ValueError, struct.error):
            return "BAD_FORMAT", ""
        if cls not in (CLASS_LESSON, CLASS_PERMIT, CLASS_REVOKE):
            return "BAD_FORMAT", "class"
        # 3 high-S
        if int.from_bytes(sig[32:], "big") > N // 2:
            return "HIGH_S", ""
        msg = signed_message(cls, body)
        bh = hashlib.sha256(body).hexdigest()
        if cls in (CLASS_PERMIT, CLASS_REVOKE):
            # 4 signer: root or spare only
            if kid not in self.trusted:
                return "UNKNOWN_KEY", ""
            # 5
            if kid in self.frozen:
                return "FROZEN", ""
            if kid in self.revoked:
                return "REVOKED", ""
            # 6
            if not verify_raw(self.trusted[kid], msg, sig):
                return "BAD_SIGNATURE", ""
            return self._chain(cls, kv, bh, kid, commit)
        # lesson: 4 signer
        permit = None
        if kid in self.trusted:
            raw = self.trusted[kid]
        else:
            pf = kv.get("permit|file")
            if pf is None:
                return "UNKNOWN_KEY", ""
            try:
                pbytes = base64.b64decode(pf, validate=True)
                pcls, pkv, pbody, pkid, psig = self._parse_signed(pbytes)
            except Exception:
                return "BAD_FORMAT", "permit"
            if pcls != CLASS_PERMIT or int.from_bytes(psig[32:], "big") > N // 2:
                return "BAD_FORMAT", "permit"
            if pkid not in self.trusted or not verify_raw(self.trusted[pkid], signed_message(CLASS_PERMIT, pbody), psig):
                return "UNKNOWN_KEY", "permit"
            try:
                praw = bytes.fromhex(pkv.get("permit|key", ""))
            except ValueError:
                return "BAD_FORMAT", "permit key"
            if key_id(praw) != kid:
                return "UNKNOWN_KEY", "permit is for another key"
            permit, raw = (pkv, pkid), praw
        # 5
        if kid in self.revoked or (permit and permit[1] in self.revoked):
            return "REVOKED", ""
        # 6
        if not verify_raw(raw, msg, sig):
            return "BAD_SIGNATURE", ""
        # 8 lesson content
        try:
            need = int(kv.get("lesson|needs_reader", ""))
        except ValueError:
            return "BAD_RULES", "lesson|needs_reader"
        hive = kv.get("lesson|hive", "")
        if need > self.build["reader"]:
            return "UPDATE_FIRST", "needs reader %d" % need
        if hive not in HIVES_DEFINED.get(self.build["reader"], []):
            return ("UPDATE_FIRST", "hive " + hive) if hive in HIVES_ALL else ("BAD_RULES", "lesson|hive")
        tier = kv.get("lesson|tier", "")
        if permit:
            pkv = permit[0]
            try:
                until = int(pkv.get("permit|until_seq", "0"))
            except ValueError:
                until = 0
            if self.seq >= until:
                return "EXPIRED", ""
            tick = kv.get("coin|ticker", "")
            tl = [x.strip() for x in pkv.get("permit|tickers", "").split(",")]
            if tier not in [x.strip() for x in pkv.get("permit|tiers", "").split(",")] \
               or hive not in [x.strip() for x in pkv.get("permit|hives", "").split(",")] \
               or ("*" not in tl and tick not in tl):
                return "NOT_PERMITTED", ""
        if hive not in self.build["hives"]:
            return "WRONG_HIVE", ""
        if tier == "statia" and self.build["tier"] != "statia":
            return "WRONG_TIER", ""
        lid = kv.get("lesson|id", "")
        try:
            ver = int(kv.get("lesson|version", ""))
        except ValueError:
            return "BAD_RULES", "lesson|version"
        if lid in self.lessons:
            iv, ih = self.lessons[lid]
            if ver < iv:
                return "OLDER", ""
            if ver == iv:
                return ("DUPLICATE", "") if ih == bh else ("FORK", "")
        errs = lint(kv)
        if errs:
            return "BAD_RULES", ", ".join(errs)
        if commit:
            self.lessons[lid] = (ver, bh)
        return "ACCEPT", ""

    def _chain(self, cls, kv, bh, kid, commit):
        try:
            seq = int(kv.get("chain|seq", ""))
            prev = kv["chain|prev"]
        except (ValueError, KeyError):
            return "BAD_FORMAT", "chain rows"
        if seq < 1 or not re.fullmatch(r"[0-9a-f]{64}", prev):
            return "BAD_FORMAT", "chain rows"
        if seq in self.chain:
            if self.chain[seq] == bh:
                return "DUPLICATE", ""
            if commit:
                self.frozen |= set(self.trusted)
            return "FORK", ""
        if seq > self.seq + 1:
            return "HOLE", "have %d" % self.seq
        if prev != self.head:
            if commit:
                self.frozen |= set(self.trusted)
            return "FORK", "prev"
        if cls == CLASS_PERMIT:
            try:
                praw = bytes.fromhex(kv.get("permit|key", ""))
                int(kv.get("permit|until_seq", ""))
            except ValueError:
                return "BAD_FORMAT", "permit rows"
            if len(praw) != 65 or praw[0] != 4:
                return "BAD_FORMAT", "permit key"
            if commit:
                self.permits[key_id(praw)] = kv
        else:
            ks = [x.strip() for x in kv.get("revoke|keys", "").split(",") if x.strip()]
            if not ks or any(not re.fullmatch(r"[0-9a-f]{64}", x) for x in ks):
                return "BAD_FORMAT", "revoke rows"
            if commit:
                self.revoked |= set(ks)
        if commit:
            self.chain[seq] = bh
            self.seq, self.head = seq, bh
        return "ACCEPT", ""
