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
          final result = await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BLEWiFiProvisioningScreen()));
          if (result == null || result['success'] != true) return;
          if (!mounted) return;
          await _showDeviceTypePicker(result);
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
    final type = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 48),
              const SizedBox(height: 12),
              const Text('Kết nối thành công!',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Đây là thiết bị gì?',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 24),
              // Camera option
              GestureDetector(
                onTap: () => Navigator.pop(ctx, 'camera'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.cameraColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cameraColor.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.cameraColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.videocam_rounded, color: AppColors.cameraColor, size: 26),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Camera', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('ESP32-CAM, camera an ninh', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Light option
              GestureDetector(
                onTap: () => Navigator.pop(ctx, 'light'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.lightColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.lightColor.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.lightColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.lightbulb_rounded, color: AppColors.lightColor, size: 26),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Đèn', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('ESP32-S3 + Relay, điều khiển đèn', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          content: Text('Camera đã được thêm thành công!'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context); // Quay về trang chủ
      }
    } else if (type == 'light') {
      await _showLightRegistrationFlow(result);
    }
  }

  Future<void> _showLightRegistrationFlow(Map result) async {
    final room = await _showRoomPicker();
    if (room == null || !mounted) return;

    final lightType = await _showLightTypePicker(room['label'] as String);
    if (lightType == null || !mounted) return;

    final topic = 'home/devices/light/${room['key']}';
    await DatabaseHelper.instance.insertDevice({
      'name': '${lightType['label']} - ${room['label']}',
      'device_type': 'light',
      'room': room['key'],
      'light_type': lightType['key'],
      'mqtt_topic': topic,
      'ble_mac': result['mac'] ?? '',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã lưu: ${lightType['label']} - ${room['label']}'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<Map<String, String>?> _showRoomPicker() {
    final rooms = [
      {'key': 'living_room',  'label': 'Phòng khách',  'emoji': '🛋️',  'color': const Color(0xFF6C63FF)},
      {'key': 'bedroom',      'label': 'Phòng ngủ',    'emoji': '🛏️',  'color': const Color(0xFF43B89C)},
      {'key': 'kitchen',      'label': 'Nhà bếp',      'emoji': '🍳',  'color': const Color(0xFFFF9F43)},
      {'key': 'bathroom',     'label': 'Nhà vệ sinh',  'emoji': '🚿',  'color': const Color(0xFF54A0FF)},
      {'key': 'bedroom2',     'label': 'Phòng ngủ 2',  'emoji': '🛏️',  'color': const Color(0xFF5F27CD)},
      {'key': 'garage',       'label': 'Nhà xe',       'emoji': '🚗',  'color': const Color(0xFF636E72)},
    ];

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chọn phòng', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Đèn sẽ được đặt ở phòng nào?', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                physics: const NeverScrollableScrollPhysics(),
                children: rooms.map((r) {
                  final color = r['color'] as Color;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, {'key': r['key'] as String, 'label': r['label'] as String}),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(r['emoji'] as String, style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 6),
                          Text(r['label'] as String,
                            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>?> _showLightTypePicker(String roomLabel) {
    final types = [
      {'key': 'main',       'label': 'Đèn chính',    'icon': Icons.lightbulb_rounded,       'color': const Color(0xFFFFD93D)},
      {'key': 'sleep',      'label': 'Đèn ngủ',      'icon': Icons.nights_stay_rounded,     'color': const Color(0xFF6C63FF)},
      {'key': 'decoration', 'label': 'Đèn trang trí','icon': Icons.auto_awesome_rounded,    'color': const Color(0xFFFF6B9D)},
      {'key': 'desk',       'label': 'Đèn bàn',      'icon': Icons.desk_rounded,            'color': const Color(0xFF54A0FF)},
      {'key': 'ceiling',    'label': 'Đèn trần',     'icon': Icons.light_rounded,           'color': const Color(0xFFFF9F43)},
      {'key': 'outdoor',    'label': 'Đèn ngoài trời','icon': Icons.outdoor_grill_rounded,  'color': const Color(0xFF43B89C)},
    ];

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Loại đèn', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$roomLabel — chọn loại đèn', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: types.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = types[i];
                  final color = t['color'] as Color;
                  final icon = t['icon'] as IconData;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, {'key': t['key'] as String, 'label': t['label'] as String}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Text(t['label'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.6), size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Huỷ', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
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
