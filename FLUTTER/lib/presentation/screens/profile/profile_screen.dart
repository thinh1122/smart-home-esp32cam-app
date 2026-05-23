import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/mqtt_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _lightCount  = 0;
  int _cameraCount = 0;
  int _memberCount = 0;
  bool _mqttOk     = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final devices = await DatabaseHelper.instance.getAllDevices();
    final members = await DatabaseHelper.instance.getAllMembers();
    final mqtt    = MQTTService().isConnected;
    if (!mounted) return;
    setState(() {
      _lightCount  = devices.where((d) => d['device_type'] == 'light').length;
      _cameraCount = devices.where((d) => d['device_type'] == 'camera').length;
      _memberCount = members.length;
      _mqttOk      = mqtt;
    });
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
            _buildAvatar(),
            const SizedBox(height: 32),
            _buildStatRow(),
            const SizedBox(height: 32),
            _sectionTitle('Hệ thống'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow(Icons.wifi_rounded,
                  'MQTT',
                  _mqttOk ? 'Đã kết nối' : 'Mất kết nối',
                  _mqttOk ? AppColors.success : Colors.redAccent),
              _InfoRow(Icons.lightbulb_rounded,
                  'Đèn thông minh', '$_lightCount thiết bị', AppColors.lightColor),
              _InfoRow(Icons.videocam_rounded,
                  'Camera', '$_cameraCount thiết bị', AppColors.cameraColor),
              _InfoRow(Icons.people_alt_rounded,
                  'Thành viên', '$_memberCount người', AppColors.accentLight),
            ]),
            const SizedBox(height: 20),
            _sectionTitle('Ứng dụng'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow(Icons.info_outline_rounded, 'Phiên bản', '1.0.0', AppColors.textSecondary),
              _InfoRow(Icons.code_rounded, 'Nền tảng', 'Flutter + ESP32', AppColors.textSecondary),
              _InfoRow(Icons.router_rounded, 'Giao thức', 'MQTT / BLE / MJPEG', AppColors.textSecondary),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Column(
      children: [
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentDim,
            border: Border.all(color: AppColors.accentLight.withOpacity(0.4), width: 2),
          ),
          child: const Icon(Icons.person_rounded, color: AppColors.accentLight, size: 44),
        ),
        const SizedBox(height: 14),
        const Text('Smart Home',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Hệ thống nhà thông minh ESP32',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ],
    );
  }

  Widget _buildStatRow() {
    return Row(
      children: [
        _statChip(Icons.lightbulb_rounded,    '$_lightCount',  'Đèn',      AppColors.lightColor),
        const SizedBox(width: 10),
        _statChip(Icons.videocam_rounded,     '$_cameraCount', 'Camera',   AppColors.cameraColor),
        const SizedBox(width: 10),
        _statChip(Icons.people_alt_rounded,   '$_memberCount', 'Thành viên', AppColors.accentLight),
      ],
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(color: Colors.white70, fontSize: 13,
            fontWeight: FontWeight.bold, letterSpacing: 0.5));
  }

  Widget _buildInfoCard(List<_InfoRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final i   = e.key;
          final row = e.value;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: row.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(row.icon, color: row.color, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(row.label,
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                    Text(row.value,
                        style: TextStyle(color: row.color, fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (i < rows.length - 1)
                const Divider(height: 1, color: Colors.white10, indent: 68),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String   label, value;
  final Color    color;
  const _InfoRow(this.icon, this.label, this.value, this.color);
}
