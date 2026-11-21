package com.novera.ana;

import android.security.keystore.KeyGenParameterSpec;
import android.util.Base64;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;

/* loaded from: classes.dex */
final class Flex {
    private static final String ALIAS = "ana_flex_sign";

    Flex() {
    }

    private static synchronized KeyStore.PrivateKeyEntry entry() throws Exception {
        KeyStore.PrivateKeyEntry privateKeyEntry;
        synchronized (Flex.class) {
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
            keyStore.load(null);
            if (!keyStore.containsAlias(ALIAS)) {
                KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance("EC", "AndroidKeyStore");
                keyPairGenerator.initialize(new KeyGenParameterSpec.Builder(ALIAS, 12).setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1")).setDigests("SHA-256").build());
                keyPairGenerator.generateKeyPair();
            }
            privateKeyEntry = (KeyStore.PrivateKeyEntry) keyStore.getEntry(ALIAS, null);
        }
        return privateKeyEntry;
    }

    static String publicKey() {
        try {
            return Base64.encodeToString(entry().getCertificate().getPublicKey().getEncoded(), 2);
        } catch (Exception unused) {
            return "";
        }
    }

    static String sign(String str) {
        try {
            PrivateKey privateKey = entry().getPrivateKey();
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(privateKey);
            signature.update(str.getBytes(StandardCharsets.UTF_8));
            return Base64.encodeToString(signature.sign(), 2);
        } catch (Exception unused) {
            return "";
        }
    }

    static boolean verify(String str, String str2, String str3) {
        try {
            PublicKey generatePublic = KeyFactory.getInstance("EC").generatePublic(new X509EncodedKeySpec(Base64.decode(str, 2)));
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initVerify(generatePublic);
            signature.update(str2.getBytes(StandardCharsets.UTF_8));
            return signature.verify(Base64.decode(str3, 2));
        } catch (Exception unused) {
            return false;
        }
    }

    static byte[][] signRaw(byte[] bArr) {
        try {
            KeyStore.PrivateKeyEntry entry = entry();
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(entry.getPrivateKey());
            signature.update(bArr);
            byte[] derToRawLowS = derToRawLowS(signature.sign());
            byte[] encoded = entry.getCertificate().getPublicKey().getEncoded();
            byte[] copyOfRange = Arrays.copyOfRange(encoded, encoded.length - 65, encoded.length);
            if (copyOfRange[0] != 4) {
                return null;
            }
            return new byte[][]{copyOfRange, derToRawLowS};
        } catch (Exception unused) {
            return null;
        }
    }

    static byte[] derToRawLowS(byte[] bArr) {
        byte b = bArr[1];
        int i = (b & 128) != 0 ? (b & Byte.MAX_VALUE) + 2 : 2;
        byte b2 = bArr[i + 1];
        int i2 = i + 2;
        int i3 = b2 + i2;
        BigInteger bigInteger = new BigInteger(1, Arrays.copyOfRange(bArr, i2, i3));
        byte b3 = bArr[i3 + 1];
        int i4 = i3 + 2;
        BigInteger bigInteger2 = new BigInteger(1, Arrays.copyOfRange(bArr, i4, b3 + i4));
        BigInteger bigInteger3 = new BigInteger("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16);
        if (bigInteger2.compareTo(bigInteger3.shiftRight(1)) > 0) {
            bigInteger2 = bigInteger3.subtract(bigInteger2);
        }
        byte[] bArr2 = new byte[64];
        put32(bArr2, 0, bigInteger);
        put32(bArr2, 32, bigInteger2);
        return bArr2;
    }

    private static void put32(byte[] bArr, int i, BigInteger bigInteger) {
        byte[] byteArray = bigInteger.toByteArray();
        int min = Math.min(byteArray.length, 32);
        System.arraycopy(byteArray, byteArray.length - min, bArr, (i + 32) - min, min);
    }

    static String sha256(String str) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(str.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", Byte.valueOf(b)));
            }
            return sb.toString();
        } catch (Exception unused) {
            return "";
        }
    }
}
