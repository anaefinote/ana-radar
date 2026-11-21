package com.novera.ana;

import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.content.ClipData;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Parcelable;
import android.widget.DatePicker;
import android.widget.EditText;
import android.widget.LinearLayout;
import com.novera.ana.BillCore;
import com.novera.ana.Bills;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Objects;

/* loaded from: classes.dex */
final class BillsUi {
    static final int REQ_PIC = 43;
    static String picFor = "";

    interface Repeat {
        void picked(int i, String str);
    }

    private BillsUi() {
    }

    static void onNotification(final Context context) {
        new Thread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda7
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.lambda$onNotification$0(context);
            }
        }).start();
    }

    static /* synthetic */ void lambda$onNotification$0(Context context) {
        List<String> check = Bills.check(context);
        if (check.isEmpty()) {
            return;
        }
        MainActivity mainActivity = MainActivity.current;
        if (mainActivity != null) {
            Iterator<String> it = check.iterator();
            while (it.hasNext()) {
                mainActivity.toast(it.next());
            }
        }
        MainActivity.poke();
    }

    static void open(final MainActivity mainActivity) {
        if (!mainActivity.getSharedPreferences("ana", 0).getBoolean("bill_nomoney_ok", false)) {
            new AlertDialog.Builder(mainActivity).setTitle("Before you start: Novvera never touches money").setMessage("Novvera never touches money. Not yours, not your group's, not ever. ANA can't pay, hold, move, collect or send a single cent. You pay your billers yourself, in your own bank or biller app. ANA only keeps track, on your phone.\n\nWhen someone helps with your bill, they pay your biller directly, from their own bank or biller app. When you help, you do the same. Groups that pool money choose their own person to hold it. Never Novvera, never ANA.").setCancelable(false).setPositiveButton("I understand", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda54
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.lambda$open$1(MainActivity.this, dialogInterface, i);
                }
            }).setNegativeButton("Not now", (DialogInterface.OnClickListener) null).show();
        } else {
            Bills.load(mainActivity);
            new Thread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda55
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.lambda$open$3(MainActivity.this);
                }
            }).start();
        }
    }

    static /* synthetic */ void lambda$open$1(MainActivity mainActivity, DialogInterface dialogInterface, int i) {
        mainActivity.getSharedPreferences("ana", 0).edit().putBoolean("bill_nomoney_ok", true).apply();
        open(mainActivity);
    }

    static /* synthetic */ void lambda$open$3(final MainActivity mainActivity) {
        final List<String> check = Bills.check(mainActivity);
        mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda33
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.lambda$open$2(check, mainActivity);
            }
        });
    }

    static /* synthetic */ void lambda$open$2(List list, MainActivity mainActivity) {
        Iterator it = list.iterator();
        while (it.hasNext()) {
            mainActivity.toast((String) it.next());
        }
        showList(mainActivity);
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void showList(final MainActivity mainActivity) {
        ArrayList<Bills.Bill> arrayList = new ArrayList(Bills.list);
        ArrayList arrayList2 = new ArrayList();
        final ArrayList arrayList3 = new ArrayList();
        Bills.Goal goal = Bills.goal();
        arrayList2.add("Your 30-day settlement goal:  " + bar(goal.pct) + "  " + (goal.bills == 0 ? "add a bill to start" : goal.pct + "%"));
        arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda21
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.showGoal(MainActivity.this);
            }
        });
        if (Bills.passOn()) {
            arrayList2.add("You're 30 days ahead, and someone helped you get here. Pass it on");
            arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda22
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.invite(MainActivity.this, true);
                }
            });
        }
        for (final Bills.Bill bill : arrayList) {
            arrayList2.add(Bills.line(bill));
            arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda23
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.showBill(MainActivity.this, bill);
                }
            });
        }
        arrayList2.add("+  A bill coming up (settle it on time)");
        arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda24
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.newBill(MainActivity.this, "plan");
            }
        });
        arrayList2.add("+  A bill I already paid");
        arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda25
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.newBill(MainActivity.this, "paid");
            }
        });
        arrayList2.add("Import a bill, journey, receipt or thank-you...");
        Objects.requireNonNull(mainActivity);
        arrayList3.add(new BillsUi$$ExternalSyntheticLambda26(mainActivity));
        arrayList2.add("Tell someone about ANA");
        arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda27
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.invite(MainActivity.this, false);
            }
        });
        arrayList2.add("Novvera never touches money (read this)");
        arrayList3.add(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda28
            @Override // java.lang.Runnable
            public final void run() {
                new AlertDialog.Builder(r0).setTitle("Novvera never touches money").setMessage("Novvera never touches money. Not yours, not your group's, not ever. ANA can't pay, hold, move, collect or send a single cent. You pay your billers yourself, in your own bank or biller app. ANA only keeps track, on your phone.").setPositiveButton("OK", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda1
                    @Override // android.content.DialogInterface.OnClickListener
                    public final void onClick(DialogInterface dialogInterface, int i) {
                        BillsUi.showList(MainActivity.this);
                    }
                }).show();
            }
        });
        new AlertDialog.Builder(mainActivity).setTitle("Bills  ·  " + Bills.total() + " eFLEX earned").setItems((CharSequence[]) arrayList2.toArray(new String[0]), new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda29
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                ((Runnable) arrayList3.get(i)).run();
            }
        }).setNegativeButton("Close", (DialogInterface.OnClickListener) null).show();
    }

    static String bar(int i) {
        int i2 = 0;
        int max = Math.max(0, Math.min(10, i / 10));
        StringBuilder sb = new StringBuilder();
        while (i2 < 10) {
            sb.append(i2 < max ? "█" : "░");
            i2++;
        }
        return sb.toString();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void showGoal(final MainActivity mainActivity) {
        Bills.Goal goal = Bills.goal();
        StringBuilder sb = new StringBuilder("Have everything due in the next 30 days settled before it's due. Then this month's pay isn't paying this month's bills: you're off the payday cycle.\n\n");
        if (goal.bills == 0) {
            sb.append("Add your bills (light, water, phone, internet, TV ...) and they show here.");
        } else {
            sb.append(bar(goal.pct));
            sb.append("  ");
            sb.append(goal.pct);
            sb.append("%\n");
            sb.append(goal.pct >= 100 ? "You're there: everything due in the next 30 days is settled.\n" : "To go: " + BillCore.money(Math.max(0L, goal.total - goal.covered), "USD") + " of " + BillCore.money(goal.total, "USD") + " (in US dollars)\n");
            for (String str : goal.lines) {
                sb.append("\n");
                sb.append(str);
            }
            sb.append("\n\nTwo ways forward: settle a bill early, or set a little aside each day. And your people can step in: post your journey.");
        }
        AlertDialog.Builder negativeButton = new AlertDialog.Builder(mainActivity).setTitle("Your 30-day settlement goal").setMessage(sb.toString()).setNegativeButton("Back", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda11
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                BillsUi.showList(MainActivity.this);
            }
        });
        if (goal.bills > 0 && goal.pct < 100) {
            negativeButton.setPositiveButton("Post my journey", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda12
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.postJourney(MainActivity.this);
                }
            });
        }
        negativeButton.show();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void postJourney(final MainActivity mainActivity) {
        if (myName(mainActivity).isEmpty()) {
            askName(mainActivity, new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda13
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.postJourney(MainActivity.this);
                }
            });
        } else {
            new AlertDialog.Builder(mainActivity).setTitle("Post your journey").setMessage("It shows how far you are from 30 days ahead and which bills are left, so your people can step in. It goes only to who you send it to: a family chat, your church group, your GST group.\n\nShow the names of people who've helped you?").setPositiveButton("Show them", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda14
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.sendJourney(MainActivity.this, true);
                }
            }).setNegativeButton("Keep them private", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda15
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.sendJourney(MainActivity.this, false);
                }
            }).show();
        }
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void sendJourney(MainActivity mainActivity, boolean z) {
        try {
            send(mainActivity, Bills.shareJourney(mainActivity, myName(mainActivity), z), "My 30-day journey");
        } catch (Exception e) {
            mainActivity.toast("Couldn't make the file: " + e.getMessage());
        }
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void invite(MainActivity mainActivity, boolean z) {
        String concat = (z ? "Someone helped me get my bills 30 days ahead, so I'm passing it on. " : "").concat("I'm using ANA to get my bills settled before they're due and off the payday cycle. Friends and family can step in and help, and everybody who helps earns eFLEX. Novvera never touches money: you always pay your biller yourself. Ask me about it.");
        Intent intent = new Intent("android.intent.action.SEND");
        intent.setType("text/plain");
        intent.putExtra("android.intent.extra.TEXT", concat);
        mainActivity.startActivity(Intent.createChooser(intent, z ? "Pass it on" : "Tell someone about ANA"));
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* JADX WARN: Removed duplicated region for block: B:64:0x01b1  */
    /* JADX WARN: Removed duplicated region for block: B:66:0x01b4  */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    public static void showBill(final com.novera.ana.MainActivity r16, final com.novera.ana.Bills.Bill r17) {
        /*
            Method dump skipped, instructions count: 558
            To view this dump add '--comments-level debug' option
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.BillsUi.showBill(com.novera.ana.MainActivity, com.novera.ana.Bills$Bill):void");
    }

    static /* synthetic */ void lambda$showBill$18(MainActivity mainActivity, Bills.Bill bill, DialogInterface dialogInterface, int i) {
        Bills.remove(mainActivity, bill);
        MainActivity.poke();
    }

    static /* synthetic */ void lambda$showBill$21(MainActivity mainActivity) {
        List<String> check = Bills.check(mainActivity);
        mainActivity.toast(check.isEmpty() ? "No matching notification yet" : check.get(0));
        MainActivity.poke();
    }

    static /* synthetic */ void lambda$showBill$25(MainActivity mainActivity, Bills.Bill bill) {
        mainActivity.toast("Added: " + Bills.addSetAside(mainActivity, bill).name + ", daily. Tap it each day you set it aside.");
        MainActivity.poke();
    }

    static /* synthetic */ void lambda$showBill$28(MainActivity mainActivity, Bills.Bill bill, DialogInterface dialogInterface, int i) {
        Bills.remove(mainActivity, bill);
        MainActivity.poke();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void newBill(final MainActivity mainActivity, final String str) {
        LinearLayout linearLayout = new LinearLayout(mainActivity);
        linearLayout.setOrientation(1);
        int i = (int) (mainActivity.getResources().getDisplayMetrics().density * 20.0f);
        linearLayout.setPadding(i, i / 2, i, 0);
        final EditText field = field(mainActivity, linearLayout, "Bill (e.g. Light bill, Water, Phone)", 16385);
        final EditText field2 = field(mainActivity, linearLayout, "Amount (e.g. 125.00)", 8194);
        final EditText field3 = field(mainActivity, linearLayout, "Currency", 4097);
        field3.setText(mainActivity.getSharedPreferences("ana", 0).getString("bill_cur", "BBD"));
        new AlertDialog.Builder(mainActivity).setTitle(str.equals("plan") ? "A bill coming up" : "A bill I already paid").setMessage(str.equals("plan") ? "Pay it on or before the due date and it earns the most eFLEX." : "Reported after paying: it earns half of paying on time.").setView(linearLayout).setPositiveButton("Next", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda0
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                BillsUi.lambda$newBill$38(field, field2, field3, mainActivity, str, dialogInterface, i2);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$newBill$38(EditText editText, EditText editText2, EditText editText3, final MainActivity mainActivity, String str, DialogInterface dialogInterface, int i) {
        final String trim = editText.getText().toString().trim();
        final long cents = BillCore.cents(editText2.getText().toString());
        final String upperCase = editText3.getText().toString().trim().toUpperCase(Locale.US);
        if (trim.isEmpty() || cents <= 0 || !upperCase.matches("[A-Z]{3}")) {
            mainActivity.toast("Give the bill a name, an amount and a currency (BBD or USD)");
            return;
        }
        mainActivity.getSharedPreferences("ana", 0).edit().putString("bill_cur", upperCase).apply();
        if (str.equals("paid")) {
            pickApp(mainActivity, Bills.addPaid(mainActivity, trim, cents, upperCase), new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda39
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.checkNow(MainActivity.this);
                }
            });
        } else {
            pickRepeat(mainActivity, new Repeat() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda40
                @Override // com.novera.ana.BillsUi.Repeat
                public final void picked(int i2, String str2) {
                    BillsUi.lambda$newBill$37(MainActivity.this, trim, cents, upperCase, i2, str2);
                }
            });
        }
    }

    static /* synthetic */ void lambda$newBill$37(final MainActivity mainActivity, final String str, final long j, final String str2, final int i, final String str3) {
        Calendar calendar = Calendar.getInstance();
        DatePickerDialog datePickerDialog = new DatePickerDialog(mainActivity, new DatePickerDialog.OnDateSetListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda36
            @Override // android.app.DatePickerDialog.OnDateSetListener
            public final void onDateSet(DatePicker datePicker, int i2, int i3, int i4) {
                BillsUi.lambda$newBill$36(MainActivity.this, str, j, str2, i, str3, datePicker, i2, i3, i4);
            }
        }, calendar.get(1), calendar.get(2), calendar.get(5));
        datePickerDialog.setTitle(i > 0 ? "First due date" : "Due date");
        datePickerDialog.getDatePicker().setMinDate(System.currentTimeMillis() - 1000);
        datePickerDialog.show();
    }

    static /* synthetic */ void lambda$newBill$36(final MainActivity mainActivity, String str, long j, String str2, int i, String str3, DatePicker datePicker, int i2, int i3, int i4) {
        String str4;
        final Bills.Bill addPlan = Bills.addPlan(mainActivity, str, j, str2, String.format(Locale.US, "%04d-%02d-%02d", Integer.valueOf(i2), Integer.valueOf(i3 + 1), Integer.valueOf(i4)), i, str3);
        if (addPlan.dates().size() > 1) {
            str4 = "Locked: " + addPlan.dates().size() + " due dates in the next 12 months";
        } else {
            str4 = "Locked";
        }
        mainActivity.toast(str4);
        pickApp(mainActivity, addPlan, new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda57
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.showBill(MainActivity.this, addPlan);
            }
        });
    }

    static void pickRepeat(final MainActivity mainActivity, final Repeat repeat) {
        final int[] iArr = {0, 1, 1, 2, 1, 3, 1};
        final String[] strArr = {"month", "day", "week", "week", "month", "month", "year"};
        new AlertDialog.Builder(mainActivity).setTitle("How often is it due?").setItems(new String[]{"Once", "Daily", "Weekly", "Every 2 weeks", "Monthly", "Every 3 months", "Yearly", "Every ... (choose)"}, new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda34
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                BillsUi.lambda$pickRepeat$40(iArr, repeat, strArr, mainActivity, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$pickRepeat$40(int[] iArr, final Repeat repeat, String[] strArr, final MainActivity mainActivity, DialogInterface dialogInterface, int i) {
        if (i < iArr.length) {
            repeat.picked(iArr[i], strArr[i]);
            return;
        }
        LinearLayout linearLayout = new LinearLayout(mainActivity);
        linearLayout.setOrientation(1);
        int i2 = (int) (mainActivity.getResources().getDisplayMetrics().density * 20.0f);
        linearLayout.setPadding(i2, i2 / 2, i2, 0);
        final EditText field = field(mainActivity, linearLayout, "Every how many? (e.g. 10)", 2);
        new AlertDialog.Builder(mainActivity).setTitle("Every ...").setView(linearLayout).setItems(new String[]{"days", "weeks", "months", "years"}, new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda20
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface2, int i3) {
                BillsUi.lambda$pickRepeat$39(field, mainActivity, repeat, dialogInterface2, i3);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$pickRepeat$39(EditText editText, MainActivity mainActivity, Repeat repeat, DialogInterface dialogInterface, int i) {
        int i2;
        try {
            i2 = Integer.parseInt(editText.getText().toString().trim());
        } catch (Exception unused) {
            i2 = 0;
        }
        if (i2 < 1 || i2 > 366) {
            mainActivity.toast("A number from 1 to 366");
        } else {
            repeat.picked(i2, BillCore.UNITS[i]);
        }
    }

    static EditText field(MainActivity mainActivity, LinearLayout linearLayout, String str, int i) {
        EditText editText = new EditText(mainActivity);
        editText.setHint(str);
        editText.setInputType(i);
        editText.setSingleLine(true);
        linearLayout.addView(editText);
        return editText;
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void checkNow(final MainActivity mainActivity) {
        new Thread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda18
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.lambda$checkNow$41(MainActivity.this);
            }
        }).start();
    }

    static /* synthetic */ void lambda$checkNow$41(MainActivity mainActivity) {
        Iterator<String> it = Bills.check(mainActivity).iterator();
        while (it.hasNext()) {
            mainActivity.toast(it.next());
        }
        MainActivity.poke();
    }

    static String label(MainActivity mainActivity, String str) {
        try {
            PackageManager packageManager = mainActivity.getPackageManager();
            return packageManager.getApplicationLabel(packageManager.getApplicationInfo(str, 0)).toString();
        } catch (Exception unused) {
            String string = mainActivity.getSharedPreferences("ana", 0).getString("ios_" + str, "");
            if (string.isEmpty()) {
                return str;
            }
            return string + " (iPhone)";
        }
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void pickApp(final MainActivity mainActivity, final Bills.Bill bill, final Runnable runnable) {
        new Thread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda4
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.lambda$pickApp$46(MainActivity.this, runnable, bill);
            }
        }).start();
    }

    static /* synthetic */ void lambda$pickApp$46(final MainActivity mainActivity, final Runnable runnable, final Bills.Bill bill) {
        final List<String[]> recentApps = Bills.recentApps(mainActivity);
        mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda2
            @Override // java.lang.Runnable
            public final void run() {
                BillsUi.lambda$pickApp$45(recentApps, mainActivity, runnable, bill);
            }
        });
    }

    static /* synthetic */ void lambda$pickApp$45(final List list, final MainActivity mainActivity, final Runnable runnable, final Bills.Bill bill) {
        if (list.isEmpty()) {
            new AlertDialog.Builder(mainActivity).setTitle("Pick the payment app").setMessage("No app has sent ANA a notification yet. Pay the bill with your bank or biller app; when its notification arrives, open the bill and pick the app.").setPositiveButton("OK", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda8
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.lambda$pickApp$42(runnable, dialogInterface, i);
                }
            }).show();
            return;
        }
        final String[] strArr = new String[list.size()];
        for (int i = 0; i < list.size(); i++) {
            strArr[i] = label(mainActivity, ((String[]) list.get(i))[0]);
        }
        new AlertDialog.Builder(mainActivity).setTitle("Which app will show the payment? (your bank or the biller)").setItems(strArr, new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda9
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                BillsUi.lambda$pickApp$43(MainActivity.this, bill, list, strArr, runnable, dialogInterface, i2);
            }
        }).setNegativeButton("Later", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda10
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                BillsUi.lambda$pickApp$44(runnable, dialogInterface, i2);
            }
        }).show();
    }

    static /* synthetic */ void lambda$pickApp$42(Runnable runnable, DialogInterface dialogInterface, int i) {
        if (runnable != null) {
            runnable.run();
        }
    }

    static /* synthetic */ void lambda$pickApp$43(MainActivity mainActivity, Bills.Bill bill, List list, String[] strArr, Runnable runnable, DialogInterface dialogInterface, int i) {
        Bills.setApp(mainActivity, bill, ((String[]) list.get(i))[0], strArr[i]);
        if (runnable != null) {
            runnable.run();
        }
        checkNow(mainActivity);
    }

    static /* synthetic */ void lambda$pickApp$44(Runnable runnable, DialogInterface dialogInterface, int i) {
        if (runnable != null) {
            runnable.run();
        }
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void pickPicture(MainActivity mainActivity, Bills.Bill bill) {
        picFor = bill.id;
        Intent intent = new Intent("android.intent.action.GET_CONTENT");
        intent.setType("image/*");
        intent.addCategory("android.intent.category.OPENABLE");
        mainActivity.startActivityForResult(Intent.createChooser(intent, "A picture of the receipt"), REQ_PIC);
    }

    static void pictureResult(MainActivity mainActivity, Intent intent) {
        Bills.Bill find = Bills.find(picFor);
        if (find == null || intent == null || intent.getData() == null) {
            return;
        }
        try {
            InputStream openInputStream = mainActivity.getContentResolver().openInputStream(intent.getData());
            try {
                File file = new File(Bills.dir(mainActivity), find.id + ".img");
                FileOutputStream fileOutputStream = new FileOutputStream(file);
                try {
                    byte[] bArr = new byte[65536];
                    long j = 0;
                    while (openInputStream != null) {
                        int read = openInputStream.read(bArr);
                        if (read <= 0) {
                            break;
                        }
                        fileOutputStream.write(bArr, 0, read);
                        j += read;
                        if (j > 20971520) {
                            break;
                        }
                    }
                    fileOutputStream.close();
                    mainActivity.toast(Bills.claim(mainActivity, find, file.getName()));
                    MainActivity.poke();
                    if (openInputStream != null) {
                        openInputStream.close();
                    }
                } finally {
                }
            } finally {
            }
        } catch (Exception e) {
            mainActivity.toast("Couldn't read the picture: " + e.getMessage());
        }
    }

    static String myName(MainActivity mainActivity) {
        return mainActivity.getSharedPreferences("ana", 0).getString("bill_name", "");
    }

    static void askName(final MainActivity mainActivity, final Runnable runnable) {
        final EditText editText = new EditText(mainActivity);
        editText.setHint("Your name, as friends know you");
        editText.setSingleLine(true);
        new AlertDialog.Builder(mainActivity).setTitle("Your name").setMessage("It goes in the files you share.").setView(editText).setPositiveButton("OK", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda53
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                BillsUi.lambda$askName$47(editText, mainActivity, runnable, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$askName$47(EditText editText, MainActivity mainActivity, Runnable runnable, DialogInterface dialogInterface, int i) {
        String replace = editText.getText().toString().trim().replace("\t", " ");
        if (replace.isEmpty()) {
            return;
        }
        mainActivity.getSharedPreferences("ana", 0).edit().putString("bill_name", replace).apply();
        runnable.run();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static void share(final MainActivity mainActivity, final Bills.Bill bill, final String str) {
        StringBuilder sb;
        if (myName(mainActivity).isEmpty()) {
            final EditText editText = new EditText(mainActivity);
            editText.setHint("Your name, as friends know you");
            editText.setSingleLine(true);
            new AlertDialog.Builder(mainActivity).setTitle("Your name").setMessage("It goes in the bill files you share.").setView(editText).setPositiveButton("OK", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda19
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.lambda$share$48(editText, mainActivity, bill, str, dialogInterface, i);
                }
            }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
            return;
        }
        try {
            String shareReceipt = bill.kind.equals("help") ? Bills.shareReceipt(mainActivity, bill, myName(mainActivity)) : Bills.shareBill(mainActivity, bill, myName(mainActivity));
            if (bill.kind.equals("help")) {
                String str2 = bill.ownerName;
                sb = new StringBuilder("Help receipt for ");
                sb.append(str2);
            } else {
                String str3 = bill.name;
                sb = new StringBuilder("Ask for help with ");
                sb.append(str3);
            }
            send(mainActivity, shareReceipt, sb.toString());
        } catch (Exception e) {
            mainActivity.toast("Couldn't make the file: " + e.getMessage());
        }
    }

    static /* synthetic */ void lambda$share$48(EditText editText, MainActivity mainActivity, Bills.Bill bill, String str, DialogInterface dialogInterface, int i) {
        String replace = editText.getText().toString().trim().replace("\t", " ");
        if (replace.isEmpty()) {
            return;
        }
        mainActivity.getSharedPreferences("ana", 0).edit().putString("bill_name", replace).apply();
        share(mainActivity, bill, str);
    }

    static void send(MainActivity mainActivity, String str, String str2) {
        File dir = AnaFiles.dir(mainActivity);
        File file = new File(dir, str);
        File file2 = new File(dir, str.substring(0, str.length() - 8) + ".sha256");
        Uri uriFor = AnaFiles.uriFor(mainActivity, file);
        Uri uriFor2 = AnaFiles.uriFor(mainActivity, file2);
        ArrayList<? extends Parcelable> arrayList = new ArrayList<>();
        arrayList.add(uriFor);
        arrayList.add(uriFor2);
        Intent intent = new Intent("android.intent.action.SEND_MULTIPLE");
        intent.setType("*/*");
        intent.putParcelableArrayListExtra("android.intent.extra.STREAM", arrayList);
        ClipData newRawUri = ClipData.newRawUri(str, uriFor);
        newRawUri.addItem(new ClipData.Item(uriFor2));
        intent.setClipData(newRawUri);
        intent.addFlags(1);
        mainActivity.startActivity(Intent.createChooser(intent, str2 + " (2 files: .pngmesh + .sha256)"));
    }

    static void journey(final MainActivity mainActivity, final BillCore.Signed signed) {
        if (signed.keyId.equals(Bills.myKeyId())) {
            mainActivity.toast("That's your own journey");
            return;
        }
        final List<String[]> journeyBills = Bills.journeyBills(signed);
        String str = signed.get("journey|owner_name");
        StringBuilder sb = new StringBuilder(str + " is " + signed.get("journey|pct") + "% of the way to having their bills settled 30 days ahead.");
        if (!signed.get("journey|helped_by").isEmpty()) {
            sb.append("\nHelped so far by: ");
            sb.append(signed.get("journey|helped_by"));
        }
        sb.append("\n\nNovvera never touches money. If you step in, you pay the biller yourself, from your own bank or biller app. When ");
        sb.append(str);
        sb.append(" confirms, you both earn eFLEX.");
        if (journeyBills.isEmpty()) {
            new AlertDialog.Builder(mainActivity).setTitle(str + "'s journey").setMessage(String.valueOf(sb) + "\n\nNothing left to settle right now.").setPositiveButton("OK", (DialogInterface.OnClickListener) null).show();
            return;
        }
        final String[] strArr = new String[journeyBills.size()];
        for (int i = 0; i < journeyBills.size(); i++) {
            strArr[i] = BillCore.money(Bills.num(journeyBills.get(i)[2]), journeyBills.get(i)[3]) + "  " + journeyBills.get(i)[1] + "  ·  due " + Bills.fmtDue(journeyBills.get(i)[4]);
        }
        new AlertDialog.Builder(mainActivity).setTitle(str + "'s journey  ·  " + signed.get("journey|pct") + "%").setMessage(sb).setPositiveButton("Step in...", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda35
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                new AlertDialog.Builder(r0).setTitle("Which bill?").setItems(strArr, new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda3
                    @Override // android.content.DialogInterface.OnClickListener
                    public final void onClick(DialogInterface dialogInterface2, int i3) {
                        BillsUi.lambda$journey$51(r1, r2, r3, dialogInterface2, i3);
                    }
                }).show();
            }
        }).setNegativeButton("Not now", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$journey$51(List list, final MainActivity mainActivity, final BillCore.Signed signed, DialogInterface dialogInterface, int i) {
        final String[] strArr = (String[]) list.get(i);
        final long num = Bills.num(strArr[2]);
        final EditText editText = new EditText(mainActivity);
        editText.setInputType(8194);
        editText.setText(BillCore.money(num, "").trim().replace(",", ""));
        new AlertDialog.Builder(mainActivity).setTitle(strArr[1]).setMessage("How much will you pay (" + strArr[3] + ")? You pay the biller yourself.").setView(editText).setPositiveButton("I'll help", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda56
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface2, int i2) {
                BillsUi.lambda$journey$50(editText, num, mainActivity, signed, strArr, dialogInterface2, i2);
            }
        }).setNegativeButton("Back", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$journey$50(EditText editText, long j, final MainActivity mainActivity, BillCore.Signed signed, String[] strArr, DialogInterface dialogInterface, int i) {
        long cents = BillCore.cents(editText.getText().toString());
        if (cents <= 0 || cents > j) {
            mainActivity.toast("Between 0.01 and the bill's amount");
        } else {
            final Bills.Bill acceptFromJourney = Bills.acceptFromJourney(mainActivity, signed, strArr, cents);
            pickApp(mainActivity, acceptFromJourney, new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda37
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.showBill(MainActivity.this, acceptFromJourney);
                }
            });
        }
    }

    static void received(final MainActivity mainActivity, final byte[] bArr) {
        if (BillCore.classOf(bArr) == REQ_PIC) {
            new Thread(new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda30
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.lambda$received$53(MainActivity.this, bArr);
                }
            }).start();
            return;
        }
        final BillCore.Signed read = BillCore.read(bArr);
        if (read.ok && read.cls == 45) {
            journey(mainActivity, read);
            return;
        }
        String[] look = Bills.look(mainActivity, read);
        if (!look[0].equals("ok")) {
            mainActivity.toast(look[1]);
            return;
        }
        if (read.cls == 40) {
            final EditText editText = new EditText(mainActivity);
            editText.setInputType(8194);
            editText.setHint("How much will you pay?");
            final long num = Bills.num(read.get("bill|cents"));
            editText.setText(BillCore.money(num, "").trim().replace(",", ""));
            new AlertDialog.Builder(mainActivity).setTitle("Help pay a bill").setMessage(look[1] + "\n\nHow much will you pay (" + read.get("bill|currency") + ")?").setView(editText).setPositiveButton("I'll help", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda31
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.lambda$received$55(editText, num, mainActivity, read, dialogInterface, i);
                }
            }).setNegativeButton("Not now", (DialogInterface.OnClickListener) null).show();
            return;
        }
        if (read.cls == 41) {
            new AlertDialog.Builder(mainActivity).setTitle("Did they help?").setMessage(look[1]).setPositiveButton("Yes, confirm", new DialogInterface.OnClickListener() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda32
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    BillsUi.lambda$received$56(MainActivity.this, read, dialogInterface, i);
                }
            }).setNegativeButton("No", (DialogInterface.OnClickListener) null).show();
        } else {
            mainActivity.toast(Bills.thanked(mainActivity, read));
            MainActivity.poke();
        }
    }

    static /* synthetic */ void lambda$received$53(MainActivity mainActivity, byte[] bArr) {
        String schedule = Bills.schedule(mainActivity, bArr, "iPhone");
        if (schedule == null) {
            schedule = "Already checking that bill";
        }
        mainActivity.toast(schedule);
        checkNow(mainActivity);
    }

    static /* synthetic */ void lambda$received$55(EditText editText, long j, final MainActivity mainActivity, BillCore.Signed signed, DialogInterface dialogInterface, int i) {
        long cents = BillCore.cents(editText.getText().toString());
        if (cents <= 0 || cents > j) {
            mainActivity.toast("Between 0.01 and the bill's amount");
        } else {
            final Bills.Bill acceptBill = Bills.acceptBill(mainActivity, signed, cents);
            pickApp(mainActivity, acceptBill, new Runnable() { // from class: com.novera.ana.BillsUi$$ExternalSyntheticLambda16
                @Override // java.lang.Runnable
                public final void run() {
                    BillsUi.showBill(MainActivity.this, acceptBill);
                }
            });
        }
    }

    static /* synthetic */ void lambda$received$56(MainActivity mainActivity, BillCore.Signed signed, DialogInterface dialogInterface, int i) {
        try {
            String confirmHelp = Bills.confirmHelp(mainActivity, signed);
            MainActivity.poke();
            mainActivity.toast("Confirmed. Now send the thank-you back to " + signed.get("help|helper_name"));
            send(mainActivity, confirmHelp, "Thank-you for " + signed.get("help|helper_name"));
        } catch (Exception e) {
            mainActivity.toast("Couldn't confirm: " + e.getMessage());
        }
    }
}
