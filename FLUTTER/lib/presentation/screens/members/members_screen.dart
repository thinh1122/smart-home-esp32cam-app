import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';
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
    final rows = await DatabaseHelper.instance.getAllMembers(userId: AuthService.instance.userId);
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
      builder: (ctx) {
        final ac = AC.of(ctx);
        return AlertDialog(
          backgroundColor: ac.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Thêm thành viên', style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(ac, idCtrl, 'ID', Icons.tag_rounded),
              const SizedBox(height: 12),
              _field(ac, nameCtrl, 'Tên', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(ac, roleCtrl, 'Vai trò', Icons.badge_rounded),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Huỷ', style: TextStyle(color: ac.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ac.accent,
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
        );
      },
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
      }, userId: AuthService.instance.userId);
      await DatabaseHelper.instance.addLog('Đăng ký khuôn mặt', '$name (ID: $id)');
      await _load();
      if (mounted) _snack('Đã đăng ký: $name', AppColors.success);
    }
  }

  Future<void> _delete(Member member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ac = AC.of(ctx);
        return AlertDialog(
          backgroundColor: ac.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Xoá thành viên?', style: TextStyle(color: ac.textPrimary)),
          content: Text('${member.name} sẽ bị xoá khỏi hệ thống nhận diện.', style: TextStyle(color: ac.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Huỷ', style: TextStyle(color: ac.textSecondary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xoá', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
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
      }, userId: AuthService.instance.userId);
      await _load();
      if (mounted) _snack('Đã cập nhật khuôn mặt: ${member.name}', AppColors.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(ac),
            if (_loading)
              Expanded(child: Center(child: CircularProgressIndicator(color: ac.accent)))
            else if (_members.isEmpty)
              Expanded(child: _buildEmpty(ac))
            else
              Expanded(child: _buildList(ac)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: ac.accent,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('Thêm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHeader(AC ac) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 16),
      child: Row(
        children: [
          if (Navigator.canPop(context))
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thành viên', style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Quản lý khuôn mặt được nhận diện', style: TextStyle(color: ac.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _syncing ? null : _sync,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ac.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ac.border),
              ),
              child: _syncing
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: ac.accent, strokeWidth: 2))
                  : Icon(Icons.sync_rounded, color: ac.textSecondary, size: 20),
            ),
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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: ac.card,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline_rounded, color: ac.textSecondary, size: 48),
          ),
          const SizedBox(height: 20),
          Text('Chưa có thành viên', style: TextStyle(color: ac.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Thêm khuôn mặt để hệ thống nhận diện hoạt động',
              style: TextStyle(color: ac.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _sync,
            style: OutlinedButton.styleFrom(
              foregroundColor: ac.accentLight,
              side: BorderSide(color: ac.accentLight, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Đồng bộ từ server'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AC ac) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _members.length,
      itemBuilder: (_, i) => _buildCard(ac, _members[i]),
    );
  }

  Widget _buildCard(AC ac, Member member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ac.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        leading: _buildAvatar(ac, member),
        title: Text(member.name, style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: ac.accentDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(member.role, style: TextStyle(color: ac.accentLight, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text('ID: ${member.id}', style: TextStyle(color: ac.textSecondary, fontSize: 11)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.camera_alt_rounded, color: AppColors.info, size: 20),
              tooltip: 'Cập nhật khuôn mặt',
              onPressed: () => _reEnroll(member),
            ),
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

  Widget _buildAvatar(AC ac, Member member) {
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
      backgroundColor: ac.accentDim,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(color: ac.accentLight, fontWeight: FontWeight.bold, fontSize: 18),
            )
          : null,
    );
  }

  Widget _field(AC ac, TextEditingController ctrl, String label, IconData icon) => TextField(
    controller: ctrl,
    style: TextStyle(color: ac.textPrimary),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: ac.textSecondary),
      prefixIcon: Icon(icon, color: ac.textSecondary, size: 18),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ac.border), borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: ac.accentLight), borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: ac.cardElevated,
    ),
  );
}
