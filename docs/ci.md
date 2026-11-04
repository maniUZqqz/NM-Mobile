# ساخت و انتشار (فقط GitHub Actions)

روی سرور NM هیچ Flutter یا Android SDK نصب نمی‌شود؛ ساخت و آزمون فقط در GitHub Actions انجام می‌شود (مخزن عمومی است، پس دقیقه‌های Actions رایگان است).

فایل: `.github/workflows/ci.yml`

| کار (job) | چه می‌کند |
|---|---|
| `check` | `flutter pub get` ⇐ `flutter analyze --no-fatal-infos` ⇐ `flutter test` (شاخه‌های `main` و `phase1*`، هر pull request و هر تگ `v*`) |
| `apk` | بعد از سبز شدنِ `check`: `flutter build apk --release` ⇐ آپلود به‌عنوان Artifact با نام `NM-Mobile-apk` (۳۰ روز) ⇐ فایل `SHA256SUMS.txt` کنارش |
| Release | فقط روی تگ `vX.Y.Z`: همان APK به یک GitHub Release پیوست می‌شود |

## یک نسخهٔ تازه بیرون بدهید
```bash
git checkout main && git pull
git tag v0.1.0
git push origin v0.1.0
```
بعد از چند دقیقه، در صفحهٔ **Releases** فایل `NM-Mobile-v0.1.0-….apk` آماده است. نام نسخه از تگ می‌آید (`0.1.0`) و شمارهٔ ساخت از شمارندهٔ اجرای Actions.

## امضای APK
* **پیش‌فرض:** اگر هیچ راز (secret) ی تنظیم نشده باشد، APK با کلید debug امضا می‌شود؛ نصب می‌شود ولی برای انتشار عمومی مناسب نیست. هیچ keystore ای در مخزن نیست و نباید باشد.
* **اختیاری:** در GitHub ⇐ Settings ⇐ Secrets and variables ⇐ Actions این رازها را بسازید تا APK با کلید خودتان امضا شود:

| راز | مقدار |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | فایل `.jks` به‌صورت base64 (`base64 -w0 release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | رمز keystore |
| `ANDROID_KEY_ALIAS` | نام کلید |
| `ANDROID_KEY_PASSWORD` | رمز کلید |

CI فایل `.jks` را فقط در پوشهٔ موقتِ اجرا می‌سازد (`$RUNNER_TEMP`) و `android/app/build.gradle.kts` فقط از متغیرهای محیطی می‌خواند. توجه: اگر بعداً کلید امضا را عوض کنید، اندروید اجازهٔ «به‌روزرسانی روی نسخهٔ قبلی» نمی‌دهد (باید نسخهٔ قبلی را پاک کنید).

## نکتهٔ ساخت
* نسخهٔ Flutter در CI ثابت است (`3.47.9`، Dart 3.13.7) تا ساخت‌ها تکرارپذیر باشند؛ برای عوض‌کردنش مقدار `flutter-version` را در `.github/workflows/ci.yml` عوض کنید و CI را سبز ببینید.
* Gradle 9.1 و AGP 9 (همان تنظیمِ پروژهٔ اصلی). NDK و مجوزهای SDK در CI خودکار پذیرفته می‌شوند.
* اگر ساخت قرمز شد: `python3 /root/mobile-work/ci.py runs` و `log <job>` روی سرور، یا صفحهٔ Actions.
