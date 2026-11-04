package com.amirali.smsbridge;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.CallLog;
import android.provider.ContactsContract;
import android.provider.DocumentsContract;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * کارهای بومیِ مربوط به تماس: خواندن لاگ تماس، اعلان «دستیار تماس»، خواندن پوشهٔ ضبط
 * (Storage Access Framework)، باز کردن لینک در پیام‌رسان‌ها و ذخیرهٔ مخاطب.
 * هیچ‌کدام صدای تماس را نمی‌گیرند (اندروید ۱۰+ اجازه نمی‌دهد).
 */
final class CallSupport {
    static final String CALL_CHANNEL = "nm_call_assistant";
    private static final int CALL_NOTIFICATION_ID = 9101;

    private CallSupport() {
    }

    // ───────────────────────── notification ─────────────────────────

    static void showCallNotification(Context c, String title, String text) {
        try {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel ch = new NotificationChannel(
                        CALL_CHANNEL, "دستیار تماس NM", NotificationManager.IMPORTANCE_HIGH);
                ch.setDescription("هنگام زنگ خوردن یا گرفتن تماس، دستیار فروش NM را نشان می‌دهد");
                nm.createNotificationChannel(ch);
            }
            Intent launch = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
            if (launch == null) return;
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
            PendingIntent pi = PendingIntent.getActivity(c, CALL_NOTIFICATION_ID, launch, flags);

            Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? new Notification.Builder(c, CALL_CHANNEL)
                    : new Notification.Builder(c);
            b.setSmallIcon(android.R.drawable.sym_action_call)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setCategory(Notification.CATEGORY_CALL)
                    .setAutoCancel(true)
                    .setContentIntent(pi)
                    .setFullScreenIntent(pi, true);
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                b.setPriority(Notification.PRIORITY_HIGH);
            }
            nm.notify(CALL_NOTIFICATION_ID, b.build());
        } catch (Throwable ignored) {
        }
    }

    static void cancelCallNotification(Context c) {
        try {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(CALL_NOTIFICATION_ID);
        } catch (Throwable ignored) {
        }
    }

    // ───────────────────────── messengers and contacts ─────────────────────────

    static boolean isInstalled(Context c, String pkg) {
        try {
            c.getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /** لینک را (ترجیحاً در همان پیام‌رسان نصب‌شده) باز می‌کند. */
    static boolean openUrl(Context c, String url, String pkg) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (pkg != null && !pkg.isEmpty() && isInstalled(c, pkg)) i.setPackage(pkg);
            c.startActivity(i);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /** صفحهٔ «ذخیرهٔ مخاطب» سیستم را با نام و شماره باز می‌کند. */
    static boolean insertContact(Context c, String name, String number) {
        try {
            Intent i = new Intent(ContactsContract.Intents.Insert.ACTION);
            i.setType(ContactsContract.RawContacts.CONTENT_TYPE);
            if (name != null && !name.isEmpty()) i.putExtra(ContactsContract.Intents.Insert.NAME, name);
            if (number != null && !number.isEmpty()) i.putExtra(ContactsContract.Intents.Insert.PHONE, number);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }
}
