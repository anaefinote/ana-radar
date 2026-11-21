package com.novera.ana;

import android.content.Context;
import android.graphics.Bitmap;
import com.novera.ana.Wallets;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/* loaded from: classes.dex */
final class Witness {
    static final int CLS = 22;
    static final String[] FIELDS = {"version", "coin", "address", "direction", "units", "amount", "txid", "block_time", "notified_ms", "app", "via", "party", "note"};

    private Witness() {
    }

    static File dir(Context context) {
        return new File(context.getFilesDir(), "proofs");
    }

    static String fileName(Wallets.Wallet wallet) {
        String optString = wallet.proofDetail.optString("txid");
        if (optString.isEmpty()) {
            return null;
        }
        return "proof_" + wallet.proofDetail.optString("coin", "COIN") + "_" + optString.substring(0, Math.min(12, optString.length())) + ".pngmesh";
    }

    static boolean exists(Context context, Wallets.Wallet wallet) {
        String fileName = fileName(wallet);
        return fileName == null || context == null || new File(dir(context), fileName).exists();
    }

    static String save(Context context, Wallets.Wallet wallet) {
        String fileName = fileName(wallet);
        if (fileName != null && context != null) {
            try {
                byte[][] signRaw = Flex.signRaw("probe".getBytes(StandardCharsets.UTF_8));
                if (signRaw == null) {
                    return null;
                }
                ArrayList arrayList = new ArrayList();
                for (String str : FIELDS) {
                    arrayList.add(new String[]{"proof", str, str.equals("version") ? "1" : wallet.proofDetail.optString(str)});
                }
                arrayList.add(new String[]{"phone", "key", hex(signRaw[0])});
                arrayList.add(new String[]{"sig", "key_id", hex(MessageDigest.getInstance("SHA-256").digest(signRaw[0]))});
                byte[] trailerPrefix = trailerPrefix(arrayList, arrayList.size() + 1);
                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                byteArrayOutputStream.write("ANA-PMSH1|22|".getBytes(StandardCharsets.US_ASCII));
                byteArrayOutputStream.write(MessageDigest.getInstance("SHA-256").digest(trailerPrefix));
                byte[][] signRaw2 = Flex.signRaw(byteArrayOutputStream.toByteArray());
                if (signRaw2 != null && Arrays.equals(signRaw2[0], signRaw[0])) {
                    ByteArrayOutputStream byteArrayOutputStream2 = new ByteArrayOutputStream();
                    byteArrayOutputStream2.write(trailerPrefix);
                    DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream2);
                    str(dataOutputStream, "sig");
                    str(dataOutputStream, "value");
                    str(dataOutputStream, hex(signRaw2[1]));
                    dataOutputStream.flush();
                    byte[] byteArray = byteArrayOutputStream2.toByteArray();
                    ArrayList arrayList2 = new ArrayList();
                    arrayList2.add(new String[]{"WATCH", Wallets.when(System.currentTimeMillis() / 1000.0d), "", "ana.watch", "Ownership proven", wallet.proofDetail.optString("note")});
                    ByteArrayOutputStream byteArrayOutputStream3 = new ByteArrayOutputStream();
                    AnaMesh.preview(arrayList2, "ANA ownership witness").compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream3);
                    byteArrayOutputStream3.write(byteArray);
                    DataOutputStream dataOutputStream2 = new DataOutputStream(byteArrayOutputStream3);
                    dataOutputStream2.writeLong(byteArray.length);
                    dataOutputStream2.flush();
                    byte[] byteArray2 = byteArrayOutputStream3.toByteArray();
                    File dir = dir(context);
                    if (!dir.exists() && !dir.mkdirs()) {
                        return null;
                    }
                    FileOutputStream fileOutputStream = new FileOutputStream(new File(dir, fileName));
                    try {
                        fileOutputStream.write(byteArray2);
                        fileOutputStream.close();
                        fileOutputStream = new FileOutputStream(new File(dir, fileName.substring(0, fileName.length() - 8) + ".sha256"));
                        try {
                            fileOutputStream.write(AnaMesh.sidecar(fileName, byteArray2).getBytes(StandardCharsets.UTF_8));
                            fileOutputStream.close();
                            return fileName;
                        } finally {
                        }
                    } finally {
                    }
                }
            } catch (Exception unused) {
            }
        }
        return null;
    }

    static byte[] trailerPrefix(List<String[]> list, int i) throws Exception {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream);
        dataOutputStream.write("PMSH".getBytes(StandardCharsets.US_ASCII));
        dataOutputStream.writeInt(1);
        dataOutputStream.writeInt(1);
        dataOutputStream.writeInt(CLS);
        dataOutputStream.writeInt(3);
        str(dataOutputStream, "section");
        str(dataOutputStream, "key");
        str(dataOutputStream, "value");
        dataOutputStream.writeInt(i);
        for (String[] strArr : list) {
            for (String str : strArr) {
                str(dataOutputStream, str);
            }
        }
        dataOutputStream.flush();
        return byteArrayOutputStream.toByteArray();
    }

    private static void str(DataOutputStream dataOutputStream, String str) throws Exception {
        byte[] bytes = str.getBytes(StandardCharsets.UTF_8);
        dataOutputStream.writeInt(bytes.length);
        dataOutputStream.write(bytes);
    }

    static String hex(byte[] bArr) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bArr) {
            sb.append(String.format("%02x", Byte.valueOf(b)));
        }
        return sb.toString();
    }
}
