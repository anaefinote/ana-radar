package com.novera.ana;

import android.app.Notification;
import android.content.ComponentName;
import android.content.Context;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

/* loaded from: classes.dex */
public class AnaListener extends NotificationListenerService {
    static volatile AnaListener instance;

    @Override // android.service.notification.NotificationListenerService
    public void onListenerConnected() {
        instance = this;
        long currentTimeMillis = System.currentTimeMillis();
        AnaLog.append(this, "SYS", currentTimeMillis, getPackageName(), "Listener connected", "", "sys-" + currentTimeMillis, 0L);
        MainActivity.poke();
    }

    @Override // android.service.notification.NotificationListenerService
    public void onListenerDisconnected() {
        instance = null;
        long currentTimeMillis = System.currentTimeMillis();
        AnaLog.append(this, "SYS", currentTimeMillis, getPackageName(), "Listener disconnected", "", "sys-" + currentTimeMillis, 0L);
        MainActivity.poke();
        requestRebind(new ComponentName(this, (Class<?>) AnaListener.class));
    }

    @Override // android.service.notification.NotificationListenerService
    public void onNotificationPosted(StatusBarNotification statusBarNotification) {
        if (statusBarNotification == null || getPackageName().equals(statusBarNotification.getPackageName())) {
            return;
        }
        record(this, "LIVE", statusBarNotification);
        MainActivity.poke();
        if ("com.wallet.crypto.trustapp".equals(statusBarNotification.getPackageName())) {
            Wallets.refreshAll(this);
        }
        BillsUi.onNotification(this);
    }

    static int clear(String str) {
        AnaListener anaListener = instance;
        if (anaListener == null) {
            return -1;
        }
        try {
            StatusBarNotification[] activeNotifications = anaListener.getActiveNotifications();
            if (activeNotifications == null) {
                return 0;
            }
            int i = 0;
            for (StatusBarNotification statusBarNotification : activeNotifications) {
                if (statusBarNotification != null && str.equals(statusBarNotification.getPackageName()) && statusBarNotification.isClearable()) {
                    anaListener.cancelNotification(statusBarNotification.getKey());
                    i++;
                }
            }
            return i;
        } catch (SecurityException unused) {
            return -1;
        }
    }

    static int scan(Context context) {
        AnaListener anaListener = instance;
        int i = -1;
        if (anaListener == null) {
            return -1;
        }
        try {
            StatusBarNotification[] activeNotifications = anaListener.getActiveNotifications();
            i = 0;
            if (activeNotifications != null) {
                int length = activeNotifications.length;
                int i2 = 0;
                while (i < length) {
                    StatusBarNotification statusBarNotification = activeNotifications[i];
                    if (statusBarNotification != null && !context.getPackageName().equals(statusBarNotification.getPackageName())) {
                        record(context, "SCAN", statusBarNotification);
                        i2++;
                    }
                    i++;
                }
                i = i2;
            }
            MainActivity.poke();
        } catch (SecurityException unused) {
        }
        return i;
    }

    static void record(Context context, String str, StatusBarNotification statusBarNotification) {
        String str2;
        String str3;
        if ("0".equals(context.getSharedPreferences("ana", 0).getString("p_capture", "1"))) {
            return;
        }
        Notification notification = statusBarNotification.getNotification();
        Bundle bundle = notification != null ? notification.extras : null;
        if (bundle == null) {
            str2 = "";
            str3 = str2;
        } else {
            String clean = AnaLog.clean(bundle.getCharSequence("android.title"));
            String clean2 = AnaLog.clean(bundle.getCharSequence("android.text"));
            String clean3 = AnaLog.clean(bundle.getCharSequence("android.bigText"));
            if (clean3.length() > clean2.length()) {
                clean2 = clean3;
            }
            CharSequence[] charSequenceArray = bundle.getCharSequenceArray("android.textLines");
            if (charSequenceArray != null) {
                for (CharSequence charSequence : charSequenceArray) {
                    clean2 = clean2 + " / " + AnaLog.clean(charSequence);
                }
            }
            String clean4 = AnaLog.clean(bundle.getCharSequence("android.subText"));
            if (clean4.length() > 0) {
                str3 = clean2 + " [" + clean4 + "]";
                str2 = clean;
            } else {
                str2 = clean;
                str3 = clean2;
            }
        }
        long currentTimeMillis = System.currentTimeMillis() - statusBarNotification.getPostTime();
        long j = notification != null ? notification.when : 0L;
        AnaLog.append(context, str, statusBarNotification.getPostTime(), statusBarNotification.getPackageName(), str2, str3, statusBarNotification.getKey(), currentTimeMillis, (j <= 0 || Math.abs(j - statusBarNotification.getPostTime()) < 60000) ? 0L : j);
    }
}
