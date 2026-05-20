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

            // Push screen chọn loại thiết bị — toàn bộ flow xử lý bên trong
            final saved = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => _DeviceTypeScreen(bleMac: result['mac'] ?? '')));
            if (saved == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Thiết bị đã được lưu!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ));
              Navigator.pop(context);
            }
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

// ── Screen chọn loại thiết bị (xử lý toàn bộ flow) ──────────
class _DeviceTypeScreen extends StatefulWidget {
  final String bleMac;
  const _DeviceTypeScreen({required this.bleMac});

  @override
  State<_DeviceTypeScreen> createState() => _DeviceTypeScreenState();
}

class _DeviceTypeScreenState extends State<_DeviceTypeScreen> {
  Future<void> _onTapCamera() async {
    await DatabaseHelper.instance.insertDevice({
      'name': 'Camera an ninh',
      'device_type': 'camera',
      'room': 'entrance',
      'mqtt_topic': 'home/devices/camera/entrance',
      'ble_mac': widget.bleMac,
    });
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _onTapLight() async {
    final room = await Navigator.push<_PickResult>(context,
      MaterialPageRoute(builder: (_) => const _RoomPickerScreen()));
    if (room == null || !mounted) return;

    final lightType = await Navigator.push<_PickResult>(context,
      MaterialPageRoute(builder: (_) => _LightTypePickerScreen(roomLabel: room.label)));
    if (lightType == null || !mounted) return;

    await DatabaseHelper.instance.insertDevice({
      'name': '${lightType.label} - ${room.label}',
      'device_type': 'light',
      'room': room.key,
      'light_type': lightType.key,
      'mqtt_topic': 'home/devices/light/${room.key}',
      'ble_mac': widget.bleMac,
    });

    if (mounted) Navigator.pop(context, true);
  }

  Widget _typeOption(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.6), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Loại thiết bị', style: TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 64)),
              const SizedBox(height: 16),
              const Center(child: Text('Kết nối thành công!',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              const Center(child: Text('Đây là thiết bị gì?',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14))),
              const SizedBox(height: 40),
              _typeOption('Camera', 'ESP32-CAM, camera an ninh',
                  Icons.videocam_rounded, AppColors.cameraColor, _onTapCamera),
              const SizedBox(height: 16),
              _typeOption('Đèn', 'ESP32-S3 + Relay, điều khiển đèn',
                  Icons.lightbulb_rounded, AppColors.lightColor, _onTapLight),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Screen chọn phòng ─────────────────────────────────────────
class _RoomPickerScreen extends StatelessWidget {
  const _RoomPickerScreen();

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Chọn phòng', style: TextStyle(color: Colors.white, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white10),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Đèn sẽ được đặt ở phòng nào?',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.3,
                  children: _rooms.map((r) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, r),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: r.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: r.color.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(r.emoji, style: const TextStyle(fontSize: 32)),
                            const SizedBox(height: 8),
                            Text(r.label,
                                style: TextStyle(color: r.color, fontSize: 13, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Screen chọn loại đèn ──────────────────────────────────────
class _LightTypePickerScreen extends StatelessWidget {
  final String roomLabel;
  const _LightTypePickerScreen({required this.roomLabel});

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Loại đèn', style: TextStyle(color: Colors.white, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white10),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$roomLabel — chọn loại đèn',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: _types.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final t = _types[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, t),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          decoration: BoxDecoration(
                            color: t.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: t.color.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: t.color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                                child: Icon(t.icon ?? Icons.lightbulb_rounded, color: t.color, size: 22),
                              ),
                              const SizedBox(width: 16),
                              Text(t.label,
                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Icon(Icons.chevron_right_rounded, color: t.color.withOpacity(0.6), size: 22),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
