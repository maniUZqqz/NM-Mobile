import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/domain/brand_guide.dart';
import 'package:nm_mobile/features/calls/domain/recording_matcher.dart';
import 'package:nm_mobile/features/calls/presentation/call_format.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// راه‌اندازی ضبط تماس (برگرفته از صفحهٔ راه‌اندازیِ SMS-and-call). فقط یک راه داریم: خواندنِ فایل‌های
/// ضبط‌کنندهٔ داخلیِ خودِ گوشی. ضبط‌کنندهٔ دسترس‌پذیری، تبدیل به متنِ روی گوشی و ارسال به سرورِ دلخواه
/// در NM-Mobile نیست؛ متن را فقط NM می‌سازد.
class CallSetupPage extends StatefulWidget {
  const CallSetupPage({super.key});

  @override
  State<CallSetupPage> createState() => _CallSetupPageState();
}

class _CallSetupPageState extends State<CallSetupPage> with WidgetsBindingObserver {
  CallSettings _settings = const CallSettings();
  BridgeStatus _status = BridgeStatus.unknown;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // بعد از برگشت از صفحهٔ مجوزها، وضعیت را تازه کن
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _load() async {
    final settings = await CallSettingsStorage.load();
    final status = await SmsBridge.status();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _status = status;
      _loading = false;
    });
  }

  Future<void> _refreshStatus() async {
    final status = await SmsBridge.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  RecorderBrand get _brand =>
      detectRecorderBrand(manufacturer: _status.manufacturer, brand: _status.brand, model: _status.model);

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _acceptConsent() async {
    final at = DateTime.now();
    setState(() => _settings = _settings.copyWith(consentAcceptedAt: at));
    await CallSettingsStorage.update((s) => s.copyWith(consentAcceptedAt: at));
  }

  Future<void> _request(Permission permission) async {
    try {
      await permission.request();
    } catch (_) {}
    await _refreshStatus();
    if (!mounted) return;
    final granted = await permission.isGranted;
    if (!granted && await permission.isPermanentlyDenied) {
      _snack('اجازه بسته شده؛ از تنظیمات برنامه روشنش کنید.');
      await openAppSettings();
    }
  }

  Permission get _audioPermission => _status.sdk >= 33 ? Permission.audio : Permission.storage;

  Future<void> _save() async {
    if (!_settings.consentAccepted) {
      _snack('ابتدا اطلاعیه‌ی مسئولیت ضبط را بپذیرید.');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = _settings.copyWith(setupCompleted: true);
      await CallSettingsStorage.update((current) => updated.copyWith(lastScanAtMillis: current.lastScanAtMillis));
      try {
        final service = FlutterBackgroundService();
        if (await service.isRunning()) service.invoke('scanRecordings');
      } catch (_) {}
      if (!mounted) return;
      setState(() => _settings = updated);
      _snack('ذخیره شد. ضبط‌های تازه خودکار پیدا می‌شوند؛ به NM فقط با رضایتِ ثبت‌شده می‌روند.');
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('ضبط تماس')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final guide = guideFor(_brand);
    return Scaffold(
      appBar: AppBar(title: const Text('ضبط تماس و ارسال به NM')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _chain(theme),
          const SizedBox(height: 14),
          _consentCard(theme),
          if (_settings.consentAccepted) ...[
            const SizedBox(height: 14),
            _permissionsCard(theme),
            const SizedBox(height: 14),
            _builtInCard(theme, guide),
            const SizedBox(height: 14),
            _nmCard(theme),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: const Text('ذخیره و شروع کار خودکار'),
        ),
      ),
    );
  }

  Widget _chain(ThemeData theme) {
    return _Card(
      icon: Icons.account_tree_rounded,
      color: AppColors.primary,
      title: 'چطور کار می‌کند',
      child: Text(
        '۱) تماس انجام می‌شود و ضبط‌کنندهٔ خودِ گوشی آن را ذخیره می‌کند (اندروید به برنامه‌ها اجازهٔ ضبط صدای تماس نمی‌دهد).\n'
        '۲) NM-Mobile فایل را خودکار پیدا می‌کند و به همان تماس در تاریخچهٔ گوشی وصل می‌کند.\n'
        '۳) «ارسال به NM» را می‌زنید (یا ارسال خودکار را روشن می‌کنید). اگر رضایتِ ضبطِ آن شماره در NM ثبت نباشد، '
        'اول از شما می‌پرسد و بدون تأیید هیچ فایلی نمی‌رود.\n'
        '۴) تبدیل به متن و یادداشتِ هوش مصنوعی در سرور NM انجام می‌شود و در جزئیات تماس می‌آید.',
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.9),
      ),
    );
  }

  Widget _consentCard(ThemeData theme) {
    final accepted = _settings.consentAccepted;
    return _Card(
      icon: Icons.gavel_rounded,
      color: accepted ? AppColors.success : AppColors.warning,
      title: 'اطلاعیه‌ی مسئولیت ضبط تماس',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kRecordingConsentText, style: theme.textTheme.bodyMedium?.copyWith(height: 1.8)),
          const SizedBox(height: 10),
          if (accepted)
            const StatusPill(label: 'پذیرفته شد', color: AppColors.success, icon: Icons.check_circle_rounded)
          else
            FilledButton.icon(
              onPressed: _acceptConsent,
              icon: const Icon(Icons.check_rounded),
              label: const Text('می‌خوانم و مسئولیت را می‌پذیرم'),
            ),
        ],
      ),
    );
  }

  Widget _permissionsCard(ThemeData theme) {
    Widget row(String label, String why, bool ok, Permission? permission) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: ok ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(why, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (!ok && permission != null)
              TextButton(onPressed: () => _request(permission), child: const Text('اجازه بده')),
          ],
        ),
      );
    }

    return _Card(
      icon: Icons.verified_user_rounded,
      color: AppColors.secondary,
      title: 'مجوزهای لازم',
      child: Column(
        children: [
          row('تاریخچه‌ی تماس', 'برای وصل کردن ضبط به شماره، نام و زمان تماس', _status.callLog, Permission.phone),
          row('فایل‌های صوتی', 'برای پیدا کردن فایل ضبط‌کنندهٔ گوشی', _status.audioMedia, _audioPermission),
          row('اعلان‌ها', 'برای پایداری سرویس پس‌زمینه و اعلانِ دستیار تماس', _status.notifications, Permission.notification),
        ],
      ),
    );
  }

  Widget _builtInCard(ThemeData theme, BrandGuide guide) {
    return _Card(
      icon: Icons.phone_in_talk_rounded,
      color: AppColors.accent,
      title: 'ضبط‌کنندهٔ خودِ گوشی',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'گوشی شما: ${_status.manufacturer.isEmpty ? 'نامشخص' : '${_status.manufacturer} ${_status.model}'} '
            '(اندروید ${_status.sdk > 0 ? _androidName(_status.sdk) : '؟'})',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('برند تشخیص‌داده‌شده: ${guide.title}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Text('برای روشن کردن ضبط خودکار در خودِ گوشی:', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          for (var i = 0; i < guide.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(guide.steps[i], style: theme.textTheme.bodyMedium?.copyWith(height: 1.7))),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _note(theme, Icons.folder_open_rounded, 'محل ذخیره: ${guide.folderHint}'),
          if (guide.caveat.isNotEmpty) _note(theme, Icons.warning_amber_rounded, guide.caveat, color: AppColors.warning),
          if (!guide.canWatchFolder)
            _note(
              theme,
              Icons.block_rounded,
              'روی این برند فایل ضبط برای برنامهٔ دیگر قابل خواندن نیست؛ ضبط تماس از راه NM-Mobile ممکن نیست.',
              color: AppColors.error,
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.watchPhoneRecorder,
            onChanged: (v) => setState(() => _settings = _settings.copyWith(watchPhoneRecorder: v)),
            title: const Text('پیدا کردن خودکار فایل‌های ضبط‌کنندهٔ گوشی'),
            subtitle: const Text(
              'پوشه‌های سامسونگ، شیائومی، هواوی، اوپو/ریلمی/وان‌پلاس، ویوو و ضبط‌کننده‌های دیگر بررسی می‌شود.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _nmCard(ThemeData theme) {
    return _Card(
      icon: Icons.cloud_upload_rounded,
      color: AppColors.primary,
      title: 'ارسال به NM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.autoUploadToNm,
            onChanged: (v) => setState(() => _settings = _settings.copyWith(autoUploadToNm: v)),
            title: const Text('ارسال خودکار به NM'),
            subtitle: const Text(
              'فقط برای شماره‌هایی که رضایتِ ضبطشان قبلاً در NM ثبت شده. برای بقیه فایل نمی‌رود و منتظرِ تأییدِ شما می‌ماند.',
              style: TextStyle(height: 1.6),
            ),
          ),
          _note(
            theme,
            Icons.verified_user_rounded,
            'بدون ثبتِ رضایت هیچ فایلی ارسال نمی‌شود، چه خودکار چه دستی. تبدیل به متن فقط در سرور NM است.',
            color: AppColors.success,
          ),
          DropdownButtonFormField<int>(
            initialValue: _settings.importDays,
            decoration: const InputDecoration(labelText: 'در اولین اسکن، ضبط‌های چند روز اخیر وارد شود؟'),
            items: const [1, 3, 7, 14, 30]
                .map((d) => DropdownMenuItem<int>(value: d, child: Text('$d روز اخیر')))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _settings = _settings.copyWith(importDays: v));
            },
          ),
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.7))),
        ],
      ),
    );
  }

  String _androidName(int sdk) {
    const names = {
      24: '7',
      25: '7.1',
      26: '8',
      27: '8.1',
      28: '9',
      29: '10',
      30: '11',
      31: '12',
      32: '12L',
      33: '13',
      34: '14',
      35: '15',
      36: '16',
    };
    return names[sdk] ?? 'API $sdk';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.color, required this.title, required this.child});

  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
