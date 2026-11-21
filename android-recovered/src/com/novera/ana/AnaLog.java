package com.novera.ana;

import android.content.Context;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;

/* loaded from: classes.dex */
final class AnaLog {
    static final String FILE = "ana_log.txt";
    static final String HEADER = "#src\twhen\tpostMs\tpackage\ttitle\ttext\tkey\tlagMs\teventMs";

    private AnaLog() {
    }

    static String clean(CharSequence charSequence) {
        if (charSequence == null) {
            return "";
        }
        return charSequence.toString().replace('\t', ' ').replace("\r", " ").replace("\n", " / ").replace("\u2028", " / ").replace("\u2029", " / ").replace("\u000b", " / ").replace("\f", " / ").replace("\u0085", " / ").trim();
    }

    static void append(Context context, String str, long j, String str2, String str3, String str4, String str5, long j2) {
        append(context, str, j, str2, str3, str4, str5, j2, 0L);
    }

    static synchronized void append(Context context, String str, long j, String str2, String str3, String str4, String str5, long j2, long j3) {
        synchronized (AnaLog.class) {
            String format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date(j));
            StringBuilder sb = new StringBuilder();
            if (!new File(context.getFilesDir(), FILE).exists()) {
                sb.append("#src\twhen\tpostMs\tpackage\ttitle\ttext\tkey\tlagMs\teventMs\n");
            }
            sb.append(clean(str));
            sb.append('\t');
            sb.append(format);
            sb.append('\t');
            sb.append(j);
            sb.append('\t');
            sb.append(clean(str2));
            sb.append('\t');
            sb.append(clean(str3));
            sb.append('\t');
            sb.append(clean(str4));
            sb.append('\t');
            sb.append(clean(str5));
            sb.append('\t');
            sb.append(j2);
            sb.append('\t');
            sb.append(j3);
            sb.append('\n');
            try {
                FileOutputStream openFileOutput = context.openFileOutput(FILE, 32768);
                try {
                    openFileOutput.write(sb.toString().getBytes(StandardCharsets.UTF_8));
                    if (openFileOutput != null) {
                        openFileOutput.close();
                    }
                } finally {
                }
            } catch (IOException unused) {
            }
        }
    }

    static synchronized int prune(Context context, int i) {
        FileOutputStream openFileOutput;
        long j;
        synchronized (AnaLog.class) {
            if (i <= 0) {
                return 0;
            }
            if (!new File(context.getFilesDir(), FILE).exists()) {
                return 0;
            }
            long currentTimeMillis = System.currentTimeMillis() - (i * 86400000);
            StringBuilder sb = new StringBuilder(HEADER);
            sb.append('\n');
            int i2 = 0;
            for (String str : readAll(context)) {
                String[] split = str.split("\t", -1);
                try {
                    j = Long.parseLong(split.length > 2 ? split[2] : "0");
                } catch (NumberFormatException unused) {
                    j = 0;
                }
                if (j <= 0 || j >= currentTimeMillis) {
                    sb.append(str);
                    sb.append('\n');
                } else {
                    i2++;
                }
            }
            if (i2 == 0) {
                return 0;
            }
            try {
                openFileOutput = context.openFileOutput(FILE, 0);
            } catch (IOException unused2) {
            }
            try {
                openFileOutput.write(sb.toString().getBytes(StandardCharsets.UTF_8));
                if (openFileOutput != null) {
                    openFileOutput.close();
                }
                return i2;
            } catch (Throwable th) {
                if (openFileOutput != null) {
                    try {
                        openFileOutput.close();
                    } catch (Throwable th2) {
                        th.addSuppressed(th2);
                    }
                }
                throw th;
            }
        }
    }

    static synchronized List<String> readAll(Context context) {
        synchronized (AnaLog.class) {
            ArrayList arrayList = new ArrayList();
            File file = new File(context.getFilesDir(), FILE);
            if (!file.exists()) {
                return arrayList;
            }
            try {
                BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8));
                while (true) {
                    try {
                        String readLine = bufferedReader.readLine();
                        if (readLine == null) {
                            break;
                        }
                        if (readLine.length() != 0 && readLine.charAt(0) != '#') {
                            arrayList.add(readLine);
                        }
                    } catch (Throwable th) {
                        try {
                            bufferedReader.close();
                        } catch (Throwable th2) {
                            th.addSuppressed(th2);
                        }
                        throw th;
                    }
                }
                bufferedReader.close();
            } catch (IOException unused) {
            }
            return arrayList;
        }
    }

    static synchronized String readText(Context context) {
        String sb;
        synchronized (AnaLog.class) {
            StringBuilder sb2 = new StringBuilder(HEADER);
            sb2.append('\n');
            Iterator<String> it = readAll(context).iterator();
            while (it.hasNext()) {
                sb2.append(it.next());
                sb2.append('\n');
            }
            sb = sb2.toString();
        }
        return sb;
    }
}
