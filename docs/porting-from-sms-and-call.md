# انتقال از SMS-and-call (وضعیت: انجام شد)

[`maniUZqqz/SMS-and-call`](https://github.com/maniUZqqz/SMS-and-call) نسخهٔ مستقلِ همین برنامه است: **اصلاحِ زمان‌بندیِ پیامک** و **ماژول ضبط تماس**. بعد از اینکه این کارها در `main` آن مخزن نشست (کامیت‌های `567bad6`، `0a8da45`، `deb261a`، `4f5a680`) در NM-Mobile آمدند. روش: **ادغامِ سه‌طرفه** برای هر فایل (مبنا = نسخهٔ قبلی همان کامیت، «ما» = NM-Mobile، «آن‌ها» = SMS-and-call، با یکسان‌سازی نام بسته)، نه کپی کورکورانه. گیت‌وی NM (claim ⇒ ذخیره ⇒ ارسال ⇒ گزارش) همچنان منبع حقیقت است.

## چه چیزی آمد

| کامیتِ SMS-and-call | چه چیزی | کامیتِ NM-Mobile |
|---|---|---|
| `567bad6` | اصلاح XLSX (خانه‌های self-closing)، تاریخ‌های امن در برابر منطقهٔ زمانی، `FileMutex` برای ذخیره‌ها، کلید شماره (`phoneKey`)، هستهٔ لغو (`optout.dart`)، `send_settings.dart`؛ آزمون‌ها (`07df2a9`: `regression_import_xlsx_test`) | `5f4ca35` |
| `0a8da45` | **زمان‌بندی**: آلارم‌های بومی (`WakeScheduler` / `WakeReceiver`، با دوباره‌سازی بعد از ری‌استارت و تغییر ساعت)، `campaign_runner`، `schedule_planner`، `campaign_engine` بازنویسی‌شده (سقف ارسال، تلاش دوباره، لغو)، صفحهٔ لغو، کارت «سلامت زمان‌بندی»، `LockCoordinator`/`WakeHub`، `OemSettings`؛ آزمون‌ها (`campaign_runner_test`, `schedule_planner_test`, `scheduling_review_test`) | `d076171` |
| `deb261a` | **ضبط تماس**: `recording_scanner` (واردکردن از پوشهٔ ضبط‌کنندهٔ گوشی با MediaStore)، `recording_matcher` (وصل‌کردن فایل به لاگ تماس)، `brand_guide`، `recording_repository`، `call_settings` (سبک‌شده)، `call_format`، صفحهٔ راه‌اندازی (بازنویسی برای NM)؛ بومی: `CallMedia` (لاگ تماس، فایل‌های صوتی، کپی)، `AudioPlayerBridge`، `ShareHelper`، FileProvider؛ آزمون‌ها (`recording_matcher_test`, `recording_flow_test`, `call_review_test`, `new_ui_test`، تطبیق‌یافته) | `d076171` (بومی)، `f930e2e`، `73e4278` |
| `4f5a680` | CI/مستندات | نیامد؛ CI خودِ NM-Mobile است (Flutter ثابتِ `3.47.9`، همان فکرِ `PIPELINE.md`) |

## یک پیاده‌سازی، نه دو تا

* **پیدا کردن ضبط:** فقط `recording_scanner` + `recording_matcher` + `brand_guide` ِ SMS-and-call. پیاده‌سازی قبلیِ من (انتخابِ پوشه با SAF، `CallRecordingSource`، `RecordingCycle`، matcher خودم) **حذف شد**؛ در تاریخچهٔ گیت (کامیت `7b50851`) هست. دلیل: همان کار را می‌کرد و کدِ آن‌ها برای برندها پوشهٔ مشخص و آزمون دارد. اگر روی گوشی‌ای فایلی در MediaStore دیده نشود، «انتخابِ پوشه با SAF» را می‌شود از همان کامیت برگرداند.
* **لاگ تماس:** فقط `queryCallLog` ِ آن‌ها (`CallMedia`). خواننده‌ی خودم (`readCallLog`) حذف شد.
* **گیرندهٔ وضعیت تماس:** `PhoneCallReceiver` ِ NM-Mobile می‌ماند (رویداد زنگ/گرفتن/پایان برای ثبت زنده در NM و دستیار تماس) و بعد از پایان تماس همان آلارم `call_ended` ِ `WakeScheduler` را می‌گذارد که `PhoneStateReceiver` ِ آن‌ها می‌گذاشت. `PhoneStateReceiver` ِ آن‌ها نیامد (وابسته به ضبط داخلی).
* **ارسال و دروازهٔ رضایت:** `RecordingPipeline` ساختارِ صفِ آن‌ها (ادعای ضبط با lease، تلاش دوباره با فاصلهٔ فزاینده، `nextDueAt`) را نگه داشته ولی مرحله‌هایش NM است: لاگ تماس در NM ⇒ **رضایت** (`calls/consent/`؛ بدون رضایت فایل ارسال نمی‌شود، `needsConsent`) ⇒ `calls/<uid>/recording/` ⇒ پرسش از `calls/<uid>/` تا متن و یادداشت آماده شود (`ANALYSED`). `RecordingSync` جای `CallCycle` ِ آن‌ها (اسکن + پردازش صف) را می‌گیرد؛ `NmCallCycle` (ثبت زنده + ارسال لاگ تماس به NM) ویژهٔ NM است.

## عمداً نیامد، و چرا

| چه چیزی | وضعیت | دلیل |
|---|---|---|
| تبدیل به متن روی گوشی یا ابری (`transcription.dart`، `OpenAiCompatibleTranscriber`، `TranscriptionProvider`، آزمون‌هایش) | **حذف شد** (نه غیرفعال): در کد وجود ندارد و از رابط هم نمی‌شود رسید | تبدیل صدا به متن فقط در سرورِ NM انجام می‌شود (گرهٔ پردازش یا متیس طبق اولویتِ مالک)، با سیاست داده و رضایتِ NM |
| ارسال به «سرور دلخواه» (`RemoteUploader`، `uploadUrl`، `uploadToken`) | **حذف شد** | صدای مشتری فقط باید به NM برود؛ آدرس دلخواه یعنی نشتِ خارج از سیاستِ NM |
| ضبط داخلی با **AccessibilityService** (`CallRecorderAccessibilityService`، `RecorderEngine`، ضبط دستی، `smsbridge_accessibility.xml`، دسترسی میکروفون `RECORD_AUDIO`) | **حذف شد**؛ در manifest و رابط نیست و مجوز دسترس‌پذیری هرگز خواسته نمی‌شود (نه حتی پشتِ کلید) | ۱) سیاستِ Google Play ضبط تماس با دسترس‌پذیری را ممنوع می‌کند؛ ۲) از اندروید ۱۰ به بعد میکروفون هنگام تماس برای برنامه‌های پس‌زمینه ساکت می‌شود و فقط یک سوی مکالمه (با بلندگو) ضبط می‌شود؛ ۳) شکننده و وابسته به برند است؛ ۴) پژوهش ما (`docs/research/call-recording-feasibility.md`) راهِ قابل‌اتکا را «ضبط‌کنندهٔ داخلیِ خودِ گوشی + خواندن فایل» می‌داند |
| `SecureStore` (کلید API تبدیل به متن) | نیامد | دیگر کلیدی روی گوشی نیست؛ توکنِ دستگاه NM در پوشهٔ خصوصی برنامه است (`allowBackup=false`) |
| تغییرات `gateway_engine.dart` (گیت‌وی OTP اختیاری `gatewayEnabled`، فایل `sent_ids`) | نیامد | گیت‌وی NM خودش قبل از ارسال شناسه را روی دیسک می‌نویسد و ارسال دوباره نمی‌کند؛ ولی `LockCoordinator` و آلارم زنده‌ماندن به آن اضافه شد |
| `server_settings_sheet.dart` | نیامد | آدرس سرور هنگام جفت‌سازی با NM تعیین می‌شود |
| لیستِ ضبط‌های محلیِ آن‌ها با جست‌وجو در متن (`recordings_tab`، `recording_detail_page`) | با نسخهٔ NM-محور عوض شد (`recordings_section.dart`، `recording_detail_page.dart`) | متن در NM است؛ فهرست وضعیتِ «ارسال/رضایت/متن آماده» را نشان می‌دهد |
| کارِ emulator_smoke / job ِ شبیه‌ساز | نیامد | هنوز لازم نبود؛ گیرندهٔ `ARM_TEST` درون `WakeReceiver` هست (export نشده) برای آینده |

## چیزهایی که برای NM اضافه شد (روی کدِ آن‌ها)

* **لغو (opt-out) سراسری برای کمپین‌های محلی:** پاسخِ «لغو/stop» از هر شماره (چه ارسال پیامک‌های دریافتی به NM روشن باشد چه نه) به فهرست لغوِ محلی (`OptOutSource.reply`) می‌رود؛ و فهرستِ «دیگر پیام نده»ی سراسریِ NM هر ۱۰ دقیقه با `GET sms/optouts/` به همان فهرست می‌آید (`OptOutSource.nm`؛ اگر سرور این مسیر را ندارد بی‌صدا رد می‌شود؛ نگاه کنید به `docs/api-contract.md`). `campaign_runner` پیش‌تر هر شمارهٔ این فهرست را رد می‌کرد. با این، کمپین‌های محلیِ مخاطب‌ها هم هرگز به شمارهٔ لغوشده پیام نمی‌دهند.
* **آلارم زنده‌ماندنِ گیت‌وی:** سرویس هر چند دقیقه یک آلارم ۲۰دقیقه‌ای را عقب می‌اندازد؛ اگر اندروید سرویس را بکشد آلارم می‌رسد و `WakeReceiver` سرویس را دوباره بالا می‌آورد.
* **قفل CPU/Wi-Fi هماهنگ:** گیت‌وی هم از `LockCoordinator` استفاده می‌کند، تا قفلِ کمپین‌ها و قفلِ گیت‌وی همدیگر را رها نکنند.
