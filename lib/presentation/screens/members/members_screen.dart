import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/member_sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import 'face_enroll_screen.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Member> _members = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getAllMembers();
    if (!mounted) return;
    setState(() {
      _members = rows.map(Member.fromMap).toList();
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await MemberSyncService.instance.syncFromServer();
    await _load();
    if (mounted) {
      setState(() => _syncing = false);
      _snack('Đã đồng bộ từ AI server', AppColors.success);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController(text: '${_members.length}');
    final roleCtrl = TextEditingController(text: 'Thành viên');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Thêm thành viên', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(idCtrl, 'ID', Icons.tag_rounded),
            const SizedBox(height: 12),
            _field(nameCtrl, 'Tên', Icons.person_rounded),
            const SizedBox(height: 12),
            _field(roleCtrl, 'Vai trò', Icons.badge_rounded),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final id = idCtrl.text.trim();
              final role = roleCtrl.text.trim().isEmpty ? 'Thành viên' : roleCtrl.text.trim();
              if (name.isEmpty || id.isEmpty) return;
              Navigator.pop(ctx);
              _goEnroll(id: id, name: name, role: role);
            },
            child: const Text('Tiếp theo →', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _goEnroll({required String id, required String name, required String role}) async {
    final avatarBase64 = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => FaceEnrollScreen(memberId: id, memberName: name, memberRole: role)),
    );

    if (avatarBase64 != null) {
      await DatabaseHelper.instance.insertMember({
        'id': id,
        'name': name,
        'role': role,
        'avatar': avatarBase64,
      });
      await DatabaseHelper.instance.addLog('Đăng ký khuôn mặt', '$name (ID: $id)');
      await _load();
      if (mounted) _snack('Đã đăng ký: $name', AppColors.success);
    }
  }

  Future<void> _delete(Member member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xoá thành viên?', style: TextStyle(color: Colors.white)),
        content: Text('${member.name} sẽ bị xoá khỏi hệ thống nhận diện.', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await MemberSyncService.instance.deleteFromServer(member.id, member.name);
    await DatabaseHelper.instance.deleteMember(member.id);
    await DatabaseHelper.instance.addLog('Xoá thành viên', '${member.name} (ID: ${member.id})');
    await _load();
    if (mounted) _snack('Đã xoá: ${member.name}', AppColors.error);
  }

  Future<void> _reEnroll(Member member) async {
    final avatarBase64 = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => FaceEnrollScreen(memberId: member.id, memberName: member.name, memberRole: member.role)),
    );
    if (avatarBase64 != null) {
      await DatabaseHelper.instance.insertMember({
        'id': member.id,
        'name': member.name,
        'role': member.role,
        'avatar': avatarBase64,
      });
      await _load();
      if (mounted) _snack('Đã cập nhật khuôn mặt: ${member.name}', AppColors.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            else if (_members.isEmpty)
              Expanded(child: _buildEmpty())
            else
              Expanded(child: _buildList()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('Thêm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thành viên', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('Quản lý khuôn mặt được nhận diện', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          // Sync button
          GestureDetector(
            onTap: _syncing ? null : _sync,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: _syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, color: Colors.white70, size: 20),
            ),
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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline_rounded, color: AppColors.textSecondary, size: 48),
          ),
          const SizedBox(height: 20),
          const Text('Chưa có thành viên', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Thêm khuôn mặt để hệ thống nhận diện hoạt động', style: TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _sync,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentLight,
              side: const BorderSide(color: AppColors.accentLight, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Đồng bộ từ server'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _members.length,
      itemBuilder: (_, i) => _buildCard(_members[i]),
    );
  }

  Widget _buildCard(Member member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        leading: _buildAvatar(member),
        title: Text(member.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(member.role, style: const TextStyle(color: AppColors.accentLight, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text('ID: ${member.id}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Re-enroll
            IconButton(
              icon: const Icon(Icons.camera_alt_rounded, color: AppColors.info, size: 20),
              tooltip: 'Cập nhật khuôn mặt',
              onPressed: () => _reEnroll(member),
            ),
            // Delete
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              tooltip: 'Xoá',
              onPressed: () => _delete(member),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Member member) {
    ImageProvider? provider;
    if (member.isNetworkAvatar) {
      provider = NetworkImage(member.avatar);
    } else if (member.avatar.isNotEmpty) {
      try {
        final bytes = base64Decode(member.avatar);
        provider = MemoryImage(Uint8List.fromList(bytes));
      } catch (_) {}
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: AppColors.accentDim,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.bold, fontSize: 18),
            )
          : null,
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.accentLight), borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: AppColors.surface,
    ),
  );
}
