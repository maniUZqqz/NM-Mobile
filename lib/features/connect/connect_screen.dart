import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:nm_mobile/core/constants/app_constants.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// صفحهٔ اتصال: آدرس سرور + حساب کارمندی NM ⇐ جفت‌سازی و دریافت توکن دستگاه.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.session, this.notifyService = true});

  /// برای تست؛ پیش‌فرض همان نمونهٔ سراسری است.
  final NmSession? session;

  /// بعد از جفت‌سازی به سرویس پس‌زمینه خبر بدهد؟ (در تست خاموش است)
  final bool notifyService;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _url = TextEditingController(text: kSuggestedServerUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();

  bool _busy = false;
  bool _showPass = false;
  String? _error;
  String _model = '';
  String _android = '';

  NmSession get _session => widget.session ?? NmSession.instance;

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    try {
      final s = await SmsBridge.status();
      if (!mounted) return;
      final label = '${s.manufacturer} ${s.model}'.trim();
      setState(() {
        _model = label;
        _android = s.sdk > 0 ? 'API ${s.sdk}' : '';
        if (_name.text.isEmpty && label.isNotEmpty) _name.text = label;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _isPlainHttp {
    final t = _url.text.trim().toLowerCase();
    return t.isNotEmpty && !t.startsWith('https://');
  }

  Future<void> _submit() async {
    if (_busy) return;
    final url = _url.text.trim();
    final user = _user.text.trim();
    final pass = _pass.text;
    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'آدرس سرور، نام کاربری و رمز عبور را وارد کنید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.pair(
        serverUrl: url,
        username: user,
        password: pass,
        deviceName: _name.text.trim().isEmpty ? 'گوشی من' : _name.text.trim(),
        model: _model,
        androidVersion: _android,
      );
      _pass.clear();
      if (widget.notifyService) {
        try {
          FlutterBackgroundService().invoke('sessionChanged');
        } catch (_) {}
      }
    } on NmApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطای غیرمنتظره: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [AppColors.primary, AppColors.secondary],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.hub_rounded,
                        color: AppColors.background,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'اتصال به NM',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'این گوشی را با حساب کارمندی NM جفت کنید. رمز عبور فقط یک بار '
                    'برای جفت‌سازی فرستاده می‌شود و روی گوشی ذخیره نمی‌شود؛ '
                    'بعد از آن فقط یک «توکن دستگاه» می‌ماند که از پنل NM قابل لغو است.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'آدرس سرور NM',
                      hintText: kSuggestedServerUrl,
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                  ),
                  if (_isPlainHttp) ...[
                    const SizedBox(height: 10),
                    const _HttpWarning(),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'نام کاربری NM',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: !_showPass,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'رمز عبور',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _showPass = !_showPass),
                        icon: Icon(
                          _showPass
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'نام این گوشی (در پنل NM دیده می‌شود)',
                      prefixIcon: Icon(Icons.smartphone_rounded),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded),
                    label: Text(_busy ? 'در حال اتصال…' : 'اتصال و جفت‌سازی'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'فقط کاربران «کارمند» NM می‌توانند وصل شوند.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HttpWarning extends StatelessWidget {
  const _HttpWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'این آدرس http است؛ یعنی رمز و توکن بدون رمزگذاری روی شبکه می‌روند '
              'و روی Wi-Fi یا اینترنتِ ناامن قابل شنود است. در صورت امکان '
              'سرور را با https (گواهی SSL) راه‌اندازی کنید و آدرس https بزنید.',
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
