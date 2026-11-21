package com.novera.ana;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.text.TextPaint;
import android.text.TextUtils;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

/* loaded from: classes.dex */
final class AnaMesh {
    static final int CLASS_ANA_ENTRIES = 20;
    static final int CLASS_GST = 21;
    private static final int MAX_DRAWN = 40;
    static final int VERSION = 1;
    static final String[] COLS = {"src", "when", "postMs", "package", "title", "text", "key", "lagMs", "eventMs"};
    static final String[] GST_COLS = {"id", "kind", "group", "from", "fromName", "when", "a", "b", "c", "d"};
    private static final int BG = Color.rgb(14, 22, 33);
    private static final int CARD = Color.rgb(24, 33, 45);
    private static final int CARD_E = Color.rgb(22, 50, 74);
    private static final int INK = Color.rgb(232, 238, 245);
    private static final int MUTE = Color.rgb(143, 163, 184);
    private static final int DIM = Color.rgb(95, 115, 136);
    private static final int BODY = Color.rgb(185, 199, 214);

    private AnaMesh() {
    }

    static byte[] write(List<String[]> list) throws IOException {
        return write(CLASS_ANA_ENTRIES, COLS, list, list, null);
    }

    static byte[] writeGst(List<String[]> list, List<String[]> list2, String str) throws IOException {
        return write(CLASS_GST, GST_COLS, list, list2, str);
    }

    private static byte[] write(int i, String[] strArr, List<String[]> list, List<String[]> list2, String str) throws IOException {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        Bitmap preview = preview(list2, str);
        preview.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream);
        preview.recycle();
        ByteArrayOutputStream byteArrayOutputStream2 = new ByteArrayOutputStream();
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream2);
        dataOutputStream.writeBytes("PMSH");
        dataOutputStream.writeInt(VERSION);
        dataOutputStream.writeInt(VERSION);
        dataOutputStream.writeInt(i);
        dataOutputStream.writeInt(strArr.length);
        int length = strArr.length;
        for (int i2 = 0; i2 < length; i2 += VERSION) {
            str(dataOutputStream, strArr[i2]);
        }
        dataOutputStream.writeInt(list.size());
        for (String[] strArr2 : list) {
            int i3 = 0;
            while (i3 < strArr.length) {
                str(dataOutputStream, i3 < strArr2.length ? strArr2[i3] : "");
                i3 += VERSION;
            }
        }
        dataOutputStream.flush();
        byteArrayOutputStream.write(byteArrayOutputStream2.toByteArray());
        DataOutputStream dataOutputStream2 = new DataOutputStream(byteArrayOutputStream);
        dataOutputStream2.writeLong(r4.length);
        dataOutputStream2.flush();
        return byteArrayOutputStream.toByteArray();
    }

    private static void str(DataOutputStream dataOutputStream, String str) throws IOException {
        if (str == null) {
            str = "";
        }
        byte[] bytes = str.getBytes(StandardCharsets.UTF_8);
        dataOutputStream.writeInt(bytes.length);
        dataOutputStream.write(bytes);
    }

    static String sidecar(String str, byte[] bArr) {
        return sha256(bArr) + "\n" + str + "\n" + bArr.length + "\n";
    }

    static List<String[]> read(byte[] bArr) throws IOException {
        return read(bArr, CLASS_ANA_ENTRIES, COLS);
    }

    static List<String[]> readGst(byte[] bArr) throws IOException {
        return read(bArr, CLASS_GST, GST_COLS);
    }

    static int classOf(byte[] bArr) {
        try {
            long readLong = new DataInputStream(new ByteArrayInputStream(bArr, bArr.length - 8, 8)).readLong();
            long length = (bArr.length - 8) - readLong;
            if (readLong >= 16 && length >= 0) {
                DataInputStream dataInputStream = new DataInputStream(new ByteArrayInputStream(bArr, (int) length, (int) readLong));
                dataInputStream.skipBytes(12);
                return dataInputStream.readInt();
            }
        } catch (Exception unused) {
        }
        return -1;
    }

    private static List<String[]> read(byte[] bArr, int i, String[] strArr) throws IOException {
        String str;
        int length = bArr.length;
        int i2 = CLASS_ANA_ENTRIES;
        if (length < CLASS_ANA_ENTRIES) {
            throw new IOException("too small to be a .pngmesh");
        }
        long readLong = new DataInputStream(new ByteArrayInputStream(bArr, bArr.length - 8, 8)).readLong();
        long length2 = (bArr.length - 8) - readLong;
        if (readLong < 12 || length2 < 0) {
            throw new IOException("no pngmesh trailer");
        }
        DataInputStream dataInputStream = new DataInputStream(new ByteArrayInputStream(bArr, (int) length2, (int) readLong));
        byte[] bArr2 = new byte[4];
        dataInputStream.readFully(bArr2);
        int i3 = 0;
        if (bArr2[0] == 80 && bArr2[VERSION] == 77 && bArr2[2] == 83) {
            int i4 = 3;
            if (bArr2[3] == 72) {
                int readInt = dataInputStream.readInt();
                if (readInt != VERSION) {
                    throw new IOException("pngmesh version " + readInt + " is newer than this ANA");
                }
                int readInt2 = dataInputStream.readInt();
                ArrayList arrayList = new ArrayList();
                int i5 = 0;
                while (i5 < readInt2) {
                    int readInt3 = dataInputStream.readInt();
                    if (readInt3 == i4) {
                        throw new IOException("this .pngmesh holds a 3D shape, not ANA entries");
                    }
                    if (readInt3 != i) {
                        if (readInt3 == CLASS_GST) {
                            str = "this .pngmesh is a GST file";
                        } else if (readInt3 == i2) {
                            str = "this .pngmesh holds log entries, not GST";
                        } else {
                            str = "unknown pngmesh part class " + readInt3;
                        }
                        throw new IOException(str);
                    }
                    int readInt4 = dataInputStream.readInt();
                    String[] strArr2 = new String[readInt4];
                    for (int i6 = i3; i6 < readInt4; i6 += VERSION) {
                        strArr2[i6] = rstr(dataInputStream);
                    }
                    int readInt5 = dataInputStream.readInt();
                    int i7 = i3;
                    while (i7 < readInt5) {
                        String[] strArr3 = new String[readInt4];
                        for (int i8 = i3; i8 < readInt4; i8 += VERSION) {
                            strArr3[i8] = rstr(dataInputStream);
                        }
                        String[] strArr4 = new String[strArr.length];
                        int i9 = i3;
                        while (i9 < strArr.length) {
                            strArr4[i9] = "";
                            for (int i10 = i3; i10 < readInt4; i10 += VERSION) {
                                if (strArr[i9].equals(strArr2[i10])) {
                                    strArr4[i9] = strArr3[i10];
                                }
                            }
                            i9 += VERSION;
                            i3 = 0;
                        }
                        arrayList.add(strArr4);
                        i7 += VERSION;
                        i3 = 0;
                    }
                    i5 += VERSION;
                    i2 = CLASS_ANA_ENTRIES;
                    i3 = 0;
                    i4 = 3;
                }
                return arrayList;
            }
        }
        throw new IOException("not a pngmesh trailer");
    }

    private static String rstr(DataInputStream dataInputStream) throws IOException {
        int readInt = dataInputStream.readInt();
        if (readInt < 0 || readInt > 16777216) {
            throw new IOException("damaged string in pngmesh");
        }
        byte[] bArr = new byte[readInt];
        dataInputStream.readFully(bArr);
        return new String(bArr, StandardCharsets.UTF_8);
    }

    static boolean looksLikePngmesh(byte[] bArr) {
        if (bArr.length < CLASS_ANA_ENTRIES) {
            return false;
        }
        try {
            long readLong = new DataInputStream(new ByteArrayInputStream(bArr, bArr.length - 8, 8)).readLong();
            long length = (bArr.length - 8) - readLong;
            if (readLong < 12 || length < 0) {
                return false;
            }
            int i = (int) length;
            if (bArr[i] == 80 && bArr[i + VERSION] == 77 && bArr[i + 2] == 83) {
                return bArr[i + 3] == 72;
            }
            return false;
        } catch (IOException unused) {
            return false;
        }
    }

    static String sidecarHash(byte[] bArr) {
        if (bArr.length > 4096) {
            return null;
        }
        String str = new String(bArr, StandardCharsets.UTF_8);
        int indexOf = str.indexOf(10);
        if (indexOf >= 0) {
            str = str.substring(0, indexOf);
        }
        String lowerCase = str.trim().toLowerCase();
        if (lowerCase.matches("[0-9a-f]{64}")) {
            return lowerCase;
        }
        return null;
    }

    static String sha256(byte[] bArr) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bArr);
            StringBuilder sb = new StringBuilder();
            int length = digest.length;
            for (int i = 0; i < length; i += VERSION) {
                sb.append(String.format("%02x", Integer.valueOf(digest[i] & 255)));
            }
            return sb.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    static Bitmap preview(List<String[]> list) {
        return preview(list, null);
    }

    static Bitmap preview(List<String[]> list, String str) {
        String str2;
        int min = Math.min(list.size(), MAX_DRAWN);
        float f = 270.0f;
        float f2 = 157.5f;
        float f3 = (min * 270.0f) + 157.5f;
        Bitmap createBitmap = Bitmap.createBitmap(1080, (int) ((list.size() > min ? 90.0f : 0.0f) + f3 + 22.5f), Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(createBitmap);
        canvas.drawColor(BG);
        Paint paint = new Paint(VERSION);
        TextPaint textPaint = new TextPaint(VERSION);
        textPaint.setTypeface(Typeface.DEFAULT);
        textPaint.setColor(INK);
        textPaint.setTextSize(54.0f);
        String str3 = "ANA";
        if (str != null && !str.startsWith("ANA")) {
            str3 = "GST";
        }
        canvas.drawText(str3, 31.5f, 76.5f, textPaint);
        textPaint.setColor(MUTE);
        float f4 = 29.25f;
        textPaint.setTextSize(29.25f);
        if (str != null) {
            str2 = str + "  ·  .pngmesh  ·  check with its .sha256";
        } else {
            str2 = list.size() + " entr" + (list.size() == VERSION ? "y" : "ies") + "  ·  .pngmesh  ·  check with its .sha256";
        }
        canvas.drawText(str2, 166.5f, 72.0f, textPaint);
        int i = 0;
        while (i < min) {
            String[] strArr = list.get(i);
            float f5 = f2 + (i * f);
            String str4 = strArr[3];
            String str5 = strArr[4];
            String str6 = strArr[5];
            StringBuilder sb = new StringBuilder();
            sb.append(str4);
            sb.append(" ");
            sb.append(str5);
            sb.append(" ");
            sb.append(str6);
            paint.setColor(sb.toString().toLowerCase().contains("ether") ? CARD_E : CARD);
            float f6 = (f5 + f) - 18.0f;
            TextPaint textPaint2 = textPaint;
            canvas.drawRect(27.0f, f5, 1053.0f, f6, paint);
            paint.setColor(tagColor(strArr[0]));
            canvas.drawRect(27.0f, f5, 40.5f, f6, paint);
            textPaint2.setTextSize(29.25f);
            textPaint2.setColor(tagColor(strArr[0]));
            float f7 = f5 + 47.25f;
            canvas.drawText(strArr[0], 63.0f, f7, textPaint2);
            textPaint2.setColor(MUTE);
            canvas.drawText(strArr[VERSION], 409.5f, f7, textPaint2);
            textPaint2.setTextSize(27.0f);
            textPaint2.setColor(DIM);
            canvas.drawText(fit(strArr[3], textPaint2, 972.0f), 63.0f, f5 + 90.0f, textPaint2);
            textPaint2.setTextSize(33.75f);
            textPaint2.setColor(INK);
            canvas.drawText(fit(strArr[4], textPaint2, 972.0f), 63.0f, f5 + 137.25f, textPaint2);
            textPaint2.setTextSize(29.25f);
            textPaint2.setColor(BODY);
            canvas.drawText(fit(strArr[5], textPaint2, 972.0f), 63.0f, f5 + 189.0f, textPaint2);
            f4 = 29.25f;
            i += VERSION;
            textPaint = textPaint2;
            f = 270.0f;
            f2 = 157.5f;
        }
        float f8 = f4;
        TextPaint textPaint3 = textPaint;
        if (list.size() > min) {
            textPaint3.setTextSize(f8);
            textPaint3.setColor(MUTE);
            canvas.drawText("+ " + (list.size() - min) + " more in the file", 31.5f, f3 + 58.5f, textPaint3);
        }
        return createBitmap;
    }

    private static String fit(String str, TextPaint textPaint, float f) {
        if (str == null) {
            str = "";
        }
        return TextUtils.ellipsize(str, textPaint, f, TextUtils.TruncateAt.END).toString();
    }

    private static int tagColor(String str) {
        return "LIVE".equals(str) ? Color.rgb(61, 220, 151) : "SCAN".equals(str) ? Color.rgb(77, 163, 255) : "MANUAL".equals(str) ? Color.rgb(245, 185, 66) : "GST".equals(str) ? Color.rgb(61, 220, 151) : "IMPORT".equals(str) ? Color.rgb(180, 140, 255) : Color.rgb(122, 139, 160);
    }
}
