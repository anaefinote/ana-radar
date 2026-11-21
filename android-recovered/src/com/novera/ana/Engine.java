package com.novera.ana;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.lang.reflect.Array;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.RoundingMode;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/* loaded from: classes.dex */
public class Engine {
    final int CLASS_LESSON = 30;
    final String B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    final String B32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    final String[] KNOWN_IDS = {"bitcoin", "litecoin", "ethereum", "cardano"};
    String coingeckoBase = "https://api.coingecko.com/api/v3";
    final BigInteger P = new BigInteger("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16);
    final BigInteger N = new BigInteger("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16);
    final BigInteger CB = new BigInteger("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16);
    final BigInteger GX = new BigInteger("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296", 16);
    final BigInteger GY = new BigInteger("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5", 16);
    final String SPKI_PREFIX = "3059301306072a8648ce3d020106082a8648ce3d030107034200";
    String[] SECTIONS = {"lesson", "coin", "address", "reader", "server", "param", "test"};

    public String toHex(byte[] bArr) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bArr) {
            sb.append("0123456789abcdef".charAt((b & 255) >> 4));
            sb.append("0123456789abcdef".charAt(b & 15));
        }
        return sb.toString();
    }

    public byte[] fromHex(String str) {
        String trim = str.trim();
        if (trim.length() % 2 != 0) {
            throw new IllegalArgumentException("odd-length hex");
        }
        int length = trim.length() / 2;
        byte[] bArr = new byte[length];
        for (int i = 0; i < length; i++) {
            int i2 = i * 2;
            int digit = Character.digit(trim.charAt(i2), 16);
            int digit2 = Character.digit(trim.charAt(i2 + 1), 16);
            if (digit < 0 || digit2 < 0) {
                throw new IllegalArgumentException("bad hex");
            }
            bArr[i] = (byte) ((digit * 16) + digit2);
        }
        return bArr;
    }

    byte[] utf8(String str) {
        try {
            return str.getBytes("UTF-8");
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    String fromUtf8(byte[] bArr) {
        try {
            return new String(bArr, "UTF-8");
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public byte[] sha256(byte[] bArr) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(bArr);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    String sha256hex(byte[] bArr) {
        return toHex(sha256(bArr));
    }

    public byte[] cat(byte[] bArr, byte[] bArr2) {
        byte[] bArr3 = new byte[bArr.length + bArr2.length];
        System.arraycopy(bArr, 0, bArr3, 0, bArr.length);
        System.arraycopy(bArr2, 0, bArr3, bArr.length, bArr2.length);
        return bArr3;
    }

    public String b64enc(byte[] bArr) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < bArr.length; i += 3) {
            int i2 = i + 1;
            int i3 = i + 2;
            int i4 = ((bArr[i] & 255) << 16) | ((i2 < bArr.length ? bArr[i2] & 255 : 0) << 8) | (i3 < bArr.length ? bArr[i3] & 255 : 0);
            sb.append("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charAt((i4 >> 18) & 63));
            sb.append("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charAt((i4 >> 12) & 63));
            char c = '=';
            sb.append(i2 < bArr.length ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charAt((i4 >> 6) & 63) : '=');
            if (i3 < bArr.length) {
                c = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charAt(i4 & 63);
            }
            sb.append(c);
        }
        return sb.toString();
    }

    public byte[] b64dec(String str) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < str.length(); i++) {
            char charAt = str.charAt(i);
            if (charAt == '=' || "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(charAt) >= 0) {
                sb.append(charAt);
            }
        }
        String sb2 = sb.toString();
        while (sb2.length() > 0 && sb2.charAt(sb2.length() - 1) == '=') {
            sb2 = sb2.substring(0, sb2.length() - 1);
        }
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        int i2 = 0;
        int i3 = 0;
        for (int i4 = 0; i4 < sb2.length(); i4++) {
            i2 = (i2 << 6) | "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(sb2.charAt(i4));
            int i5 = i3 + 6;
            if (i5 >= 8) {
                i3 -= 2;
                byteArrayOutputStream.write((i2 >> i3) & 255);
            } else {
                i3 = i5;
            }
        }
        return byteArrayOutputStream.toByteArray();
    }

    public byte[] b58dec(String str) {
        BigInteger bigInteger = BigInteger.ZERO;
        BigInteger valueOf = BigInteger.valueOf(58L);
        for (int i = 0; i < str.length(); i++) {
            int indexOf = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".indexOf(str.charAt(i));
            if (indexOf < 0) {
                return null;
            }
            bigInteger = bigInteger.multiply(valueOf).add(BigInteger.valueOf(indexOf));
        }
        byte[] byteArray = bigInteger.signum() == 0 ? new byte[0] : bigInteger.toByteArray();
        if (byteArray.length > 1 && byteArray[0] == 0) {
            int length = byteArray.length - 1;
            byte[] bArr = new byte[length];
            System.arraycopy(byteArray, 1, bArr, 0, length);
            byteArray = bArr;
        }
        int i2 = 0;
        while (i2 < str.length() && str.charAt(i2) == '1') {
            i2++;
        }
        byte[] bArr2 = new byte[byteArray.length + i2];
        System.arraycopy(byteArray, 0, bArr2, i2, byteArray.length);
        return bArr2;
    }

    public String b58enc(byte[] bArr) {
        int i;
        BigInteger bigInteger = new BigInteger(1, bArr);
        BigInteger valueOf = BigInteger.valueOf(58L);
        StringBuilder sb = new StringBuilder();
        while (true) {
            if (bigInteger.signum() <= 0) {
                break;
            }
            BigInteger[] divideAndRemainder = bigInteger.divideAndRemainder(valueOf);
            sb.append("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".charAt(divideAndRemainder[1].intValue()));
            bigInteger = divideAndRemainder[0];
        }
        for (i = 0; i < bArr.length && bArr[i] == 0; i++) {
            sb.append('1');
        }
        return sb.reverse().toString();
    }

    public boolean b58checkOk(String str, String str2) {
        byte[] b58dec = b58dec(str);
        if (b58dec != null && b58dec.length == 25) {
            byte[] bArr = new byte[21];
            System.arraycopy(b58dec, 0, bArr, 0, 21);
            byte[] sha256 = sha256(sha256(bArr));
            for (int i = 0; i < 4; i++) {
                if (sha256[i] != b58dec[i + 21]) {
                    return false;
                }
            }
            for (String str3 : str2 == null ? new String[0] : str2.split(",")) {
                if (Integer.parseInt(str3.trim()) == (b58dec[0] & 255)) {
                    return true;
                }
            }
        }
        return false;
    }

    public int bech32Polymod(int[] iArr) {
        int[] iArr2 = {996825010, 642813549, 513874426, 1027748829, 705979059};
        int i = 1;
        for (int i2 : iArr) {
            int i3 = i >>> 25;
            i = ((i & 33554431) << 5) ^ i2;
            for (int i4 = 0; i4 < 5; i4++) {
                if (((i3 >> i4) & 1) != 0) {
                    i ^= iArr2[i4];
                }
            }
        }
        return i;
    }

    public int bech32Variant(String str, String str2) {
        int lastIndexOf;
        if (str != null && str.length() >= 8) {
            String lowerCase = str.toLowerCase();
            if ((str.equals(lowerCase) || str.equals(str.toUpperCase())) && (lastIndexOf = lowerCase.lastIndexOf(49)) >= 1 && lastIndexOf + 7 <= lowerCase.length()) {
                String substring = lowerCase.substring(0, lastIndexOf);
                if (str2 != null && str2.length() > 0 && !substring.equals(str2.toLowerCase())) {
                    return 0;
                }
                int[] iArr = new int[(substring.length() * 2) + 1 + ((lowerCase.length() - lastIndexOf) - 1)];
                int i = 0;
                int i2 = 0;
                while (i < substring.length()) {
                    char charAt = substring.charAt(i);
                    if (charAt < '!' || charAt > '~') {
                        return 0;
                    }
                    iArr[i2] = charAt >> 5;
                    i++;
                    i2++;
                }
                int i3 = i2 + 1;
                iArr[i2] = 0;
                int i4 = 0;
                while (i4 < substring.length()) {
                    iArr[i3] = substring.charAt(i4) & 31;
                    i4++;
                    i3++;
                }
                int i5 = lastIndexOf + 1;
                while (i5 < lowerCase.length()) {
                    int indexOf = "qpzry9x8gf2tvdw0s3jn54khce6mua7l".indexOf(lowerCase.charAt(i5));
                    if (indexOf < 0) {
                        return 0;
                    }
                    iArr[i3] = indexOf;
                    i5++;
                    i3++;
                }
                int bech32Polymod = bech32Polymod(iArr);
                if (bech32Polymod == 1) {
                    return 1;
                }
                if (bech32Polymod == 734539939) {
                    return 2;
                }
            }
        }
        return 0;
    }

    /* JADX WARN: Code restructure failed: missing block: B:25:0x0018, code lost:
    
        if (java.util.regex.Pattern.compile(r4).matcher(r7).matches() == false) goto L10;
     */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    public boolean addrOk(java.lang.String r3, java.lang.String r4, java.lang.String r5, java.lang.String r6, java.lang.String r7) {
        /*
            r2 = this;
            r0 = 0
            if (r7 != 0) goto L4
            return r0
        L4:
            if (r4 == 0) goto L1b
            int r1 = r4.length()     // Catch: java.lang.Exception -> L1a
            if (r1 <= 0) goto L1b
            java.util.regex.Pattern r4 = java.util.regex.Pattern.compile(r4)     // Catch: java.lang.Exception -> L1a
            java.util.regex.Matcher r4 = r4.matcher(r7)     // Catch: java.lang.Exception -> L1a
            boolean r4 = r4.matches()     // Catch: java.lang.Exception -> L1a
            if (r4 != 0) goto L1b
        L1a:
            return r0
        L1b:
            java.lang.String r4 = "hex_evm"
            boolean r4 = r4.equals(r3)
            if (r4 == 0) goto L2a
            java.lang.String r3 = "0x[0-9a-fA-F]{40}"
            boolean r3 = r7.matches(r3)
            return r3
        L2a:
            java.lang.String r4 = "base58check"
            boolean r4 = r4.equals(r3)
            if (r4 == 0) goto L37
            boolean r3 = r2.b58checkOk(r7, r6)
            return r3
        L37:
            java.lang.String r4 = "bech32"
            boolean r3 = r4.equals(r3)
            if (r3 == 0) goto L46
            int r3 = r2.bech32Variant(r7, r5)
            if (r3 == 0) goto L46
            r0 = 1
        L46:
            return r0
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.Engine.addrOk(java.lang.String, java.lang.String, java.lang.String, java.lang.String, java.lang.String):boolean");
    }

    /* JADX WARN: Multi-variable type inference failed */
    public BigInteger[] padd(BigInteger[] bigIntegerArr, BigInteger[] bigIntegerArr2) {
        BigInteger mod;
        if (bigIntegerArr == null) {
            return bigIntegerArr2;
        }
        if (bigIntegerArr2 == 0) {
            return bigIntegerArr;
        }
        if (bigIntegerArr[0].equals(bigIntegerArr2[0])) {
            if (!bigIntegerArr[1].equals(bigIntegerArr2[1]) || bigIntegerArr[1].signum() == 0) {
                return null;
            }
            BigInteger valueOf = BigInteger.valueOf(3L);
            BigInteger bigInteger = bigIntegerArr[0];
            mod = bigInteger.multiply(bigInteger).multiply(valueOf).subtract(valueOf).multiply(bigIntegerArr[1].shiftLeft(1).modInverse(this.P)).mod(this.P);
        } else {
            mod = bigIntegerArr2[1].subtract(bigIntegerArr[1]).multiply(bigIntegerArr2[0].subtract(bigIntegerArr[0]).mod(this.P).modInverse(this.P)).mod(this.P);
        }
        BigInteger mod2 = mod.multiply(mod).subtract(bigIntegerArr[0]).subtract(bigIntegerArr2[0]).mod(this.P);
        return new BigInteger[]{mod2, mod.multiply(bigIntegerArr[0].subtract(mod2)).subtract(bigIntegerArr[1]).mod(this.P)};
    }

    public BigInteger[] pmul(BigInteger bigInteger, BigInteger[] bigIntegerArr) {
        BigInteger[] bigIntegerArr2 = null;
        for (int bitLength = bigInteger.bitLength() - 1; bitLength >= 0; bitLength--) {
            bigIntegerArr2 = padd(bigIntegerArr2, bigIntegerArr2);
            if (bigInteger.testBit(bitLength)) {
                bigIntegerArr2 = padd(bigIntegerArr2, bigIntegerArr);
            }
        }
        return bigIntegerArr2;
    }

    BigInteger[] gpoint() {
        return new BigInteger[]{this.GX, this.GY};
    }

    public boolean onCurve(BigInteger[] bigIntegerArr) {
        if (bigIntegerArr == null) {
            return false;
        }
        BigInteger bigInteger = bigIntegerArr[1];
        BigInteger mod = bigInteger.multiply(bigInteger).mod(this.P);
        BigInteger bigInteger2 = bigIntegerArr[0];
        return mod.equals(bigInteger2.multiply(bigInteger2).multiply(bigIntegerArr[0]).subtract(bigIntegerArr[0].multiply(BigInteger.valueOf(3L))).add(this.CB).mod(this.P));
    }

    public byte[] i2o(BigInteger bigInteger) {
        byte[] byteArray = bigInteger.toByteArray();
        byte[] bArr = new byte[32];
        int min = Math.min(byteArray.length, 32);
        System.arraycopy(byteArray, byteArray.length - min, bArr, 32 - min, min);
        return bArr;
    }

    public byte[] hmac(byte[] bArr, byte[] bArr2) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(bArr, "HmacSHA256"));
            return mac.doFinal(bArr2);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public BigInteger rfc6979k(BigInteger bigInteger, byte[] bArr) {
        byte[] i2o = i2o(bigInteger);
        byte[] i2o2 = i2o(new BigInteger(1, bArr).mod(this.N));
        byte[] bArr2 = new byte[32];
        for (int i = 0; i < 32; i++) {
            bArr2[i] = 1;
        }
        byte[] hmac = hmac(new byte[32], cat(cat(cat(bArr2, new byte[]{0}), i2o), i2o2));
        byte[] hmac2 = hmac(hmac, bArr2);
        byte[] hmac3 = hmac(hmac, cat(cat(cat(hmac2, new byte[]{1}), i2o), i2o2));
        byte[] hmac4 = hmac(hmac3, hmac2);
        while (true) {
            byte[] hmac5 = hmac(hmac3, hmac4);
            BigInteger bigInteger2 = new BigInteger(1, hmac5);
            if (bigInteger2.signum() > 0 && bigInteger2.compareTo(this.N) < 0) {
                return bigInteger2;
            }
            hmac3 = hmac(hmac3, cat(hmac5, new byte[]{0}));
            hmac4 = hmac(hmac3, hmac5);
        }
    }

    public byte[] derInt(BigInteger bigInteger) {
        byte[] byteArray = bigInteger.toByteArray();
        byte[] bArr = new byte[byteArray.length + 2];
        bArr[0] = 2;
        bArr[1] = (byte) byteArray.length;
        System.arraycopy(byteArray, 0, bArr, 2, byteArray.length);
        return bArr;
    }

    public byte[] signMsg(BigInteger bigInteger, byte[] bArr) {
        byte[] sha256 = sha256(bArr);
        BigInteger bigInteger2 = new BigInteger(1, sha256);
        BigInteger rfc6979k = rfc6979k(bigInteger, sha256);
        BigInteger mod = pmul(rfc6979k, gpoint())[0].mod(this.N);
        BigInteger mod2 = rfc6979k.modInverse(this.N).multiply(bigInteger2.add(mod.multiply(bigInteger))).mod(this.N);
        if (mod.signum() == 0 || mod2.signum() == 0) {
            throw new RuntimeException("signing failed, try again");
        }
        byte[] derInt = derInt(mod);
        byte[] derInt2 = derInt(mod2);
        byte[] bArr2 = new byte[derInt.length + 2 + derInt2.length];
        bArr2[0] = 48;
        bArr2[1] = (byte) (derInt.length + derInt2.length);
        System.arraycopy(derInt, 0, bArr2, 2, derInt.length);
        System.arraycopy(derInt2, 0, bArr2, derInt.length + 2, derInt2.length);
        return bArr2;
    }

    public BigInteger[] parseDer(byte[] bArr) {
        try {
            if (bArr.length < 8 || bArr[0] != 48 || (bArr[1] & 255) != bArr.length - 2 || bArr[2] != 2) {
                return null;
            }
            int i = bArr[3] & 255;
            BigInteger bigInteger = new BigInteger(1, Arrays.copyOfRange(bArr, 4, 4 + i));
            if (bArr[i + 4] != 2) {
                return null;
            }
            int i2 = bArr[i + 5] & 255;
            int i3 = i + 6;
            int i4 = i2 + i3;
            if (i4 != bArr.length) {
                return null;
            }
            return new BigInteger[]{bigInteger, new BigInteger(1, Arrays.copyOfRange(bArr, i3, i4))};
        } catch (Exception unused) {
        }
        return null;
    }

    public boolean verifyMsg(byte[] bArr, byte[] bArr2, byte[] bArr3) {
        BigInteger[] parseDer;
        if (bArr == null) {
            return false;
        }
        try {
            if (bArr.length != 91) {
                return false;
            }
            byte[] fromHex = fromHex("3059301306072a8648ce3d020106082a8648ce3d030107034200");
            for (int i = 0; i < fromHex.length; i++) {
                if (bArr[i] != fromHex[i]) {
                    return false;
                }
            }
            if (bArr[26] != 4) {
                return false;
            }
            BigInteger[] bigIntegerArr = {new BigInteger(1, Arrays.copyOfRange(bArr, 27, 59)), new BigInteger(1, Arrays.copyOfRange(bArr, 59, 91))};
            if (!onCurve(bigIntegerArr) || (parseDer = parseDer(bArr3)) == null) {
                return false;
            }
            BigInteger bigInteger = parseDer[0];
            BigInteger bigInteger2 = parseDer[1];
            if (bigInteger.signum() > 0 && bigInteger2.signum() > 0 && bigInteger.compareTo(this.N) < 0 && bigInteger2.compareTo(this.N) < 0) {
                BigInteger bigInteger3 = new BigInteger(1, sha256(bArr2));
                BigInteger modInverse = bigInteger2.modInverse(this.N);
                BigInteger[] padd = padd(pmul(bigInteger3.multiply(modInverse).mod(this.N), gpoint()), pmul(bigInteger.multiply(modInverse).mod(this.N), bigIntegerArr));
                if (padd != null) {
                    return padd[0].mod(this.N).equals(bigInteger);
                }
                return false;
            }
            return false;
        } catch (Exception unused) {
            return false;
        }
    }

    public byte[] spkiFor(BigInteger bigInteger) {
        BigInteger[] pmul = pmul(bigInteger, gpoint());
        return cat(cat(fromHex("3059301306072a8648ce3d020106082a8648ce3d03010703420004"), i2o(pmul[0])), i2o(pmul[1]));
    }

    String keyIdOf(byte[] bArr) {
        return toHex(sha256(bArr)).substring(0, 16);
    }

    public BigInteger newPrivateKey() {
        SecureRandom secureRandom = new SecureRandom();
        while (true) {
            BigInteger bigInteger = new BigInteger(256, secureRandom);
            if (bigInteger.signum() != 0 && bigInteger.compareTo(this.N) < 0) {
                return bigInteger;
            }
        }
    }

    public String[] readKeyFile(File file) {
        if (!file.exists()) {
            return null;
        }
        BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
        String str = null;
        String str2 = null;
        String str3 = null;
        while (true) {
            String readLine = bufferedReader.readLine();
            if (readLine == null) {
                break;
            }
            if (readLine.startsWith("private=")) {
                str = readLine.substring(8).trim();
            }
            if (readLine.startsWith("public=")) {
                str2 = readLine.substring(7).trim();
            }
            if (readLine.startsWith("id=")) {
                str3 = readLine.substring(3).trim();
            }
        }
        bufferedReader.close();
        if (str != null && str2 != null && str3 != null) {
            byte[] spkiFor = spkiFor(new BigInteger(str, 16));
            if (b64enc(spkiFor).equals(str2) && keyIdOf(spkiFor).equals(str3)) {
                return new String[]{str, str2, str3};
            }
        }
        return null;
    }

    public String[] createKeyFile(File file) throws IOException {
        BigInteger newPrivateKey = newPrivateKey();
        byte[] spkiFor = spkiFor(newPrivateKey);
        String[] strArr = {toHex(i2o(newPrivateKey)), b64enc(spkiFor), keyIdOf(spkiFor)};
        File parentFile = file.getParentFile();
        if (parentFile != null) {
            parentFile.mkdirs();
        }
        PrintWriter printWriter = new PrintWriter(new OutputStreamWriter(new FileOutputStream(file), "UTF-8"));
        printWriter.println("# ANA Lesson Maker signing key. KEEP PRIVATE. Back it up somewhere safe. Never email it or put it in a synced folder.");
        printWriter.println("# Anyone holding the private line can sign lessons that every ANA will trust.");
        printWriter.println("private=" + strArr[0]);
        printWriter.println("public=" + strArr[1]);
        printWriter.println("id=" + strArr[2]);
        printWriter.close();
        return strArr;
    }

    public void wstr(DataOutputStream dataOutputStream, String str) throws IOException {
        if (str == null) {
            str = "";
        }
        byte[] utf8 = utf8(str);
        dataOutputStream.writeInt(utf8.length);
        dataOutputStream.write(utf8);
    }

    public String rstr(DataInputStream dataInputStream) throws IOException {
        int readInt = dataInputStream.readInt();
        if (readInt < 0 || readInt > 16777216) {
            throw new IOException("damaged string in pngmesh");
        }
        byte[] bArr = new byte[readInt];
        dataInputStream.readFully(bArr);
        return fromUtf8(bArr);
    }

    public byte[] trailerPrefix(String[][] strArr, int i) throws IOException {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream);
        dataOutputStream.writeBytes("PMSH");
        dataOutputStream.writeInt(1);
        dataOutputStream.writeInt(1);
        dataOutputStream.writeInt(30);
        dataOutputStream.writeInt(3);
        wstr(dataOutputStream, "section");
        wstr(dataOutputStream, "key");
        wstr(dataOutputStream, "value");
        dataOutputStream.writeInt(i);
        for (String[] strArr2 : strArr) {
            for (int i2 = 0; i2 < 3; i2++) {
                wstr(dataOutputStream, strArr2[i2]);
            }
        }
        dataOutputStream.flush();
        return byteArrayOutputStream.toByteArray();
    }

    public byte[] wrapFile(byte[] bArr, byte[] bArr2) throws IOException {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream);
        dataOutputStream.write(bArr);
        dataOutputStream.write(bArr2);
        dataOutputStream.writeLong(bArr2.length);
        dataOutputStream.flush();
        return byteArrayOutputStream.toByteArray();
    }

    class Parsed {
        int cls;
        int lastRowOffset;
        String[][] rows;
        byte[] trailer;

        Parsed() {
        }
    }

    public Parsed parseFile(byte[] bArr) throws IOException {
        if (bArr.length < 20) {
            throw new IOException("too small to be a .pngmesh");
        }
        long readLong = new DataInputStream(new ByteArrayInputStream(bArr, bArr.length - 8, 8)).readLong();
        long length = (bArr.length - 8) - readLong;
        if (readLong < 12 || length < 0) {
            throw new IOException("no pngmesh trailer");
        }
        int i = (int) length;
        int i2 = (int) readLong;
        ByteArrayInputStream byteArrayInputStream = new ByteArrayInputStream(bArr, i, i2);
        DataInputStream dataInputStream = new DataInputStream(byteArrayInputStream);
        byte[] bArr2 = new byte[4];
        dataInputStream.readFully(bArr2);
        if (bArr2[0] != 80 || bArr2[1] != 77 || bArr2[2] != 83 || bArr2[3] != 72) {
            throw new IOException("not a pngmesh trailer");
        }
        int readInt = dataInputStream.readInt();
        if (readInt != 1) {
            throw new IOException("pngmesh version " + readInt + " is newer than this ANA");
        }
        if (dataInputStream.readInt() != 1) {
            throw new IOException("a lesson holds exactly one part");
        }
        Parsed parsed = new Parsed();
        parsed.cls = dataInputStream.readInt();
        if (parsed.cls != 30) {
            throw new IOException("this .pngmesh is not a lesson (class " + parsed.cls + ")");
        }
        if (dataInputStream.readInt() != 3) {
            throw new IOException("a lesson has exactly 3 columns");
        }
        String rstr = rstr(dataInputStream);
        String rstr2 = rstr(dataInputStream);
        String rstr3 = rstr(dataInputStream);
        if (!rstr.equals("section") || !rstr2.equals("key") || !rstr3.equals("value")) {
            throw new IOException("lesson columns are wrong");
        }
        int readInt2 = dataInputStream.readInt();
        if (readInt2 < 1 || readInt2 > 100000) {
            throw new IOException("lesson row count is wrong");
        }
        parsed.rows = (String[][]) Array.newInstance((Class<?>) String.class, readInt2, 3);
        for (int i3 = 0; i3 < readInt2; i3++) {
            if (i3 == readInt2 - 1) {
                parsed.lastRowOffset = i2 - byteArrayInputStream.available();
            }
            for (int i4 = 0; i4 < 3; i4++) {
                parsed.rows[i3][i4] = rstr(dataInputStream);
            }
        }
        if (byteArrayInputStream.available() != 0) {
            throw new IOException("extra bytes after the last row");
        }
        parsed.trailer = Arrays.copyOfRange(bArr, i, i2 + i);
        return parsed;
    }

    String sidecarText(String str, byte[] bArr) {
        return sha256hex(bArr) + "\n" + str + "\n" + bArr.length + "\n";
    }

    public String sidecarHash(byte[] bArr) {
        if (bArr == null || bArr.length > 4096) {
            return null;
        }
        String fromUtf8 = fromUtf8(bArr);
        int indexOf = fromUtf8.indexOf(10);
        if (indexOf >= 0) {
            fromUtf8 = fromUtf8.substring(0, indexOf);
        }
        String lowerCase = fromUtf8.trim().toLowerCase();
        if (lowerCase.matches("[0-9a-f]{64}")) {
            return lowerCase;
        }
        return null;
    }

    class ServerKeyOrder implements Comparator {
        ServerKeyOrder() {
        }

        @Override // java.util.Comparator
        public int compare(Object obj, Object obj2) {
            int i;
            int i2;
            String str = (String) obj2;
            try {
                i = Integer.parseInt(((String) obj).substring(7));
            } catch (Exception unused) {
                i = 0;
            }
            try {
                i2 = Integer.parseInt(str.substring(7));
            } catch (Exception unused2) {
                i2 = 0;
            }
            if (i < i2) {
                return -1;
            }
            return i > i2 ? 1 : 0;
        }
    }

    public String[][] rowsFrom(LinkedHashMap<String, String> linkedHashMap) {
        ArrayList arrayList = new ArrayList();
        for (int i = 0; i < this.SECTIONS.length; i++) {
            ArrayList arrayList2 = new ArrayList();
            for (String str : linkedHashMap.keySet()) {
                if (str.startsWith(this.SECTIONS[i] + "/")) {
                    arrayList2.add(str);
                }
            }
            if (this.SECTIONS[i].equals("server")) {
                Collections.sort(arrayList2, new ServerKeyOrder());
            }
            for (int i2 = 0; i2 < arrayList2.size(); i2++) {
                String str2 = (String) arrayList2.get(i2);
                String str3 = this.SECTIONS[i];
                arrayList.add(new String[]{str3, str2.substring(str3.length() + 1), linkedHashMap.get(str2)});
            }
        }
        return (String[][]) arrayList.toArray(new String[0][]);
    }

    public byte[] buildLesson(LinkedHashMap<String, String> linkedHashMap, BigInteger bigInteger, byte[] bArr) throws IOException {
        String keyIdOf = keyIdOf(spkiFor(bigInteger));
        String[][] rowsFrom = rowsFrom(linkedHashMap);
        int length = rowsFrom.length;
        String[][] strArr = new String[length + 1][];
        System.arraycopy(rowsFrom, 0, strArr, 0, rowsFrom.length);
        strArr[rowsFrom.length] = new String[]{"sig", "key_id", keyIdOf};
        byte[] trailerPrefix = trailerPrefix(strArr, length + 2);
        byte[] signMsg = signMsg(bigInteger, utf8(sha256hex(trailerPrefix)));
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream);
        dataOutputStream.write(trailerPrefix);
        wstr(dataOutputStream, "sig");
        wstr(dataOutputStream, "value");
        wstr(dataOutputStream, b64enc(signMsg));
        dataOutputStream.flush();
        return wrapFile(bArr, byteArrayOutputStream.toByteArray());
    }

    public String verifyLesson(byte[] bArr, byte[] bArr2, ArrayList<String[]> arrayList) {
        try {
            String sidecarHash = sidecarHash(bArr2);
            if (sidecarHash == null) {
                return "the .sha256 file is missing or unreadable";
            }
            if (!sidecarHash.equals(sha256hex(bArr))) {
                return "the file does not match its .sha256 (damaged or changed)";
            }
            Parsed parseFile = parseFile(bArr);
            int length = parseFile.rows.length;
            if (length < 3) {
                return "lesson is too short";
            }
            String[] strArr = parseFile.rows[length - 1];
            String[] strArr2 = parseFile.rows[length - 2];
            if (strArr[0].equals("sig") && strArr[1].equals("value")) {
                if (strArr2[0].equals("sig") && strArr2[1].equals("key_id")) {
                    byte[] bArr3 = null;
                    for (int i = 0; i < arrayList.size(); i++) {
                        if (arrayList.get(i)[0].equals(strArr2[2])) {
                            bArr3 = b64dec(arrayList.get(i)[1]);
                        }
                    }
                    if (bArr3 == null) {
                        return "lesson is signed by a key this ANA does not trust";
                    }
                    if (verifyMsg(bArr3, utf8(sha256hex(Arrays.copyOfRange(parseFile.trailer, 0, parseFile.lastRowOffset))), b64dec(strArr[2]))) {
                        return null;
                    }
                    return "the signature does not check out";
                }
                return "lesson has no key id";
            }
            return "lesson is not signed";
        } catch (IOException e) {
            return e.getMessage();
        } catch (Exception e2) {
            return "lesson could not be read: " + String.valueOf(e2);
        }
    }

    public LinkedHashMap<String, String> kvFromRows(String[][] strArr) {
        LinkedHashMap<String, String> linkedHashMap = new LinkedHashMap<>();
        for (int i = 0; i < strArr.length; i++) {
            String[] strArr2 = strArr[i];
            linkedHashMap.put(strArr2[0] + "/" + strArr2[1], strArr[i][2]);
        }
        return linkedHashMap;
    }

    public LinkedHashMap<String, String> parseDraft(String str) throws Exception {
        LinkedHashMap<String, String> linkedHashMap = new LinkedHashMap<>();
        String[] split = str.split("\r?\n");
        for (int i = 0; i < split.length; i++) {
            String trim = split[i].trim();
            if (trim.length() != 0 && !trim.startsWith("#")) {
                int indexOf = trim.indexOf(61);
                if (indexOf < 1) {
                    throw new Exception("line " + (i + 1) + ": expected  section/key = value");
                }
                String trim2 = trim.substring(0, indexOf).trim();
                String trim3 = trim.substring(indexOf + 1).trim();
                if (!trim2.matches("[a-z_]+/[A-Za-z0-9_.-]+")) {
                    throw new Exception("line " + (i + 1) + ": bad key  " + trim2);
                }
                if (linkedHashMap.containsKey(trim2)) {
                    throw new Exception("line " + (i + 1) + ": " + trim2 + " appears twice");
                }
                linkedHashMap.put(trim2, trim3);
            }
        }
        return linkedHashMap;
    }

    public void normalise(LinkedHashMap<String, String> linkedHashMap) {
        String str = linkedHashMap.get("reader/name");
        Iterator it = new ArrayList(linkedHashMap.keySet()).iterator();
        while (it.hasNext()) {
            String str2 = (String) it.next();
            if (str2.startsWith("server/")) {
                String trim = linkedHashMap.get(str2).trim();
                if ("esplora".equals(str) && trim.length() > 0 && !trim.endsWith("/")) {
                    trim = trim + "/";
                }
                linkedHashMap.put(str2, trim);
            }
        }
    }

    public ArrayList<String> lint(LinkedHashMap<String, String> linkedHashMap, boolean z) {
        boolean z2;
        int i;
        ArrayList<String> arrayList = new ArrayList<>();
        ArrayList arrayList2 = new ArrayList();
        boolean z3 = false;
        for (String str : linkedHashMap.keySet()) {
            String substring = str.substring(0, str.indexOf(47));
            int i2 = 0;
            boolean z4 = false;
            while (true) {
                String[] strArr = this.SECTIONS;
                if (i2 >= strArr.length) {
                    break;
                }
                if (strArr[i2].equals(substring)) {
                    z4 = true;
                }
                i2++;
            }
            if (!z4) {
                arrayList.add(str + ": unknown section (the signature rows are added for you)");
                z3 = true;
            }
            if ("?".equals(linkedHashMap.get(str))) {
                arrayList.add(str + ": still says ?  - fill it in");
                arrayList2.add(str);
            }
        }
        if (z3) {
            return arrayList;
        }
        boolean z5 = false;
        for (int i3 = 0; i3 < arrayList2.size(); i3++) {
            if (((String) arrayList2.get(i3)).startsWith("address/")) {
                z5 = true;
            }
        }
        String str2 = linkedHashMap.get("lesson/id");
        if (str2 == null || !str2.matches("[a-z0-9][a-z0-9_-]{1,31}")) {
            arrayList.add("lesson/id: use 2-32 lowercase letters, digits, - or _");
        }
        if (!isInt(linkedHashMap.get("lesson/version"), 1, 1000000)) {
            arrayList.add("lesson/version: whole number, 1 or more");
        }
        if (!isInt(linkedHashMap.get("lesson/needs_reader"), 1, 1000)) {
            arrayList.add("lesson/needs_reader: whole number, 1 or more");
        }
        if (isEmpty(linkedHashMap.get("coin/name"))) {
            arrayList.add("coin/name: missing");
        }
        if (linkedHashMap.get("coin/ticker") == null || !linkedHashMap.get("coin/ticker").matches("[A-Z0-9]{1,10}")) {
            arrayList.add("coin/ticker: 1-10 capital letters or digits");
        }
        if (!isInt(linkedHashMap.get("coin/decimals"), 0, 30)) {
            arrayList.add("coin/decimals: whole number 0-30");
        }
        if (!isInt(linkedHashMap.get("coin/display_decimals"), 0, 18)) {
            arrayList.add("coin/display_decimals: whole number 0-18");
        }
        if (linkedHashMap.get("coin/price_id") == null || !linkedHashMap.get("coin/price_id").matches("[a-z0-9-]{1,60}")) {
            arrayList.add("coin/price_id: the CoinGecko id, lowercase");
        }
        ArrayList<String[]> formsOf = formsOf(linkedHashMap);
        if (formsOf.isEmpty()) {
            arrayList.add("address: need at least one address/form1.kind");
        }
        for (int i4 = 0; i4 < formsOf.size(); i4++) {
            String[] strArr2 = formsOf.get(i4);
            String str3 = "address/" + strArr2[0];
            if (!strArr2[1].equals("base58check") && !strArr2[1].equals("bech32") && !strArr2[1].equals("hex_evm")) {
                arrayList.add(str3 + ".kind: must be base58check, bech32 or hex_evm");
            }
            try {
                Pattern.compile(strArr2[2]);
                if (strArr2[2].length() == 0) {
                    arrayList.add(str3 + ".pattern: missing");
                }
            } catch (Exception unused) {
                arrayList.add(str3 + ".pattern: not a valid pattern");
            }
            if (strArr2[1].equals("bech32") && !strArr2[3].matches("[a-z0-9]{1,20}")) {
                arrayList.add(str3 + ".hrp: the address prefix, such as bc or addr");
            }
            if (strArr2[1].equals("base58check") && !strArr2[4].matches("[0-9]{1,3}(,[0-9]{1,3})*")) {
                arrayList.add(str3 + ".versions: numbers like 0,5");
            }
        }
        String str4 = linkedHashMap.get("reader/name");
        if (str4 == null || (!str4.equals("esplora") && !str4.equals("evm") && !str4.equals("json"))) {
            arrayList.add("reader/name: must be esplora, evm or json");
        }
        int i5 = 0;
        for (String str5 : linkedHashMap.keySet()) {
            if (str5.startsWith("server/")) {
                i5++;
                String str6 = linkedHashMap.get(str5);
                if (!str5.substring(7).matches("[0-9]{1,2}")) {
                    arrayList.add(str5 + ": server keys are numbers, 1 2 3 ...");
                }
                if (!str6.matches("https://[^/\\s@?#]+(/\\S*)?") && (!z || !str6.matches("http://[^/\\s@?#]+(/\\S*)?"))) {
                    arrayList.add(str5 + ": must be an https:// address with no username or password in it");
                }
                if (str6.toLowerCase().matches(".*[?&](api_?key|key|token|secret|project_id|auth|access_token)=.*")) {
                    arrayList.add(str5 + ": looks like it carries a key. Lessons are readable by anyone, so they can never hold secrets");
                }
            }
        }
        if (i5 < 1) {
            arrayList.add("server: need at least server/1");
        }
        for (String str7 : linkedHashMap.keySet()) {
            if (!str7.startsWith("test/") && linkedHashMap.get(str7).toLowerCase().matches(".*(apikey|api_key|api-key|x-api|authorization|bearer |project_id|secret).*")) {
                arrayList.add(str7 + ": looks like a secret. Lessons can never hold keys");
            }
        }
        if ("json".equals(str4)) {
            String str8 = linkedHashMap.get("param/method");
            if (str8 == null || (!str8.equals("GET") && !str8.equals("POST"))) {
                arrayList.add("param/method: GET or POST");
            }
            if (isEmpty(linkedHashMap.get("param/balance_path"))) {
                arrayList.add("param/balance_path: where the balance sits in the reply, like 0.balance");
            }
            String str9 = linkedHashMap.get("param/balance_type");
            if (str9 == null || (!str9.equals("number") && !str9.equals("text_integer"))) {
                arrayList.add("param/balance_type: number or text_integer");
            }
            if ("POST".equals(str8) && (linkedHashMap.get("param/body") == null || !linkedHashMap.get("param/body").contains("{address}"))) {
                arrayList.add("param/body: a POST body must contain {address}");
            }
            if ("GET".equals(str8)) {
                for (String str10 : linkedHashMap.keySet()) {
                    if (str10.startsWith("server/") && !linkedHashMap.get(str10).contains("{address}")) {
                        arrayList.add(str10 + ": a GET server address must contain {address}");
                    }
                }
            }
        }
        if ("evm".equals(str4) && !isInt(linkedHashMap.get("param/chain_id"), 1, Integer.MAX_VALUE)) {
            arrayList.add("param/chain_id: whole number, like 1 for Ethereum");
        }
        int i6 = 0;
        int i7 = 0;
        for (String str11 : linkedHashMap.keySet()) {
            if (str11.startsWith("test/good.")) {
                i6++;
                if (!z5 && !anyFormOk(linkedHashMap, linkedHashMap.get(str11))) {
                    arrayList.add(str11 + ": this address should be valid but fails every address rule");
                }
            }
            if (str11.startsWith("test/bad.")) {
                i7++;
                if (!z5 && anyFormOk(linkedHashMap, linkedHashMap.get(str11))) {
                    arrayList.add(str11 + ": this address should be rejected but passes an address rule");
                }
            }
        }
        if (!z5 && linkedHashMap.containsKey("test/probe_address") && !anyFormOk(linkedHashMap, linkedHashMap.get("test/probe_address"))) {
            arrayList.add("test/probe_address: fails every address rule");
        }
        if (i6 < 1) {
            arrayList.add("test/good.1: need at least one good address");
        }
        if (i7 < 1) {
            arrayList.add("test/bad.1: need at least one bad address");
        }
        ArrayList<String> arrayList3 = new ArrayList<>();
        for (int i8 = 0; i8 < arrayList.size(); i8++) {
            String str12 = arrayList.get(i8);
            if (str12.indexOf("still says ?") < 0) {
                z2 = false;
                for (0; i < arrayList2.size(); i + 1) {
                    if (!str12.startsWith(((String) arrayList2.get(i)) + ":")) {
                        i = str12.startsWith(((String) arrayList2.get(i)) + ".") ? 0 : i + 1;
                    }
                    z2 = true;
                }
            } else {
                z2 = false;
            }
            if (!z2) {
                arrayList3.add(str12);
            }
        }
        return arrayList3;
    }

    boolean isEmpty(String str) {
        return str == null || str.trim().length() == 0;
    }

    public boolean isInt(String str, int i, int i2) {
        try {
            int parseInt = Integer.parseInt(str.trim());
            return parseInt >= i && parseInt <= i2;
        } catch (Exception unused) {
            return false;
        }
    }

    public ArrayList<String[]> formsOf(LinkedHashMap<String, String> linkedHashMap) {
        ArrayList<String[]> arrayList = new ArrayList<>();
        for (String str : linkedHashMap.keySet()) {
            Matcher matcher = Pattern.compile("address/(form[0-9]+)\\.kind").matcher(str);
            if (matcher.matches()) {
                String group = matcher.group(1);
                arrayList.add(new String[]{group, linkedHashMap.get(str), nz(linkedHashMap.get("address/" + group + ".pattern")), nz(linkedHashMap.get("address/" + group + ".hrp")), nz(linkedHashMap.get("address/" + group + ".versions"))});
            }
        }
        return arrayList;
    }

    String nz(String str) {
        return str == null ? "" : str;
    }

    public boolean anyFormOk(LinkedHashMap<String, String> linkedHashMap, String str) {
        ArrayList<String[]> formsOf = formsOf(linkedHashMap);
        for (int i = 0; i < formsOf.size(); i++) {
            String[] strArr = formsOf.get(i);
            if (addrOk(strArr[1], strArr[2], strArr[3], strArr[4], str)) {
                return true;
            }
        }
        return false;
    }

    public String confirmText(LinkedHashMap<String, String> linkedHashMap) {
        int i;
        ArrayList arrayList = new ArrayList();
        Iterator<String> it = linkedHashMap.keySet().iterator();
        while (true) {
            if (!it.hasNext()) {
                break;
            }
            String next = it.next();
            if (next.startsWith("server/")) {
                String replaceFirst = linkedHashMap.get(next).replaceFirst("^https?://", "");
                int length = replaceFirst.length();
                for (int i2 = 0; i2 < replaceFirst.length(); i2++) {
                    char charAt = replaceFirst.charAt(i2);
                    if (charAt == '/' || charAt == ':' || charAt == '?' || charAt == '#') {
                        length = i2;
                        break;
                    }
                }
                String substring = replaceFirst.substring(0, length);
                if (!arrayList.contains(substring)) {
                    arrayList.add(substring);
                }
            }
        }
        StringBuilder sb = new StringBuilder();
        for (i = 0; i < arrayList.size(); i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append((String) arrayList.get(i));
        }
        return "Add " + linkedHashMap.get("coin/name") + " (" + linkedHashMap.get("coin/ticker") + ")?  ANA will send the addresses you watch to: " + String.valueOf(sb);
    }

    public String cq(String str) {
        return str.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
    }

    public String[] http(String str, String str2, String str3, int i) {
        try {
            boolean z = System.getProperty("os.name", "").toLowerCase().indexOf("win") >= 0;
            StringBuilder sb = new StringBuilder("silent\nshow-error\nlocation\nmax-time = ");
            sb.append(i);
            sb.append("\nuser-agent = \"ANA-LessonMaker/1\"\nheader = \"accept: application/json\"\nwrite-out = \"\\n|||%{http_code}\"\n");
            if (!"GET".equals(str)) {
                sb.append("request = \"");
                sb.append(str);
                sb.append("\"\n");
            }
            if (str3 != null) {
                sb.append("header = \"content-type: application/json\"\ndata-binary = \"");
                sb.append(cq(str3));
                sb.append("\"\n");
            }
            sb.append("url = \"");
            sb.append(cq(str2));
            sb.append("\"\n");
            ProcessBuilder processBuilder = new ProcessBuilder(z ? "curl.exe" : "curl", "-K", "-");
            processBuilder.redirectErrorStream(true);
            Process start = processBuilder.start();
            OutputStream outputStream = start.getOutputStream();
            outputStream.write(utf8(sb.toString()));
            outputStream.close();
            InputStream inputStream = start.getInputStream();
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            byte[] bArr = new byte[8192];
            while (true) {
                int read = inputStream.read(bArr);
                if (read <= 0) {
                    break;
                }
                byteArrayOutputStream.write(bArr, 0, read);
            }
            start.waitFor();
            String fromUtf8 = fromUtf8(byteArrayOutputStream.toByteArray());
            Matcher matcher = Pattern.compile("\\n\\|\\|\\|([0-9]{3})").matcher(fromUtf8);
            int i2 = -1;
            String str4 = "0";
            int i3 = 0;
            while (matcher.find()) {
                i2 = matcher.start();
                i3 = matcher.end();
                str4 = matcher.group(1);
            }
            if (i2 < 0) {
                return new String[]{"0", fromUtf8.trim()};
            }
            String trim = fromUtf8.substring(i3).trim();
            if (!str4.equals("000")) {
                return new String[]{str4, fromUtf8.substring(0, i2)};
            }
            if (trim.length() <= 0) {
                trim = "could not connect";
            }
            return new String[]{"0", trim};
        } catch (IOException unused) {
            return httpFallback(str, str2, str3, i);
        } catch (Exception e) {
            return new String[]{"0", String.valueOf(e)};
        }
    }

    public String[] httpFallback(String str, String str2, String str3, int i) {
        try {
            HttpURLConnection httpURLConnection = (HttpURLConnection) new URL(str2).openConnection();
            int i2 = i * 1000;
            httpURLConnection.setConnectTimeout(i2);
            httpURLConnection.setReadTimeout(i2);
            httpURLConnection.setRequestProperty("accept", "application/json");
            httpURLConnection.setRequestProperty("User-Agent", "ANA-LessonMaker/1");
            httpURLConnection.setRequestMethod(str);
            if (str3 != null) {
                httpURLConnection.setDoOutput(true);
                httpURLConnection.setRequestProperty("content-type", "application/json");
                OutputStream outputStream = httpURLConnection.getOutputStream();
                outputStream.write(utf8(str3));
                outputStream.close();
            }
            int responseCode = httpURLConnection.getResponseCode();
            InputStream errorStream = responseCode >= 400 ? httpURLConnection.getErrorStream() : httpURLConnection.getInputStream();
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            if (errorStream != null) {
                byte[] bArr = new byte[8192];
                while (true) {
                    int read = errorStream.read(bArr);
                    if (read <= 0) {
                        break;
                    }
                    byteArrayOutputStream.write(bArr, 0, read);
                }
            }
            StringBuilder sb = new StringBuilder();
            sb.append(responseCode);
            return new String[]{sb.toString(), fromUtf8(byteArrayOutputStream.toByteArray())};
        } catch (Exception e) {
            return new String[]{"0", String.valueOf(e)};
        }
    }

    public Object jparse(String str) {
        int[] iArr = {0};
        Object jval = jval(str, iArr);
        jws(str, iArr);
        if (iArr[0] == str.length()) {
            return jval;
        }
        throw new RuntimeException("extra text after JSON");
    }

    void jws(String str, int[] iArr) {
        while (iArr[0] < str.length() && Character.isWhitespace(str.charAt(iArr[0]))) {
            iArr[0] = iArr[0] + 1;
        }
    }

    public void jexpect(String str, int[] iArr, char c) {
        jws(str, iArr);
        if (iArr[0] >= str.length() || str.charAt(iArr[0]) != c) {
            throw new RuntimeException("JSON: expected " + c);
        }
        iArr[0] = iArr[0] + 1;
    }

    public Object jval(String str, int[] iArr) {
        char charAt;
        char charAt2;
        jws(str, iArr);
        if (iArr[0] >= str.length()) {
            throw new RuntimeException("JSON ended early");
        }
        char charAt3 = str.charAt(iArr[0]);
        if (charAt3 == '{') {
            iArr[0] = iArr[0] + 1;
            LinkedHashMap linkedHashMap = new LinkedHashMap();
            jws(str, iArr);
            if (str.charAt(iArr[0]) == '}') {
                iArr[0] = iArr[0] + 1;
                return linkedHashMap;
            }
            do {
                jws(str, iArr);
                String jstr = jstr(str, iArr);
                jexpect(str, iArr, ':');
                linkedHashMap.put(jstr, jval(str, iArr));
                jws(str, iArr);
                int i = iArr[0];
                iArr[0] = i + 1;
                charAt2 = str.charAt(i);
                if (charAt2 == '}') {
                    return linkedHashMap;
                }
            } while (charAt2 == ',');
            throw new RuntimeException("JSON: expected , or }");
        }
        if (charAt3 == '[') {
            iArr[0] = iArr[0] + 1;
            ArrayList arrayList = new ArrayList();
            jws(str, iArr);
            if (str.charAt(iArr[0]) == ']') {
                iArr[0] = iArr[0] + 1;
                return arrayList;
            }
            do {
                arrayList.add(jval(str, iArr));
                jws(str, iArr);
                int i2 = iArr[0];
                iArr[0] = i2 + 1;
                charAt = str.charAt(i2);
                if (charAt == ']') {
                    return arrayList;
                }
            } while (charAt == ',');
            throw new RuntimeException("JSON: expected , or ]");
        }
        if (charAt3 == '\"') {
            return jstr(str, iArr);
        }
        if (str.startsWith("true", iArr[0])) {
            iArr[0] = iArr[0] + 4;
            return Boolean.TRUE;
        }
        if (str.startsWith("false", iArr[0])) {
            iArr[0] = iArr[0] + 5;
            return Boolean.FALSE;
        }
        if (str.startsWith("null", iArr[0])) {
            iArr[0] = iArr[0] + 4;
            return null;
        }
        int i3 = iArr[0];
        while (iArr[0] < str.length() && "+-0123456789.eE".indexOf(str.charAt(iArr[0])) >= 0) {
            iArr[0] = iArr[0] + 1;
        }
        if (i3 == iArr[0]) {
            throw new RuntimeException("JSON: unexpected character " + charAt3);
        }
        return new BigDecimal(str.substring(i3, iArr[0]));
    }

    public String jstr(String str, int[] iArr) {
        char c;
        char c2;
        if (str.charAt(iArr[0]) != '\"') {
            throw new RuntimeException("JSON: expected a string");
        }
        iArr[0] = iArr[0] + 1;
        StringBuilder sb = new StringBuilder();
        while (true) {
            int i = iArr[0];
            iArr[0] = i + 1;
            char charAt = str.charAt(i);
            if (charAt == '\"') {
                return sb.toString();
            }
            if (charAt == '\\') {
                int i2 = iArr[0];
                iArr[0] = i2 + 1;
                char charAt2 = str.charAt(i2);
                if (charAt2 == 'n') {
                    c = '\n';
                } else if (charAt2 == 't') {
                    c = '\t';
                } else if (charAt2 == 'r') {
                    c = '\r';
                } else {
                    if (charAt2 == 'b') {
                        c2 = '\b';
                    } else if (charAt2 == 'f') {
                        c2 = '\f';
                    } else if (charAt2 == 'u') {
                        int i3 = iArr[0];
                        sb.append((char) Integer.parseInt(str.substring(i3, i3 + 4), 16));
                        iArr[0] = iArr[0] + 4;
                    } else {
                        sb.append(charAt2);
                    }
                    sb.append(c2);
                }
                sb.append(c);
            } else {
                sb.append(charAt);
            }
        }
    }

    public Object jpath(Object obj, String str) {
        if (str != null && str.length() != 0) {
            String[] split = str.split("\\.");
            for (int i = 0; i < split.length; i++) {
                if (obj instanceof Map) {
                    obj = ((Map) obj).get(split[i]);
                } else {
                    if (!(obj instanceof List)) {
                        return null;
                    }
                    int parseInt = Integer.parseInt(split[i]);
                    List list = (List) obj;
                    obj = (parseInt < 0 || parseInt >= list.size()) ? null : list.get(parseInt);
                }
                if (obj == null) {
                    return null;
                }
            }
        }
        return obj;
    }

    public BigInteger bigAt(Object obj, String str) {
        Object jpath = jpath(obj, str);
        if (jpath instanceof BigDecimal) {
            return ((BigDecimal) jpath).toBigInteger();
        }
        if (jpath instanceof String) {
            return new BigInteger(((String) jpath).trim());
        }
        return null;
    }

    public class Probe {
        public long ms;
        public boolean ok;
        public BigInteger raw;
        public String reader = "";
        public String url = "";
        public String params = "";
        public String note = "";

        public Probe() {
        }
    }

    public LinkedHashMap<String, String> params(String str) {
        LinkedHashMap<String, String> linkedHashMap = new LinkedHashMap<>();
        if (str == null) {
            return linkedHashMap;
        }
        String[] split = str.split(";");
        for (int i = 0; i < split.length; i++) {
            int indexOf = split[i].indexOf(61);
            if (indexOf > 0) {
                linkedHashMap.put(split[i].substring(0, indexOf).trim(), split[i].substring(indexOf + 1).trim());
            }
        }
        return linkedHashMap;
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r2v0, types: [java.lang.String] */
    /* JADX WARN: Type inference failed for: r2v1 */
    public Probe runProbe(String str, String str2, String str3, String str4) {
        long j;
        LinkedHashMap<String, String> params;
        String str5;
        String str6;
        String str7;
        String str8;
        boolean z = str2;
        Probe probe = new Probe();
        probe.reader = str;
        probe.url = z;
        probe.params = str3;
        long currentTimeMillis = System.currentTimeMillis();
        try {
            params = params(str3);
            j = currentTimeMillis;
        } catch (Exception e) {
            e = e;
            j = currentTimeMillis;
        }
        try {
            try {
                if (str.equals("esplora")) {
                    if (z.endsWith("/")) {
                        str7 = z;
                    } else {
                        str7 = ((String) z) + "/";
                    }
                    String[] http = http("GET", str7 + "address/" + str4, null, 20);
                    if (!http[0].startsWith("2")) {
                        if (http[0].equals("0")) {
                            str8 = http[1];
                        } else {
                            str8 = "server said " + http[0];
                        }
                        throw new Exception(str8);
                    }
                    Object jparse = jparse(http[1]);
                    BigInteger bigAt = bigAt(jparse, "chain_stats.funded_txo_sum");
                    BigInteger bigAt2 = bigAt(jparse, "chain_stats.spent_txo_sum");
                    if (bigAt == null || bigAt2 == null) {
                        throw new Exception("reply has no chain_stats");
                    }
                    BigInteger subtract = bigAt.subtract(bigAt2);
                    BigInteger bigAt3 = bigAt(jparse, "mempool_stats.funded_txo_sum");
                    BigInteger bigAt4 = bigAt(jparse, "mempool_stats.spent_txo_sum");
                    if (bigAt3 != null && bigAt4 != null) {
                        subtract = subtract.add(bigAt3).subtract(bigAt4);
                    }
                    probe.raw = subtract;
                } else if (str.equals("evm")) {
                    String[] http2 = http("POST", z, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"" + str4 + "\",\"latest\"]}", 20);
                    if (!http2[0].startsWith("2")) {
                        if (http2[0].equals("0")) {
                            str6 = http2[1];
                        } else {
                            str6 = "server said " + http2[0];
                        }
                        throw new Exception(str6);
                    }
                    Object jpath = jpath(jparse(http2[1]), "result");
                    if (!(jpath instanceof String) || !((String) jpath).startsWith("0x")) {
                        throw new Exception("reply has no result");
                    }
                    String substring = ((String) jpath).substring(2);
                    probe.raw = substring.length() == 0 ? BigInteger.ZERO : new BigInteger(substring, 16);
                } else {
                    if (!str.equals("json")) {
                        throw new Exception("unknown reader " + str);
                    }
                    String[] http3 = http(params.containsKey("method") ? params.get("method") : "GET", z.replace("{address}", str4), params.containsKey("body") ? params.get("body").replace("{address}", str4) : null, 20);
                    if (!http3[0].startsWith("2")) {
                        if (http3[0].equals("0")) {
                            str5 = http3[1];
                        } else {
                            str5 = "server said " + http3[0];
                        }
                        throw new Exception(str5);
                    }
                    BigInteger bigAt5 = bigAt(jparse(http3[1]), params.get("balance_path"));
                    if (bigAt5 == null) {
                        throw new Exception("the balance was not where balance_path says");
                    }
                    probe.raw = bigAt5;
                }
                probe.ok = true;
            } catch (Exception e2) {
                e = e2;
                probe.ok = z;
                probe.note = e.getMessage();
                probe.ms = System.currentTimeMillis() - j;
                return probe;
            }
        } catch (Exception e3) {
            e = e3;
            z = 0;
            probe.ok = z;
            probe.note = e.getMessage();
            probe.ms = System.currentTimeMillis() - j;
            return probe;
        }
        probe.ms = System.currentTimeMillis() - j;
        return probe;
    }

    public String fmtAmount(BigInteger bigInteger, int i, int i2) {
        return new BigDecimal(bigInteger).movePointLeft(i).setScale(i2, RoundingMode.DOWN).toPlainString();
    }

    public ArrayList<String[]> readRecipes(String str) {
        ArrayList<String[]> arrayList = new ArrayList<>();
        for (String str2 : str.split("\r?\n")) {
            String trim = str2.trim();
            if (trim.length() != 0 && !trim.startsWith("#")) {
                String[] split = trim.split("\\|", -1);
                if (split.length >= 3) {
                    arrayList.add(new String[]{split[0].trim(), split[1].trim().toLowerCase(), split[2].trim(), split.length > 3 ? split[3].trim() : ""});
                }
            }
        }
        return arrayList;
    }

    public String defaultRecipes() {
        return "# reader | coin id (CoinGecko id) | server | settings\n# Starting points only. A server that no longer answers simply shows as failed when you press Detect.\n# Add your own lines. Never put an API key in here: lessons are readable by anyone.\nesplora | bitcoin | https://mempool.space/api/ |\nesplora | litecoin | https://litecoinspace.org/api/ |\nevm | ethereum | https://ethereum-rpc.publicnode.com | chain_id=1\njson | cardano | https://api.koios.rest/api/v1/address_info | method=POST;body={\"_addresses\":[\"{address}\"]};balance_path=0.balance;balance_type=text_integer\n";
    }

    public String[] known(String str) {
        if (str.equals("bitcoin")) {
            return new String[]{"Bitcoin", "BTC", "8", "6", "address/form1.kind = bech32\naddress/form1.hrp = bc\naddress/form1.pattern = ^bc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{25,87}$\naddress/form2.kind = base58check\naddress/form2.versions = 0,5\naddress/form2.pattern = ^[13][1-9A-HJ-NP-Za-km-z]{25,34}$\n"};
        }
        if (str.equals("litecoin")) {
            return new String[]{"Litecoin", "LTC", "8", "4", "address/form1.kind = bech32\naddress/form1.hrp = ltc\naddress/form1.pattern = ^ltc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{25,87}$\naddress/form2.kind = base58check\naddress/form2.versions = 48,50\naddress/form2.pattern = ^[LM][1-9A-HJ-NP-Za-km-z]{25,34}$\n"};
        }
        if (str.equals("ethereum")) {
            return new String[]{"Ethereum", "ETH", "18", "5", "address/form1.kind = hex_evm\naddress/form1.pattern = ^0x[0-9a-fA-F]{40}$\n"};
        }
        if (str.equals("cardano")) {
            return new String[]{"Cardano", "ADA", "6", "4", "address/form1.kind = bech32\naddress/form1.hrp = addr\naddress/form1.pattern = ^addr1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{50,120}$\n"};
        }
        return null;
    }

    public String describeShape(String str) {
        if (str == null || str.trim().length() == 0) {
            return "";
        }
        String trim = str.trim();
        int bech32Variant = bech32Variant(trim, null);
        if (bech32Variant != 0) {
            return (bech32Variant == 2 ? "bech32m" : "bech32") + " address, prefix " + trim.substring(0, trim.toLowerCase().lastIndexOf(49)).toLowerCase() + ", " + trim.length() + " characters, checksum OK";
        }
        byte[] b58dec = b58dec(trim);
        if (b58dec != null) {
            int i = b58dec[0] & 255;
            StringBuilder sb = new StringBuilder();
            sb.append(i);
            if (b58checkOk(trim, sb.toString())) {
                return "base58check address, version byte " + (b58dec[0] & 255) + ", checksum OK";
            }
        }
        return trim.matches("0x[0-9a-fA-F]{40}") ? "0x address (EVM family: Ethereum, Optimism, Base, Polygon ...)" : "shape not recognised";
    }

    public String learnForm(String str) {
        if (str == null) {
            return "address/form1.kind = ?\n";
        }
        String trim = str.trim();
        if (bech32Variant(trim, null) != 0) {
            String lowerCase = trim.substring(0, trim.toLowerCase().lastIndexOf(49)).toLowerCase();
            return "address/form1.kind = bech32\naddress/form1.hrp = " + lowerCase + "\naddress/form1.pattern = ^" + lowerCase + "1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{20,120}$\n";
        }
        byte[] b58dec = b58dec(trim);
        if (b58dec != null) {
            int i = b58dec[0] & 255;
            StringBuilder sb = new StringBuilder();
            sb.append(i);
            if (b58checkOk(trim, sb.toString())) {
                return "address/form1.kind = base58check\naddress/form1.versions = " + (b58dec[0] & 255) + "\naddress/form1.pattern = ^[1-9A-HJ-NP-Za-km-z]{25,35}$\n";
            }
        }
        if (!trim.matches("0x[0-9a-fA-F]{40}")) {
            return "address/form1.kind = ?\n";
        }
        return "address/form1.kind = hex_evm\naddress/form1.pattern = ^0x[0-9a-fA-F]{40}$\n";
    }

    public String mutateBad(String str) {
        if (str.matches("0x[0-9a-fA-F]{40}")) {
            return str.substring(0, str.length() - 1);
        }
        int lastIndexOf = str.toLowerCase().lastIndexOf(49);
        boolean z = bech32Variant(str, null) != 0;
        String str2 = z ? "qpzry9x8gf2tvdw0s3jn54khce6mua7l" : "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        for (int i = 1; i < str.length() - lastIndexOf; i++) {
            int length = str.length() - i;
            char charAt = str.charAt(length);
            for (int i2 = 0; i2 < str2.length(); i2++) {
                char charAt2 = str2.charAt(i2);
                if (charAt2 != charAt && (!z || !Character.isUpperCase(charAt))) {
                    String str3 = str.substring(0, length) + charAt2 + str.substring(length + 1);
                    if (z) {
                        if (bech32Variant(str3, null) == 0) {
                            return str3;
                        }
                    } else if (!b58checkOk(str3, "0,5,48,50,111,196")) {
                        return str3;
                    }
                }
            }
        }
        return str.substring(0, str.length() - 1);
    }

    /* JADX WARN: Code restructure failed: missing block: B:17:0x0057, code lost:
    
        return r0;
     */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    public java.util.ArrayList<java.lang.String[]> candidates(java.lang.String r8) {
        /*
            r7 = this;
            java.util.ArrayList r0 = new java.util.ArrayList
            r0.<init>()
            java.lang.String r1 = r8.trim()
            java.lang.String r1 = r1.toLowerCase()
            int r2 = r1.length()
            if (r2 != 0) goto L14
            return r0
        L14:
            r2 = 0
            r3 = r2
        L16:
            java.lang.String[] r4 = r7.KNOWN_IDS
            int r5 = r4.length
            r6 = 1
            if (r3 >= r5) goto L58
            r4 = r4[r3]
            java.lang.String[] r4 = r7.known(r4)
            java.lang.String[] r5 = r7.KNOWN_IDS
            r5 = r5[r3]
            boolean r5 = r5.equals(r1)
            if (r5 != 0) goto L48
            r5 = r4[r2]
            java.lang.String r5 = r5.toLowerCase()
            boolean r5 = r5.equals(r1)
            if (r5 != 0) goto L48
            r5 = r4[r6]
            java.lang.String r5 = r5.toLowerCase()
            boolean r5 = r5.equals(r1)
            if (r5 == 0) goto L45
            goto L48
        L45:
            int r3 = r3 + 1
            goto L16
        L48:
            java.lang.String[] r8 = r7.KNOWN_IDS
            r8 = r8[r3]
            r1 = r4[r2]
            r2 = r4[r6]
            java.lang.String[] r8 = new java.lang.String[]{r8, r1, r2}
            r0.add(r8)
            return r0
        L58:
            java.lang.String r1 = "GET"
            java.lang.String r3 = r7.coingeckoBase     // Catch: java.lang.Exception -> Le8
            java.lang.String r8 = r8.trim()     // Catch: java.lang.Exception -> Le8
            java.lang.String r4 = "UTF-8"
            java.lang.String r8 = java.net.URLEncoder.encode(r8, r4)     // Catch: java.lang.Exception -> Le8
            java.lang.StringBuilder r4 = new java.lang.StringBuilder     // Catch: java.lang.Exception -> Le8
            r4.<init>()     // Catch: java.lang.Exception -> Le8
            r4.append(r3)     // Catch: java.lang.Exception -> Le8
            java.lang.String r3 = "/search?query="
            r4.append(r3)     // Catch: java.lang.Exception -> Le8
            r4.append(r8)     // Catch: java.lang.Exception -> Le8
            java.lang.String r8 = r4.toString()     // Catch: java.lang.Exception -> Le8
            r3 = 0
            r4 = 20
            java.lang.String[] r8 = r7.http(r1, r8, r3, r4)     // Catch: java.lang.Exception -> Le8
            r1 = r8[r2]     // Catch: java.lang.Exception -> Le8
            java.lang.String r3 = "2"
            boolean r1 = r1.startsWith(r3)     // Catch: java.lang.Exception -> Le8
            if (r1 != 0) goto L8c
            return r0
        L8c:
            r8 = r8[r6]     // Catch: java.lang.Exception -> Le8
            java.lang.Object r8 = r7.jparse(r8)     // Catch: java.lang.Exception -> Le8
            java.lang.String r1 = "coins"
            java.lang.Object r8 = r7.jpath(r8, r1)     // Catch: java.lang.Exception -> Le8
            boolean r1 = r8 instanceof java.util.List     // Catch: java.lang.Exception -> Le8
            if (r1 == 0) goto Le8
            java.util.List r8 = (java.util.List) r8     // Catch: java.lang.Exception -> Le8
        L9e:
            int r1 = r8.size()     // Catch: java.lang.Exception -> Le8
            if (r2 >= r1) goto Le8
            int r1 = r0.size()     // Catch: java.lang.Exception -> Le8
            r3 = 6
            if (r1 >= r3) goto Le8
            java.lang.Object r1 = r8.get(r2)     // Catch: java.lang.Exception -> Le8
            java.lang.String r3 = "id"
            java.lang.Object r1 = r7.jpath(r1, r3)     // Catch: java.lang.Exception -> Le8
            java.lang.Object r3 = r8.get(r2)     // Catch: java.lang.Exception -> Le8
            java.lang.String r4 = "name"
            java.lang.Object r3 = r7.jpath(r3, r4)     // Catch: java.lang.Exception -> Le8
            java.lang.Object r4 = r8.get(r2)     // Catch: java.lang.Exception -> Le8
            java.lang.String r5 = "symbol"
            java.lang.Object r4 = r7.jpath(r4, r5)     // Catch: java.lang.Exception -> Le8
            boolean r5 = r1 instanceof java.lang.String     // Catch: java.lang.Exception -> Le8
            if (r5 == 0) goto Le5
            boolean r5 = r3 instanceof java.lang.String     // Catch: java.lang.Exception -> Le8
            if (r5 == 0) goto Le5
            java.lang.String r1 = (java.lang.String) r1     // Catch: java.lang.Exception -> Le8
            java.lang.String r3 = (java.lang.String) r3     // Catch: java.lang.Exception -> Le8
            boolean r5 = r4 instanceof java.lang.String     // Catch: java.lang.Exception -> Le8
            if (r5 == 0) goto Ldc
            java.lang.String r4 = (java.lang.String) r4     // Catch: java.lang.Exception -> Le8
            goto Lde
        Ldc:
            java.lang.String r4 = ""
        Lde:
            java.lang.String[] r1 = new java.lang.String[]{r1, r3, r4}     // Catch: java.lang.Exception -> Le8
            r0.add(r1)     // Catch: java.lang.Exception -> Le8
        Le5:
            int r2 = r2 + 1
            goto L9e
        Le8:
            return r0
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.Engine.candidates(java.lang.String):java.util.ArrayList");
    }

    public ArrayList<String[]> candidatesFromAddress(String str) {
        ArrayList<String[]> arrayList = new ArrayList<>();
        if (str != null && str.trim().length() != 0) {
            int i = 0;
            while (true) {
                String[] strArr = this.KNOWN_IDS;
                if (i >= strArr.length) {
                    break;
                }
                try {
                    if (anyFormOk(parseDraft(known(strArr[i])[4]), str.trim())) {
                        String[] known = known(this.KNOWN_IDS[i]);
                        arrayList.add(new String[]{this.KNOWN_IDS[i], known[0], known[1]});
                    }
                } catch (Exception unused) {
                }
                i++;
            }
        }
        return arrayList;
    }

    public String priceUsd(String str) {
        try {
            String[] http = http("GET", this.coingeckoBase + "/simple/price?ids=" + URLEncoder.encode(str, "UTF-8") + "&vs_currencies=usd", null, 20);
            if (!http[0].startsWith("2")) {
                return null;
            }
            Object jpath = jpath(jparse(http[1]), str + ".usd");
            if (jpath instanceof BigDecimal) {
                return ((BigDecimal) jpath).toPlainString();
            }
            return null;
        } catch (Exception unused) {
            return null;
        }
    }

    public String draftFor(String[] strArr, String str, ArrayList<Probe> arrayList) {
        int i = 0;
        String replaceAll = strArr[0].toLowerCase().replaceAll("[^a-z0-9_-]", "-");
        if (replaceAll.length() > 32) {
            replaceAll = replaceAll.substring(0, 32);
        }
        String[] known = known(strArr[0]);
        StringBuilder sb = new StringBuilder("# ANA lesson draft. Edit anything you like, then press Build & Sign.\n# Lines starting with # are ignored. A value of ? means you still have to fill it in.\n\nlesson/id = ");
        sb.append(replaceAll);
        sb.append("\nlesson/version = 1\nlesson/needs_reader = 1\n\ncoin/name = ");
        sb.append(known != null ? known[0] : strArr[1]);
        sb.append("\ncoin/ticker = ");
        sb.append(known != null ? known[1] : strArr[2].toUpperCase());
        sb.append("\ncoin/decimals = ");
        sb.append(known != null ? known[2] : "?");
        sb.append("\ncoin/display_decimals = ");
        sb.append(known != null ? known[3] : "4");
        sb.append("\ncoin/price_id = ");
        sb.append(strArr[0]);
        sb.append("\n\n");
        sb.append(known != null ? known[4] : learnForm(str));
        sb.append("\n");
        ArrayList arrayList2 = new ArrayList();
        String str2 = "";
        String str3 = "?";
        for (int i2 = 0; i2 < arrayList.size(); i2++) {
            Probe probe = arrayList.get(i2);
            if (str3.equals("?")) {
                str3 = probe.reader;
                str2 = probe.params;
            }
            if (probe.reader.equals(str3) && !arrayList2.contains(probe.url)) {
                arrayList2.add(probe.url);
            }
        }
        sb.append("reader/name = ");
        sb.append(str3);
        sb.append("\n");
        if (arrayList2.isEmpty()) {
            sb.append("server/1 = ?\n");
        } else {
            while (i < arrayList2.size()) {
                sb.append("server/");
                int i3 = i + 1;
                sb.append(i3);
                sb.append(" = ");
                sb.append((String) arrayList2.get(i));
                sb.append("\n");
                i = i3;
            }
        }
        LinkedHashMap<String, String> params = params(str2);
        for (String str4 : params.keySet()) {
            sb.append("param/");
            sb.append(str4);
            sb.append(" = ");
            sb.append(params.get(str4));
            sb.append("\n");
        }
        sb.append("\n");
        if (str != null && str.trim().length() > 0) {
            String trim = str.trim();
            sb.append("test/good.1 = ");
            sb.append(trim);
            sb.append("\ntest/bad.1 = ");
            sb.append(mutateBad(trim));
            sb.append("\ntest/probe_address = ");
            sb.append(trim);
            sb.append("\n");
        } else {
            sb.append("test/good.1 = ?\ntest/bad.1 = ?\n");
        }
        return sb.toString();
    }
}
