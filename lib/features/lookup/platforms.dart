// The five platforms that are looked up ON THE PHONE (WebView). Telegram is done by the
// NM server (method "server") and is not listed here.

/// Desktop Chrome user agent: the web clients (WhatsApp Web in particular) reject mobile ones.
const String kDesktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Safari/537.36';

/// Shown on every card of an unofficial platform, whatever the server sends.
const String kBanRiskWarning =
    'هشدار: این روش غیررسمی است و ممکن است پیام‌رسان حساب شما را محدود یا مسدود کند. '
    'فقط با حساب شخصی خودتان و با احتیاط استفاده کنید.';

class PlatformSpec {
  const PlatformSpec({
    required this.key,
    required this.label,
    required this.webUrl,
    required this.assetName,
    this.unavailableReason = '',
    this.experimental = false,
    this.loginHint = '',
  });

  /// whatsapp | eitaa | bale | soroush | rubika (same keys as the server)
  final String key;
  final String label;

  /// Web client opened for login and for lookups.
  final String webUrl;

  /// File under assets/lookup/ holding the adapter.
  final String assetName;

  /// Non-empty => no safe method exists; the platform is never looked up.
  final String unavailableReason;

  /// Method read from the client's code but not proven on a real account.
  final bool experimental;

  /// One plain sentence telling the owner how to log in on this platform.
  final String loginHint;

  bool get unavailable => unavailableReason.isNotEmpty;
}

const List<PlatformSpec> kWebViewPlatforms = <PlatformSpec>[
  PlatformSpec(
    key: 'whatsapp',
    label: 'واتساپ',
    webUrl: 'https://web.whatsapp.com/',
    assetName: 'whatsapp.js',
    loginHint:
        'روی گوشی دیگری، واتساپ ← دستگاه‌های متصل ← اتصال دستگاه، و کد QR صفحه را اسکن کنید؛ '
        'یا در صفحه «ورود با شماره تلفن» کد هشت‌حرفی را در همان واتساپ وارد کنید.',
  ),
  PlatformSpec(
    key: 'eitaa',
    label: 'ایتا',
    webUrl: 'https://web.eitaa.com/',
    assetName: 'eitaa.js',
    experimental: true,
    loginHint:
        'شماره موبایل خودتان را بنویسید و کدی را که در برنامه ایتا برایتان می‌آید وارد کنید '
        '(یا کد QR را با ایتای گوشی دیگر اسکن کنید).',
  ),
  PlatformSpec(
    key: 'bale',
    label: 'بله',
    webUrl: 'https://web.bale.ai/',
    assetName: 'bale.js',
    experimental: true,
    loginHint: 'شماره موبایل خودتان را بنویسید و کد تأیید پیامک‌شده یا داخل برنامه بله را وارد کنید.',
  ),
  PlatformSpec(
    key: 'soroush',
    label: 'سروش پلاس',
    webUrl: 'https://web.splus.ir/',
    assetName: 'soroush.js',
    experimental: true,
    loginHint:
        'شماره موبایل خودتان را بنویسید و کد تأیید را وارد کنید '
        '(یا کد QR را با سروش پلاس گوشی دیگر اسکن کنید).',
  ),
  PlatformSpec(
    key: 'rubika',
    label: 'روبیکا',
    webUrl: 'https://web.rubika.ir/',
    assetName: 'rubika.js',
    unavailableReason:
        'روبیکا راه امن و رسمی برای پیدا کردن پروفایل از روی شماره ندارد؛ این پلتفرم جستجو نمی‌شود.',
    loginHint: 'ورود به روبیکا فقط برای مشاهده است؛ جستجوی خودکار برای آن انجام نمی‌شود.',
  ),
];

PlatformSpec? platformSpecFor(String key) {
  for (final p in kWebViewPlatforms) {
    if (p.key == key) return p;
  }
  return null;
}
