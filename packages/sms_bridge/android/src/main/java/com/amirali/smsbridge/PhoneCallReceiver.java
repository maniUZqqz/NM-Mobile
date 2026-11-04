package com.amirali.smsbridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.telephony.TelephonyManager;

import org.json.JSONObject;

/**
 * تغییر وضعیت تماس‌ها را (زنگ خوردن، گرفتن، پاسخ، پایان) در صفِ فایلی می‌گذارد و هنگام
 * زنگ/گرفتنِ تماس یک اعلانِ بالا‌آمده برای «دستیار تماس» نشان می‌دهد. Dart رویدادها را
 * با drainCallEvents می‌خواند. این گیرنده هیچ صدایی ضبط نمی‌کند.
 */
public class PhoneCallReceiver extends BroadcastReceiver {
    private static final Object LOCK = new Object();
    private static String lastState = TelephonyManager.EXTRA_STATE_IDLE;
    private static String lastNumber = "";
    private static String lastEmittedNumber = null;
    private static boolean incoming = false;
    private static int session = 0;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        try {
            if (Intent.ACTION_NEW_OUTGOING_CALL.equals(action)) {
                String number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER);
                synchronized (LOCK) {
                    lastNumber = number == null ? "" : number;
                    incoming = false;
                }
                return;
            }
            if (!TelephonyManager.ACTION_PHONE_STATE_CHANGED.equals(action)) return;
            String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);
            String number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER);
            if (state == null) return;

            synchronized (LOCK) {
                if (TelephonyManager.EXTRA_STATE_RINGING.equals(state)) {
                    if (TelephonyManager.EXTRA_STATE_IDLE.equals(lastState)) {
                        session++;
                        incoming = true;
                        lastNumber = "";
                        lastEmittedNumber = null;
                    }
                    if (number != null && !number.isEmpty()) lastNumber = number;
                    // معمولاً دو broadcast می‌آید: اولی بی‌شماره؛ فقط وقتی شماره عوض شد خبر بده
                    if (lastEmittedNumber == null || !lastEmittedNumber.equals(lastNumber)) {
                        lastEmittedNumber = lastNumber;
                        emit(context, "ring", "in");
                        if (!lastNumber.isEmpty()) {
                            CallSupport.showCallNotification(context, "تماس ورودی", lastNumber);
                        }
                    }
                } else if (TelephonyManager.EXTRA_STATE_OFFHOOK.equals(state)) {
                    if (TelephonyManager.EXTRA_STATE_RINGING.equals(lastState)) {
                        emit(context, "answered", "in");
                    } else if (TelephonyManager.EXTRA_STATE_IDLE.equals(lastState)) {
                        session++;
                        incoming = false;
                        lastEmittedNumber = lastNumber;
                        emit(context, "dial", "out");
                        CallSupport.showCallNotification(context, "تماس خروجی",
                                lastNumber.isEmpty() ? "در حال گرفتن تماس" : lastNumber);
                    }
                } else if (TelephonyManager.EXTRA_STATE_IDLE.equals(state)) {
                    if (!TelephonyManager.EXTRA_STATE_IDLE.equals(lastState)) {
                        emit(context, "ended", incoming ? "in" : "out");
                        CallSupport.cancelCallNotification(context);
                        // چند ثانیه بعد از پایان تماس: ثبت لاگ تماس و پیدا کردن فایل ضبط (حتی اگر سرویس خواب باشد)
                        WakeScheduler.arm(context.getApplicationContext(), "call_ended",
                                System.currentTimeMillis() + 15_000L, "call_ended");
                    }
                    lastNumber = "";
                    lastEmittedNumber = null;
                    incoming = false;
                }
                lastState = state;
            }
        } catch (Throwable ignored) {
        }
    }

    private static void emit(Context context, String type, String direction) {
        try {
            JSONObject o = new JSONObject();
            o.put("type", type);
            o.put("number", lastNumber == null ? "" : lastNumber);
            o.put("direction", direction);
            o.put("session", session);
            o.put("at", System.currentTimeMillis());
            Queues.append(context, Queues.CALL_EVENTS, o);
        } catch (Throwable ignored) {
        }
    }
}
