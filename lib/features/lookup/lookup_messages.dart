// Persian sentences for the refusals the server (or an adapter) can give. The server's own
// Persian message wins when present; these are the fallbacks and the adapter error codes.

const Map<String, String> kLookupMessages = <String, String>{
  'platform_disabled': 'این پیام‌رسان در پنل NM خاموش است. مدیر باید آن را روشن کند.',
  'no_matching_call': 'جستجو فقط برای شمارهٔ یک تماس واقعی همین گوشی مجاز است.',
  'not_staff': 'این گوشی دیگر به حساب کارمند وصل نیست.',
  'recently_refreshed': 'این شماره تازه جستجو شده؛ تازه‌سازی دوباره بعد از یک ساعت ممکن است.',
  'rate_limited': 'سقف جستجوی امروز/این ساعت پر شده؛ بعداً دوباره تلاش کنید.',
  'bulk_blocked': 'تعداد شماره‌های متفاوت زیاد بود؛ برای ایمنی حساب‌ها جستجو متوقف شد.',
  'bad_number': 'شماره درست نیست.',
  'platform_not_ready': 'این پلتفرم هنوز آماده نیست (مثلاً حساب تلگرام در پنل وصل نشده).',
  'no_call': 'برای جستجو باید شمارهٔ یک تماس واقعی انتخاب شود.',
  // adapter codes
  'login_required': 'وارد این پیام‌رسان نشده‌اید. از «پیام‌رسان‌ها» وارد شوید.',
  'adapter_unavailable': 'برای این پیام‌رسان راه امنی برای جستجو وجود ندارد.',
  'app_not_ready': 'صفحه پیام‌رسان آماده نشد (اینترنت یا ورود را بررسی کنید).',
  'no_result_timeout': 'پیام‌رسان در زمان مقرر جواب نداد.',
  'timeout': 'زمان جستجو تمام شد.',
  'browser_rejected': 'واتساپ این مرورگر را نپذیرفت.',
  'chat_already_open': 'صفحه تازه نبود؛ دوباره تلاش کنید.',
  'no_webpack_runtime': 'ساختار صفحه این پیام‌رسان عوض شده؛ جستجو ممکن نیست.',
  'no_actions_module': 'ساختار صفحه این پیام‌رسان عوض شده؛ جستجو ممکن نیست.',
  'no_query_module': 'ساختار صفحه واتساپ عوض شده؛ جستجو ممکن نیست.',
  'unknown_record_shape': 'قالب داده‌های این پیام‌رسان شناخته نشد.',
  'bad_adapter_output': 'جواب صفحه قابل خواندن نبود.',
};

/// Message for a code: the server's text if it sent one, else our fallback, else a generic line.
String lookupMessage(String code, [String? serverMessage]) {
  if (serverMessage != null && serverMessage.trim().isNotEmpty) return serverMessage.trim();
  final base = code.split(':').first.trim();
  return kLookupMessages[base] ?? 'جستجو انجام نشد ($base).';
}

/// Codes after which nothing else may be tried in this run.
const Set<String> kStopRunCodes = <String>{
  'rate_limited',
  'bulk_blocked',
  'no_matching_call',
  'not_staff',
  'bad_number',
  'no_call',
};
