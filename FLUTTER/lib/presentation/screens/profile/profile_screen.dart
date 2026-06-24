import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/avatar_service.dart';
import '../lights/living_room_light_screen.dart';
import '../camera/front_door_cam_screen.dart';
import '../members/members_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int  _lightCount  = 0;
  int  _cameraCount = 0;
  int  _memberCount = 0;
  bool _mqttOk      = false;
  List<Map<String, dynamic>> _lightDevices = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final devices = await DatabaseHelper.instance.getAllDevices(userId: AuthService.instance.userId);
    final members = await DatabaseHelper.instance.getAllMembers(userId: AuthService.instance.userId);
    if (!mounted) return;
    setState(() {
      _lightDevices = devices.where((d) => d['device_type'] == 'light').toList();
      _lightCount   = _lightDevices.length;
      _cameraCount  = devices.where((d) => d['device_type'] == 'camera').length;
      _memberCount  = members.length;
      _mqttOk       = MQTTService().isConnected;
    });
    if (!_mqttOk) {
      final ok = await MQTTService().connect();
      if (mounted) setState(() => _mqttOk = ok);
    }
  }

  void _onTapLight() {
    if (_lightDevices.isEmpty) return;
    if (_lightDevices.length == 1) {
      final room = _lightDevices.first['room'] as String;
      Navigator.push(context, MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room)));
      return;
    }
    final ac = AC.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: ac.iconFaint, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Chọn phòng', style: TextStyle(color: ac.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._lightDevices.map((d) {
              final room = d['room'] as String;
              final name = d['name'] as String;
              return ListTile(
                leading: Icon(Icons.lightbulb_rounded, color: ac.lightColor),
                title: Text(name, style: TextStyle(color: ac.textPrimary)),
                subtitle: Text(room, style: TextStyle(color: ac.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room)));
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _onTapCamera() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FrontDoorCamScreen()));
  }

  void _onTapMembers() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MembersScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 28),
            _buildHeader(ac),
            const SizedBox(height: 32),
            _sectionTitle('Hệ thống', ac),
            const SizedBox(height: 12),
            _buildMqttTile(ac),
            _buildInfoCard(ac, [
              _InfoTile(
                icon: Icons.lightbulb_rounded,
                label: 'Đèn thông minh',
                value: '$_lightCount thiết bị',
                color: ac.lightColor,
                onTap: _lightCount > 0 ? _onTapLight : null,
              ),
              _InfoTile(
                icon: Icons.videocam_rounded,
                label: 'Camera',
                value: '$_cameraCount thiết bị',
                color: ac.cameraColor,
                onTap: _onTapCamera,
              ),
              _InfoTile(
                icon: Icons.people_alt_rounded,
                label: 'Thành viên',
                value: '$_memberCount người',
                color: ac.accentLight,
                onTap: _onTapMembers,
              ),
            ]),
            const SizedBox(height: 20),
            _sectionTitle('Ứng dụng', ac),
            const SizedBox(height: 12),
            _buildThemeTile(ac),
            const SizedBox(height: 8),
            _buildInfoCard(ac, [
              _InfoTile(icon: Icons.info_outline_rounded, label: 'Phiên bản', value: '1.0.0', color: ac.textSecondary),
              _InfoTile(icon: Icons.code_rounded, label: 'Nền tảng', value: 'Flutter + ESP32', color: ac.textSecondary),
              _InfoTile(icon: Icons.router_rounded, label: 'Giao thức', value: 'MQTT / BLE / MJPEG', color: ac.textSecondary),
            ]),
            const SizedBox(height: 32),
            _buildAuthButtons(ac),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AC ac) {
    final auth = AuthService.instance;
    return Row(
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: AvatarService.instance,
          builder: (_, path, __) {
            final img = AvatarService.instance.imageProvider;
            return GestureDetector(
              onTap: () async => AvatarService.instance.pickFromGallery(),
              child: Stack(
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ac.accentDim,
                      border: Border.all(color: ac.accentLight.withOpacity(0.4), width: 2),
                      image: img != null
                          ? DecorationImage(image: img, fit: BoxFit.cover)
                          : null,
                    ),
                    child: img == null
                        ? Center(
                            child: Text(
                              auth.userName.isNotEmpty ? auth.userName[0].toUpperCase() : '?',
                              style: TextStyle(color: ac.accentLight,
                                  fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: ac.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: ac.bg, width: 1.5),
                      ),
                      child: const Icon(Icons.camera_alt_rounded, size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(auth.userName.isNotEmpty ? auth.userName : 'Smart Home',
                  style: TextStyle(color: ac.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(auth.userEmail, style: TextStyle(color: ac.textSecondary, fontSize: 12)),
              const SizedBox(height: 2),
              ValueListenableBuilder<bool>(
                valueListenable: MQTTService().connectionNotifier,
                builder: (_, connected, __) => Text(
                  connected ? '● Đang hoạt động' : '● Mất kết nối',
                  style: TextStyle(
                    color: connected ? ac.success : ac.error,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadStats,
          icon: Icon(Icons.refresh_rounded, color: ac.iconMuted, size: 22),
        ),
      ],
    );
  }

  Widget _buildMqttTile(AC ac) {
    return ValueListenableBuilder<bool>(
      valueListenable: MQTTService().connectionNotifier,
      builder: (_, connected, __) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: ac.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ac.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (connected ? ac.success : ac.error).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.wifi_rounded,
                    color: connected ? ac.success : ac.error, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('MQTT', style: TextStyle(color: ac.textPrimary, fontSize: 14))),
              if (!connected)
                GestureDetector(
                  onTap: () async {
                    final ok = await MQTTService().connect();
                    if (mounted) setState(() => _mqttOk = ok);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: const Text('Kết nối lại',
                        style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              Text(
                connected ? 'Đã kết nối (${MQTTService().lastTransport})' : 'Mất kết nối',
                style: TextStyle(
                  color: connected ? ac.success : ac.error,
                  fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButtons(AC ac) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showChangeNameDialog,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Đổi tên hiển thị',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: ac.accentLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: ac.accentLight.withOpacity(0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Đổi mật khẩu',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: ac.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: ac.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Đăng xuất',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: ac.error.withOpacity(0.15),
              foregroundColor: ac.error,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: ac.error.withOpacity(0.3)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmLogout() {
    final ac = AC.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ac.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Đăng xuất?', style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc muốn đăng xuất không?', style: TextStyle(color: ac.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Huỷ', style: TextStyle(color: ac.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              MQTTService().disconnect();
              await AuthService.instance.logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ac.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  void _showChangeNameDialog() {
    final ac = AC.of(context);
    final ctrl = TextEditingController(text: AuthService.instance.userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ac.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Đổi tên', style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: ac.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nhập tên mới',
            hintStyle: TextStyle(color: ac.textDim),
            filled: true,
            fillColor: ac.cardElevated,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Huỷ', style: TextStyle(color: ac.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final err = await AuthService.instance.changeName(ctrl.text);
              if (!mounted) return;
              Navigator.pop(ctx);
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              } else {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật tên')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ac.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final ac = AC.of(context);
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final conCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ac.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Đổi mật khẩu', style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogInput(ac, oldCtrl, 'Mật khẩu cũ', obscure: true),
            const SizedBox(height: 12),
            _dialogInput(ac, newCtrl, 'Mật khẩu mới', obscure: true),
            const SizedBox(height: 12),
            _dialogInput(ac, conCtrl, 'Xác nhận mật khẩu mới', obscure: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Huỷ', style: TextStyle(color: ac.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newCtrl.text != conCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Mật khẩu mới không khớp')));
                return;
              }
              final err = await AuthService.instance.changePassword(oldCtrl.text, newCtrl.text);
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(err ?? 'Đã đổi mật khẩu thành công')));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ac.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Widget _dialogInput(AC ac, TextEditingController ctrl, String hint, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: TextStyle(color: ac.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ac.textDim),
        filled: true,
        fillColor: ac.cardElevated,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildThemeTile(AC ac) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (_, mode, __) {
        final isDark = mode == ThemeMode.dark;
        return Container(
          decoration: BoxDecoration(
            color: ac.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ac.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.indigo : Colors.orange).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    color: isDark ? Colors.indigo.shade200 : Colors.orange,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(isDark ? 'Giao diện tối' : 'Giao diện sáng',
                      style: TextStyle(color: ac.textPrimary, fontSize: 14)),
                ),
                Switch(
                  value: isDark,
                  onChanged: (_) => ThemeNotifier.instance.toggle(),
                  activeColor: Colors.indigo.shade200,
                  activeTrackColor: Colors.indigo.withOpacity(0.3),
                  inactiveThumbColor: Colors.orange,
                  inactiveTrackColor: Colors.orange.withOpacity(0.2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title, AC ac) => Text(title,
      style: TextStyle(color: ac.textSecondary, fontSize: 13,
          fontWeight: FontWeight.bold, letterSpacing: 0.5));

  Widget _buildInfoCard(AC ac, List<_InfoTile> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ac.border),
      ),
      child: Column(
        children: tiles.asMap().entries.map((e) {
          final i    = e.key;
          final tile = e.value;
          return Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(i == 0 ? 20 : i == tiles.length - 1 ? 20 : 0),
                  onTap: tile.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: tile.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(tile.icon, color: tile.color, size: 18),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text(tile.label, style: TextStyle(color: ac.textPrimary, fontSize: 14))),
                        Text(tile.value, style: TextStyle(color: tile.color, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (tile.onTap != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right_rounded, color: tile.color.withOpacity(0.5), size: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (i < tiles.length - 1)
                Divider(height: 1, color: ac.divider, indent: 68),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _InfoTile {
  final IconData icon;
  final String   label, value;
  final Color    color;
  final VoidCallback? onTap;
  const _InfoTile({required this.icon, required this.label,
      required this.value, required this.color, this.onTap});
}
