import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/device_config_service.dart';
import '../../../core/services/database_helper.dart';
import 'ble_wifi_provisioning_screen.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: const SizedBox(height: 32)),
            SliverToBoxAdapter(child: _buildScanAnimation()),
            SliverToBoxAdapter(child: const SizedBox(height: 36)),
            SliverToBoxAdapter(child: _buildSetupButtons()),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildAiServerCard()),
            SliverToBoxAdapter(child: const SizedBox(height: 32)),
            SliverToBoxAdapter(child: _buildCategoriesLabel()),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildCategories()),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
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
              Text('Add Device', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Connect your smart devices', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(Icons.help_outline_rounded, color: Colors.white54, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildScanAnimation() {
    return Center(
      child: SizedBox(
        width: 220, height: 220,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (ctx, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentDim.withOpacity(0.3 * _pulseController.value), width: 1.5),
                  ),
                ),
                Container(
                  width: 170, height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentDim.withOpacity(0.5 * _pulseController.value), width: 1.5),
                  ),
                ),
                Container(
                  width: 110 + (_pulseController.value * 16),
                  height: 110 + (_pulseController.value * 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [AppColors.accent.withOpacity(0.8), AppColors.accentDim.withOpacity(0.4)],
                    ),
                    boxShadow: [AppDecor.glowShadow(AppColors.accent, blur: 24 * _pulseController.value)],
                  ),
                  child: const Icon(Icons.radar_rounded, color: Colors.white, size: 44),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSetupButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () async {
          try {
            final result = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BLEWiFiProvisioningScreen()));
            if (result == null || result['success'] != true) return;
            if (!mounted) return;
            await Future.delayed(const Duration(milliseconds: 300));
            if (!mounted) return;
            await _showDeviceTypePicker(result);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
            }
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B3BE8), Color(0xFF7C6FF7)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [AppDecor.glowShadow(AppColors.accent)],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bluetooth_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text('BLE WiFi Setup', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeviceTypePicker(Map result) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 48),
            const SizedBox(height: 12),
            const Text('Kết nối thành công!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Đây là thiết bị gì?', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 24),
            _typeOption(ctx, 'camera', 'Camera', 'ESP32-CAM, camera an ninh', Icons.videocam_rounded, AppColors.cameraColor),
            const SizedBox(height: 12),
            _typeOption(ctx, 'light', 'Đèn', 'ESP32-S3 + Relay, điều khiển đèn', Icons.lightbulb_rounded, AppColors.lightColor),
          ],
        ),
      ),
    );

    if (type == null || !mounted) return;

    if (type == 'camera') {
      await DatabaseHelper.instance.insertDevice({
        'name': 'Camera an ninh',
        'device_type': 'camera',
        'room': 'entrance',
        'mqtt_topic': 'home/devices/camera/entrance',
        'ble_mac': result['mac'] ?? '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Camera đã được thêm!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ));
        // Quay về DevicesScreen (pop AddDeviceScreen)
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    } else if (type == 'light') {
      await _showLightRegistrationFlow(result);
    }
  }

  Widget _typeOption(BuildContext ctx, String value, String title, String subtitle, IconData icon, Color color) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLightRegistrationFlow(Map result) async {
    final room = await showModalBottomSheet<_PickResult>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const _RoomPickerSheet(),
    );
    if (room == null || !mounted) return;

    // Chờ dismiss animation xong hoàn toàn trên iOS
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final lightType = await showModalBottomSheet<_PickResult>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _LightTypePickerSheet(roomLabel: room.label),
    );
    if (lightType == null || !mounted) return;

    await DatabaseHelper.instance.insertDevice({
      'name': '${lightType.label} - ${room.label}',
      'device_type': 'light',
      'room': room.key,
      'light_type': lightType.key,
      'mqtt_topic': 'home/devices/light/${room.key}',
      'ble_mac': result['mac'] ?? '',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ Đã lưu: ${lightType.label} - ${room.label}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ));
      // Quay về DevicesScreen
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  Widget _buildAiServerCard() {
    final svc = DeviceConfigService.instance;
    final hasIp = svc.hasAiIp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hasIp ? Colors.green.withOpacity(0.25) : Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (hasIp ? Colors.green : Colors.white12).withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.smart_toy_rounded,
                  color: hasIp ? Colors.greenAccent : Colors.white38, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Server (Python)',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    hasIp ? '${svc.aiIp}:${svc.aiPort}' : 'Chờ Python khởi động...',
                    style: TextStyle(
                      color: hasIp ? Colors.greenAccent : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasIp ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasIp ? 'Auto' : 'MQTT',
                style: TextStyle(
                  color: hasIp ? Colors.greenAccent : Colors.white38,
                  fontSize: 10, fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesLabel() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Text('Device Categories', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCategories() {
    final cats = [
      _Cat('Lighting', 'Bulbs, Strips', Icons.lightbulb_rounded, AppColors.lightColor),
      _Cat('Security', 'Cameras, Locks', Icons.security_rounded, AppColors.cameraColor),
      _Cat('Appliances', 'AC, Fridge', Icons.kitchen_rounded, AppColors.accentLight),
      _Cat('Climate', 'Thermostats', Icons.thermostat_rounded, AppColors.climateColor),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: cats.map(_buildCatCard).toList(),
      ),
    );
  }

  Widget _buildCatCard(_Cat cat) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cat.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(cat.icon, color: cat.color, size: 22),
          ),
          const Spacer(),
          Text(cat.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(cat.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Cat {
  final String name, subtitle;
  final IconData icon;
  final Color color;
  const _Cat(this.name, this.subtitle, this.icon, this.color);
}

class _PickResult {
  final String key, label, emoji;
  final Color color;
  final IconData? icon;
  const _PickResult(this.key, this.label, this.emoji, this.color, {this.icon});
}

// ── Bottom sheet chọn phòng ───────────────────────────────────
class _RoomPickerSheet extends StatelessWidget {
  const _RoomPickerSheet();

  static final _rooms = [
    _PickResult('living_room', 'Phòng khách',  '🛋️', const Color(0xFF6C63FF)),
    _PickResult('bedroom',     'Phòng ngủ',    '🛏️', const Color(0xFF43B89C)),
    _PickResult('kitchen',     'Nhà bếp',      '🍳', const Color(0xFFFF9F43)),
    _PickResult('bathroom',    'Nhà vệ sinh',  '🚿', const Color(0xFF54A0FF)),
    _PickResult('bedroom2',    'Phòng ngủ 2',  '🛏️', const Color(0xFF5F27CD)),
    _PickResult('garage',      'Nhà xe',       '🚗', const Color(0xFF636E72)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Chọn phòng', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Đèn sẽ được đặt ở phòng nào?', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            physics: const NeverScrollableScrollPhysics(),
            children: _rooms.map((r) => GestureDetector(
              onTap: () => Navigator.pop(context, r),
              child: Container(
                decoration: BoxDecoration(
                  color: r.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: r.color.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(r.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(r.label, style: TextStyle(color: r.color, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}

// ── Bottom sheet chọn loại đèn ────────────────────────────────
class _LightTypePickerSheet extends StatelessWidget {
  final String roomLabel;
  const _LightTypePickerSheet({required this.roomLabel});

  static final _types = [
    _PickResult('main',       'Đèn chính',     '💡', const Color(0xFFFFD93D), icon: Icons.lightbulb_rounded),
    _PickResult('sleep',      'Đèn ngủ',       '🌙', const Color(0xFF6C63FF), icon: Icons.nights_stay_rounded),
    _PickResult('decoration', 'Đèn trang trí', '✨', const Color(0xFFFF6B9D), icon: Icons.auto_awesome_rounded),
    _PickResult('desk',       'Đèn bàn',       '🔦', const Color(0xFF54A0FF), icon: Icons.desk_rounded),
    _PickResult('ceiling',    'Đèn trần',      '☀️', const Color(0xFFFF9F43), icon: Icons.light_rounded),
    _PickResult('outdoor',    'Đèn ngoài trời','🌿', const Color(0xFF43B89C), icon: Icons.park_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Loại đèn', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$roomLabel — chọn loại đèn', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          ...List.generate(_types.length, (i) {
            final t = _types[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context, t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: t.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.color.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: t.color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                        child: Icon(t.icon ?? Icons.lightbulb_rounded, color: t.color, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Text(t.label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded, color: t.color.withOpacity(0.6), size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}
