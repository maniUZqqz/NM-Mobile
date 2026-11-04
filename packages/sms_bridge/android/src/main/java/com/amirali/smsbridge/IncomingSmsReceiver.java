package com.amirali.smsbridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Telephony;
import android.telephony.SmsMessage;

import org.json.JSONObject;

/**
 * پیامک‌های دریافتی را در صفِ فایلی می‌گذارد (حتی وقتی برنامه بسته است). Dart آن‌ها را
 * با drainIncoming می‌خواند و فقط وقتی «ارسال پیامک‌های دریافتی» روشن است (یا متن کلمهٔ
 * «لغو/stop» است) به NM می‌فرستد؛ این فیلتر سمت Dart است و در تست‌ها پوشش دارد.
 */
public class IncomingSmsReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) {
            return;
        }
        try {
            SmsMessage[] msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent);
            if (msgs == null || msgs.length == 0) return;
            StringBuilder body = new StringBuilder();
            String from = null;
            long at = System.currentTimeMillis();
            for (SmsMessage m : msgs) {
                if (m == null) continue;
                if (from == null) from = m.getOriginatingAddress();
                String part = m.getMessageBody();
                if (part != null) body.append(part);
                long ts = m.getTimestampMillis();
                if (ts > 0) at = ts;
            }
            JSONObject o = new JSONObject();
            o.put("from", from == null ? "" : from);
            o.put("body", body.toString());
            o.put("at", at);
            o.put("subId", intent.getIntExtra("subscription", -1));
            o.put("slot", intent.getIntExtra("slot", -1));
            Queues.append(context, Queues.INCOMING_SMS, o);
        } catch (Throwable ignored) {
        }
    }
}
