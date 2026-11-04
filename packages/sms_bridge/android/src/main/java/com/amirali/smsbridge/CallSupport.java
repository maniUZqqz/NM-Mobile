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

    // ───────────────────────── call log ─────────────────────────

    static List<Map<String, Object>> readCallLog(Context c, long sinceMs, int limit) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (c.checkSelfPermission(Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            return out;
        }
        Cursor cur = null;
        try {
            cur = c.getContentResolver().query(
                    CallLog.Calls.CONTENT_URI,
                    new String[]{
                            CallLog.Calls._ID,
                            CallLog.Calls.NUMBER,
                            CallLog.Calls.TYPE,
                            CallLog.Calls.DATE,
                            CallLog.Calls.DURATION,
                            CallLog.Calls.CACHED_NAME
                    },
                    CallLog.Calls.DATE + " > ?",
                    new String[]{String.valueOf(sinceMs)},
                    CallLog.Calls.DATE + " DESC");
            if (cur == null) return out;
            while (cur.moveToNext() && out.size() < limit) {
                Map<String, Object> m = new HashMap<>();
                m.put("id", cur.getLong(0));
                String number = cur.getString(1);
                m.put("number", number == null ? "" : number);
                m.put("type", cur.getInt(2));
                m.put("date", cur.getLong(3));
                m.put("duration", cur.getLong(4));
                String name = cur.getString(5);
                m.put("name", name == null ? "" : name);
                out.add(m);
            }
        } catch (Throwable ignored) {
        } finally {
            if (cur != null) {
                try {
                    cur.close();
                } catch (Throwable ignored) {
                }
            }
        }
        return out;
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

    // ───────────────────────── SAF recordings folder ─────────────────────────

    private static boolean isAudio(String name, String mime) {
        String n = name == null ? "" : name.toLowerCase(Locale.ROOT);
        if (mime != null && mime.startsWith("audio/")) return true;
        return n.endsWith(".m4a") || n.endsWith(".mp3") || n.endsWith(".wav") || n.endsWith(".amr")
                || n.endsWith(".3gp") || n.endsWith(".aac") || n.endsWith(".ogg") || n.endsWith(".opus")
                || n.endsWith(".flac") || n.endsWith(".mp4") || n.endsWith(".awb");
    }

    static List<Map<String, Object>> listRecordings(Context c, String treeUriStr, long sinceMs, int maxFiles) {
        List<Map<String, Object>> out = new ArrayList<>();
        try {
            Uri tree = Uri.parse(treeUriStr);
            String rootId = DocumentsContract.getTreeDocumentId(tree);
            walk(c, tree, rootId, sinceMs, out, 0, maxFiles);
        } catch (Throwable ignored) {
        }
        return out;
    }

    private static void walk(Context c, Uri tree, String docId, long since,
                             List<Map<String, Object>> out, int depth, int max) {
        if (depth > 3 || out.size() >= max) return;
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId);
        Cursor cur = null;
        try {
            cur = c.getContentResolver().query(
                    children,
                    new String[]{
                            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                            DocumentsContract.Document.COLUMN_MIME_TYPE,
                            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                            DocumentsContract.Document.COLUMN_SIZE
                    },
                    null, null, null);
            if (cur == null) return;
            while (cur.moveToNext() && out.size() < max) {
                String id = cur.getString(0);
                String name = cur.getString(1);
                String mime = cur.getString(2);
                long modified = cur.getLong(3);
                long size = cur.getLong(4);
                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) {
                    walk(c, tree, id, since, out, depth + 1, max);
                } else if (isAudio(name, mime) && modified >= since) {
                    Map<String, Object> m = new HashMap<>();
                    m.put("uri", DocumentsContract.buildDocumentUriUsingTree(tree, id).toString());
                    m.put("name", name == null ? "" : name);
                    m.put("modified", modified);
                    m.put("size", size);
                    m.put("mime", mime == null ? "" : mime);
                    out.add(m);
                }
            }
        } catch (Throwable ignored) {
        } finally {
            if (cur != null) {
                try {
                    cur.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    /** فایلِ یک uri را در cache کپی می‌کند (برای آپلود) و مسیر را برمی‌گرداند؛ خطا ⇒ null. */
    static String copyToCache(Context c, String uriStr, String suggestedName) {
        try {
            Uri uri = Uri.parse(uriStr);
            File dir = new File(c.getCacheDir(), "nm-rec");
            if (!dir.exists()) //noinspection ResultOfMethodCallIgnored
                dir.mkdirs();
            String safe = (suggestedName == null || suggestedName.isEmpty() ? "rec.m4a" : suggestedName)
                    .replaceAll("[^A-Za-z0-9._-]", "_");
            File out = new File(dir, System.currentTimeMillis() + "-" + safe);
            try (InputStream in = c.getContentResolver().openInputStream(uri);
                 FileOutputStream sink = new FileOutputStream(out)) {
                if (in == null) return null;
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) >= 0) {
                    if (n > 0) sink.write(buf, 0, n);
                }
                sink.flush();
            }
            return out.getAbsolutePath();
        } catch (Throwable t) {
            return null;
        }
    }

    static void deleteCacheFile(Context c, String path) {
        try {
            File f = new File(path);
            File dir = new File(c.getCacheDir(), "nm-rec");
            if (f.getAbsolutePath().startsWith(dir.getAbsolutePath())) //noinspection ResultOfMethodCallIgnored
                f.delete();
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
