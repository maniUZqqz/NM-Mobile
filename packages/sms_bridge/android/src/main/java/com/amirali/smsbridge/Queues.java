package com.amirali.smsbridge;

import android.content.Context;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * صف‌های فایلیِ کوچک (یک JSON در هر خط) بین گیرنده‌های بومی (که حتی وقتی برنامه بسته است
 * اجرا می‌شوند) و کد Dart. نوشتن و خالی‌کردن زیر یک قفلِ مشترک انجام می‌شود.
 */
final class Queues {
    static final String INCOMING_SMS = "nm_incoming_sms.jsonl";
    static final String SMS_DELIVERY = "nm_sms_delivery.jsonl";
    static final String CALL_EVENTS = "nm_call_events.jsonl";

    private static final Object LOCK = new Object();
    private static final long MAX_BYTES = 512 * 1024;

    private Queues() {
    }

    static void append(Context context, String name, JSONObject item) {
        synchronized (LOCK) {
            try {
                File f = new File(context.getFilesDir(), name);
                if (f.exists() && f.length() > MAX_BYTES) {
                    // صفِ بی‌مصرف نباید بی‌نهایت بزرگ شود
                    f.delete();
                }
                try (FileOutputStream out = new FileOutputStream(f, true)) {
                    out.write((item.toString() + "\n").getBytes(StandardCharsets.UTF_8));
                    out.flush();
                }
            } catch (Throwable ignored) {
            }
        }
    }

    /** همهٔ ردیف‌ها را برمی‌گرداند و فایل را پاک می‌کند. */
    static List<Map<String, Object>> drain(Context context, String name) {
        List<Map<String, Object>> out = new ArrayList<>();
        synchronized (LOCK) {
            File f = new File(context.getFilesDir(), name);
            if (!f.exists()) return out;
            try {
                ByteArrayOutputStream buf = new ByteArrayOutputStream();
                try (FileInputStream in = new FileInputStream(f)) {
                    byte[] chunk = new byte[16 * 1024];
                    int n;
                    while ((n = in.read(chunk)) >= 0) {
                        if (n > 0) buf.write(chunk, 0, n);
                    }
                }
                String text = new String(buf.toByteArray(), StandardCharsets.UTF_8);
                for (String line : text.split("\n")) {
                    String t = line.trim();
                    if (t.isEmpty()) continue;
                    try {
                        JSONObject j = new JSONObject(t);
                        Map<String, Object> m = new HashMap<>();
                        Iterator<String> keys = j.keys();
                        while (keys.hasNext()) {
                            String k = keys.next();
                            Object v = j.get(k);
                            if (v == JSONObject.NULL) continue;
                            m.put(k, v);
                        }
                        out.add(m);
                    } catch (Throwable ignored) {
                    }
                }
                //noinspection ResultOfMethodCallIgnored
                f.delete();
            } catch (Throwable ignored) {
            }
        }
        return out;
    }
}
