import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/mqtt_service.dart';
import '../lights/living_room_light_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  // Trang thai tung thiet bi
  final Map<String, bool>  _states = {
    'living_room': false,
  };
  final Map<String, double> _watts = {
    'living_room': 0,
  };

  StreamSubscription? _stateSub;
  StreamSubscription? _powerSub;

  @override
  void initState() {
    super.initState();

    _stateSub = MQTTService().deviceStateStream.listen((msg) {
      final topic = msg['topic'] as String;
      final data  = msg['data']  as Map<String, dynamic>;
      if (topic.endsWith('/state')) {
        final parts = topic.split('/');
        if (parts.length >= 4) {
          final room = parts[3];
          final on   = (data['state'] as String?)?.toUpperCase() == 'ON';
          if (mounted && _states.containsKey(room)) {
            setState(() => _states[room] = on);
          }
        }
      }
    });

    _powerSub = MQTTService().devicePowerStream.listen((msg) {
      final topic = msg['topic'] as String;
      final data  = msg['data']  as Map<String, dynamic>;
      final parts = topic.split('/');
      if (parts.length >= 4) {
        final room = parts[3];
        final watt = (data['watt'] as num?)?.toDouble() ?? 0;
        if (mounted && _watts.containsKey(room)) {
          setState(() => _watts[room] = watt);
        }
      }
    });
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildSummary(),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Thiet bi', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _DeviceCard(
                    name:     'Den phong khach',
                    room:     'living_room',
                    type:     'Den thong minh',
                    icon:     Icons.lightbulb_rounded,
                    color:    AppColors.lightColor,
                    isOn:     _states['living_room'] ?? false,
                    watt:     _watts['living_room']  ?? 0,
                    onToggle: (v) => _toggle('living_room', v),
                    onTap:    () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LivingRoomLightScreen())),
                  ),
                  const SizedBox(height: 14),
                  // Them thiet bi khac o day
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
              Text('Thiet bi', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Quan ly thiet bi nha ban', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/add_device'),
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70, size: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final onCount  = _states.values.where((v) => v).length;
    final total    = _states.length;
    final totalWatt = _watts.values.fold(0.0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _summaryChip(Icons.devices_rounded,    '$onCount/$total bat', AppColors.accentLight),
          const SizedBox(width: 10),
          _summaryChip(Icons.bolt_rounded,        '${totalWatt.round()}W', AppColors.lightColor),
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

// ============================================================
// Device Card Widget
// ============================================================
class _DeviceCard extends StatelessWidget {
  final String   name, room, type;
  final IconData icon;
  final Color    color;
  final bool     isOn;
  final double   watt;
  final ValueChanged<bool> onToggle;
  final VoidCallback       onTap;

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
            // Icon
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
            // Info
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
                        isOn ? 'Dang bat' : 'Tat',
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
            // Toggle
            Switch(
              value: isOn,
              onChanged: onToggle,
              activeColor: color,
              activeTrackColor: color.withOpacity(0.25),
              inactiveThumbColor: Colors.white30,
              inactiveTrackColor: Colors.white10,
            ),
          ],
        ),
      ),
    );
  }
}
