import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/app_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _svc = AppNotificationService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onUpdate);
    _svc.markAllRead();
  }

  @override
  void dispose() {
    _svc.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  String _formatTime(DateTime t) {
    final now  = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1)  return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours   < 24) return '${diff.inHours} giờ trước';
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _svc.items;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(items),
            Expanded(
              child: items.isEmpty ? _buildEmpty() : _buildList(items),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<AppNotification> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thông báo',
                    style: TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('Nhận diện & cảnh báo hệ thống',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (items.isNotEmpty)
            TextButton.icon(
              onPressed: () => _svc.clearAll(),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Xoá hết'),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: Colors.white24, size: 52),
          ),
          const SizedBox(height: 20),
          const Text('Chưa có thông báo',
              style: TextStyle(color: Colors.white54, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Thông báo nhận diện và cảnh báo\nsẽ hiện ở đây',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList(List<AppNotification> items) {
    // Nhóm theo ngày
    final Map<String, List<AppNotification>> grouped = {};
    for (final n in items) {
      final now  = DateTime.now();
      final diff = now.difference(n.time);
      final key  = diff.inDays == 0 ? 'Hôm nay'
                 : diff.inDays == 1 ? 'Hôm qua'
                 : '${n.time.day}/${n.time.month}/${n.time.year}';
      grouped.putIfAbsent(key, () => []).add(n);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
            child: Text(entry.key,
                style: const TextStyle(color: Colors.white38, fontSize: 12,
                    fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
          ...entry.value.map((n) => _buildCard(n)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCard(AppNotification n) {
    final isAlert = n.isAlert;
    final color   = isAlert ? Colors.redAccent : AppColors.accentLight;
    final icon    = isAlert
        ? Icons.warning_amber_rounded
        : Icons.face_retouching_natural_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isAlert
              ? Colors.red.withOpacity(0.08)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isAlert
                ? Colors.redAccent.withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          color: isAlert ? Colors.redAccent : Colors.white,
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(n.body,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          color: AppColors.textDim, size: 11),
                      const SizedBox(width: 4),
                      Text(_formatTime(n.time),
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
