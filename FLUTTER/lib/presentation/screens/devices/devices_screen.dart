import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/auth_service.dart';
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
    Future.microtask(() => MQTTService().resubscribeState());

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
        final validRooms = _devices.map((d) => d['room'] as String).toSet();
        if (!validRooms.contains(room)) return;
        final watt = (data['watt'] as num?)?.toDouble() ?? 0;
        if (mounted) setState(() => _watts[room] = watt);
      }
    });
  }

  Future<void> _loadDevices() async {
    final rows = await DatabaseHelper.instance.getAllDevices(userId: AuthService.instance.userId);
    if (mounted) {
      setState(() {
        _devices = rows;
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
    final ac = AC.of(context);
    final lights  = _devices.where((d) => d['device_type'] == 'light').toList();
    final cameras = _devices.where((d) => d['device_type'] == 'camera').toList();

    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(ac),
            const SizedBox(height: 8),
            _buildSummary(ac, lights),
            const SizedBox(height: 24),
            Expanded(
              child: _devices.isEmpty
                ? _buildEmpty(ac)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      if (lights.isNotEmpty) ...[
                        _sectionLabel(ac, 'Đèn thông minh', Icons.lightbulb_rounded, ac.lightColor),
                        const SizedBox(height: 12),
                        ...lights.map((d) => _buildLightCard(ac, d)),
                      ],
                      if (cameras.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionLabel(ac, 'Camera', Icons.videocam_rounded, ac.cameraColor),
                        const SizedBox(height: 12),
                        ...cameras.map((d) => _buildCameraCard(ac, d)),
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

  Widget _buildEmpty(AC ac) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices_other_rounded, color: ac.iconFaint, size: 64),
          const SizedBox(height: 16),
          Text('Chưa có thiết bị nào', style: TextStyle(color: ac.textSecondary, fontSize: 15)),
          const SizedBox(height: 8),
          Text('Nhấn + để thêm thiết bị mới', style: TextStyle(color: ac.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sectionLabel(AC ac, String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLightCard(AC ac, Map<String, dynamic> d) {
    final room  = d['room'] as String;
    final isOn  = _states[room] ?? false;
    final watt  = _watts[room]  ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _DeviceCard(
        ac:      ac,
        name:    d['name'] as String,
        room:    room,
        type:    _lightTypeLabel(d['light_type'] as String? ?? ''),
        icon:    Icons.lightbulb_rounded,
        color:   ac.lightColor,
        isOn:    isOn,
        watt:    watt,
        onToggle: (v) => _toggle(room, v),
        onTap:   () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room))),
        onDelete: () => _deleteDevice(d['id'] as int, room, d['ble_mac'] as String? ?? ''),
      ),
    );
  }

  Widget _buildCameraCard(AC ac, Map<String, dynamic> d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _DeviceCard(
        ac:        ac,
        name:      d['name'] as String,
        room:      d['room'] as String,
        type:      'Camera an ninh',
        icon:      Icons.videocam_rounded,
        color:     ac.cameraColor,
        isOn:      true,
        watt:      0,
        showSwitch: false,
        onToggle:  (_) {},
        onTap:     () {},
        onDelete:  () => _deleteDevice(d['id'] as int, d['room'] as String, d['ble_mac'] as String? ?? ''),
      ),
    );
  }

  String _lightTypeLabel(String key) {
    const map = {
      'main': 'Đèn chính', 'sleep': 'Đèn ngủ',
      'decoration': 'Đèn trang trí', 'desk': 'Đèn bàn',
      'ceiling': 'Đèn trần', 'outdoor': 'Đèn ngoài trời',
    };
    return map[key] ?? 'Đèn thông minh';
  }

  Future<void> _deleteDevice(int id, String room, String bleMac) async {
    final ac = AC.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ac.card,
        title: Text('Xoá thiết bị?', style: TextStyle(color: ac.textPrimary)),
        content: Text(
          'Thiết bị sẽ bị xoá khỏi danh sách.\nESP32 sẽ xoá WiFi và chờ kết nối lại qua BLE.',
          style: TextStyle(color: ac.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Huỷ', style: TextStyle(color: ac.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Xoá', style: TextStyle(color: ac.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (bleMac.isNotEmpty) {
      final macTopic = bleMac.replaceAll(':', '').toLowerCase();
      final configTopic = 'home/devices/config/$macTopic';
      MQTTService().publish(configTopic, {
        'action': 'reset_wifi',
        'ts': DateTime.now().millisecondsSinceEpoch,
      }, retain: true);
      // Clear retained message sau 3s để ESP32 không bị reset loop khi boot lại
      Future.delayed(const Duration(seconds: 3), () {
        MQTTService().publishRaw(configTopic, '', retain: true);
      });
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await DatabaseHelper.instance.deleteDevice(id);
    await DatabaseHelper.instance.addLog('Xoá thiết bị', 'Phòng: $room', userId: AuthService.instance.userId);
    _loadDevices();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã xoá thiết bị. ESP32 đang reset về BLE mode...'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ));
    }
  }

  Widget _buildHeader(AC ac) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Thiết bị', style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('Quản lý thiết bị nhà bạn', style: TextStyle(color: ac.textSecondary, fontSize: 13)),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _loadDevices,
                icon: Icon(Icons.refresh_rounded, color: ac.textSecondary, size: 24),
                tooltip: 'Tải lại',
              ),
              IconButton(
                onPressed: () async {
                  await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
                  _loadDevices();
                },
                icon: Icon(Icons.add_circle_outline_rounded, color: ac.textSecondary, size: 26),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(AC ac, List<Map<String, dynamic>> lights) {
    final onCount   = lights.where((d) => _states[d['room']] == true).length;
    final total     = _devices.length;
    final totalWatt = _watts.values.fold(0.0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _summaryChip(ac.accentLight, Icons.devices_rounded, '$onCount/$total bật'),
          const SizedBox(width: 10),
          _summaryChip(ac.lightColor, Icons.bolt_rounded, '${totalWatt.round()}W'),
        ],
      ),
    );
  }

  Widget _summaryChip(Color color, IconData icon, String label) {
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

class _DeviceCard extends StatelessWidget {
  final AC       ac;
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
    required this.ac,
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
          color: isOn ? color.withOpacity(0.12) : ac.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isOn ? color.withOpacity(0.35) : ac.border,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: isOn ? color.withOpacity(0.2) : ac.border,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: isOn ? color : ac.iconMuted, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(color: ac.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(type, style: TextStyle(color: ac.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: isOn ? ac.success : ac.textDim,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isOn ? 'Đang bật' : 'Tắt',
                        style: TextStyle(
                          color: isOn ? ac.success : ac.textDim,
                          fontSize: 11, fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isOn && watt > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.bolt_rounded, color: ac.lightColor, size: 12),
                        Text('${watt.round()}W',
                            style: TextStyle(color: ac.lightColor, fontSize: 11, fontWeight: FontWeight.w600)),
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
                  color: ac.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.delete_outline_rounded, color: ac.error, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
