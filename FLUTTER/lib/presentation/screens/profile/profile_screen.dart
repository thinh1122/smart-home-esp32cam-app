import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/mqtt_service.dart';
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
    final devices = await DatabaseHelper.instance.getAllDevices();
    final members = await DatabaseHelper.instance.getAllMembers();
    if (!mounted) return;
    setState(() {
      _lightDevices = devices.where((d) => d['device_type'] == 'light').toList();
      _lightCount   = _lightDevices.length;
      _cameraCount  = devices.where((d) => d['device_type'] == 'camera').length;
      _memberCount  = members.length;
      _mqttOk       = MQTTService().isConnected;
    });
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
            const SizedBox(height: 28),
            _buildStatRow(),
            const SizedBox(height: 32),
            _sectionTitle('Hệ thống'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoTile(
                icon: Icons.wifi_rounded,
                label: 'MQTT',
                value: _mqttOk ? 'Đã kết nối' : 'Mất kết nối',
                color: _mqttOk ? AppColors.success : Colors.redAccent,
              ),
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
            _sectionTitle('Ứng dụng'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoTile(icon: Icons.info_outline_rounded, label: 'Phiên bản', value: '1.0.0', color: AppColors.textSecondary),
              _InfoTile(icon: Icons.code_rounded, label: 'Nền tảng', value: 'Flutter + ESP32', color: AppColors.textSecondary),
              _InfoTile(icon: Icons.router_rounded, label: 'Giao thức', value: 'MQTT / BLE / MJPEG', color: AppColors.textSecondary),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentDim,
            border: Border.all(color: AppColors.accentLight.withOpacity(0.4), width: 2),
          ),
          child: const Icon(Icons.home_rounded, color: AppColors.accentLight, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Smart Home',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                _mqttOk ? '● Đang hoạt động' : '● Mất kết nối',
                style: TextStyle(
                  color: _mqttOk ? AppColors.success : Colors.redAccent,
                  fontSize: 12, fontWeight: FontWeight.w600,
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

  Widget _buildStatRow() {
    return Row(
      children: [
        _statChip(Icons.lightbulb_rounded, '$_lightCount', 'Đèn',
            AppColors.lightColor, _lightCount > 0 ? _onTapLight : null),
        const SizedBox(width: 10),
        _statChip(Icons.videocam_rounded, '$_cameraCount', 'Camera',
            AppColors.cameraColor, _cameraCount > 0 ? _onTapCamera : null),
        const SizedBox(width: 10),
        _statChip(Icons.people_alt_rounded, '$_memberCount', 'Thành viên',
            AppColors.accentLight, _memberCount > 0 ? _onTapMembers : null),
      ],
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(onTap != null ? 0.35 : 0.15)),
          ),
          child: Column(
            children: [
              Icon(icon, color: onTap != null ? color : color.withOpacity(0.4), size: 22),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      color: onTap != null ? color : color.withOpacity(0.4),
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              if (onTap != null) ...[
                const SizedBox(height: 4),
                Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.5), size: 10),
              ],
            ],
          ),
        ),
      ),
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
