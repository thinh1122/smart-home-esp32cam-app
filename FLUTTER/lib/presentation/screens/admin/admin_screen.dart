import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _logs  = [];
  bool _loading = true;
  int? _filterUserId; // null = tất cả

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await DatabaseHelper.instance.getAllUsers();
    final logs  = await DatabaseHelper.instance.getAllLogs(limit: 100);
    if (!mounted) return;
    setState(() { _users = users; _logs = logs; _loading = false; });
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final ac = AC.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ac.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Xoá tài khoản?', style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Xoá "${user['name']}" và toàn bộ thiết bị, thành viên của tài khoản này?',
            style: TextStyle(color: ac.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Huỷ', style: TextStyle(color: ac.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Xoá', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await DatabaseHelper.instance.addLog(
      'Admin xoá tài khoản', '${user['name']} (${user['email']})', userId: 0);
    await DatabaseHelper.instance.deleteUser(user['id']);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã xoá tài khoản ${user['name']}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      appBar: AppBar(
        backgroundColor: ac.card,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Colors.red, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin Panel',
                    style: TextStyle(color: ac.textPrimary,
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Smart Home System',
                    style: TextStyle(color: ac.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh_rounded, color: ac.iconMuted),
          ),
          IconButton(
            onPressed: () async {
              await AuthService.instance.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
              );
            },
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: ac.accent,
          unselectedLabelColor: ac.textSecondary,
          indicatorColor: ac.accent,
          tabs: const [
            Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'Tài khoản'),
            Tab(icon: Icon(Icons.devices_rounded, size: 18), text: 'Thiết bị'),
            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Lịch sử'),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: ac.accent))
          : TabBarView(
              controller: _tab,
              children: [
                _buildUsersTab(ac),
                _buildDevicesTab(ac),
                _buildLogsTab(ac),
              ],
            ),
    );
  }

  // ── TAB 1: USERS ──────────────────────────────────────────
  Widget _buildUsersTab(AC ac) {
    final realUsers = _users.where((u) =>
        u['email'].toString().toLowerCase() != 'admin@gmail.com').toList();

    return Column(
      children: [
        _statBar(ac, realUsers.length),
        Expanded(
          child: realUsers.isEmpty
              ? _empty(ac, 'Chưa có tài khoản nào')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: realUsers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _userCard(ac, realUsers[i]),
                ),
        ),
      ],
    );
  }

  Widget _statBar(AC ac, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: ac.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ac.accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.people_alt_rounded, color: ac.accent, size: 22),
          const SizedBox(width: 12),
          Text('Tổng số tài khoản: ',
              style: TextStyle(color: ac.textSecondary, fontSize: 14)),
          Text('$count',
              style: TextStyle(color: ac.accent,
                  fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _userCard(AC ac, Map<String, dynamic> user) {
    final name  = user['name'] ?? '';
    final email = user['email'] ?? '';
    final id    = user['id'] as int;
    final createdAt = user['created_at'] ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ac.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: ac.accent.withOpacity(0.15),
          child: Text(initial,
              style: TextStyle(color: ac.accent,
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        title: Text(name,
            style: TextStyle(color: ac.textPrimary,
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(email,
            style: TextStyle(color: ac.textSecondary, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 20),
              onPressed: () => _deleteUser(user),
            ),
            Icon(Icons.expand_more_rounded, color: ac.iconMuted),
          ],
        ),
        children: [
          _userDetail(ac, id, createdAt),
        ],
      ),
    );
  }

  Widget _userDetail(AC ac, int userId, String createdAt) {
    return FutureBuilder(
      future: Future.wait([
        DatabaseHelper.instance.getDevicesByUserId(userId),
        DatabaseHelper.instance.getMembersByUserId(userId),
      ]),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: CircularProgressIndicator(color: ac.accent, strokeWidth: 2),
          );
        }
        final devices = snap.data![0];
        final members = snap.data![1];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(color: ac.divider),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    color: ac.textDim, size: 13),
                const SizedBox(width: 6),
                Text('Đăng ký: ${_formatDate(createdAt)}',
                    style: TextStyle(color: ac.textDim, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            // Devices
            Row(
              children: [
                Icon(Icons.devices_rounded, color: ac.accentLight, size: 14),
                const SizedBox(width: 6),
                Text('Thiết bị (${devices.length})',
                    style: TextStyle(color: ac.textSecondary,
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            if (devices.isEmpty)
              Text('  Chưa có thiết bị',
                  style: TextStyle(color: ac.textDim, fontSize: 12))
            else
              ...devices.map((d) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    Icon(_deviceIcon(d['device_type']),
                        color: ac.accentLight, size: 13),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      '${d['name']} · ${d['room']}',
                      style: TextStyle(color: ac.textPrimary, fontSize: 12),
                    )),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ac.accentDim,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(d['device_type'] ?? '',
                          style: TextStyle(color: ac.accentLight, fontSize: 10)),
                    ),
                  ],
                ),
              )),
            const SizedBox(height: 10),
            // Members
            Row(
              children: [
                Icon(Icons.face_rounded, color: Colors.green, size: 14),
                const SizedBox(width: 6),
                Text('Thành viên nhận diện (${members.length})',
                    style: TextStyle(color: ac.textSecondary,
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            if (members.isEmpty)
              Text('  Chưa đăng ký khuôn mặt',
                  style: TextStyle(color: ac.textDim, fontSize: 12))
            else
              ...members.map((m) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        color: Colors.green, size: 13),
                    const SizedBox(width: 6),
                    Text('${m['name']} · ${m['role'] ?? ''}',
                        style: TextStyle(color: ac.textPrimary, fontSize: 12)),
                  ],
                ),
              )),
          ],
        );
      },
    );
  }

  // ── TAB 2: DEVICES ────────────────────────────────────────
  Widget _buildDevicesTab(AC ac) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getAllDevices(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: ac.accent));
        }
        final devices = snap.data!;
        if (devices.isEmpty) return _empty(ac, 'Chưa có thiết bị nào');

        // Group by device_type
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final d in devices) {
          final type = d['device_type'] ?? 'other';
          grouped.putIfAbsent(type, () => []).add(d);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Summary chips
            Wrap(
              spacing: 8, runSpacing: 8,
              children: grouped.entries.map((e) => _chip(
                ac, _deviceIcon(e.key), e.key, e.value.length,
              )).toList(),
            ),
            const SizedBox(height: 16),
            ...grouped.entries.map((e) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(_deviceIcon(e.key), color: ac.accentLight, size: 16),
                    const SizedBox(width: 8),
                    Text(e.key.toUpperCase(),
                        style: TextStyle(color: ac.textSecondary,
                            fontSize: 11, fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                  ]),
                ),
                ...e.value.map((d) => _deviceRow(ac, d)),
                const SizedBox(height: 16),
              ],
            )),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getAllDevices() async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery('''
      SELECT d.*, u.name as user_name, u.email as user_email
      FROM devices d
      LEFT JOIN users u ON d.user_id = u.id
      ORDER BY d.created_at DESC
    ''');
  }

  Widget _chip(AC ac, IconData icon, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ac.accentDim,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ac.accent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: ac.accentLight, size: 14),
          const SizedBox(width: 6),
          Text('$label: $count',
              style: TextStyle(color: ac.accentLight,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _deviceRow(AC ac, Map<String, dynamic> d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ac.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: ac.accentDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_deviceIcon(d['device_type']),
                color: ac.accentLight, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['name'] ?? '',
                    style: TextStyle(color: ac.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${d['room']} · ${d['user_name'] ?? 'Unknown'}',
                    style: TextStyle(color: ac.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(_formatDate(d['created_at'] ?? ''),
              style: TextStyle(color: ac.textDim, fontSize: 10)),
        ],
      ),
    );
  }

  // ── TAB 3: LOGS ───────────────────────────────────────────
  Widget _buildLogsTab(AC ac) {
    final realUsers = _users.where((u) =>
        u['email'].toString().toLowerCase() != 'admin@gmail.com').toList();

    final filtered = _filterUserId == null
        ? _logs
        : _logs.where((l) => l['user_id'] == _filterUserId).toList();

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: ac.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ac.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _filterUserId,
                isExpanded: true,
                dropdownColor: ac.card,
                icon: Icon(Icons.filter_list_rounded, color: ac.accentLight, size: 18),
                style: TextStyle(color: ac.textPrimary, fontSize: 13),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tất cả tài khoản', style: TextStyle(color: ac.textSecondary)),
                  ),
                  ...realUsers.map((u) => DropdownMenuItem<int?>(
                    value: u['id'] as int,
                    child: Text('${u['name']} (${u['email']})',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ac.textPrimary)),
                  )),
                ],
                onChanged: (v) => setState(() => _filterUserId = v),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Expanded(child: _empty(ac, 'Chưa có lịch sử hoạt động'))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final log     = filtered[i];
                final isFirst = i == 0;
                final isLast  = i == filtered.length - 1;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 40,
                        child: Column(
                          children: [
                            if (!isFirst)
                              Expanded(child: Center(child: Container(width: 2, color: ac.border))),
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _logColor(log['action'] ?? ''),
                                border: Border.all(color: ac.bg, width: 2),
                              ),
                            ),
                            if (!isLast)
                              Expanded(child: Center(child: Container(width: 2, color: ac.border))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(bottom: 10, top: isFirst ? 0 : 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ac.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ac.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _logColor(log['action'] ?? '').withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(log['action'] ?? '',
                                        style: TextStyle(
                                          color: _logColor(log['action'] ?? ''),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        )),
                                  ),
                                  const Spacer(),
                                  Text(_formatDateTime(log['timestamp'] ?? ''),
                                      style: TextStyle(color: ac.textDim, fontSize: 10)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(log['detail'] ?? '',
                                  style: TextStyle(color: ac.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────
  Widget _empty(AC ac, String msg) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inbox_rounded, color: ac.textDim, size: 48),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(color: ac.textDim, fontSize: 14)),
      ],
    ),
  );

  IconData _deviceIcon(String? type) {
    switch (type) {
      case 'light':  return Icons.lightbulb_rounded;
      case 'camera': return Icons.videocam_rounded;
      case 'relay':  return Icons.power_rounded;
      default:       return Icons.devices_rounded;
    }
  }

  Color _logColor(String action) {
    if (action.contains('Xoá') || action.contains('xoá')) return AppColors.error;
    if (action.contains('Đăng ký') || action.contains('đăng ký')) return AppColors.success;
    if (action.contains('Thêm') || action.contains('thêm')) return AppColors.accent;
    return AppColors.accentLight;
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
    } catch (_) { return iso; }
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} '
          '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }
}
