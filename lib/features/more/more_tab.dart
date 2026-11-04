import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/home/presentation/home_page.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:nm_mobile/features/settings/presentation/permissions_sheet.dart';

/// «بیشتر»: اطلاعات دستگاه، گیت‌وی پیامک، پیام‌رسان‌ها، مجوزها و قطع اتصال.
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  Future<void> _unpair(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded, color: AppColors.warning),
        title: const Text('قطع اتصال این گوشی؟'),
        content: const Text(
          'توکن این گوشی از NM لغو و از گوشی پاک می‌شود. پیامک‌های در صف دیگر '
          'از این گوشی ارسال نمی‌شوند. هر وقت خواستید می‌توانید دوباره جفت کنید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('قطع اتصال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NmSession.instance.unpair();
    try {
      FlutterBackgroundService().invoke('sessionChanged');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = NmSession.instance;
    final data = session.data;
    final client = session.client;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'این گوشی',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                _kv('نام دستگاه', data?.deviceName ?? '-'),
                _kv(
                  'کاربر',
                  data == null
                      ? '-'
                      : (data.displayName.isEmpty
                            ? data.username
                            : '${data.displayName} (${data.username})'),
                ),
                _kv('سرور', data?.serverUrl ?? '-', ltr: true),
                if (data != null && data.serverUrl.startsWith('http://'))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'اتصال شما http است (بدون رمزگذاری). برای امنیت بیشتر از '
                      'https استفاده کنید.',
                      style: TextStyle(color: AppColors.warning, height: 1.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _tile(
          context,
          icon: Icons.sms_rounded,
          title: 'گیت‌وی پیامک',
          subtitle: 'ارسال پیامک‌های صف NM، مخاطب‌ها، کمپین‌ها و گزارش',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const HomePage())),
        ),
        if (client != null)
          _tile(
            context,
            icon: Icons.forum_rounded,
            title: 'پیام‌رسان‌ها',
            subtitle: 'ورود به پیام‌رسان‌ها و شناسایی تماس‌گیرنده',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MessengersScreen(facade: LookupFacade(client)),
              ),
            ),
          ),
        _tile(
          context,
          icon: Icons.verified_user_rounded,
          title: 'مجوزهای گوشی',
          subtitle: 'پیامک، تلفن، اعلان، باتری',
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const PermissionsSheet(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _unpair(context),
          icon: const Icon(Icons.link_off_rounded, color: AppColors.error),
          label: const Text(
            'قطع اتصال این گوشی',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {bool ltr = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              k,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              v,
              textDirection: ltr ? TextDirection.ltr : null,
              textAlign: ltr ? TextAlign.left : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
