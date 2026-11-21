package com.novera.ana;

import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/* loaded from: classes.dex */
public class AnaRule {
    public static final int CLASS_LESSON = 30;
    public static final int CLASS_PERMIT = 31;
    public static final int CLASS_REVOKE = 32;
    public static final String[] HIVES_ALL = {"watch", "efinote", "clipnote", "pacenote", "hivenote", "flex"};
    public static final String[] HIVES_LEVEL1 = {"watch"};
    final List<String> hives;
    public Signed last;
    final int reader;
    final String tier;
    final Engine E = new Engine();
    final LinkedHashMap<String, byte[]> trusted = new LinkedHashMap<>();
    int seq = 0;
    String head = zeros64();
    final HashMap<Integer, String> chain = new HashMap<>();
    final HashSet<String> revoked = new HashSet<>();
    final HashSet<String> frozen = new HashSet<>();
    final HashMap<String, String> lessonVer = new HashMap<>();
    final HashMap<String, String> lessonHash = new HashMap<>();

    public AnaRule(int i, String str, List<String> list, List<String> list2) {
        this.reader = i;
        this.tier = str;
        this.hives = list;
        for (int i2 = 0; i2 < list2.size(); i2++) {
            byte[] fromHex = this.E.fromHex(list2.get(i2));
            LinkedHashMap<String, byte[]> linkedHashMap = this.trusted;
            Engine engine = this.E;
            linkedHashMap.put(engine.toHex(engine.sha256(fromHex)), fromHex);
        }
    }

    static String zeros64() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 64; i++) {
            sb.append('0');
        }
        return sb.toString();
    }

    static class Bad extends Exception {
        Bad(String str) {
            super(str);
        }
    }

    static class Signed {
        byte[] body;
        int cls;
        String keyId;
        LinkedHashMap<String, String> kv = new LinkedHashMap<>();
        byte[] sig;

        Signed() {
        }
    }

    int u32(byte[] bArr, int[] iArr) throws Bad {
        int i = iArr[0];
        if (i + 4 > bArr.length) {
            throw new Bad("short");
        }
        int i2 = (bArr[i + 3] & 255) | ((bArr[i] & 255) << 24) | ((bArr[i + 1] & 255) << 16) | ((bArr[i + 2] & 255) << 8);
        iArr[0] = i + 4;
        return i2;
    }

    String str(byte[] bArr, int[] iArr) throws Bad {
        int u32 = u32(bArr, iArr);
        if (u32 < 0 || u32 > 16777216 || iArr[0] + u32 > bArr.length) {
            throw new Bad("bad string");
        }
        try {
            String charBuffer = Charset.forName("UTF-8").newDecoder().decode(ByteBuffer.wrap(bArr, iArr[0], u32)).toString();
            iArr[0] = iArr[0] + u32;
            return charBuffer;
        } catch (Exception unused) {
            throw new Bad("bad utf-8");
        }
    }

    Signed parseSigned(byte[] bArr) throws Bad {
        if (bArr == null || bArr.length < 20) {
            throw new Bad("too small");
        }
        long j = 0;
        for (int i = 0; i < 8; i++) {
            j = (j << 8) | (bArr[(bArr.length - 8) + i] & 255);
        }
        long length = (bArr.length - 8) - j;
        if (j < 12 || length < 0) {
            throw new Bad("no trailer");
        }
        byte[] copyOfRange = Arrays.copyOfRange(bArr, (int) length, bArr.length - 8);
        if (copyOfRange[0] != 80 || copyOfRange[1] != 77 || copyOfRange[2] != 83 || copyOfRange[3] != 72) {
            throw new Bad("magic");
        }
        int[] iArr = {4};
        if (u32(copyOfRange, iArr) != 1 || u32(copyOfRange, iArr) != 1) {
            throw new Bad("version or parts");
        }
        Signed signed = new Signed();
        signed.cls = u32(copyOfRange, iArr);
        if (u32(copyOfRange, iArr) != 3 || !str(copyOfRange, iArr).equals("section") || !str(copyOfRange, iArr).equals("key") || !str(copyOfRange, iArr).equals("value")) {
            throw new Bad("columns");
        }
        int u32 = u32(copyOfRange, iArr);
        if (u32 < 3 || u32 > 100000) {
            throw new Bad("rows");
        }
        String[][] strArr = new String[u32][];
        int i2 = 0;
        for (int i3 = 0; i3 < u32; i3++) {
            if (i3 == u32 - 1) {
                i2 = iArr[0];
            }
            strArr[i3] = new String[]{str(copyOfRange, iArr), str(copyOfRange, iArr), str(copyOfRange, iArr)};
        }
        if (iArr[0] != copyOfRange.length) {
            throw new Bad("extra bytes");
        }
        int i4 = u32 - 2;
        String[] strArr2 = strArr[i4];
        String[] strArr3 = strArr[u32 - 1];
        if (!strArr2[0].equals("sig") || !strArr2[1].equals("key_id") || !strArr3[0].equals("sig") || !strArr3[1].equals("value")) {
            throw new Bad("sig rows");
        }
        if (!strArr2[2].matches("[0-9a-f]{64}") || !strArr3[2].matches("[0-9a-f]{128}")) {
            throw new Bad("sig hex");
        }
        for (int i5 = 0; i5 < i4; i5++) {
            if ("|lesson|coin|address|reader|server|param|test|permit|chain|revoke|".indexOf("|" + strArr[i5][0] + "|") < 0) {
                throw new Bad("section " + strArr[i5][0]);
            }
            String[] strArr4 = strArr[i5];
            String str = strArr4[0] + "|" + strArr4[1];
            if (signed.kv.containsKey(str)) {
                throw new Bad("duplicate row " + str);
            }
            signed.kv.put(str, strArr[i5][2]);
        }
        signed.body = Arrays.copyOfRange(copyOfRange, 0, i2);
        signed.keyId = strArr2[2];
        signed.sig = this.E.fromHex(strArr3[2]);
        return signed;
    }

    byte[] message(int i, byte[] bArr) {
        Engine engine = this.E;
        return engine.cat(engine.utf8("ANA-PMSH1|" + i + "|"), this.E.sha256(bArr));
    }

    boolean highS(byte[] bArr) {
        return new BigInteger(1, Arrays.copyOfRange(bArr, 32, 64)).compareTo(this.E.N.shiftRight(1)) > 0;
    }

    boolean verify(byte[] bArr, byte[] bArr2, byte[] bArr3) {
        if (bArr == null || bArr.length != 65 || bArr[0] != 4 || bArr3.length != 64 || highS(bArr3)) {
            return false;
        }
        byte[] derInt = this.E.derInt(new BigInteger(1, Arrays.copyOfRange(bArr3, 0, 32)));
        byte[] derInt2 = this.E.derInt(new BigInteger(1, Arrays.copyOfRange(bArr3, 32, 64)));
        byte[] bArr4 = new byte[derInt.length + 2 + derInt2.length];
        bArr4[0] = 48;
        bArr4[1] = (byte) (derInt.length + derInt2.length);
        System.arraycopy(derInt, 0, bArr4, 2, derInt.length);
        System.arraycopy(derInt2, 0, bArr4, derInt.length + 2, derInt2.length);
        Engine engine = this.E;
        Objects.requireNonNull(engine);
        return engine.verifyMsg(engine.cat(engine.fromHex("3059301306072a8648ce3d020106082a8648ce3d030107034200"), bArr), bArr2, bArr4);
    }

    public String[] check(byte[] bArr, byte[] bArr2) {
        Signed signed = null;
        this.last = null;
        String sidecarHash = bArr2 == null ? null : this.E.sidecarHash(bArr2);
        if (sidecarHash == null || !sidecarHash.equals(this.E.sha256hex(bArr))) {
            return v("BAD_SIDECAR", "");
        }
        try {
            Signed parseSigned = parseSigned(bArr);
            if (parseSigned.cls != 30 && parseSigned.cls != 31 && parseSigned.cls != 32) {
                return v("BAD_FORMAT", "class");
            }
            if (highS(parseSigned.sig)) {
                return v("HIGH_S", "");
            }
            byte[] message = message(parseSigned.cls, parseSigned.body);
            String sha256hex = this.E.sha256hex(parseSigned.body);
            if (parseSigned.cls != 30) {
                if (!this.trusted.containsKey(parseSigned.keyId)) {
                    return v("UNKNOWN_KEY", "");
                }
                if (this.frozen.contains(parseSigned.keyId)) {
                    return v("FROZEN", "");
                }
                if (this.revoked.contains(parseSigned.keyId)) {
                    return v("REVOKED", "");
                }
                if (!verify(this.trusted.get(parseSigned.keyId), message, parseSigned.sig)) {
                    return v("BAD_SIGNATURE", "");
                }
                return chainStep(parseSigned, sha256hex);
            }
            byte[] bArr3 = this.trusted.get(parseSigned.keyId);
            if (bArr3 == null) {
                String str = parseSigned.kv.get("permit|file");
                if (str == null) {
                    return v("UNKNOWN_KEY", "");
                }
                try {
                    signed = parseSigned(this.E.b64dec(str));
                    if (signed.cls != 31 || highS(signed.sig)) {
                        return v("BAD_FORMAT", "permit");
                    }
                    byte[] bArr4 = this.trusted.get(signed.keyId);
                    if (bArr4 == null || !verify(bArr4, message(31, signed.body), signed.sig)) {
                        return v("UNKNOWN_KEY", "permit");
                    }
                    String str2 = signed.kv.get("permit|key");
                    if (str2 == null || !str2.matches("[0-9a-f]{130}")) {
                        return v("BAD_FORMAT", "permit key");
                    }
                    bArr3 = this.E.fromHex(str2);
                    Engine engine = this.E;
                    if (!engine.toHex(engine.sha256(bArr3)).equals(parseSigned.keyId)) {
                        return v("UNKNOWN_KEY", "permit is for another key");
                    }
                } catch (Exception unused) {
                    return v("BAD_FORMAT", "permit");
                }
            }
            if (this.revoked.contains(parseSigned.keyId) || (signed != null && this.revoked.contains(signed.keyId))) {
                return v("REVOKED", "");
            }
            if (!verify(bArr3, message, parseSigned.sig)) {
                return v("BAD_SIGNATURE", "");
            }
            int intOr = intOr(parseSigned.kv.get("lesson|needs_reader"), -1);
            if (intOr < 1) {
                return v("BAD_RULES", "lesson|needs_reader");
            }
            String nz = nz(parseSigned.kv.get("lesson|hive"));
            if (intOr > this.reader) {
                return v("UPDATE_FIRST", "needs reader " + intOr);
            }
            if (!in(nz, HIVES_LEVEL1)) {
                if (!in(nz, HIVES_ALL)) {
                    return v("BAD_RULES", "lesson|hive");
                }
                return v("UPDATE_FIRST", "hive " + nz);
            }
            String nz2 = nz(parseSigned.kv.get("lesson|tier"));
            if (signed != null) {
                if (this.seq >= intOr(signed.kv.get("permit|until_seq"), 0)) {
                    return v("EXPIRED", "");
                }
                String nz3 = nz(parseSigned.kv.get("coin|ticker"));
                List<String> list = list(signed.kv.get("permit|tickers"));
                if (!list(signed.kv.get("permit|tiers")).contains(nz2) || !list(signed.kv.get("permit|hives")).contains(nz) || (!list.contains("*") && !list.contains(nz3))) {
                    return v("NOT_PERMITTED", "");
                }
            }
            if (!this.hives.contains(nz)) {
                return v("WRONG_HIVE", "");
            }
            if (nz2.equals("statia") && !this.tier.equals("statia")) {
                return v("WRONG_TIER", "");
            }
            String nz4 = nz(parseSigned.kv.get("lesson|id"));
            int intOr2 = intOr(parseSigned.kv.get("lesson|version"), -1);
            if (intOr2 < 1) {
                return v("BAD_RULES", "lesson|version");
            }
            if (this.lessonVer.containsKey(nz4)) {
                int parseInt = Integer.parseInt(this.lessonVer.get(nz4));
                if (intOr2 < parseInt) {
                    return v("OLDER", "");
                }
                if (intOr2 == parseInt) {
                    return v(this.lessonHash.get(nz4).equals(sha256hex) ? "DUPLICATE" : "FORK", "");
                }
            }
            ArrayList<String> lintLesson = lintLesson(parseSigned.kv);
            if (!lintLesson.isEmpty()) {
                return v("BAD_RULES", lintLesson.toString());
            }
            HashMap<String, String> hashMap = this.lessonVer;
            StringBuilder sb = new StringBuilder();
            sb.append(intOr2);
            hashMap.put(nz4, sb.toString());
            this.lessonHash.put(nz4, sha256hex);
            this.last = parseSigned;
            return v("ACCEPT", "");
        } catch (Bad e) {
            return v("BAD_FORMAT", e.getMessage());
        }
    }

    String[] chainStep(Signed signed, String str) {
        int intOr = intOr(signed.kv.get("chain|seq"), -1);
        String str2 = signed.kv.get("chain|prev");
        if (intOr < 1 || str2 == null || !str2.matches("[0-9a-f]{64}")) {
            return v("BAD_FORMAT", "chain rows");
        }
        if (this.chain.containsKey(Integer.valueOf(intOr))) {
            if (this.chain.get(Integer.valueOf(intOr)).equals(str)) {
                return v("DUPLICATE", "");
            }
            this.frozen.addAll(this.trusted.keySet());
            return v("FORK", "");
        }
        int i = this.seq;
        if (intOr > i + 1) {
            return v("HOLE", "have " + i);
        }
        if (!str2.equals(this.head)) {
            this.frozen.addAll(this.trusted.keySet());
            return v("FORK", "prev");
        }
        if (signed.cls == 31) {
            String str3 = signed.kv.get("permit|key");
            if (str3 == null || !str3.matches("04[0-9a-f]{128}") || intOr(signed.kv.get("permit|until_seq"), -1) < 0) {
                return v("BAD_FORMAT", "permit rows");
            }
        } else {
            List<String> list = list(signed.kv.get("revoke|keys"));
            if (list.isEmpty()) {
                return v("BAD_FORMAT", "revoke rows");
            }
            for (int i2 = 0; i2 < list.size(); i2++) {
                if (!list.get(i2).matches("[0-9a-f]{64}")) {
                    return v("BAD_FORMAT", "revoke rows");
                }
            }
            this.revoked.addAll(list);
        }
        this.chain.put(Integer.valueOf(intOr), str);
        this.seq = intOr;
        this.head = str;
        this.last = signed;
        return v("ACCEPT", "");
    }

    ArrayList<String> lintLesson(LinkedHashMap<String, String> linkedHashMap) {
        LinkedHashMap<String, String> linkedHashMap2 = new LinkedHashMap<>();
        for (Map.Entry<String, String> entry : linkedHashMap.entrySet()) {
            String key = entry.getKey();
            if (!key.startsWith("permit|") && !key.equals("lesson|hive") && !key.equals("lesson|tier")) {
                linkedHashMap2.put(key.replaceFirst("\\|", "/"), entry.getValue());
            }
        }
        ArrayList<String> lint = this.E.lint(linkedHashMap2, false);
        String nz = nz(linkedHashMap.get("lesson|tier"));
        if (!nz.equals("ana") && !nz.equals("statia")) {
            lint.add("lesson|tier: ana or statia");
        }
        return lint;
    }

    static String[] v(String str, String str2) {
        return new String[]{str, str2};
    }

    static String nz(String str) {
        return str == null ? "" : str;
    }

    static boolean in(String str, String[] strArr) {
        for (String str2 : strArr) {
            if (str2.equals(str)) {
                return true;
            }
        }
        return false;
    }

    static int intOr(String str, int i) {
        try {
            return Integer.parseInt(str.trim());
        } catch (Exception unused) {
            return i;
        }
    }

    static List<String> list(String str) {
        ArrayList arrayList = new ArrayList();
        if (str == null) {
            return arrayList;
        }
        String[] split = str.split(",");
        for (int i = 0; i < split.length; i++) {
            if (split[i].trim().length() > 0) {
                arrayList.add(split[i].trim());
            }
        }
        return arrayList;
    }
}
