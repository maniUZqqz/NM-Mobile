import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:nm_mobile/app/main_shell.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/connect/connect_screen.dart';

/// اگر گوشی جفت نشده باشد صفحهٔ اتصال، وگرنه برنامهٔ اصلی.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  StreamSubscription<Map<String, dynamic>?>? _revokedSub;

  @override
  void initState() {
    super.initState();
    NmSession.instance.load();
    // سرویس پس‌زمینه وقتی بفهمد توکن لغو شده خبر می‌دهد؛ برگردیم به صفحهٔ اتصال
    try {
      _revokedSub = FlutterBackgroundService().on('sessionRevoked').listen((_) {
        NmSession.instance.load();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _revokedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NmSession.instance,
      builder: (context, _) {
        final s = NmSession.instance;
        if (!s.loaded) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        return s.paired ? const MainShell() : const ConnectScreen();
      },
    );
  }
}
