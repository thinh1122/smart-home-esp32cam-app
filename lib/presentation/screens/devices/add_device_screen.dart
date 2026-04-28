import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/device_config_service.dart';
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

  void _showServerSettingsDialog() {
    final svc = DeviceConfigService.instance;
    final ipCtrl   = TextEditingController(text: svc.aiIp);
    final portCtrl = TextEditingController(text: svc.aiPort.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: AppColors.info, size: 20),
            SizedBox(width: 8),
            Text('AI Server', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nhập IP của máy tính đang chạy Python server (cùng mạng WiFi với điện thoại)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipCtrl,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'IP Address',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '192.168.1.x',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.computer_rounded, color: AppColors.info, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '5000',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.settings_ethernet_rounded, color: AppColors.info, size: 18),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final ip   = ipCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? 5000;
              if (ip.isEmpty) return;
              await DeviceConfigService.instance.saveAiServer(ip, port: port);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Đã lưu: http://$ip:$port'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              }
            },
            child: const Text('Lưu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
                // Outer ring
                Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentDim.withOpacity(0.3 * _pulseController.value), width: 1.5),
                  ),
                ),
                // Middle ring
                Container(
                  width: 170, height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentDim.withOpacity(0.5 * _pulseController.value), width: 1.5),
                  ),
                ),
                // Inner pulse
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
      child: Column(
        children: [
          // BLE Provisioning (primary)
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BLEWiFiProvisioningScreen())),
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
          const SizedBox(height: 12),
          // Server settings
          GestureDetector(
            onTap: _showServerSettingsDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.dns_rounded, color: AppColors.info, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Cấu hình AI Server', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                      Text(
                        DeviceConfigService.instance.hasAiIp
                            ? DeviceConfigService.instance.aiBaseUrl
                            : 'Chưa cấu hình',
                        style: TextStyle(
                          color: DeviceConfigService.instance.hasAiIp ? AppColors.info : AppColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
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
