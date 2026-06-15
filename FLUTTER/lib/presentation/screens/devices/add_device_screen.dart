import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/device_config_service.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/auth_service.dart';
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
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 32)),
            SliverToBoxAdapter(child: _buildScanAnimation(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 36)),
            SliverToBoxAdapter(child: _buildSetupButtons(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildAiServerCard(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 32)),
            SliverToBoxAdapter(child: _buildCategoriesLabel(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildCategories(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AC ac) {
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 20, 20, 0),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thêm thiết bị', style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Kết nối thiết bị thông minh', style: TextStyle(color: ac.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ac.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ac.border),
            ),
            child: Icon(Icons.help_outline_rounded, color: ac.iconMuted, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildScanAnimation(AC ac) {
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
                    border: Border.all(color: ac.accentDim.withOpacity(0.3 * _pulseController.value), width: 1.5),
                  ),
                ),
                Container(
                  width: 170, height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ac.accentDim.withOpacity(0.5 * _pulseController.value), width: 1.5),
                  ),
                ),
                Container(
                  width: 110 + (_pulseController.value * 16),
                  height: 110 + (_pulseController.value * 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [ac.accent.withOpacity(0.8), ac.accentDim.withOpacity(0.4)],
                    ),
                    boxShadow: [AppDecor.glowShadow(ac.accent, blur: 24 * _pulseController.value)],
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

  Widget _buildSetupButtons(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () async {
          try {
            final result = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BLEWiFiProvisioningScreen()));
            if (result == null || result['success'] != true) return;
            if (!mounted) return;

            final saved = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => _DeviceTypeScreen(bleMac: result['mac'] ?? '')));
            if (saved == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Thiết bị đã được lưu!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ));
              Navigator.of(context).popUntil((route) => route.isFirst);
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
            boxShadow: [AppDecor.glowShadow(ac.accent)],
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

  Widget _buildAiServerCard(AC ac) {
    final svc = DeviceConfigService.instance;
    final hasIp = svc.hasAiIp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ac.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hasIp ? Colors.green.withOpacity(0.25) : ac.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (hasIp ? Colors.green : ac.iconFaint).withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.smart_toy_rounded,
                  color: hasIp ? Colors.greenAccent : ac.iconMuted, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Server (Python)',
                      style: TextStyle(color: ac.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    hasIp ? '${svc.aiIp}:${svc.aiPort}' : 'Chờ Python khởi động...',
                    style: TextStyle(
                      color: hasIp ? Colors.greenAccent : ac.iconMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasIp ? Colors.green.withOpacity(0.15) : ac.border,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasIp ? 'Auto' : 'MQTT',
                style: TextStyle(
                  color: hasIp ? Colors.greenAccent : ac.iconMuted,
                  fontSize: 10, fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesLabel(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text('Thêm thủ công', style: TextStyle(color: ac.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCategories(AC ac) {
    final cats = [
      _Cat('Đèn thông minh', 'Bóng đèn, đèn relay', Icons.lightbulb_rounded, AppColors.lightColor,
          onTap: _addLightManual),
      _Cat('Camera', 'Camera an ninh', Icons.security_rounded, AppColors.cameraColor,
          onTap: _addCameraManual),
      _Cat('Thiết bị khác', 'AC, Tủ lạnh...', Icons.kitchen_rounded, AppColors.accentLight),
      _Cat('Cảm biến', 'Nhiệt độ, độ ẩm', Icons.thermostat_rounded, AppColors.climateColor),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: cats.map((c) => _buildCatCard(ac, c)).toList(),
      ),
    );
  }

  Future<void> _addLightManual() async {
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
      'ble_mac': '',
    }, userId: AuthService.instance.userId);
    await DatabaseHelper.instance.addLog('Thêm thiết bị', '${lightType.label} - ${room.label}', userId: AuthService.instance.userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã thêm đèn thành công!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ));
      Navigator.pop(context);
    }
  }

  Future<void> _addCameraManual() async {
    await DatabaseHelper.instance.insertDevice({
      'name': 'Camera an ninh',
      'device_type': 'camera',
      'room': 'entrance',
      'mqtt_topic': 'home/devices/camera/entrance',
      'ble_mac': '',
    }, userId: AuthService.instance.userId);
    await DatabaseHelper.instance.addLog('Thêm thiết bị', 'Camera an ninh', userId: AuthService.instance.userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã thêm camera thành công!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ));
      Navigator.pop(context);
    }
  }

  Widget _buildCatCard(AC ac, _Cat cat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: cat.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ac.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: cat.onTap != null
                  ? cat.color.withOpacity(0.25)
                  : ac.border,
            ),
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
              Text(cat.name, style: TextStyle(color: ac.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(cat.subtitle, style: TextStyle(color: ac.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cat {
  final String name, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _Cat(this.name, this.subtitle, this.icon, this.color, {this.onTap});
}

class _PickResult {
  final String key, label, emoji;
  final Color color;
  final IconData? icon;
  const _PickResult(this.key, this.label, this.emoji, this.color, {this.icon});
}

// ── Screen chọn loại thiết bị ────────────────────────────────
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
    }, userId: AuthService.instance.userId);
    await DatabaseHelper.instance.addLog('Thêm thiết bị', 'Camera an ninh (BLE)', userId: AuthService.instance.userId);
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
    }, userId: AuthService.instance.userId);
    await DatabaseHelper.instance.addLog('Thêm thiết bị', '${lightType.label} - ${room.label} (BLE)', userId: AuthService.instance.userId);

    final macTopic = widget.bleMac.replaceAll(':', '').toLowerCase();
    MQTTService().publish('home/devices/config/$macTopic', {
      'room': room.key,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    if (mounted) Navigator.pop(context, true);
  }

  Widget _typeOption(AC ac, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
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
                    Text(title, style: TextStyle(color: ac.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: ac.textSecondary, fontSize: 12)),
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
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      appBar: AppBar(
        backgroundColor: ac.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Loại thiết bị', style: TextStyle(color: ac.textPrimary, fontSize: 17)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 64)),
              const SizedBox(height: 16),
              Center(child: Text('Kết nối thành công!',
                  style: TextStyle(color: ac.textPrimary, fontSize: 20, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Center(child: Text('Đây là thiết bị gì?',
                  style: TextStyle(color: ac.textSecondary, fontSize: 14))),
              const SizedBox(height: 40),
              _typeOption(ac, 'Camera', 'ESP32-CAM, camera an ninh',
                  Icons.videocam_rounded, AppColors.cameraColor, _onTapCamera),
              const SizedBox(height: 16),
              _typeOption(ac, 'Đèn', 'ESP32-S3 + Relay, điều khiển đèn',
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
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      appBar: AppBar(
        backgroundColor: ac.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Chọn phòng', style: TextStyle(color: ac.textPrimary, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: ac.divider),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Đèn sẽ được đặt ở phòng nào?',
                  style: TextStyle(color: ac.textSecondary, fontSize: 14)),
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
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      appBar: AppBar(
        backgroundColor: ac.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Loại đèn', style: TextStyle(color: ac.textPrimary, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: ac.divider),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$roomLabel — chọn loại đèn',
                  style: TextStyle(color: ac.textSecondary, fontSize: 14)),
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
                                  style: TextStyle(color: ac.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
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
