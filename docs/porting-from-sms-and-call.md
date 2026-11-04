# انتقال از SMS-and-call (وضعیت: هنوز «نشسته» نیست)

پروژهٔ دوم، [`maniUZqqz/SMS-and-call`](https://github.com/maniUZqqz/SMS-and-call)، نسخهٔ مستقلِ همین برنامه است: **اصلاحِ زمان‌بندیِ پیامک** و **ماژول ضبط تماس + تبدیل به متن**. قرار بر این بود که بعد از «نشستن» آن‌ها در `main` همان کد را اینجا بیاوریم و تکرار نکنیم.

## وضعیتِ زمانِ بررسی (۱۴۰۵/۰۸/۱۳ حدود ساعت ۱۰:۳۰ تهران)

* `main` در SMS-and-call فقط یک کامیت دارد: «Initial import of sms_sender, unmodified». هیچ Release ای نیست و `/root/mobile-work/PIPELINE.md` هنوز ساخته نشده بود.
* کار در شاخهٔ `dev/work` در جریان است (کامیت‌های `wip:`)، شامل:
  * **زمان‌بندی:** `features/campaigns/domain/schedule_planner.dart`، `services/campaign_runner.dart`، `WakeScheduler.java` / `WakeReceiver.java` (آلارم دقیق)، `scheduler_health_card.dart`
  * **ضبط تماس:** `features/calls/*` (`recording_scanner`, `recording_matcher`, `recording_pipeline`, `call_engine`, `transcription`, `brand_guide`, `call_setup_page`)، و بومی: `PhoneStateReceiver`, `RecorderEngine`, `CallRecorderAccessibilityService`, `CallMedia`, `OemSettings`
  * **لغوِ دریافت:** `features/optout/*`
* چون در `main` نشسته نیست، **چیزی از آن‌ها کپی نشد** (تا کار دوبل و ناهمگام نشود). کامیتِ مرجع برای وقتی که نشست: ثبت شود در پیامِ کامیتِ انتقال.

## چه چیزی در NM-Mobile همین حالا هست (مخصوصِ NM)

| قابلیت | کجا | رابط برای جایگزینی |
|---|---|---|
| ثبتِ زنده، لاگ تماس، شناسایی تماس‌گیرنده | `calls/services/call_cycle.dart` | — (وابسته به API ِ NM) |
| منبع فایل‌های ضبط (فقط پوشهٔ ضبط‌کنندهٔ داخلی با SAF) | `calls/services/recording_source.dart` ⇒ `CallRecordingSource` | ماژول SMS-and-call می‌تواند این رابط را پیاده کند |
| وصل‌کردن فایل به تماس | `calls/domain/recording_matcher.dart` | می‌شود با `recording_matcher` ِ آن‌ها یکی کرد |
| دروازهٔ رضایت + آپلود به NM | `calls/services/recording_cycle.dart` | ثابت می‌ماند (قانون NM) |
| ارسال پیامکِ صف NM | `gateway/services/sms_pipeline.dart` | — |

## وقتی نشست، چه باید کرد

1. `git log` ِ SMS-and-call را ببینید و کامیت‌هایِ «scheduling» و «call recording» را پیدا کنید.
2. **زمان‌بندی:** `schedule_planner`/`campaign_runner`/`WakeScheduler` را بیاورید و `CampaignEngine` ِ محلیِ این برنامه (فقط برای کمپین‌های محلیِ مخاطب‌ها) را با آن عوض کنید. پیامک‌های **صف NM** با این کار کاری ندارند.
3. **ضبط تماس:** `recording_scanner`/`transcription` را به‌شکل یک `CallRecordingSource` جدید بپوشانید. دقت: بخشی از ماژول آن‌ها **ضبط از راه AccessibilityService** است؛ طبق پژوهش ما (`docs/research/call-recording-feasibility.md`) این روش در اندروید ۱۰+ شکننده و در Google Play ممنوع است؛ اگر آورده شود باید پشت یک کلیدِ خاموشِ پیش‌فرض باشد.
4. **تبدیل به متن** در NM-Mobile روی گوشی انجام **نمی‌شود**؛ فایل با رضایت به NM می‌رود و NM (سرور پردازش یا متیس، طبق اولویتِ مالک) آن را پیاده می‌کند. پس `transcription.dart` ِ آن‌ها لازم نیست.
5. بخش بومی `sms_bridge` در دو پروژه متفاوت شده؛ هنگام ادغام، تغییراتِ NM-Mobile (`IncomingSmsReceiver`, `DeliveryReceiver`, `PhoneCallReceiver`, `CallSupport`, `Queues`) را نگه دارید.
