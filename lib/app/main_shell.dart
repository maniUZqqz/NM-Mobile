import 'package:flutter/material.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/more/more_tab.dart';
import 'package:nm_mobile/features/monitor/monitor_page.dart';

/// قاب اصلی برنامه بعد از جفت‌سازی: وضعیت NM، تماس‌ها، دستیار، بیشتر.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['وضعیت NM', 'بیشتر'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_tab],
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [MonitorPage(), MoreTab()],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
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
