import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/database_helper.dart';
import '../lights/living_room_light_screen.dart';
import 'add_device_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  final Map<String, bool>   _states = {};
  final Map<String, double> _watts  = {};

  StreamSubscription? _stateSub;
  StreamSubscription? _powerSub;

  @override
  void initState() {
    super.initState();
    _loadDevices();

    _stateSub = MQTTService().deviceStateStream.listen((msg) {
      final topic = msg['topic'] as String;
      final data  = msg['data']  as Map<String, dynamic>;
      if (topic.endsWith('/state')) {
        final parts = topic.split('/');
        if (parts.length >= 4) {
          final room = parts[3];
          final validRooms = _devices.map((d) => d['room'] as String).toSet();
          if (!validRooms.contains(room)) return;
          final on = (data['state'] as String?)?.toUpperCase() == 'ON';
          if (mounted) setState(() => _states[room] = on);
        }
      }
    });

    _powerSub = MQTTService().devicePowerStream.listen((msg) {
      final topic = msg['topic'] as String;
      final data  = msg['data']  as Map<String, dynamic>;
      final parts = topic.split('/');
      if (parts.length >= 4) {
        final room = parts[3];
        // Chỉ cập nhật nếu room có trong danh sách thiết bị
        final validRooms = _devices.map((d) => d['room'] as String).toSet();
        if (!validRooms.contains(room)) return;
        final watt = (data['watt'] as num?)?.toDouble() ?? 0;
        if (mounted) setState(() => _watts[room] = watt);
      }
    });
  }

  Future<void> _loadDevices() async {
    final rows = await DatabaseHelper.instance.getAllDevices();
    if (mounted) {
      setState(() {
        _devices = rows;
        // Xoá watts/states của rooms không còn trong DB
        final validRooms = rows.map((d) => d['room'] as String).toSet();
        _watts.removeWhere((room, _) => !validRooms.contains(room));
        _states.removeWhere((room, _) => !validRooms.contains(room));
      });
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _powerSub?.cancel();
    super.dispose();
  }

  void _toggle(String room, bool val) {
    setState(() => _states[room] = val);
    MQTTService().controlLight(room, val);
  }

  @override
  Widget build(BuildContext context) {
    final lights  = _devices.where((d) => d['device_type'] == 'light').toList();
    final cameras = _devices.where((d) => d['device_type'] == 'camera').toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildSummary(lights),
            const SizedBox(height: 24),
            Expanded(
              child: _devices.isEmpty
                ? _buildEmpty()
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      if (lights.isNotEmpty) ...[
                        _sectionLabel('Đèn thông minh', Icons.lightbulb_rounded, AppColors.lightColor),
                        const SizedBox(height: 12),
                        ...lights.map((d) => _buildLightCard(d)),
                      ],
                      if (cameras.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionLabel('Camera', Icons.videocam_rounded, AppColors.cameraColor),
                        const SizedBox(height: 12),
                        ...cameras.map((d) => _buildCameraCard(d)),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices_other_rounded, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          const Text('Chưa có thiết bị nào', style: TextStyle(color: Colors.white54, fontSize: 15)),
          const SizedBox(height: 8),
          const Text('Nhấn + để thêm thiết bị mới', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLightCard(Map<String, dynamic> d) {
    final room  = d['room'] as String;
    final isOn  = _states[room] ?? false;
    final watt  = _watts[room]  ?? 0.0;
    final color = AppColors.lightColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _DeviceCard(
        name:     d['name'] as String,
        room:     room,
        type:     _lightTypeLabel(d['light_type'] as String? ?? ''),
        icon:     Icons.lightbulb_rounded,
        color:    color,
        isOn:     isOn,
        watt:     watt,
        onToggle: (v) => _toggle(room, v),
        onTap:    () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room))),
        onDelete: () => _deleteDevice(d['id'] as int, room),
      ),
    );
  }

  Widget _buildCameraCard(Map<String, dynamic> d) {
    final color = AppColors.cameraColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _DeviceCard(
        name:       d['name'] as String,
        room:       d['room'] as String,
        type:       'Camera an ninh',
        icon:       Icons.videocam_rounded,
        color:      color,
        isOn:       true,
        watt:       0,
        showSwitch: false,
        onToggle:   (_) {},
        onTap:      () {},
        onDelete:   () => _deleteDevice(d['id'] as int, d['room'] as String),
      ),
    );
  }

  String _lightTypeLabel(String key) {
    const map = {
      'main':       'Đèn chính',
      'sleep':      'Đèn ngủ',
      'decoration': 'Đèn trang trí',
      'desk':       'Đèn bàn',
      'ceiling':    'Đèn trần',
      'outdoor':    'Đèn ngoài trời',
    };
    return map[key] ?? 'Đèn thông minh';
  }

  Future<void> _deleteDevice(int id, String room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Xoá thiết bị?', style: TextStyle(color: Colors.white)),
        content: const Text('Thiết bị sẽ bị xoá khỏi danh sách.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.deleteDevice(id);
      _loadDevices();
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Thiết bị', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Quản lý thiết bị nhà bạn', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _loadDevices,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 24),
                tooltip: 'Tải lại',
              ),
              IconButton(
                onPressed: () async {
                  await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
                  _loadDevices();
                },
                icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70, size: 26),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(List<Map<String, dynamic>> lights) {
    final onCount   = lights.where((d) => _states[d['room']] == true).length;
    final total     = lights.length;
    final totalWatt = _watts.values.fold(0.0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _summaryChip(Icons.devices_rounded, '$onCount/$total bật', AppColors.accentLight),
          const SizedBox(width: 10),
          _summaryChip(Icons.bolt_rounded, '${totalWatt.round()}W', AppColors.lightColor),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Device Card ────────────────────────────────────────────────
class _DeviceCard extends StatelessWidget {
  final String   name, room, type;
  final IconData icon;
  final Color    color;
  final bool     isOn;
  final double   watt;
  final ValueChanged<bool> onToggle;
  final VoidCallback       onTap;
  final VoidCallback       onDelete;
  final bool               showSwitch;

  const _DeviceCard({
    required this.name,
    required this.room,
    required this.type,
    required this.icon,
    required this.color,
    required this.isOn,
    required this.watt,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
    this.showSwitch = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isOn ? color.withOpacity(0.12) : AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isOn ? color.withOpacity(0.35) : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: isOn ? color.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: isOn ? color : Colors.white38, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(type, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: isOn ? AppColors.success : AppColors.textDim,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isOn ? 'Đang bật' : 'Tắt',
                        style: TextStyle(
                          color: isOn ? AppColors.success : AppColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isOn && watt > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.bolt_rounded, color: AppColors.lightColor, size: 12),
                        Text(
                          '${watt.round()}W',
                          style: const TextStyle(color: AppColors.lightColor, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
