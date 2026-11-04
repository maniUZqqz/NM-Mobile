import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    NmSession.instance.load();
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
