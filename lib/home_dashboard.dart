import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'living_room_light.dart';
import 'front_door_cam.dart';
import 'add_device.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({Key? key}) : super(key: key);

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final Color _bgColor = const Color(0xFF12121A);
  final Color _cardColor = const Color(0xFF1E1E2A);
  final Color _accentColor = const Color(0xFFA2B0FF); // Màu tím nhạt chủ đạo
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
              _buildAppBar(),
              const SizedBox(height: 28),
              _buildTopGrid(),
              const SizedBox(height: 48),
              _buildSectionTitle('Favorite Devices', rightText: 'View All'),
              const SizedBox(height: 16),
              _buildFavoriteDevices(),
              const SizedBox(height: 80), // Khoảng trống cho FAB & BottomNav
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
        },
        backgroundColor: _accentColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add, color: Colors.black, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // Quản lý thanh tiêu đề (Avatar + Lời chào)
  Widget _buildAppBar() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'), // Ảnh placeholder
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome Home',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Everything is running smoothly',
                style: TextStyle(
                  color: _subTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.notifications_none_rounded, color: _accentColor),
      ],
    );
  }

  // Quản lý Grid hiển thị thông số 2x2
  Widget _buildTopGrid() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _buildStatCard(Icons.lightbulb_outline, Colors.amber, '3', 'LIGHTS ACTIVE'),
              const SizedBox(height: 12),
              _buildStatCard(Icons.security, _accentColor, 'Secure', 'SYSTEM STATUS'),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _buildStatCard(Icons.thermostat, Colors.cyanAccent, '24.5°C', 'AVG. INDOOR'),
              const SizedBox(height: 12),
              _buildStatCard(Icons.eco_outlined, Colors.white, 'Optimal', 'ENERGY MODE'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, Color iconColor, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: _subTextColor, fontSize: 10, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  // Tiêu đề của từng mục lớn
  Widget _buildSectionTitle(String title, {String? rightText}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (rightText != null)
          Text(
            rightText,
            style: TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.w500),
          ),
      ],
    );
  }

  // Section Daily Rituals dạng scroll ngang
  Widget _buildDailyRituals() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _buildRitualCard('Good Morning', 'Blinds & Coffee', Icons.wb_sunny_outlined, Colors.amber, _cardColor),
          const SizedBox(width: 16),
          _buildRitualCard('Movie Night', 'Dim & Surround...', Icons.movie_outlined, Colors.white, _accentColor),
        ],
      ),
    );
  }

  Widget _buildRitualCard(String title, String subtitle, IconData icon, Color iconColor, Color bgColor) {
    bool isAccent = bgColor == _accentColor;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isAccent ? Colors.black.withOpacity(0.1) : Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            style: TextStyle(
              color: isAccent ? Colors.black87 : _textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: isAccent ? Colors.black54 : _subTextColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Danh sách Favorite Devices List (Cột dọc)
  Widget _buildFavoriteDevices() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FrontDoorCamScreen())),
          child: _buildCameraCard(),
        ),
      ],
    );
  }

  Widget _buildDeviceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required bool isActive,
    required String statusText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Switch(
                    value: isActive,
                    onChanged: (val) {},
                    activeColor: _accentColor,
                    inactiveTrackColor: Colors.black26,
                  ),
                  Text(
                    statusText,
                    style: TextStyle(color: isActive ? _accentColor : _subTextColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: _subTextColor, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildClimateControlCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.air, color: Colors.amber),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Switch(
                    value: true,
                    onChanged: (val) {},
                    activeColor: Colors.amberAccent,
                  ),
                  const Text(
                    'COOLING',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Climate Control', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('22°', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.amber,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.amber,
                    trackHeight: 2.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  ),
                  child: Slider(
                    value: 22,
                    min: 16,
                    max: 30,
                    onChanged: (val) {},
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraCard() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Nền camera ESP32-CAM thật
            Mjpeg(
              isLive: true,
              error: (context, error, stack) => Container(color: Colors.black26),
              stream: 'http://192.168.110.101:8080/stream',  // ✅ IP Relay Server đúng
            ),
            // Lớp phủ Gradient nhẹ để làm nổi bật chữ LIVE
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.4), Colors.transparent], // Giảm bớt đen ở dưới
                ),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF14141E), // Đồng bộ với màu nền gốc
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home_filled, isActive: true),
            _buildNavItem(Icons.grid_view_rounded, isActive: false, onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FrontDoorCamScreen()));
            }),
            _buildNavItem(Icons.settings_input_component_outlined, isActive: false, onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LivingRoomLightScreen()));
            }),
            _buildNavItem(Icons.person_outline, isActive: false, onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, {required bool isActive, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? _accentColor.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? _accentColor : _subTextColor,
        ),
      ),
    );
  }
}
