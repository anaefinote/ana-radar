package com.novera.ana;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileNotFoundException;

/* loaded from: classes.dex */
public class AnaFiles extends ContentProvider {
    @Override // android.content.ContentProvider
    public boolean onCreate() {
        return true;
    }

    static File dir(Context context) {
        File file = new File(context.getCacheDir(), "export");
        if (!file.exists()) {
            file.mkdirs();
        }
        return file;
    }

    static Uri uriFor(Context context, File file) {
        return Uri.parse("content://" + context.getPackageName() + ".files/" + Uri.encode(file.getName()));
    }

    private File fileFor(Uri uri) throws FileNotFoundException {
        String lastPathSegment = uri.getLastPathSegment();
        if (lastPathSegment == null || lastPathSegment.contains("/") || lastPathSegment.contains("..")) {
            throw new FileNotFoundException("bad name");
        }
        File file = new File(dir(getContext()), lastPathSegment);
        if (file.exists()) {
            return file;
        }
        throw new FileNotFoundException(lastPathSegment);
    }

    @Override // android.content.ContentProvider
    public ParcelFileDescriptor openFile(Uri uri, String str) throws FileNotFoundException {
        return ParcelFileDescriptor.open(fileFor(uri), 268435456);
    }

    @Override // android.content.ContentProvider
    public String getType(Uri uri) {
        uri.getLastPathSegment();
        return "application/octet-stream";
    }

    @Override // android.content.ContentProvider
    public Cursor query(Uri uri, String[] strArr, String str, String[] strArr2, String str2) {
        try {
            File fileFor = fileFor(uri);
            if (strArr == null) {
                strArr = new String[]{"_display_name", "_size"};
            }
            MatrixCursor matrixCursor = new MatrixCursor(strArr, 1);
            Object[] objArr = new Object[strArr.length];
            for (int i = 0; i < strArr.length; i++) {
                if ("_display_name".equals(strArr[i])) {
                    objArr[i] = fileFor.getName();
                } else if ("_size".equals(strArr[i])) {
                    objArr[i] = Long.valueOf(fileFor.length());
                }
            }
            matrixCursor.addRow(objArr);
            return matrixCursor;
        } catch (FileNotFoundException unused) {
            return null;
        }
    }

    @Override // android.content.ContentProvider
    public Uri insert(Uri uri, ContentValues contentValues) {
        throw new UnsupportedOperationException();
    }

    @Override // android.content.ContentProvider
    public int delete(Uri uri, String str, String[] strArr) {
        throw new UnsupportedOperationException();
    }

    @Override // android.content.ContentProvider
    public int update(Uri uri, ContentValues contentValues, String str, String[] strArr) {
        throw new UnsupportedOperationException();
    }
}
