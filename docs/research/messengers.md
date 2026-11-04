# پیام‌رسان‌ها: باز کردن چت با شماره تلفن از داخل اپ NM-Mobile

تاریخ پژوهش: ۱۴۰۵/۰۸/۱۳ (۲۰۲۶-۱۱-۰۴). نسخهٔ ماشین‌خوان همین فایل: `messengers.json` (کنار همین فایل).

قاعده‌ای که رعایت شده: فقط چیزی «تأیید‌شده» نوشته شده که منبعش (آدرس + آنچه می‌گوید) آمده است. هر جا منبعی نبود نوشته شده «تأیید نشده». هیچ قالب لینکی از خودم نساخته‌ام.

## ۱. خلاصهٔ یک‌نگاه

| پیام‌رسان | فعال در ۱۴۰۵؟ | بستهٔ اندروید | لینک با شمارهٔ تلفن | لینک با نام‌کاربری |
|---|---|---|---|---|
| تلگرام | بله | `org.telegram.messenger` ، `org.telegram.messenger.web` | **دارد (رسمی و مستند)** | `https://t.me/{username}` |
| واتساپ | بله | `com.whatsapp` ، `com.whatsapp.w4b` (بیزینس) | **دارد** (`wa.me`) — منبع رسمی قابل استخراج نبود، منبع ثانویه | تأیید نشده |
| ایتا | بله | `ir.eitaa.messenger` | **مستند رسمی ندارد** (فقط شواهد داخل APK؛ استفاده نشود) | `https://eitaa.com/{username}` |
| بله | بله | `ir.nasim` | **ندارد** (در مستندات رسمی) | `https://ble.ir/{username}` (برای بازو مستند؛ برای کاربر عادی تأیید نشده) |
| سروش پلاس | بله | `mobi.mmdt.ottplus` | **مستند رسمی ندارد** | `https://splus.ir/{username}` |
| روبیکا | بله | `app.rbmain.a` (فعلی) ، `ir.resaneh1.iptv` (قدیمی) | **مستند رسمی ندارد** | `https://rubika.ir/{username}` (قابل‌اتکا بودن تأیید نشده) |

نتیجه برای ساخت اپ: فقط تلگرام و واتساپ لینکِ شماره‌دارِ قابل‌اتکا دارند. برای ایتا، بله، سروش‌پلاس و روبیکا تنها راهِ مجاز این است که شماره را به‌صورت «مخاطب گوشی» ذخیره کنیم (بخش ۴) و، اگر لازم شد، خودِ اپ پیام‌رسان را باز کنیم.

## ۲. جزئیات هر پیام‌رسان

### تلگرام (Telegram)
- **فعال بودن:** بله. صفحه‌های رسمی FAQ و API (لایهٔ ۲۱۴) در ۲۰۲۶ در دسترس‌اند.
- **بستهٔ اندروید:** `org.telegram.messenger` (متغیر `APP_PACKAGE` در https://github.com/DrKLO/Telegram/blob/master/gradle.properties) و پسوند `.web` برای ساخت نسخهٔ سایت رسمی (`applicationIdSuffix ".web"` در `TMessagesProj_App/build.gradle` همان مخزن) یعنی `org.telegram.messenger.web`.
- **لینک با شماره (رسمی):**
  - `https://t.me/+{digits}` و `tg://resolve?phone={digits}` — منبع: https://core.telegram.org/api/links ، بخش «Phone number links» (قالب‌ها: `t.me/+<phone_number>?text=<draft_text>&profile` و `tg://resolve?phone=<phone_number>&text=<draft_text>&profile`). پارامتر اختیاری `text` برای متنِ از پیش نوشته و `profile` برای باز کردن پروفایل به‌جای چت.
  - **قالب شماره:** «international format» (https://core.telegram.org/method/contacts.resolvePhone) یعنی کد کشور + شماره، فقط رقم، بدون صفر ابتدایی داخلی. مثال ایران: `0912 123 4567` می‌شود `989121234567`. در کد رسمی اپ (`LaunchActivity.java`) علامت `+` ابتدایی در `tg://resolve?phone=+…` حذف می‌شود، پس هر دو شکل پذیرفته است؛ ما فقط ارقام می‌فرستیم.
- **اگر طرف مخاطب نیست / تلگرام ندارد / حریم خصوصی بسته است:**
  - FAQ رسمی (https://telegram.org/faq، «How does t.me work?»): لینکِ `t.me/+123456789` «will only work if your privacy settings let others find you by your phone number». یعنی اگر طرف در تنظیمات «چه کسی با شمارهٔ من پیدایم کند» را بسته باشد، لینک کار نمی‌کند.
  - API: `contacts.resolvePhone` — «Resolve a phone number to get user info, if their privacy settings allow it»؛ خطا: `PHONE_NOT_OCCUPIED` — «No user is associated to the specified phone number» (https://core.telegram.org/method/contacts.resolvePhone). این متد فقط برای حساب کاربر است («Only users can use this method»).
  - رفتار اپ: پیام «There is no Telegram account with this phone number.» (رشتهٔ `NoPhoneFound` در https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/res/values/strings.xml). یعنی از بیرون فرق «حساب ندارد» و «حریم خصوصی بسته» معلوم نمی‌شود.
  - نیازی نیست طرف مخاطب باشد؛ به شرط بازبودنِ حریم خصوصی، چت باز می‌شود.
- **لینک با نام‌کاربری:** `https://t.me/{username}` یا `tg://resolve?domain={username}` (https://core.telegram.org/api/links، «Public username links»).

### واتساپ (WhatsApp)
- **فعال بودن:** بله (شرایط خدمات با تاریخ ۲۰۲۶ زنده است: https://www.whatsapp.com/legal/terms-of-service). وضعیت دسترسی/فیلترینگ در ایران ۱۴۰۵: تأیید نشده.
- **بستهٔ اندروید:** `com.whatsapp` و برای واتساپ بیزینس `com.whatsapp.w4b`. منبع: فقط منابع ثانویه (ثابتِ `businessWhatsAppPackageName` در pub.dev/flutter_whatsapp_stickers؛ انجمن b4x.com). مستند رسمی واتساپ برای نام بسته دریافت نشد.
- **لینک با شماره:** `https://wa.me/{digits}` (و قالب قدیمی‌تر `whatsapp://send?phone={digits}`).
  - **منبع:** صفحهٔ رسمی «How to use click to chat» (https://faq.whatsapp.com/5913398998672934) وجود دارد ولی متنش با جاوااسکریپت بارگذاری می‌شود و من نتوانستم متن آن را استخراج کنم. بنابراین قالب را از منبع ثانویه می‌آورم: پشتیبانی tyntec (https://www.tyntec.com/helpcenter/docs/faqs/whatsapp-business/your-whatsapp-account/how-can-i-add-a-whatsapp-conversation-button-on-my-website/) که همان صفحهٔ رسمی را ارجاع می‌دهد: شماره با کد کشور، بدون `+`، بدون پرانتز و خط تیره؛ مثال درست `https://wa.me/15551234567`.
  - **قالب شماره:** فقط رقم با کد کشور (`989121234567`)، بدون `+` و بدون صفر ابتدایی.
  - `whatsapp://send?phone=` فقط از بحث توسعه‌دهندگان تأیید می‌شود (ضعیف)؛ پیش از استفاده روی گوشی آزمایش شود.
- **اگر شماره در واتساپ نیست یا مخاطب نیست:** مخاطب‌بودن لازم نیست. اگر شماره ثبت نشده یا قالب غلط باشد، منابع ثانویه پیام «Phone number shared via url is invalid» را گزارش کرده‌اند (مثلاً https://www.khaleejtimes.com/technology/now-use-whatsapp-without-opening-the-app-heres-how- و تاپیک https://community.thunkable.com/t/solved-whatsapp-link-error/1960607). تأیید رسمی نشده.
- **تفاوتِ دو بسته:** گزارشِ یک کاربر: `wa.me` ممکن است کاربر را بین واتساپ و بیزینس مخیر کند و `whatsapp://send` مستقیم بیزینس را باز کند (تأیید نشده؛ از Stack Overflow).
- **نام‌کاربری:** برای واتساپ لینک نام‌کاربری تأیید نشده.

### ایتا (Eitaa)
- **فعال بودن:** بله. بازار: نسخهٔ 7.1.8، آخرین به‌روزرسانی ۲۰۲۶-۱۰-۱۸، حدود ۶۴ میلیون نصب (https://cafebazaar.ir/app/ir.eitaa.messenger). مایکت: نسخهٔ 7.1.2 (۱۴۰۵/۰۶/۲۲) (https://myket.ir/app/ir.eitaa.messenger).
- **بسته:** `ir.eitaa.messenger` (بازار + مایکت + `package=` مانیفست APK رسمی https://eitaa.com/app/apk).
- **لینک با نام‌کاربری:** `https://eitaa.com/{username}` — صفحهٔ رسمی https://eitaa.com پیوند `https://eitaa.com/eitaa_ads` دارد و مانیفست APK دامنه‌های `eitaa.com`، `eitaa.ir`، `eitaa.net` را برای VIEW ثبت کرده است.
- **لینک با شماره: ندارد (مستند رسمی).** مستندات توسعه‌دهندگان https://developer.eitaa.com فقط SDK برنامک‌ها را شرح می‌دهد (`openEitaaLink(url)` برای باز کردن لینک ایتا داخل اپ، و `requestContact` که **خودِ کاربر** شمارهٔ خودش را به برنامک می‌دهد).
- **شواهد داخل APK (نه مستند، نه آزموده):** روی APK رسمی نسخهٔ 7.1.8 بدون نصب و اجرا فقط رشته‌ها را بررسی کردم: اپ فورکِ کلاینت تلگرام است و رشته‌های `et://resolve`، `et:resolve`، `https://eitaa.com/+%s`، کلاس `TL_contacts_resolvePhone` و پیام `NoPhoneFound` دارد؛ مانیفست scheme سفارشی `et` را ثبت کرده است. این قویاً نشان می‌دهد قالب‌هایی شبیه تلگرام ممکن است کار کند، ولی چون مستند نیست و روی گوشی آزموده نشده، **در اپ NM استفاده نمی‌شود** (در JSON زیر `candidates_unverified_do_not_use` آمده).
- **حریم خصوصی رسمی:** شماره فقط به کسانی نشان داده می‌شود که شما را در مخاطبینشان ذخیره کرده‌اند؛ همگام‌سازی مخاطبین با اجازهٔ کاربر انجام می‌شود (https://eitaa.com/page/privacy/ ، بند ۲.۴).

### بله (Bale)
- **فعال بودن:** بله. مایکت: نسخهٔ 10.1.10، آخرین به‌روزرسانی ۱۴۰۵/۰۲/۱۲، حدود ۲۵ میلیون دانلود (https://myket.ir/app/ir.nasim). مستندات توسعه‌دهندگان زنده است (https://docs.bale.ai).
- **بسته:** `ir.nasim` (صفحهٔ «بله» در مایکت). صفحهٔ بازار با این نام بسته جواب نداد (۴۰۴)؛ بنابراین فقط مایکت شاهد است.
- **لینک با نام‌کاربری:** مستندات رسمی فقط لینک بازو را می‌آورند: `ble.ir/<bot_username>?start=<parameter>` و برای مینی‌اپ `https://ble.ir/<bot_username>?startapp=<start_param>` (https://docs.bale.ai ، https://docs.bale.ai/miniapp). نمونه‌ها: `ble.ir/botfather` و `ble.ir/supportbot`. لینک نام‌کاربری برای کاربر عادی مستند نیست (همان قالب محتمل است ولی تأیید نشده).
- **لینک با شماره: ندارد** (در مستندات رسمی هیچ قالبی با شماره نیست). وجودِ قابلیتی بی‌مستند رد نشده، ولی تأیید هم نشده.

### سروش پلاس (Soroush Plus)
- **فعال بودن:** بله. بازار: نسخهٔ 8.1.1.0، به‌روزرسانی ۲۰۲۶-۱۰-۲۴ (https://cafebazaar.ir/app/mobi.mmdt.ottplus). مایکت: ۱۴۰۵/۰۸/۰۲، ۲۰ میلیون دانلود. سازنده: «ستاک هوشمند شریف». «سروش» قدیمیِ صداوسیما (فراخوان مزایدهٔ ۱۳۹۸ طبق خبر زومیت) محصول جداست و وضعیتش تأیید نشده؛ اپ فعلی همان «سروش پلاس» است.
- **بسته:** `mobi.mmdt.ottplus`.
- **لینک با نام‌کاربری:** `https://splus.ir/{username}` — پیوندهای رسمی https://splus.ir/soroushplus ، https://splus.ir/botfather ، https://splus.ir/support در سایت https://soroushplus.com ، و مانیفست APK رسمی 8.1.1.0 که دامنهٔ `splus.ir` را ثبت کرده و یک scheme سفارشی `soroush://` هم دارد (قالب و کاربردش مستند نیست؛ استفاده نشود).
- **لینک با شماره: ندارد (مستند رسمی).** سند توسعه‌دهندگان (https://soroushplus.com/p/documents) فقط API بازو در `api.splus.ir` است.

### روبیکا (Rubika)
- **فعال بودن:** بله. مایکت: `app.rbmain.a` نسخهٔ 4.1.1، ۱۴۰۵/۰۷/۲۷، حدود ۴۵ میلیون دانلود (https://myket.ir/app/app.rbmain.a). آدرس قدیمی `ir.resaneh1.iptv` در مایکت به همین صفحه هدایت می‌شود. صفحهٔ `ir.resaneh1.iptv` در بازار نوشته «به درخواست مالک غیرفعال شده» (https://cafebazaar.ir/app/ir.resaneh1.iptv).
- **لینک با نام‌کاربری:** `https://rubika.ir/{username}` — از لینک `rubika.ir/supportbot` در پرسش‌های متداول رسمی (https://rubika.ir/faq) و `go.rubika.ir/supportbot` در صفحهٔ اصلی. زومیت یک‌بار گزارش داده بود نمایش پروفایل از `rubika.ir/نام‌کاربری` قطع شده؛ تاریخش نامعلوم است، پس قابل‌اتکا بودن تأیید نشده.
- **لینک با شماره: مستند رسمی ندارد.** https://rubika.ir/botapi فقط API بازو است. scheme سفارشیِ اپ در مانیفست به‌صورت resource تعریف شده و رمزگشایی نشد (تأیید نشده).

## ۳. چرا جست‌وجوی خودکارِ پروفایل با شماره نمی‌سازیم

مالک پرسیده بود چرا «تشخیص خودکار اینکه این شماره در کدام پیام‌رسان هست» ساخته نمی‌شود. خلاصهٔ موضع هر سرویس (با منبع):

- **تلگرام:** متد `contacts.resolvePhone` فقط «اگر حریم خصوصی اجازه بدهد» جواب می‌دهد و فقط برای حساب کاربر است، نه ربات. شرایط خدمات API (https://core.telegram.org/api/terms): بند ۱.۱ «Telegram is a privacy-oriented platform… must guard users' privacy with utmost care» و بند ۱.۴ ممنوعیت «making actions on behalf of the user without the user's knowledge and consent». سیاست حریم خصوصی (https://telegram.org/privacy، بند ۳.۴): همگام‌سازی مخاطبین فقط با اجازهٔ کاربر است.
- **واتساپ:** شرایط خدمات (https://www.whatsapp.com/legal/terms-of-service، بند «Harm To WhatsApp Or Our Users») دسترسی «directly, indirectly, through automated or other means» به شیوهٔ غیرمجاز را ممنوع می‌کند، از جمله (e) ساخت حساب با روش خودکار/غیرمجاز و (f) «collect information of or about our users in any impermissible or unauthorized manner». مستندی برای جست‌وجوی پروفایل با شماره برای اشخاص ثالث در این پژوهش پیدا نشد (تأیید نشده).
- **ایتا، بله، سروش پلاس، روبیکا:** APIهای رسمی‌شان «بازو» و «برنامک/مینی‌اپ» است (https://developer.eitaa.com ، https://docs.bale.ai ، https://soroushplus.com/p/documents ، https://rubika.ir/botapi). هیچ‌کدام در مستندات، جست‌وجوی پروفایل با شماره برای شخص ثالث ندارند. تنها مسیر شماره، `requestContact` است که **خودِ کاربر** شمارهٔ خودش را به برنامک می‌دهد. ایتا در سیاست حریم خصوصی می‌گوید شماره فقط به کسانی نشان داده می‌شود که شما را مخاطب کرده‌اند (https://eitaa.com/page/privacy/).
- **نتیجه:** هر راهِ خودکار (اسکرپ، ساخت حساب برای کاوش، وارد کردن انبوه مخاطبین) یا از شرایط خدمات خارج است یا حریم خصوصیِ طرف را دور می‌زند. NM فقط این کار را می‌کند: لینکِ رسمی را با شماره باز می‌کند (فقط تلگرام/واتساپ) و مشتری/کاربر خودش تصمیم می‌گیرد. (این بخش مشاورهٔ حقوقی نیست.)

## ۴. تنها راهِ مجازِ پیام‌رسان‌های بدون لینک شماره‌دار

۱. شماره را به‌صورت **مخاطب گوشی** ذخیره کنیم (بخش ۵).
۲. اگر آن پیام‌رسان «همگام‌سازی مخاطبین» را روشن داشته باشد، خودش مخاطب را تشخیص می‌دهد و کاربر در کارت مخاطبِ گوشی دکمهٔ آن پیام‌رسان را می‌بیند. شاهد فنی (بدون آزمون روی دستگاه): مانیفست هر سه اپ ایتا، سروش پلاس و روبیکا نوع‌دادهٔ `vnd.android.cursor.item/vnd.<package>.android.profile` را ثبت کرده است (مانند مثال تلگرام در مانیفست رسمی https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/AndroidManifest.xml). این یعنی اپ‌ها در برنامهٔ مخاطبین گوشی «ردیف پروفایل» می‌گذارند؛ تأیید روی گوشی واقعی انجام نشده.
۳. اگر نخواستیم به همین بسنده کنیم، فقط **خودِ اپ پیام‌رسان را باز کنیم** (با `queries` برای نام بسته) تا کاربر دستی جست‌وجو کند.

## ۵. ثبت مخاطب: Intent درج مخاطب

- **Intent:** `ContactsContract.Intents.Insert.ACTION` که برابر `Intent.ACTION_INSERT` است (کد منبع AOSP: https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/provider/ContactsContract.java ).
- **extraهای تأییدشده در AOSP:** `Insert.NAME` = `"name"`، `Insert.PHONE` = `"phone"`، `Insert.PHONE_TYPE`، `Insert.COMPANY` = `"company"`، `Insert.JOB_TITLE`، `Insert.NOTES` = `"notes"`، `Insert.EMAIL`، `Insert.SECONDARY_PHONE`… و `Insert.FULL_MODE` برای دور زدن حالت «درج سریع».
- **نوع MIME:** اپ مخاطبینِ AOSP برای `ACTION_INSERT` سه نوع را می‌پذیرد: `vnd.android.cursor.dir/person` ، `vnd.android.cursor.dir/contact` ، `vnd.android.cursor.dir/raw_contact` (https://android.googlesource.com/platform/packages/apps/Contacts/+/refs/heads/main/AndroidManifest.xml). پس `intent.setType(ContactsContract.RawContacts.CONTENT_TYPE)` درست است. اپ‌های مخاطبینِ سازنده‌ها (سامسونگ و…) ممکن است فرق کنند؛ تأیید نشده.
- **نکتهٔ Android 11+ (Package visibility):** بر پایهٔ https://developer.android.com/training/package-visibility/automatic : «You can start another app's activity using either an implicit or explicit intent regardless of whether that app is visible to your app». پس `startActivity` برای درج مخاطب نیاز به `queries` ندارد؛ فقط `ActivityNotFoundException` را بگیریم. اما اگر قبلش با `resolveActivity`/`queryIntentActivities` یا `canLaunchUrl` بپرسیم «آیا هست؟»، باید در مانیفست اعلام شود (https://developer.android.com/training/package-visibility/declaring):
  - `<package android:name="org.telegram.messenger"/>` برای هر بستهٔ مشخص (ایتا، بله، سروش پلاس، روبیکا، واتساپ، بیزینس…).
  - یا `<intent>` با دقیقاً یک `<action>`؛ در `<data>` فقط `scheme` / `host` / `mimeType` مجاز است (path و port و pathPattern نادیده گرفته می‌شوند).
  - `QUERY_ALL_PACKAGES` لازم نیست و بهتر است استفاده نشود (در همان سند «guidelines» دارد و گوگل‌پلی محدودش می‌کند).
- **مجوز:** درج با Intent نیاز به `WRITE_CONTACTS` ندارد، چون کاربر در خودِ اپ مخاطبین ذخیره را تأیید می‌کند (راهنمای رسمی Contacts Provider این جلسه دریافت نشد؛ تأیید نشده).
- **پیشنهاد (نه منبع):** شمارهٔ ذخیره‌شده را به قالب `+98912…` بدهیم تا برنامهٔ مخاطبین و پیام‌رسان‌ها بهتر تطبیق دهند.

## ۶. آنچه تأیید نشد

- متن رسمی `faq.whatsapp.com/5913398998672934` (قالب دقیق و رفتار شمارهٔ ناموجود) — فقط منبع ثانویه.
- نام بستهٔ واتساپ از منبع رسمی؛ رفتار `whatsapp://send` روی بیزینس.
- هر قالب شماره‌دار برای ایتا، بله، سروش پلاس و روبیکا (روی دستگاه آزموده نشد؛ فقط ایتا شواهد APK دارد).
- لینک نام‌کاربری کاربر عادی در بله؛ قابل‌اتکا بودن `rubika.ir/{username}`.
- اینکه آیا بله همگام‌سازی مخاطبین به «ردیف پروفایل» می‌گذارد (APK بله بررسی نشد).
- وضعیت واتساپ در ایران ۱۴۰۵.

## ۷. روش کار این پژوهش (برای شفافیت)

- صفحه‌های `core.telegram.org` و `developer.android.com` و `faq.whatsapp.com` از این ماشین مستقیم باز نمی‌شدند؛ نسخهٔ بایگانی‌شدهٔ web.archive.org آن‌ها (۲۰۲۶) خوانده شد. کد AOSP از `android.googlesource.com` و کد تلگرام از GitHub مستقیم خوانده شد.
- APKهای رسمی ایتا، روبیکا و سروش پلاس فقط **برای بررسی ایستا** خوانده شدند: مانیفست از راه HTTP range، و برای ایتا چند فایل dex؛ هیچ چیزی نصب یا اجرا نشد.
- هیچ حساب یا شمارهٔ واقعی آزموده نشد و هیچ جست‌وجوی خودکاری روی سرویس‌ها انجام نشد.
