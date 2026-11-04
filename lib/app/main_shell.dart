import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/assistant/assistant_home_tab.dart';
import 'package:nm_mobile/features/assistant/assistant_page.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/presentation/calls_tab.dart';
import 'package:nm_mobile/features/monitor/monitor_page.dart';
import 'package:nm_mobile/features/more/more_tab.dart';

/// قاب اصلی برنامه بعد از جفت‌سازی: وضعیت NM، تماس‌ها، دستیار، بیشتر.
/// وقتی تماسی زنگ می‌خورد (یا می‌گیریم)، سرویس پس‌زمینه آن را در NM ثبت می‌کند و همین‌جا
/// دستیار تماس خودکار باز می‌شود.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  final CallStateStore _calls = FileCallStateStore();
  Timer? _timer;
  ActiveCall? _active;
  int _shownSession = -1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _checkActiveCall());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkActiveCall() async {
    final st = await _calls.load();
    final a = st.active;
    final cur = (a != null && !a.ended && a.number.isNotEmpty) ? a : null;
    if (!mounted) return;
    if (cur?.session != _active?.session || cur?.uid != _active?.uid) {
      setState(() => _active = cur);
    }
    if (cur != null && cur.session != _shownSession) {
      // کمی صبر می‌کنیم تا ثبتِ تماس در NM (uid) انجام شود؛ بعد از ۸ ثانیه به هر حال باز می‌کنیم.
      final waited = DateTime.now().difference(cur.startedAt);
      if (cur.uid.isNotEmpty || waited > const Duration(seconds: 8)) {
        _shownSession = cur.session;
        _openAssistant(cur);
      }
    }
  }

  void _openAssistant(ActiveCall a) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantPage(number: a.number, callUid: a.uid.isEmpty ? null : a.uid, direction: a.direction),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['وضعیت NM', 'تماس‌ها', 'دستیار', 'بیشتر'];
    final a = _active;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab], style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          if (a != null)
            Material(
              color: AppColors.primary.withValues(alpha: 0.16),
              child: InkWell(
                onTap: () => _openAssistant(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.call_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تماس ${a.direction == 'out' ? 'خروجی' : 'ورودی'}: ${a.display ?? a.number} — باز کردن دستیار',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [MonitorPage(), CallsTab(), AssistantHomeTab(), MoreTab()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart_rounded),
              label: 'وضعیت NM',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              selectedIcon: Icon(Icons.call_rounded),
              label: 'تماس‌ها',
            ),
            NavigationDestination(
              icon: Icon(Icons.support_agent_outlined),
              selectedIcon: Icon(Icons.support_agent_rounded),
              label: 'دستیار',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_rounded),
              selectedIcon: Icon(Icons.menu_open_rounded),
              label: 'بیشتر',
            ),
          ],
        ),
      ),
    );
  }
}
