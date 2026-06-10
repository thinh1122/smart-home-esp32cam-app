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

    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(ac, items),
            Expanded(
              child: items.isEmpty ? _buildEmpty(ac) : _buildList(ac, items),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AC ac, List<AppNotification> items) {
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 20, 12, 12),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thông báo',
                    style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Nhận diện & cảnh báo hệ thống',
                    style: TextStyle(color: ac.textSecondary, fontSize: 13)),
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

  Widget _buildEmpty(AC ac) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ac.border,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_rounded, color: ac.iconFaint, size: 52),
          ),
          const SizedBox(height: 20),
          Text('Chưa có thông báo',
              style: TextStyle(color: ac.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Thông báo nhận diện và cảnh báo\nsẽ hiện ở đây',
              textAlign: TextAlign.center,
              style: TextStyle(color: ac.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList(AC ac, List<AppNotification> items) {
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
                style: TextStyle(color: ac.textDim, fontSize: 12,
                    fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
          ...entry.value.map((n) => _buildCard(ac, n)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCard(AC ac, AppNotification n) {
    final isAlert = n.isAlert;
    final color   = isAlert ? Colors.redAccent : ac.accentLight;
    final icon    = isAlert
        ? Icons.warning_amber_rounded
        : Icons.face_retouching_natural_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isAlert ? Colors.red.withOpacity(0.08) : ac.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isAlert ? Colors.redAccent.withOpacity(0.3) : ac.border,
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
                          color: isAlert ? Colors.redAccent : ac.textPrimary,
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(n.body, style: TextStyle(color: ac.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, color: ac.textDim, size: 11),
                      const SizedBox(width: 4),
                      Text(_formatTime(n.time), style: TextStyle(color: ac.textDim, fontSize: 11)),
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
