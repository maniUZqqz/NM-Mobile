package com.amirali.smsbridge;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.telephony.SmsMessage;

import org.json.JSONObject;

/**
 * گزارش «تحویل» پیامک (اگر اپراتور بدهد). نتیجه در صف فایلی می‌رود و Dart آن را به NM
 * گزارش می‌کند. ref همان uid پیامکِ NM است.
 */
public class DeliveryReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            String ref = intent.getStringExtra("ref");
            if (ref == null || ref.isEmpty()) return;
            int status = -1;
            try {
                byte[] pdu = intent.getByteArrayExtra("pdu");
                String format = intent.getStringExtra("format");
                if (pdu != null) {
                    SmsMessage sm = format == null
                            ? SmsMessage.createFromPdu(pdu)
                            : SmsMessage.createFromPdu(pdu, format);
                    if (sm != null) status = sm.getStatus();
                }
            } catch (Throwable ignored) {
            }
            JSONObject o = new JSONObject();
            o.put("ref", ref);
            o.put("part", intent.getIntExtra("part", 0));
            o.put("total", intent.getIntExtra("total", 1));
            o.put("code", getResultCode());
            o.put("ok", getResultCode() == Activity.RESULT_OK);
            o.put("status", status);
            o.put("at", System.currentTimeMillis());
            Queues.append(context, Queues.SMS_DELIVERY, o);
        } catch (Throwable ignored) {
        }
    }
}
