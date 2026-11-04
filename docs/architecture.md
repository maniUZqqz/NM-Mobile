# معماری NM Mobile

```
 گوشی (Flutter + بخش بومی اندروید)                               سرور NM (Django)
 ┌───────────────────────────────────────────┐                  ┌──────────────────────────────┐
 │ UI: ConnectScreen، MainShell              │  HTTPS/HTTP      │  /api/v1/mobile/…            │
 │   وضعیت NM · تماس‌ها · دستیار · بیشتر      │ ───────────────▶ │  (apps/mobile)               │
 │ سرویس پس‌زمینه (flutter_background_service)│  Authorization:  │  توکن دستگاه ⇐ کارمند NM     │
 │   GatewayEngine: heartbeat، sms/claim،     │  Device <token>  └──────────────────────────────┘
 │   صف‌های بومی، CallCycle، RecordingCycle   │
 │ بخش بومی (packages/sms_bridge، جاوا)       │
 │   ارسال SMS و گزارش، گیرندهٔ پیامک دریافتی، │
 │   گیرندهٔ وضعیت تماس، لاگ تماس، SAF         │
 └───────────────────────────────────────────┘
```

## لایه‌ها

| بخش | فایل‌ها | نکته |
|---|---|---|
| کلاینت API | `lib/core/nm/nm_client.dart` | هدر `Authorization: Device <token>`، خطاهای فارسیِ سرور، ۴۰۱ ⇐ پاک‌کردن توکن |
| نشست | `lib/core/nm/nm_session.dart` | آدرس + توکن در پوشهٔ خصوصی برنامه (`nm_session.json`)؛ **رمز هرگز ذخیره نمی‌شود**؛ `install_id` یک بار ساخته می‌شود |
| پایش | `lib/features/monitor/` | `ActionRunner` بدون تأیید کاربر هیچ درخواستی نمی‌فرستد |
| گیت‌وی پیامک | `lib/features/gateway/` | `SmsPipeline` (منطقِ خالص و قابل‌تست) + `GatewayEngine` (زمان‌بندی/لاگ، آلارم زنده‌ماندن، `LockCoordinator`) |
| کمپین‌های محلی | `lib/features/campaigns/`، `contacts/`، `optout/` | از SMS-and-call: `CampaignRunner`، `SchedulePlanner`، آلارم‌های بومی؛ فهرست لغوِ محلی از پاسخ «لغو» و فهرست سراسریِ NM پر می‌شود |
| تماس‌ها | `lib/features/calls/` | `NmCallCycle` (ثبت زنده + لاگ)، `RecordingSync` + `RecordingScanner` + `RecordingPipeline` (ضبط، رضایت، ارسال؛ از SMS-and-call) |
| دستیار | `lib/features/assistant/` | محصول (null ⇒ «ثبت نشده»)، شناسایی تماس‌گیرنده، هوش مصنوعی، لینک پیام‌رسان‌ها |
| شناسایی پروفایل | `lib/features/lookup/` | مالک: جریان «lookup»؛ فقط از طریق `lookup_facade.dart` به بقیه وصل است |
| بخش بومی | `packages/sms_bridge/android/…` | `Queues` (صف فایلی بین گیرنده‌های بومی و Dart)، `CallSupport`، گیرنده‌ها، `WakeScheduler`/`WakeReceiver`، `CallMedia` |

## چرا سرویس پس‌زمینه همهٔ کارها را می‌کند
UI در پس‌زمینه ممکن است بسته باشد. گیرنده‌های بومی (پیامک دریافتی، وضعیت تماس، گزارش تحویل) حتی وقتی برنامه بسته است اجرا می‌شوند و رویدادها را در **صفِ فایلی** (`nm_*.jsonl` در `filesDir`) می‌گذارند. سرویس پس‌زمینه هر چند ثانیه صف‌ها را می‌خواند (`drain*`) و به NM می‌فرستد. UI فقط وضعیت را از فایل‌ها می‌خواند (مثلاً `nm_call_state.json` برای نمایش «تماس فعال»).

## ارسال پیامک: قواعدِ ایمنی (`SmsPipeline`)
1. `sms/claim/` ⇐ پیامک‌ها با `uid`.
2. **قبل از فراخوانی SMS**، `uid` در `nm_sms_claims.json` نوشته می‌شود (`phase=sending`).
3. ارسال با سیم‌کارتِ درست؛ سپس `sent` یا `failed` (با `error_code`) به `sms/<uid>/report/` گزارش می‌شود.
4. اگر برنامه وسط ارسال بسته شد و سرور همان `attempt` را دوباره داد ⇒ **دوباره نمی‌فرستیم**، «failed/unknown_after_restart» گزارش می‌شود. فقط اگر سرور `attempt` بزرگ‌تر بدهد (خودش دوباره صف کرده) دوباره می‌فرستیم.
5. گزارشِ ناموفق (قطع شبکه) بعداً تکرار می‌شود؛ خطای دائمی (۴xx) تمام‌شده حساب می‌شود.
6. گزارش «تحویل» از `DeliveryReceiver` بومی می‌آید و وقتی همهٔ بخش‌ها تحویل شد یک‌بار گزارش می‌شود.

## تماس‌ها
* `PhoneCallReceiver` (بومی) ⇐ رویداد `ring | dial | answered | ended` + اعلانِ «دستیار تماس»؛ بعد از پایان تماس آلارم `call_ended` (`WakeScheduler`) را هم می‌گذارد.
* `NmCallCycle.process()` ⇐ `calls/live/` همان لحظه؛ بعد از پایان تماس `calls/log/` از روی لاگ تماس گوشی (`queryCallLog`).
* **ضبط (از SMS-and-call):** `RecordingSync.run()` ⇐ `RecordingScanner` فایل‌های تازهٔ پوشهٔ ضبط‌کنندهٔ گوشی (MediaStore + قاعدهٔ پوشه برای هر برند) را وارد و با `findCallForRecording` به ردیف لاگ تماس وصل می‌کند ⇐ `RecordingPipeline`.
* `RecordingPipeline` (صفِ lease/backoff از SMS-and-call، مرحله‌های NM): تماسِ NM را پیدا کن (`matchKnownCall`) ⇒ **دروازهٔ رضایت** (`calls/consent/`؛ نبود = `needsConsent`، هیچ فایلی خوانده/فرستاده نمی‌شود) ⇒ آپلود ⇒ پرسش از NM تا `ANALYSED`. اقدام‌های کاربر: `requestSend`، `confirmConsentAndSend`.
* هیچ صدایی ضبط نمی‌شود و تبدیل به متن روی گوشی نیست؛ فقط سرور NM.

## آزمون‌ها
همه با ساختگی‌ها (MockClient، `FakeNmHttp`، `MemoryClaimStore`، منبع ضبط جعلی)؛ هیچ پیامک یا تماس واقعی و هیچ شبکه‌ای در آزمون‌ها نیست.
