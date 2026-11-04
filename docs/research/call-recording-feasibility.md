# امکان‌سنجیِ ضبط تماس و مربیِ هوشمندِ زنده در NM-Mobile (اندروید)

تاریخ پژوهش: ۱۴۰۵/۰۸/۱۳ (۲۰۲۶-۱۱-۰۴). این یادداشت صادقانه می‌گوید چه چیزی شدنی است، چه چیزی نه، و هر جا منبع نبود نوشته «تأیید نشده».

## ۰. جمع‌بندی در شش خط

1. اپِ عادی (غیرسیستمی) **نمی‌تواند صدای خطِ تماس را بگیرد** (نه صدای طرف مقابل، نه ترکیب دو طرف). این محدودیتِ طراحیِ خودِ اندروید است، نه ضعفِ برنامه‌نویسی.
2. راهِ **AccessibilityService** برای ضبطِ تماس در گوگل‌پلی صریحاً ممنوع است و حتی برای APK مستقیم شکننده و ریسک‌دار است. پیشنهاد نمی‌شود.
3. راهِ قابل‌اتکا امروز: **ضبط‌کنندهٔ داخلیِ خودِ گوشی** (در برند/منطقه/اپراتورهای مجاز) + خواندنِ فایل‌ها با انتخابِ پوشه (SAF). ولی ضبط‌کنندهٔ داخلی در همهٔ گوشی‌ها و کشورها نیست و وضعیتش در ایران برای هر برند «تأیید نشده» است.
4. **مربیِ زنده (در گوشِ فروشنده در حینِ تماس)** روی تماس معمولیِ سیم‌کارت با روش‌های مجاز قابل‌اتکا نیست. تنها مسیرِ منطقی: تماس از راهِ **VoIP/SIP یا شماره‌گیرِ خودِ NM** که صدا را خودِ ما در اختیار داریم.
5. تشخیص گفتار فارسی: بهترین مقایسهٔ منصفانه نیاز به نمونهٔ صدای واقعیِ خودِ NM دارد؛ ارقام منابع با هم قابل‌مقایسه نیستند (بخش ۶).
6. هر ضبط باید طبق قاعدهٔ NM فقط با **رضایتِ ضبط‌شدهٔ طرف مقابل** ذخیره شود؛ وضعیت قانونیِ ایران «نیاز به مشورت حقوقی».

---

## ۱. از اندروید ۱۰: برنامه‌های عادی صدای تماس را نمی‌گیرند

### آنچه منابع رسمی می‌گویند
- **منبع‌های صوتیِ خطِ تماس ممنوع‌اند.** در کد رسمی AOSP (`MediaRecorder.java`) برای `VOICE_UPLINK` ، `VOICE_DOWNLINK` و `VOICE_CALL` نوشته: ضبط از این منابع نیاز به مجوز `CAPTURE_AUDIO_OUTPUT` دارد و «This permission is reserved for use by system components and is not available to third-party applications.» (https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/media/java/android/media/MediaRecorder.java).
- **خودِ مجوز:** در `core/res/AndroidManifest.xml` اندروید تعریف شده با `protectionLevel="signature|privileged|role"` و توضیح «Not for use by third-party applications» (https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml). یعنی فقط برنامه‌های هم‌امضا با سیستم، پیش‌نصبِ privileged، یا دارندهٔ نقشِ خاص.
- **«نقش» هم راه نیست:** در `roles.xml` اندروید، این مجوز فقط به نقش‌های `SYSTEM_AUDIO_INTELLIGENCE` و `SYSTEM_AMBIENT_AUDIO_INTELLIGENCE` داده می‌شود که `systemOnly="true"` هستند (برنامهٔ عادی نمی‌تواند آن را بگیرد) (https://android.googlesource.com/platform/packages/modules/Permission/+/refs/heads/main/PermissionController/res/xml/roles.xml).
- **رفتارِ میکروفون در حینِ تماس.** راهنمای رسمی «Sharing audio input» (https://developer.android.com/media/platform/sharing-audio-input) می‌گوید وقتی تماس فعال است (`AudioManager.getMode()` برابر `MODE_IN_CALL` یا `MODE_IN_COMMUNICATION`):
  - «The call always receives audio.»
  - «The app can capture audio if it is an accessibility service.»
  - «The app can capture the voice call if it is a privileged (pre-installed) app with permission CAPTURE_AUDIO_OUTPUT.»
  یعنی طبق سیاستِ مستندِ اندروید، برنامهٔ عادیِ غیر‌دسترس‌پذیری در حینِ تماس **سکوت** می‌گیرد (در این سند عبارتِ «silence» برای حالتِ دو برنامه آمده؛ رفتار دقیقِ هر گوشی را باید روی خودِ گوشی آزمود).
- **تاریخچه (همان سند):**
  - اندروید ۹: فقط برنامهٔ پیش‌زمینه یا سرویسِ پیش‌زمینه صدای میکروفون می‌گیرد؛ در غیر این صورت سکوت می‌رسد.
  - اندروید ۱۰: «priority scheme»؛ برنامهٔ عادی و برنامهٔ عادی دیگر هرگز هم‌زمان ضبط نمی‌کنند؛ منبع‌های `CAMCORDER` و `VOICE_COMMUNICATION` «privacy-sensitive» حساب می‌شوند.
  - اندروید ۱۱: همان سیاستِ ۱۰ + متدهای `setPrivacySensitive()` برای `AudioRecord` / `MediaRecorder`.
  - اندروید ۱۲، ۱۳، ۱۴: در منابع دریافت‌شده تغییری در همین قاعدهٔ «تماس همیشه صدا می‌گیرد» ذکر نشده؛ هر تغییرِ احتمالیِ OEM‌ها «تأیید نشده».

### در عمل چه کار می‌کند و چه کار نمی‌کند
| روش | وضعیت |
|---|---|
| `VOICE_CALL` / `VOICE_UPLINK` / `VOICE_DOWNLINK` | **کار نمی‌کند** برای برنامهٔ عادی (مجوزِ privileged) |
| `MIC` / `VOICE_RECOGNITION` / `VOICE_COMMUNICATION` در حینِ تماسِ سیم‌کارت | طبق سند اندروید برای برنامهٔ عادی ممکن است سکوت برسد؛ بعضی گوشی‌ها بلندگو+میکروفون را اجازه می‌دهند (گزارش توسعه‌دهندهٔ ACR، زیر). **تأیید نشده روی دستگاهِ هدف** |
| برنامه بدون سرویسِ پیش‌زمینه | از اندروید ۹ سکوت می‌گیرد |
| دو برنامهٔ عادیِ هم‌زمان | فقط یکی صدا می‌گیرد |

گزارش‌های اضافیِ ثانویه (نه رسمی): توسعه‌دهندهٔ ACR Phone می‌نویسد از اندروید ۹ ضبط از «خط» ممکن نیست؛ برنامه‌ها به میکروفون روی آوردند که روی بعضی گوشی‌ها خوب و روی بعضی «غیرممکن» است، و اندروید ۱۰ دسترسیِ میکروفون حین تماس را به AccessibilityService محدود کرد؛ بعد از مه ۲۰۲۲ برای اندروید ۱۰+ برنامهٔ کمکیِ جدا (APH) هم لازم شد (https://nllapps.com/apps/acr/future). کاربران Fairphone و Stack Overflow هم ضبطِ سکوت در اندروید ۱۰ را گزارش کرده‌اند (https://forum.fairphone.com/t/after-android-10-update-call-recording-only-records-silence/64604).

---

## ۲. ضبط تماس با AccessibilityService

- **سیاست گوگل‌پلی (متن رسمی):** «The Accessibility API is not designed and cannot be requested for: **Remote call audio recording**…» و «The Accessibility API is prohibited from being used to … record remote call audio» (https://support.google.com/googleplay/android-developer/answer/9888170 ، بخش Accessibility API). برنامه‌هایی که هستهٔ کارشان کمک به معلولان نیست نمی‌توانند `isAccessibilityTool` را بگیرند (https://support.google.com/googleplay/android-developer/answer/10964491). پس **در گوگل‌پلی بیرون از دسترس است**.
- **از نظر فنی:** سند «Sharing audio input» می‌گوید سرویس دسترس‌پذیری در حینِ تماس صدا می‌گیرد. توسعه‌دهندگان گزارش کرده‌اند که با منبع `VOICE_RECOGNITION` در این حالت فقط سمتِ خودِ کاربر ضبط شد (https://gitlab.com/axet/android-call-recorder/-/merge_requests/39 ؛ منبعِ ثانویه). صدای طرف مقابل مگر از بلندگو نیاید ضبط نمی‌شود.
- **روی APK مستقیم (بیرون از گوگل‌پلی):** سیاستِ پلی اجرا نمی‌شود، اما:
  - کاربر باید سرویس را دستی روشن کند و پیام‌های ترسناکِ اندروید را بپذیرد؛ محدودیتِ «Restricted settings» اندروید ۱۳+ برای APK نصب‌شده خارج از فروشگاه: **در این جلسه تأیید نشد** (منبع دریافت نشد).
  - هر به‌روزرسانی اندروید/OEM می‌تواند قطعش کند؛ توسعه‌دهندهٔ ACR هم می‌نویسد «unclear how long it can be used» (همان لینک بالا).
  - ریسک اعتماد: برنامه‌ای که سرویس دسترس‌پذیری می‌خواهد، به‌طور کلی حساس است و با برند حرفه‌ایِ NM نمی‌خواند.
- **حکم:** برای NM ساخته نشود.

---

## ۳. راهِ قابل‌اتکا: ضبط‌کنندهٔ داخلیِ خودِ گوشی

### کدام برندها دارند و در چه شرایطی
- **گوگل (Pixel / برنامهٔ Phone):** «Only certain devices and operators support recording calls»؛ «You must be in a country or region where call recording is supported… not in all countries or regions»؛ در شروع و پایان ضبط **به هر دو طرف اعلام می‌شود**؛ ضبط‌ها «stored on your device» و بیرون از گوشی ذخیره/پشتیبان نمی‌شوند؛ می‌شود آن‌ها را «Share» کرد به برنامه‌های پشتیبانی‌شده (https://support.google.com/phoneapp/answer/9803950).
- **سامسونگ:** ضبطِ داخلی در برنامهٔ Phone هست، ولی «availability depends on your region, device model, and One UI version» و «might be disabled due to regional restrictions or legal requirements» (https://www.samsung.com/sa_en/support/mobile-devices/how-to-use-the-call-recording-feature-on-your-samsung-galaxy-smartphone/). مسیر مشاهده در خودِ Phone: Settings > Record calls > Recorded calls؛ صفحهٔ رسمی سامسونگ (استرالیا) مسیر فایل‌های **ضبط صدا** را «Internal storage > Recordings > Voice Recorder» می‌گوید؛ پوشهٔ دقیقِ **ضبط تماس** در این منبع نیامده (https://www.samsung.com/au/support/mobile-devices/how-to-record-play-back-and-share-voice-recordings-on-your-samsung-galaxy-phone/).
- **شیائومی:** پرسش‌وپاسخ رسمیِ شیائومی: «If your phone model, country/region, and SIM card carrier all support the call recording feature…» ضبط از راهِ اپ Google Phone است و ضبط‌ها داخل همان اپ پخش/اشتراک می‌شوند (https://www.mi.com/global/support/faq/details/KA-541461/). مسیرِ پوشهٔ `MIUI/sound_recorder/call_rec` را فقط از نتایج جستجو و انجمن‌ها دیدم؛ در صفحهٔ رسمیِ دریافت‌شده نبود ⇒ **تأیید نشده** (و برای گوشی‌های دارای شماره‌گیر خودِ شیائومی است، نه Google Phone). دیجی‌کالا (۱۴۰۲، منبع ثانویه) نوشته شیائومی در مدل‌های جدید این قابلیت را حذف کرده و تغییر منطقه کمکی نمی‌کند (https://www.digikala.com/mag/how-to-record-calls-on-xiaomi-phones/).
- **realme / Oppo / OnePlus / Vivo / هواوی / آنر / موتورولا / ناتینگ:** مسیرها و وضعیتِ رسمی را از منبعِ دریافت‌شده تأیید نکردم. فقط نتایج جستجو: realme «Music > Recordings > Call Recordings»، Oppo «Record/Call» (پرسش‌وپاسخ چینی)، Vivo «Recordings» (بلاگِ کم‌اعتبار) — همه **تأیید نشده**.

### آیا در ایران فعال/قانونی است؟
- **در هیچ‌یک از منابع بالا ایران نامبرده نشده** ⇒ «فعال بودنِ ضبط‌کنندهٔ داخلی در ایران برای هر برند» **تأیید نشده**. گوگل و سامسونگ صراحتاً می‌گویند به کشور/اپراتور/قانون بستگی دارد.
- جنبهٔ قانونی: **نیاز به مشورت حقوقی** (بخش ۷).

### چطور NM فایل‌ها را بخواند (اندروید ۱۱+)
| روش | نکته |
|---|---|
| **انتخابگرِ پوشه (SAF)** `ACTION_OPEN_DOCUMENT_TREE` — **پیشنهادی** | کاربر یک بار پوشه را انتخاب می‌کند؛ اپ با `takePersistableUriPermission` دسترسی را بین ری‌استارت‌ها نگه می‌دارد. محدودیت‌ها (اندروید ۱۱+): نمی‌شود «ریشهٔ حافظهٔ داخلی»، «ریشهٔ SD کارت» و «پوشهٔ Download» را انتخاب کرد، و فایل‌های `Android/data` و `Android/obb` در دسترس نیستند (https://developer.android.com/training/data-storage/shared/documents-files). پوشهٔ ضبط (مثل یک زیرپوشهٔ Recordings یا call_rec) قابل‌انتخاب است. هشدارِ همان سند: برای پوشه‌های بزرگ کارایی پایین می‌آید. |
| **`MANAGE_EXTERNAL_STORAGE`** (دسترسی به همهٔ فایل‌ها) | سیاستِ گوگل‌پلی: فقط برای «file managers, backup and restore apps, anti-virus apps and document management apps» و وقتی SAF/MediaStore کافی نیست؛ نیاز به «Permissions Declaration Form» (https://support.google.com/googleplay/android-developer/answer/10467955). مستندِ اندروید: https://developer.android.com/training/data-storage/manage-all-files. چون NM با APK پخش می‌شود هر دو کار می‌کنند، ولی **SAF امن‌تر** است (کاربر فقط یک پوشه می‌دهد؛ بعداً اگر وارد پلی شدیم مشکلِ سیاست نداریم). |
| **اشتراک‌گذاری (Share) از برنامهٔ Phone گوگل** | چون فایل‌های Google Phone برای برنامه‌های دیگر قابل‌خواندن نیستند (محل دقیقِ ذخیره در منبع نیست؛ «تأیید نشده»)، راهِ مطمئن: کاربر «Share» را می‌زند و NM به‌عنوان مقصدِ `audio/*` ظاهر می‌شود (طراحیِ پیشنهادیِ ما؛ قابلیتِ Share در منبعِ گوگل آمده). دستی است. |

---

## ۴. گرفتنِ صدای زنده برای مربیِ لحظه‌ای

| گزینه | حکم واقع‌گرایانه |
|---|---|
| **بلندگو + میکروفونِ گوشی** | تنها گزینهٔ بدونِ ریشه که ممکن است بعضی گوشی‌ها بدهند. مشکلات: (۱) طبق سند اندروید برنامهٔ عادی در حینِ تماس ممکن است سکوت بگیرد (OEM به OEM فرق می‌کند، **تأیید نشده**)؛ (۲) فقط صدای بلندگو و اتاق؛ پژواک و نویز؛ (۳) باید بلندگو روشن باشد؛ (۴) نیاز به سرویس پیش‌زمینه از نوع `microphone`: طبق https://developer.android.com/develop/background-work/services/fgs/service-types برای نوع microphone باید `RECORD_AUDIO` داده شده باشد و «you cannot create a microphone foreground service while your app is in the background»؛ برنامه‌ای که اندروید ۱۴ را هدف می‌گیرد (targetSdk 34) باید نوعِ سرویس و مجوز `FOREGROUND_SERVICE_MICROPHONE` را اعلام کند وگرنه `SecurityException` / `MissingForegroundServiceTypeException` (https://developer.android.com/about/versions/14/changes/fgs-types-required)؛ اندروید ۱۱: سرویسِ پیش‌زمینه‌ای که از پس‌زمینه شروع شود به میکروفون دسترسی ندارد (https://developer.android.com/about/versions/11/privacy/foreground-services). شروع از «پخش‌گیر زنگ تماس» عملاً پس‌زمینه است؛ استثناها فقط شامل مواردی مثل تعامل کاربر با نوتیف/ویجت/اکتیویتی است (https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start). یعنی کاربر باید **دستی** اپ را باز/نوتیف را لمس کند. **حکم: فقط آزمایشی، قابل‌اتکا نیست.** |
| `VOICE_RECOGNITION` / `VOICE_COMMUNICATION` | همان قاعدهٔ بالا؛ `VOICE_COMMUNICATION` «privacy-sensitive» است و اولویت بالاتر می‌گیرد ولی در حینِ تماس باز هم «the call always receives audio». تغییری در حکم نمی‌دهد. |
| **AccessibilityService** | بخش ۲: ممنوع در پلی، شکننده، فقط سمتِ کاربر. **نه.** |
| **روت / Magisk / LSPosed** | برای مالکِ عادی مناسب نیست؛ گارانتی و اعتماد را می‌برد؛ برنامه‌ای که روی ماژول‌های ریشه‌ای تکیه کند قابل‌پشتیبانی نیست. در این جلسه منبع فنی دریافت نشد ⇒ «تأیید نشده». **نه.** |
| **هدست بلوتوث / دستگاه دوم** | HFP/بلوتوث خودش به هدست مسیر می‌دهد و NM همان صدا را نمی‌گیرد؛ «دستگاه دوم که از بلندگوی گوشی ضبط کند» عملی ولی دستی و ناپایدار است و بیشتر مصنوعی است تا محصول. |
| **VoIP / SIP / شماره‌گیر خودِ NM** | **تنها مسیر واقعاً قابل‌اتکا برای مربیِ زنده.** وقتی تماس از طریق خودِ اپ (VoIP/SIP) برقرار شود، هر دو جریان صدا مال خودِ اپ است و با رضایتِ کاربر/طرف ضبط و تحلیل می‌شود. در اندروید: `ConnectionService` (تماس‌های self-managed) و `InCallService`؛ سرویسِ پیش‌زمینهٔ نوع `phoneCall` نیاز به `MANAGE_OWN_CALLS` یا نقش پیش‌فرض شماره‌گیر دارد (https://developer.android.com/develop/background-work/services/fgs/service-types). منبعِ ثانویه (گزارش خبری ۲۰۲۲، https://www.theregister.com/2022/04/22/google_banning_thirdparty_callrecording_apps/ ): سیاستِ پلی ظاهراً ضبطِ تماس‌های Wi-Fi مبتنی بر SIP را شامل نمی‌شود (تأیید رسمی نشده). |

### «شماره‌گیر پیش‌فرض» چه می‌دهد و چه نمی‌دهد
- با `RoleManager.ROLE_DIALER` برنامه باید `InCallService` را کامل پیاده کند و رابطِ تماس را مدیریت کند؛ وضعیت تماس، مسیر صدا (`CallAudioState`) و دفترچهٔ تماس در دست اوست (https://developer.android.com/develop/connectivity/telecom/dialer-app).
- ولی در تعریفِ رسمیِ نقشِ DIALER در `roles.xml` فقط گروه‌های مجوزِ phone، contacts، sms، microphone، camera و notifications آمده؛ **`CAPTURE_AUDIO_OUTPUT` در آن نیست** (همان فایل roles.xml). یعنی شماره‌گیرِ پیش‌فرض بودن «کنترلِ تماس» می‌دهد ولی **خودبه‌خود صدای خام تماس را نمی‌دهد**. پس تبدیل NM به شماره‌گیرِ پیش‌فرض برای ضبط کافی نیست.
- برنامه‌های **پیش‌نصبِ privileged** (شماره‌گیرِ سازنده) می‌توانند؛ ما نمی‌توانیم.

---

## ۵. تشخیص گفتار فارسی (ASR)

ارقام منابع روی داده‌های مختلف‌اند و **قابل‌مقایسه نیستند**؛ فقط برای ترتیبِ بزرگی هستند.

| گزینه | روی کدام گوشی‌ها | کیفیت برای فارسی | تأخیر | حکم |
|---|---|---|---|---|
| **Vosk روی گوشی** (`vosk-model-small-fa-0.42`، ۵۳ مگابایت) | هر اندرویدِ معمولی | WER خوداظهاری پروژه: ۲۳٫۴٪ (Common Voice 17) و ۱۴٫۰٪ (Fleurs). مدل بزرگ `vosk-model-fa-0.42` (۱٫۶ گیگابایت): ۱۶٫۷٪ و ۱۱٫۱٪ (https://alphacephei.com/vosk/models) | جریانی (streaming) و سبک؛ عدد تأخیر در منبع نیست ⇒ تأیید نشده | مناسب برای پیش‌نمایشِ زنده/آفلاین؛ مدل بزرگ برای سرور |
| **whisper.cpp روی گوشی** (small/medium) | گوشی‌های قوی | WER فارسی در مقالهٔ Whisper (Fleurs، جدول ۱۳): small ≈ ۵۵٫۸٪، medium ≈ ۴۱٫۰٪، large-v2 ≈ ۳۲٫۹٪ (https://arxiv.org/abs/2212.04356 ؛ ستونِ فارسی را از ترتیبِ زبان‌ها استنتاج کردم ⇒ با احتیاط). مدل کارت large-v3: «10% to 20% reduction of errors» نسبت به v2 در زبان‌های متنوع؛ ارقام فارسیِ v3 نیامده (https://huggingface.co/openai/whisper-large-v3) | تأخیر CPU گوشی: منبع ندارم ⇒ تأیید نشده | برای مربیِ زنده **غیرواقع‌گرایانه** (سنگین، دقتِ فارسیِ small/medium ضعیف) |
| **faster-whisper روی سرور GPU + تکه‌تکه (chunk)** | هر گوشی (صدا به سرور می‌رود) | همان WER Whisper (بالا) | پیاده‌سازی Whisper-Streaming: «3.3 seconds latency» روی آزمونِ طولانی (https://arxiv.org/abs/2307.14743؛ آزمونِ فارسی در مقاله نیست ⇒ تأیید نشده برای فارسی) | شدنی؛ کیفیتِ فارسی را روی نمونهٔ خودِ NM باید سنجید |
| **Google Cloud Speech-to-Text** (Chirp 3، `fa-IR`) | ابری | نتیجهٔ جستجو از مستنداتِ گوگل: فارسی (`fa-IR`) برای streaming در Chirp 3 هست؛ Chirp 3 در ۲۰۲۵-۱۰-۱۳ GA شد. صفحهٔ مستندات از این ماشین باز نشد (۴۰۳) ⇒ منبعِ دست‌دوم | تأیید نشده | دسترسی از ایران/تحریم: تأیید نشده |
| **Azure Speech** (`fa-IR`) | ابری | جدولِ زبان‌هایِ رسمی: `fa-IR` با «Real-time transcription» و «Batch» علامت ✅ دارد (https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support). دقت ذکر نشده | تأیید نشده | دسترسی از ایران: تأیید نشده |
| **Deepgram** (Nova-3) | ابری | مستندات رسمی «Persian: fa» را در فهرستِ Nova-3 دارند (https://developers.deepgram.com/docs/models-languages-overview). دقت ذکر نشده | تأیید نشده | تأیید نشده |
| **ElevenLabs Scribe** | ابری | صفحهٔ بازاریابیِ خودشان فارسی را پوشش می‌دهد؛ ادعای فروشنده: WER ≈ ۳٫۱٪ روی Fleurs فارسی و Scribe v2 Realtime حدود ۱۵۰ms (نتایج جستجو: https://elevenlabs.io/speech-to-text/persian ؛ ادعای فروشنده، مستقل تأیید نشده). یک رقیب (Soniox) ادعای ضعیف‌تر بودن Realtime را دارد (ادعای فروشنده) | ادعا: ~۱۵۰ms (فقط مدل) | تأیید مستقل نشده؛ دسترسی از ایران (مستنداتشان از این ماشین ۴۰۳ داد) تأیید نشده |

### بودجهٔ تأخیر برای «مربیِ در گوش» (برآوردِ خودم، منبع ندارد)
تکهٔ صدا ۱ تا ۲ ثانیه + شبکه ۰٫۱ تا ۰٫۵ + ASR (سرور GPU) ۰٫۳ تا ۲ + LLM ۱ تا ۳ ثانیه ⇒ **تقریباً ۳ تا ۷ ثانیه** بعد از جملهٔ طرف مقابل. این برای «نکتهٔ کوتاه بعد از هر جمله» قابل‌تحمل است، برای «پیشنهادِ لحظه‌ایِ وسطِ حرف» نه. عددِ دقیق باید با نمونهٔ واقعی اندازه‌گیری شود.

---

## ۶. واقع‌گرایی به تفکیک برند

«تأیید نشده» یعنی در منبع‌های دریافت‌شده در این جلسه نبود.

| برند | ضبط‌کنندهٔ داخلی | پوشهٔ قابل‌خواندن برای اپ | میکروفون+بلندگو حین تماس | مربیِ زنده واقع‌گرایانه؟ |
|---|---|---|---|---|
| Pixel (Google Phone) | دارد؛ منطقه/اپراتور-محور؛ ایران: تأیید نشده | عمومی نیست؛ فقط Share (محل دقیق: تأیید نشده) | طبق سند AOSP احتمالاً سکوت؛ تأیید نشده روی دستگاه | خیر (با روش‌های مجاز) |
| Samsung | دارد؛ منطقه/مدل/One UI-محور؛ ایران: تأیید نشده | فایل‌های ضبط صدا: `Recordings/Voice Recorder`؛ پوشهٔ ضبط تماس: تأیید نشده («Call» در راهنماهای قدیمی‌تر؛ ثانویه) | تأیید نشده | خیر |
| Xiaomi / Redmi / POCO | Global ROM: از راهِ Google Phone؛ شماره‌گیرِ خودِ شیائومی: `MIUI/sound_recorder/call_rec` (تأیید نشده) | تأیید نشده | تأیید نشده | خیر |
| Huawei / Honor | تأیید نشده | تأیید نشده | تأیید نشده | تأیید نشده |
| Oppo / realme / OnePlus | realme: «Music/Recordings/Call Recordings»؛ Oppo: «Record/Call» (هر دو از نتایج جستجو، تأیید نشده)؛ OnePlus: تأیید نشده | تأیید نشده | تأیید نشده | خیر |
| Vivo | تأیید نشده (پوشهٔ «Recordings» از منبع ضعیف) | تأیید نشده | تأیید نشده | تأیید نشده |
| Motorola | تأیید نشده | تأیید نشده | تأیید نشده | تأیید نشده |

(ستون «مربیِ زنده»: روی تماسِ سیم‌کارت با روش‌های مجاز، هیچ برندی قابل‌اتکا نیست؛ فقط VoIP/SIP خودِ NM.)

---

## ۷. ملاحظهٔ رضایت و قانون (کوتاه، بدون مشاورهٔ حقوقی)

- قاعدهٔ NM: **هیچ ضبطی بدون رضایتِ ضبط‌شدهٔ طرف مقابل ذخیره نمی‌شود.** یعنی ابتدای تماس یک جملهٔ رضایتِ شفاهی (و ثبتِ همان در فایل) لازم است؛ اگر نبود، فایل پاک می‌شود.
- گوگل می‌گوید: «Some laws require all people on the call to consent to being recorded»، و «Many jurisdictions require consent by all parties»؛ خودِ برنامهٔ Phone به هر دو طرف اعلام می‌کند (https://support.google.com/phoneapp/answer/9803950).
- وضعیتِ قانونیِ ضبطِ تماس در ایران برایم **نامشخص** است: **نیاز به مشورت حقوقی**.

---

## ۸. پیشنهاد برای فاز ۲

### چه چیزی ساخته شود (به ترتیب اولویت)
1. **تحلیلِ بعد از تماس (نه زنده):** NM-Mobile پوشهٔ ضبطِ گوشی را با SAF می‌بیند (یا Share را می‌پذیرد)، فایل را پس از بررسیِ جملهٔ رضایت به سرور می‌فرستد، سرور (faster-whisper روی GPU) رونویسی و خلاصه و «نکته‌های فروش» می‌سازد. کمترین ریسک، بیشترین ارزش.
2. **آزمونِ ۱ هفته‌ایِ ماتریس گوشی** (۳ تا ۵ مدلِ واقعیِ فروشنده‌ها): آیا ضبط‌کنندهٔ داخلی هست؟ پوشه و نامِ فایل چیست؟ میکروفون+بلندگو در تماس چه می‌دهد؟ این همان «تأیید نشده»های بالاست.
3. **مقایسهٔ ASR فارسی روی ۲۰ نمونهٔ واقعیِ NM** (Vosk مدل بزرگ در برابر faster-whisper در برابر یک سرویس ابری مجاز): بدون این، ارقامِ جدول ۵ فقط راهنما هستند.
4. اگر مالک «مربیِ زنده» را واقعاً می‌خواهد: **شماره‌گیر/VoIP خودِ NM** (تماس از طریق SIP trunk یا ConnectionService)، که صدا را به‌طور مشروع در اختیار می‌دهد. این پروژهٔ جداست و به خریدِ trunk و قوانین مخابرات بستگی دارد.

### نمونهٔ اولیه (prototype) چه می‌خواهد
- یک Flutter با: انتخابگر پوشهٔ SAF، پایش پوشه، آپلود، صفحهٔ «رضایت ثبت‌شد؟».
- سرور: یک سرویس faster-whisper (GPU) + صف + ذخیرهٔ رضایت.
- ۳ تا ۵ گوشیِ تستِ واقعی از برندهای اصلی.

### چه چیزی ارزشِ ساختن ندارد
- ضبط با AccessibilityService (ممنوع در پلی، شکننده، فقط یک سمت).
- ماژول‌های روت/Magisk/LSPosed.
- تلاش برای `VOICE_CALL`/`VOICE_DOWNLINK` (مجوزِ privileged).
- «شماره‌گیر پیش‌فرض» فقط به‌امیدِ ضبط (کنترلِ تماس می‌دهد، صدا نه).
- whisper.cpp روی گوشی برای فارسیِ زنده.
- مربیِ زنده روی تماسِ سیم‌کارت معمولی.

---

## ۸ب. گزینهٔ SIP / linphone (روشِ برنامهٔ abaCall)

مالک اشاره کرد برنامهٔ دیگرش (abaCall) تماس‌ها را از راهِ **SIP با کتابخانهٔ linphone** برقرار می‌کند. از روی بستهٔ برنامه (فقط ساختارِ آن؛ هیچ حساب/کلیدی استفاده نشد) دیده شد که linphone و سرورِ SIP دارد. این دقیقاً همان «تنها مسیرِ قابل‌اتکا» برای مربیِ زنده در بخش ۴ است:

| موضوع | حکم |
|---|---|
| ضبطِ کامل | وقتی تماس از راهِ SIP بگذرد، **هر دو جهتِ صدا (RTP) در اختیارِ خودِ برنامه** است؛ ضبطِ دو طرف روی گوشی یا سرور ممکن است، بدونِ محدودیتِ اندروید ۱۰. |
| مربیِ زنده | همان جریانِ صدا را می‌شود تکه‌تکه (۱ تا ۲ ثانیه) به سرور فرستاد (WebSocket) و با faster-whisper روی GPU یا یک سرویسِ مجاز رونویسی کرد؛ برآوردِ تأخیرِ کلِ «صدا ← متن ← پیشنهادِ هوش مصنوعی» حدود ۳ تا ۷ ثانیه (برآوردِ خودم، با منبع نیست). با ASR فارسیِ بهتر و یک مدلِ سریع شاید کمتر. |
| چه لازم است | یک **SIP trunk / شمارهٔ ورودی (DID)** از یک ارائه‌دهنده یا یک مرکزِ تلفن (Asterisk/FreeSWITCH) روی سرور؛ تماس‌های مشتری‌ها باید به همان شماره بیایند یا از شمارهٔ فعلی به آن **انتقال** داده شوند. تماس‌های عادیِ سیم‌کارت از این راه رد نمی‌شوند. |
| هزینه و ریسک | هزینهٔ trunk، کیفیتِ اینترنتِ گوشی (Wi-Fi/دیتا)، شمارهٔ نمایش‌داده‌شده برای مشتری (شمارهٔ trunk نه سیم‌کارت)، باتری. **قوانینِ مخابراتیِ تماسِ VoIP به PSTN در ایران: تأیید نشد، نیاز به مشورت.** |
| مجوزِ linphone | کتابخانهٔ linphone (Belledonne) به‌صورتِ GPL با گزینهٔ تجاریِ جدا عرضه می‌شود؛ پیش از قرار دادنش در NM-Mobile باید مجوز بررسی شود (**تأیید نشد**). جایگزین‌های سبک‌تر: PJSIP، یا WebRTC با یک دروازهٔ SIP روی سرور. |
| ضبط و رضایت | همان قاعدهٔ NM: بدونِ رضایتِ ثبت‌شدهٔ طرفِ مقابل، ضبط ذخیره نمی‌شود؛ در تماسِ SIP می‌شود اعلانِ «این تماس ضبط می‌شود» را هم خودکار پخش کرد. |

**در فاز ۱ ساخته نشد** (به trunk، تصمیمِ مجوز و زیرساخت نیاز دارد و ارزان نیست؛ «فقط اگر ارزان باشد» شرط بود). پیشنهادِ فاز ۲: ۱) تصمیم‌گیری دربارهٔ trunk و شماره، ۲) یک نمونهٔ اولیهٔ کوچک با PJSIP/WebRTC: یک تماسِ آزمایشی، ضبطِ دو سمت و ارسالِ جریان به سرور، ۳) سنجشِ تأخیرِ ASR روی ۲۰ نمونهٔ واقعی. تا آن موقع، ضبطِ بعد از تماس با ضبط‌کنندهٔ داخلیِ گوشی (بخش ۸) راهِ عملی است.

---

## ۹. آنچه تأیید نشد
- رفتار دقیقِ میکروفون در حینِ تماس روی هر برند/نسخهٔ اندروید (۱۲، ۱۳، ۱۴، ۱۵).
- وضعیت ضبط‌کنندهٔ داخلی در ایران برای هر برند؛ نام پوشه‌ها و الگوی نامِ فایل (غیر از Samsung `Recordings/Voice Recorder` برای ضبط صدا).
- «Restricted settings» اندروید ۱۳+ برای سرویس دسترس‌پذیریِ APK بیرونی.
- تأخیر whisper.cpp روی گوشی؛ WER فارسیِ whisper-large-v3؛ همهٔ ارقام ابری.
- دسترسی به سرویس‌های ابریِ خارجی از ایران/تحریم.
- مستندات مستقیمِ `developer.android.com` و `cloud.google.com` از این ماشین باز نمی‌شدند (۴۰۳)؛ نسخهٔ web.archive.org یا AOSP/GitHub استفاده شد.

## ۱۰. فهرست منابع اصلی
- https://developer.android.com/media/platform/sharing-audio-input
- https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/media/java/android/media/MediaRecorder.java
- https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml
- https://android.googlesource.com/platform/packages/modules/Permission/+/refs/heads/main/PermissionController/res/xml/roles.xml
- https://support.google.com/googleplay/android-developer/answer/9888170
- https://support.google.com/googleplay/android-developer/answer/10964491
- https://support.google.com/googleplay/android-developer/answer/10467955
- https://developer.android.com/training/data-storage/shared/documents-files
- https://developer.android.com/training/data-storage/manage-all-files
- https://developer.android.com/develop/background-work/services/fgs/service-types
- https://developer.android.com/about/versions/14/changes/fgs-types-required
- https://developer.android.com/about/versions/11/privacy/foreground-services
- https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- https://developer.android.com/develop/connectivity/telecom/dialer-app
- https://support.google.com/phoneapp/answer/9803950
- https://www.samsung.com/sa_en/support/mobile-devices/how-to-use-the-call-recording-feature-on-your-samsung-galaxy-smartphone/
- https://www.mi.com/global/support/faq/details/KA-541461/
- https://alphacephei.com/vosk/models
- https://arxiv.org/abs/2212.04356 ، https://arxiv.org/abs/2307.14743
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support
- https://developers.deepgram.com/docs/models-languages-overview
- https://nllapps.com/apps/acr/future (دیدگاه توسعه‌دهندهٔ یک ضبط‌کنندهٔ تجاری)
