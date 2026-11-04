import 'package:flutter/material.dart';

import 'adapter_runner.dart';
import 'login_webview_page.dart';
import 'lookup_facade.dart';
import 'lookup_models.dart';
import 'platforms.dart';

const String _kLocalRules =
    'فقط برای شمارهٔ تماس‌های واقعی همین گوشی (یا یک جستجوی دستی توسط کارمند) انجام می‌شود؛ '
    'هرگز برای فهرست شماره‌ها. فقط چیزی ذخیره می‌شود که خود پیام‌رسان به یک کاربر عادی نشان می‌دهد '
    '(نام، نام کاربری، عکس، بیو، و اینکه شماره در آن پیام‌رسان هست یا نه) و تا ۳۰ روز نگه داشته می‌شود. '
    'ورود به پیام‌رسان‌ها را فقط خودتان با حساب خودتان انجام می‌دهید.';

/// Where the owner logs into the messengers (WebViews), sees which are ready, and reads the
/// ban-risk warning. Nothing here asks for or stores a password or a code.
class MessengersScreen extends StatefulWidget {
  const MessengersScreen({super.key, required this.facade});

  final LookupFacade facade;

  @override
  State<MessengersScreen> createState() => _MessengersScreenState();
}

class _MessengersScreenState extends State<MessengersScreen> {
  LookupConfig? _config;
  String? _error;
  bool _loading = true;
  final Map<String, LoginProbe> _login = <String, LoginProbe>{};
  final Set<String> _busy = <String>{};

  WebViewAdapterRunner? get _webRunner {
    final r = widget.facade.runner;
    return r is WebViewAdapterRunner ? r : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.facade.config();
      if (!mounted) return;
      setState(() {
        _config = c;
        _loading = false;
      });
    } on NmHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = lookupMessage(e.code, e.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تنظیمات از سرور خوانده نشد.';
      });
    }
  }

  LookupPlatformConfig? _serverInfo(String key) {
    final c = _config;
    if (c == null) return null;
    for (final p in c.platforms) {
      if (p.key == key) return p;
    }
    return null;
  }

  Future<void> _probe(PlatformSpec spec) async {
    if (_busy.contains(spec.key)) return;
    setState(() => _busy.add(spec.key));
    LoginProbe result;
    try {
      result = await widget.facade.runner.probe(spec);
    } catch (_) {
      result = const LoginProbe(loggedIn: false, stage: 'error');
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(spec.key);
      _login[spec.key] = result;
    });
  }

  Future<void> _openLogin(PlatformSpec spec) async {
    final runner = _webRunner;
    if (runner == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => LoginWebViewPage(spec: spec, runner: runner)),
    );
    if (mounted) await _probe(spec);
  }

  Future<void> _clear(PlatformSpec spec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('خروج از ${spec.label}'),
        content: Text(
          'نشست ${spec.label} فقط روی همین گوشی پاک می‌شود و دیگر جستجو انجام نمی‌شود. '
          '${spec.key == 'whatsapp' ? 'برای قطع کامل، در واتساپ گوشی اصلی از «دستگاه‌های متصل» هم این دستگاه را حذف کنید. ' : ''}'
          'ادامه می‌دهید؟',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک کردن نشست')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(spec.key));
    try {
      await widget.facade.runner.clearSession(spec);
      if (mounted) _login[spec.key] = const LoginProbe(loggedIn: false, stage: 'signed_out');
    } catch (_) {
      // best effort; the probe below shows the truth
    }
    if (mounted) setState(() => _busy.remove(spec.key));
  }

  String _loginText(PlatformSpec spec) {
    final p = _login[spec.key];
    if (p == null) return 'وضعیت ورود: بررسی نشده';
    if (p.loggedIn) return 'وضعیت ورود: وارد شده‌اید';
    if (p.stage == 'error') return 'وضعیت ورود: بررسی ممکن نشد';
    return 'وضعیت ورود: وارد نشده‌اید';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('پیام‌رسان‌ها'),
        actions: <Widget>[IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('شناسایی تماس‌گیرنده', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(c != null && c.rules.isNotEmpty ? c.rules : _kLocalRules, key: const Key('lookup-rules')),
                ],
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          for (final spec in kWebViewPlatforms) _webViewCard(context, spec),
          for (final p in (c?.platforms ?? const <LookupPlatformConfig>[]).where((p) => p.isServer))
            _serverCard(context, p),
        ],
      ),
    );
  }

  Widget _webViewCard(BuildContext context, PlatformSpec spec) {
    final theme = Theme.of(context);
    final info = _serverInfo(spec.key);
    final busy = _busy.contains(spec.key);
    return Card(
      key: Key('card-${spec.key}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.forum_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(spec.label, style: theme.textTheme.titleMedium)),
                _Chip(
                  text: info == null ? 'وضعیت پنل نامشخص' : (info.enabled ? 'روشن در پنل' : 'خاموش در پنل'),
                  good: info?.enabled == true,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: <Widget>[
              if (spec.experimental) const _Chip(text: 'آزمایشی', good: false),
              if (spec.unavailable) const _Chip(text: 'در دسترس نیست', good: false),
              if (info != null && info.leftToday != null) _Chip(text: 'سهم امروز: ${info.leftToday}', good: true),
            ]),
            const SizedBox(height: 6),
            if (spec.unavailable)
              Text(spec.unavailableReason)
            else ...<Widget>[
              Text(kBanRiskWarning, key: Key('warning-${spec.key}'), style: TextStyle(color: theme.colorScheme.error)),
              if (info != null && info.warning.isNotEmpty && info.warning != kBanRiskWarning)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(info.warning)),
              const SizedBox(height: 6),
              Text(_loginText(spec), style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(spec.loginHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                FilledButton(
                  onPressed: busy || _webRunner == null ? null : () => _openLogin(spec),
                  child: const Text('ورود / باز کردن'),
                ),
                OutlinedButton(onPressed: busy ? null : () => _probe(spec), child: Text(busy ? 'لطفاً صبر کنید…' : 'بررسی ورود')),
                TextButton(onPressed: busy ? null : () => _clear(spec), child: const Text('خروج و پاک کردن نشست')),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _serverCard(BuildContext context, LookupPlatformConfig p) {
    final theme = Theme.of(context);
    final name = p.label.isEmpty ? 'تلگرام' : p.label;
    return Card(
      key: Key('card-${p.key}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
                _Chip(text: p.enabled ? 'روشن در پنل' : 'خاموش در پنل', good: p.enabled),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'جستجوی $name را سرور NM با حساب شخصی خودِ شما انجام می‌دهد. اتصال حساب (شماره، کد و رمز دومرحله‌ای) '
              'فقط از صفحهٔ پنل NM انجام می‌شود؛ این برنامه آن‌ها را نمی‌بیند.',
            ),
            const SizedBox(height: 4),
            Text(p.ready ? 'وضعیت: آماده' : 'وضعیت: هنوز وصل نشده', style: theme.textTheme.bodySmall),
            if (p.warning.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.warning)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.good});

  final String text;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? Colors.green : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}
