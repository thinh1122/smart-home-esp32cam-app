import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
// ThemeNotifier dùng để toggle dark/light mode
import '../../../core/services/database_helper.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/avatar_service.dart';
import '../../../core/services/device_config_service.dart';
import '../lights/living_room_light_screen.dart';
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
    final members = await DatabaseHelper.instance.getAllMembers();
    if (!mounted) return;
    setState(() {
      _lightDevices = devices.where((d) => d['device_type'] == 'light').toList();
      _lightCount   = _lightDevices.length;
      _cameraCount  = devices.where((d) => d['device_type'] == 'camera').length;
      _memberCount  = members.length;
      _mqttOk       = MQTTService().isConnected;
    });
    // Nếu chưa kết nối thì thử kết nối
    if (!_mqttOk) {
      final ok = await MQTTService().connect();
      if (mounted) setState(() => _mqttOk = ok);
    }
  }

  // Bấm vào chip đèn → chọn phòng rồi navigate
  void _onTapLight() {
    if (_lightDevices.isEmpty) return;
    if (_lightDevices.length == 1) {
      final room = _lightDevices.first['room'] as String;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room)));
      return;
    }
    // Có nhiều đèn → hiện bottom sheet chọn phòng
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Chọn phòng', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._lightDevices.map((d) {
              final room = d['room'] as String;
              final name = d['name'] as String;
              return ListTile(
                leading: const Icon(Icons.lightbulb_rounded, color: AppColors.lightColor),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(room, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
    // Navigate về Home tab (index 0) — dùng Navigator pop về root
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onTapMembers() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const MembersScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 28),
            _buildHeader(),
            const SizedBox(height: 32),
            _sectionTitle('Hệ thống'),
            const SizedBox(height: 12),
            _buildMqttTile(),
            _buildInfoCard([
              _InfoTile(
                icon: Icons.lightbulb_rounded,
                label: 'Đèn thông minh',
                value: '$_lightCount thiết bị',
                color: AppColors.lightColor,
                onTap: _lightCount > 0 ? _onTapLight : null,
              ),
              _InfoTile(
                icon: Icons.videocam_rounded,
                label: 'Camera',
                value: '$_cameraCount thiết bị',
                color: AppColors.cameraColor,
                onTap: _cameraCount > 0 ? _onTapCamera : null,
              ),
              _InfoTile(
                icon: Icons.people_alt_rounded,
                label: 'Thành viên',
                value: '$_memberCount người',
                color: AppColors.accentLight,
                onTap: _memberCount > 0 ? _onTapMembers : null,
              ),
            ]),
            const SizedBox(height: 20),
            _sectionTitle('Cấu hình mạng'),
            const SizedBox(height: 12),
            _buildCameraUrlTile(),
            const SizedBox(height: 20),
            _sectionTitle('Ứng dụng'),
            const SizedBox(height: 12),
            _buildThemeTile(),
            const SizedBox(height: 8),
            _buildInfoCard([
              _InfoTile(icon: Icons.info_outline_rounded, label: 'Phiên bản', value: '1.0.0', color: AppColors.textSecondary),
              _InfoTile(icon: Icons.code_rounded, label: 'Nền tảng', value: 'Flutter + ESP32', color: AppColors.textSecondary),
              _InfoTile(icon: Icons.router_rounded, label: 'Giao thức', value: 'MQTT / BLE / MJPEG', color: AppColors.textSecondary),
            ]),
            const SizedBox(height: 32),
            _buildAuthButtons(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final auth = AuthService.instance;
    return Row(
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: AvatarService.instance,
          builder: (_, path, __) {
            final img = AvatarService.instance.imageProvider;
            return GestureDetector(
              onTap: () async {
                await AvatarService.instance.pickFromGallery();
              },
              child: Stack(
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentDim,
                      border: Border.all(color: AppColors.accentLight.withOpacity(0.4), width: 2),
                      image: img != null
                          ? DecorationImage(image: img, fit: BoxFit.cover)
                          : null,
                    ),
                    child: img == null
                        ? Center(
                            child: Text(
                              auth.userName.isNotEmpty ? auth.userName[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppColors.accentLight,
                                  fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                  ),
                  // Icon camera nhỏ góc dưới phải
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 1.5),
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
                  style: const TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(auth.userEmail,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 2),
              ValueListenableBuilder<bool>(
                valueListenable: MQTTService().connectionNotifier,
                builder: (_, connected, __) => Text(
                  connected ? '● Đang hoạt động' : '● Mất kết nối',
                  style: TextStyle(
                    color: connected ? AppColors.success : Colors.redAccent,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadStats,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 22),
        ),
      ],
    );
  }

  Widget _buildMqttTile() {
    return ValueListenableBuilder<bool>(
      valueListenable: MQTTService().connectionNotifier,
      builder: (_, connected, __) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (connected ? AppColors.success : Colors.redAccent).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.wifi_rounded,
                    color: connected ? AppColors.success : Colors.redAccent, size: 18),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Text('MQTT',
                  style: TextStyle(color: Colors.white, fontSize: 14))),
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
                        style: TextStyle(color: Colors.orange, fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              Text(
                connected ? 'Đã kết nối' : 'Mất kết nối',
                style: TextStyle(
                  color: connected ? AppColors.success : Colors.redAccent,
                  fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButtons() {
    return Column(
      children: [
        // Đổi tên
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showChangeNameDialog,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Đổi tên hiển thị',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppColors.accentLight.withOpacity(0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Đổi mật khẩu
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Đổi mật khẩu',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Đăng xuất
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Đăng xuất',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error.withOpacity(0.15),
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.error.withOpacity(0.3)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Đăng xuất?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc muốn đăng xuất không?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              MQTTService().disconnect();
              await AuthService.instance.logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
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
    final ctrl = TextEditingController(text: AuthService.instance.userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Đổi tên',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nhập tên mới',
            hintStyle: const TextStyle(color: AppColors.textDim),
            filled: true,
            fillColor: AppColors.cardElevated,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final err = await AuthService.instance.changeName(ctrl.text);
              if (!mounted) return;
              Navigator.pop(ctx);
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)));
              } else {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã cập nhật tên')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
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
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final conCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Đổi mật khẩu',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogInput(oldCtrl, 'Mật khẩu cũ', obscure: true),
            const SizedBox(height: 12),
            _dialogInput(newCtrl, 'Mật khẩu mới', obscure: true),
            const SizedBox(height: 12),
            _dialogInput(conCtrl, 'Xác nhận mật khẩu mới', obscure: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newCtrl.text != conCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Mật khẩu mới không khớp')));
                return;
              }
              final err = await AuthService.instance
                  .changePassword(oldCtrl.text, newCtrl.text);
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(err ?? 'Đã đổi mật khẩu thành công')));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Widget _dialogInput(TextEditingController ctrl, String hint,
      {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDim),
        filled: true,
        fillColor: AppColors.cardElevated,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildCameraUrlTile() {
    final cfg = DeviceConfigService.instance;
    final hasUrl = cfg.hasEsp32Ip;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.cameraColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.videocam_rounded, color: AppColors.cameraColor, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('URL Camera', style: TextStyle(color: Colors.white, fontSize: 14)),
                      Text(
                        hasUrl ? '${cfg.esp32Ip}:${cfg.esp32Port}' : 'Tự động (cùng mạng WiFi)',
                        style: TextStyle(
                          color: hasUrl ? AppColors.cameraColor : AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showCameraUrlDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.cameraColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cameraColor.withOpacity(0.3)),
                    ),
                    child: const Text('Sửa', style: TextStyle(color: AppColors.cameraColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            if (hasUrl) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await cfg.saveEsp32Ip('', port: 81);
                  setState(() {});
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xoá — dùng mDNS tự động')));
                },
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded, color: AppColors.textDim, size: 14),
                    const SizedBox(width: 6),
                    const Text('Xoá để dùng tự động (cùng mạng)',
                        style: TextStyle(color: AppColors.textDim, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCameraUrlDialog() {
    final cfg = DeviceConfigService.instance;
    final ctrl = TextEditingController(
      text: cfg.hasEsp32Ip ? '${cfg.esp32Ip}:${cfg.esp32Port}' : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('URL Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập IP local hoặc URL Ngrok:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('VD: 192.168.1.100:81\nVD: abc123.ngrok.io',
                style: TextStyle(color: AppColors.textDim, fontSize: 11)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'IP:port hoặc URL ngrok',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.cardElevated,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.link_rounded, color: AppColors.cameraColor, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = ctrl.text.trim();
              if (input.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              // Parse IP:port hoặc URL ngrok
              String ip; int port = 81;
              if (input.contains(':') && !input.startsWith('http')) {
                final parts = input.split(':');
                ip = parts[0];
                port = int.tryParse(parts[1]) ?? 81;
              } else {
                ip = input.replaceAll(RegExp(r'https?://'), '');
                port = 80;
              }
              await cfg.saveEsp32Ip(ip, port: port);
              if (!mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã lưu: $ip:$port'),
                    backgroundColor: AppColors.success));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cameraColor.withOpacity(0.2),
              foregroundColor: AppColors.cameraColor,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeTile() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (_, mode, __) {
        final isDark = mode == ThemeMode.dark;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
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
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
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

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(color: Colors.white70, fontSize: 13,
          fontWeight: FontWeight.bold, letterSpacing: 0.5));

  Widget _buildInfoCard(List<_InfoTile> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
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
                  borderRadius: BorderRadius.circular(i == 0
                      ? 20 : i == tiles.length - 1 ? 20 : 0),
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
                        Expanded(
                          child: Text(tile.label,
                              style: const TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                        Text(tile.value,
                            style: TextStyle(color: tile.color, fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        if (tile.onTap != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right_rounded,
                              color: tile.color.withOpacity(0.5), size: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (i < tiles.length - 1)
                const Divider(height: 1, color: Colors.white10, indent: 68),
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
