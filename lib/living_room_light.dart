import 'package:flutter/material.dart';
import 'dart:math';

class LivingRoomLightScreen extends StatefulWidget {
  const LivingRoomLightScreen({Key? key}) : super(key: key);

  @override
  State<LivingRoomLightScreen> createState() => _LivingRoomLightScreenState();
}

class _LivingRoomLightScreenState extends State<LivingRoomLightScreen> {
  final Color _bgColor = const Color(0xFF14141E);
  final Color _cardColor = const Color(0xFF1E1E2A);
  final Color _accentColor = const Color(0xFFA5B4FC); // Tím nhạt
  final Color _textColor = Colors.white;
  final Color _subTextColor = const Color(0xFF8E8E9F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAppBar(context),
              const SizedBox(height: 32),
              _buildBrightnessCard(),
              const SizedBox(height: 24),
              _buildMoodLightingCard(),
              const SizedBox(height: 32),
              const Text('Lighting Scenes',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildScenesGrid(),
              const SizedBox(height: 24),
              _buildStatsRow(),
              const SizedBox(height: 32),
            ],
          ),
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
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 16),
            const Text(
              'Living Room\nLight',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.2),
            ),
          ],
        ),
        Row(
          children: [
            Icon(Icons.notifications_none_rounded, color: _accentColor),
            const SizedBox(width: 12),
            const CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildBrightnessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(36)),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Vòng cung Brightness Custom
              SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(
                  painter: BrightnessRingPainter(
                    percentage: 0.82,
                    accentColor: _accentColor,
                  ),
                ),
              ),
              // Thông số chữ ở giữa vòng tròn
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('BRIGHTNESS',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('82%', style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wb_sunny, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text('Active', style: TextStyle(color: Colors.amber[200], fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              )
            ],
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: _buildControlBtn(Icons.power_settings_new, 'POWER', false)),
              const SizedBox(width: 16),
              Expanded(child: _buildControlBtn(Icons.auto_awesome, 'AUTO', true)),
              const SizedBox(width: 16),
              Expanded(child: _buildControlBtn(Icons.access_time, 'TIMER', false)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildControlBtn(IconData icon, String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: isActive ? _accentColor.withOpacity(0.9) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(40),
        boxShadow: isActive ? [BoxShadow(color: _accentColor.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)] : [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? Colors.black : Colors.white, size: 28),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  color: isActive ? Colors.black : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildMoodLightingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(36)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              const Text('Mood Lighting', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            // Vòng tròn Color Wheel Custom
            child: SizedBox(
              width: 220,
              height: 220,
              child: CustomPaint(
                painter: ColorWheelPainter(),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildColorPreset(const Color(0xFFFF5252), 'RUBY', false),
              _buildColorPreset(const Color(0xFF69F0AE), 'EMERALD', false),
              _buildColorPreset(const Color(0xFF40C4FF), 'AZURE', false),
              _buildColorPreset(const Color(0xFFE040FB), 'ORCHID', true),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildColorPreset(Color color, String name, bool isSelected) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)] : [],
          ),
        ),
        const SizedBox(height: 12),
        Text(name,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildScenesGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSceneCard('Cinema', 'Warm · 20%', Icons.movie, Colors.orange[200]!)),
            const SizedBox(width: 16),
            Expanded(child: _buildSceneCard('Reading', 'Neutral · 80%', Icons.menu_book, Colors.cyan[200]!)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSceneCard('Sleep', 'Deep Red · 5%', Icons.nightlight_round, Colors.purple[200]!)),
            const SizedBox(width: 16),
            Expanded(child: _buildSceneCard('Morning', 'Sky Blue · 60%', Icons.local_cafe, Colors.white)),
          ],
        ),
      ],
    );
  }

  Widget _buildSceneCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(Icons.bolt, Colors.amber[300]!, '12W', 'POWER USAGE')),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(Icons.thermostat, Colors.cyanAccent, '2700K', 'TEMP')),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, Color iconColor, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 10, letterSpacing: 0.5)),
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
          child: Icon(icon, color: isActive ? Colors.black : _subTextColor, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: isActive ? _accentColor : _subTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    ),
    );
  }
}

// ---------------------------------------------------------
// CUSTOM PAINTER CHO VÒNG TRÒN ĐỘ SÁNG (BRIGHTNESS RING)
// ---------------------------------------------------------
class BrightnessRingPainter extends CustomPainter {
  final double percentage;
  final Color accentColor;

  BrightnessRingPainter({required this.percentage, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = size.width / 2 - 12;

    // Vòng tròn nền (Màu đen/xám mờ)
    Paint trackPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(center, radius, trackPaint);

    // Vòng tròn biểu diễn độ sáng (Mắt đầu từ góc 6h)
    Paint activePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    double startAngle = pi / 2; // Góc 6 giờ
    double sweepAngle = 2 * pi * percentage;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );

    // Nút chấm tròn phát sáng ở cuối đường (Thumb)
    double thumbAngle = startAngle + sweepAngle;
    Offset thumbCenter = Offset(
      center.dx + radius * cos(thumbAngle),
      center.dy + radius * sin(thumbAngle),
    );

    // Vòng viền lớn bên ngoài thumb tạo hiệu ứng Glow
    Paint thumbGlow = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(thumbCenter, 16, thumbGlow);

    // Chấm lõi trắng
    Paint thumbCore = Paint()..color = Colors.white;
    canvas.drawCircle(thumbCenter, 10, thumbCore);
    
    // Viền xanh nhạt bên trong thumb
    Paint thumbInnerGlow = Paint()..color = accentColor.withOpacity(0.5);
    canvas.drawCircle(thumbCenter, 6, thumbInnerGlow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


// ---------------------------------------------------------
// CUSTOM PAINTER CHO VÒNG CHỌN MÀU (COLOR WHEEL)
// ---------------------------------------------------------
class ColorWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2);
    double outerRadius = size.width / 2;
    double innerRadius = outerRadius - 12;

    // Gradient bảy sắc cầu vồng
    SweepGradient gradient = const SweepGradient(
      colors: [
        Colors.blue,
        Colors.purple,
        Colors.red,
        Colors.orange,
        Colors.yellow,
        Colors.green,
        Colors.cyan,
        Colors.blue,
      ],
      stops: [0.0, 0.14, 0.28, 0.42, 0.57, 0.71, 0.85, 1.0],
    );

    Rect rect = Rect.fromCircle(center: center, radius: outerRadius);
    Shader shader = gradient.createShader(rect);

    // 1. Phân vành tròn mỏng đầy màu sắc bên ngoài
    Paint outerRingPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, outerRadius - 2, outerRingPaint);

    // 2. Vòng đặc đầy màu sắc ở bên trong
    Paint innerPiePaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerPiePaint);

    // 3. Chấm chọn màu (Thumb - màu trắng) nằm ở góc dưới bên trái
    double thumbAngle = pi * 0.75; // Góc khoảng 135 độ
    Offset thumbCenter = Offset(
      center.dx + (innerRadius - 16) * cos(thumbAngle),
      center.dy + (innerRadius - 16) * sin(thumbAngle),
    );

    // Đổ bóng cho chấm trắng
    Path thumbPath = Path()..addOval(Rect.fromCircle(center: thumbCenter, radius: 12));
    canvas.drawShadow(thumbPath, Colors.black, 4, true);

    // Chấm trắng
    Paint thumbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(thumbCenter, 12, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
