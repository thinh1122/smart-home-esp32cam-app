import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/app_notification_service.dart';
import '../../core/services/database_helper.dart';
import 'dashboard/home_dashboard.dart';
import 'devices/devices_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  void switchTab(int index) {
    if (mounted) setState(() => _currentIndex = index);
  }

  static const _tabs = [
    _TabItem(icon: Icons.home_rounded,         label: 'Home'),
    _TabItem(icon: Icons.devices_rounded,       label: 'Devices'),
    _TabItem(icon: Icons.notifications_rounded, label: 'Thông báo'),
    _TabItem(icon: Icons.person_rounded,        label: 'Profile'),
  ];

  final _pages = const [
    HomeDashboard(),
    DevicesScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(ac),
    );
  }

  Widget _buildBottomNav(AC ac) {
    return Container(
      decoration: BoxDecoration(
        color: ac.card,
        border: Border(top: BorderSide(color: ac.divider, width: 0.5)),
        boxShadow: [
          BoxShadow(color: ac.shadowColor, blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_tabs.length, (i) => _buildNavItem(i, ac)),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, AC ac) {
    final isActive   = _currentIndex == index;
    final tab        = _tabs[index];
    final isNotifTab = index == 2;

    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (isNotifTab) AppNotificationService.instance.markAllRead();
        if (index == 0 || index == 1) {
          DatabaseHelper.deviceListNotifier.value++;
        }
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? ac.accentDim : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isNotifTab
            ? _buildNotifIcon(isActive, ac)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon,
                      color: isActive ? ac.accentLight : ac.textSecondary,
                      size: 22),
                  const SizedBox(height: 4),
                  Text(tab.label,
                      style: TextStyle(
                        color: isActive ? ac.accentLight : ac.textSecondary,
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      )),
                ],
              ),
      ),
    );
  }

  Widget _buildNotifIcon(bool isActive, AC ac) {
    return ListenableBuilder(
      listenable: AppNotificationService.instance,
      builder: (_, __) {
        final count = AppNotificationService.instance.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  count > 0
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_rounded,
                  color: isActive
                      ? ac.accentLight
                      : count > 0
                          ? Colors.orangeAccent
                          : ac.textSecondary,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text('Thông báo',
                    style: TextStyle(
                      color: isActive ? ac.accentLight : ac.textSecondary,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
            if (count > 0)
              Positioned(
                right: -6, top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TabItem {
  final IconData icon;
  final String   label;
  const _TabItem({required this.icon, required this.label});
}
