import 'package:flutter/material.dart';
import 'ble_wifi_provisioning_screen.dart';  // ⭐ THÊM MỚI

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({Key? key}) : super(key: key);

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> with SingleTickerProviderStateMixin {
  final Color _bgColor = const Color(0xFF14141E);
  final Color _cardColor = const Color(0xFF1E1E2A);
  final Color _accentColor = const Color(0xFFA5B4FC); // Màn này màu tím nhạt là chính
  final Color _textColor = Colors.white;
  final Color _subTextColor = const Color(0xFF8E8E9F);
  
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAppBar(context),
                  const SizedBox(height: 32),
                  Center(child: _buildScanningArea()),
                  const SizedBox(height: 48),
                  
                  // Chữ nhỏ QUICK SETUP
                  Text('QUICK SETUP', 
                      style: TextStyle(color: _accentColor.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  const Text('Categories', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  
                  _buildCategoriesGrid(),
                  const SizedBox(height: 24),
                  _buildProTipCard(),
                  const SizedBox(height: 100), // Không gian cuộn cho nút Add Manually và Bottom Nav
                ],
              ),
            ),
            
            // Nút "Add Manually" và "BLE Provisioning" nổi ở dưới cùng
            Positioned(
              bottom: 100,
              left: 40,
              right: 40,
              child: Column(
                children: [
                  // ⭐ THÊM MỚI - BLE Provisioning Button
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const BLEWiFiProvisioningScreen()));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20)],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('BLE WiFi Provisioning', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Add Manually Button (giữ nguyên)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262635),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Add Manually', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 16),
            const Text(
              'Add Device',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.question_mark, color: Colors.white70, size: 16),
        )
      ],
    );
  }

  Widget _buildScanningArea() {
    return Column(
      children: [
        SizedBox(
          width: 250,
          height: 250,
          child: CustomPaint(
            painter: ScannerPainter(),
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 100 + (_pulseController.value * 20),
                    height: 100 + (_pulseController.value * 20),
                    decoration: BoxDecoration(
                      color: _accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: _accentColor.withOpacity(0.4), blurRadius: 40 * _pulseController.value, spreadRadius: 10),
                      ],
                    ),
                    child: const Icon(Icons.radar, color: Colors.black, size: 40), // Gần giống icon target
                  );
                }
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Scanning for devices...', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Make sure your device is in pairing mode\nand nearby.', 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5)),
      ],
    );
  }

  Widget _buildCategoriesGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildCategoryCard('Lighting', 'Bulbs, Strips,\nPanels', Icons.lightbulb, Colors.amber[300]!)),
            const SizedBox(width: 16),
            Expanded(child: _buildCategoryCard('Security', 'Cameras,\nLocks,\nSensors', Icons.security, Colors.cyanAccent)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildCategoryCard('Appliances', 'AC, Fridge,\nPurifiers', Icons.kitchen, _accentColor)),
            const SizedBox(width: 16),
            Expanded(child: _buildCategoryCard('Climate', 'Thermostats,\nFans', Icons.thermostat, Colors.cyan[300]!)),
          ],
        ),
        const SizedBox(height: 16),
        _buildFullWidthCategoryCard('Entertainment', 'TVs, Speakers', Icons.tv, Colors.red[300]!),
      ],
    );
  }

  Widget _buildCategoryCard(String title, String subtitle, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildFullWidthCategoryCard(String title, String subtitle, IconData icon, Color iconColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildProTipCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(32)),
      child: Row(
        children: [
          // Graphic loa thông minh (tượng trưng thủ công)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Colors.grey[700]!, Colors.black]),
            ),
            child: const Icon(Icons.speaker, color: Colors.white24, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pro Tip', style: TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Most devices can be added by scanning the QR code on the back of...',
                  style: TextStyle(color: Colors.grey[300], fontSize: 10, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
          )
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home_filled, 'HOME', false, context),
            _buildNavItem(Icons.sports_esports, 'DEVICES', true), 
            _buildNavItem(Icons.light, 'SCENES', false),
            _buildNavItem(Icons.person_outline, 'PROFILE', false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, [BuildContext? context]) {
    return GestureDetector(
      onTap: () {
        if (label == 'HOME' && context != null) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      },
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? _accentColor.withOpacity(0.9) : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: isActive ? [BoxShadow(color: _accentColor.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)] : [],
          ),
          child: Icon(icon, color: isActive ? Colors.black : const Color(0xFF8E8E9F), size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: isActive ? _accentColor : const Color(0xFF8E8E9F), fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    ),
    );
  }
}

// Custom vẽ các vòng sóng Radar
class ScannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2);
    
    // Nền tối ở giữa radar
    Paint bgHole = Paint()..color = Colors.white.withOpacity(0.02)..style = PaintingStyle.fill;
    canvas.drawCircle(center, 120, bgHole);
    
    // Các đường line tròn radar
    Paint ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    canvas.drawCircle(center, 120, ringPaint);
    canvas.drawCircle(center, 80, ringPaint);
    
    // Vài đốm sáng bay lơ lửng trên vòng radar
    Paint yellowishDot = Paint()..color = Colors.amber.withOpacity(0.6)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx - 60, center.dy + 80), 6, yellowishDot);

    Paint darkBlueDot = Paint()..color = Colors.indigo.withOpacity(0.6)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx + 80, center.dy - 70), 8, darkBlueDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
