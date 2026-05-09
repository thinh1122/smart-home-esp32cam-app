import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/mqtt_service.dart';
import '../../widgets/painters/brightness_ring_painter.dart';
import '../../widgets/painters/color_wheel_painter.dart';

class LivingRoomLightScreen extends StatefulWidget {
  const LivingRoomLightScreen({super.key});

  @override
  State<LivingRoomLightScreen> createState() => _LivingRoomLightScreenState();
}

class _LivingRoomLightScreenState extends State<LivingRoomLightScreen> {
  bool _isOn = true;
  bool _isAuto = false;
  double _brightness = 0.82;
  double _colorWheelAngle = pi * 0.75;
  Color _selectedColor = const Color(0xFFE040FB);
  String _selectedScene = 'Reading';
  Timer? _brightnessDebounce;
  Timer? _colorDebounce;

  final _scenes = const [
    _Scene('Cinema', 'Warm · 20%', Icons.movie_rounded, Color(0xFFFFA040)),
    _Scene('Reading', 'Neutral · 80%', Icons.menu_book_rounded, Color(0xFF80DEEA)),
    _Scene('Sleep', 'Deep Red · 5%', Icons.nightlight_round, Color(0xFFCE93D8)),
    _Scene('Morning', 'Sky Blue · 60%', Icons.local_cafe_rounded, Colors.white70),
  ];

  final _colorPresets = const [
    _ColorPreset(Color(0xFFFF5252), 'Ruby'),
    _ColorPreset(Color(0xFF69F0AE), 'Emerald'),
    _ColorPreset(Color(0xFF40C4FF), 'Azure'),
    _ColorPreset(Color(0xFFE040FB), 'Orchid'),
  ];

  @override
  void dispose() {
    _brightnessDebounce?.cancel();
    _colorDebounce?.cancel();
    super.dispose();
  }

  void _toggleLight(bool v) {
    setState(() => _isOn = v);
    MQTTService().controlLight('living_room', v);
  }

  void _publishBrightness(double value) {
    _brightnessDebounce?.cancel();
    _brightnessDebounce = Timer(const Duration(milliseconds: 300), () {
      MQTTService().publish('home/devices/light/living_room/brightness', {
        'brightness': (value * 100).round(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _publishColor(Color color) {
    _colorDebounce?.cancel();
    _colorDebounce = Timer(const Duration(milliseconds: 300), () {
      MQTTService().publish('home/devices/light/living_room/color', {
        'r': color.red, 'g': color.green, 'b': color.blue,
        'hex': '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _applyScene(_Scene scene) {
    setState(() => _selectedScene = scene.name);
    MQTTService().publish('home/devices/light/living_room/scene', {
      'scene': scene.name,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: const SizedBox(height: 28)),
            SliverToBoxAdapter(child: _buildBrightnessCard()),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildColorCard()),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
            SliverToBoxAdapter(child: _buildScenesSection()),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildStatsRow()),
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
              Text('Living Room', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Smart Light', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _isOn ? AppColors.accentDim : AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _isOn ? AppColors.accentLight.withOpacity(0.4) : Colors.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8,
                      decoration: BoxDecoration(color: _isOn ? AppColors.success : AppColors.textDim, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(_isOn ? 'ON' : 'OFF',
                      style: TextStyle(color: _isOn ? AppColors.accentLight : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: _isOn,
                onChanged: _toggleLight,
                activeColor: AppColors.accentLight,
                activeTrackColor: AppColors.accentDim,
                inactiveThumbColor: Colors.white30,
                inactiveTrackColor: Colors.white10,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (details) {
                if (!_isOn) return;
                final center = Offset(120, 120);
                final pos = details.localPosition;
                final angle = atan2(pos.dy - center.dy, pos.dx - center.dx);
                final norm = (angle - pi / 2) / (2 * pi);
                final newBrightness = (norm + 1) % 1;
                setState(() => _brightness = newBrightness);
                _publishBrightness(newBrightness);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240, height: 240,
                    child: CustomPaint(
                      painter: BrightnessRingPainter(
                        percentage: _isOn ? _brightness : 0,
                        accentColor: _isOn ? AppColors.accentLight : Colors.white24,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('BRIGHTNESS',
                        style: TextStyle(color: _isOn ? AppColors.textSecondary : AppColors.textDim, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isOn ? '${(_brightness * 100).round()}%' : 'OFF',
                        style: TextStyle(
                          color: _isOn ? Colors.white : AppColors.textSecondary,
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wb_sunny_rounded, color: _isOn ? AppColors.lightColor : Colors.white24, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            _isOn ? 'Active' : 'Standby',
                            style: TextStyle(color: _isOn ? AppColors.lightColor : AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(child: _ctrlBtn(Icons.power_settings_new_rounded, 'POWER', !_isOn, () => _toggleLight(!_isOn))),
                const SizedBox(width: 14),
                Expanded(child: _ctrlBtn(Icons.auto_awesome_rounded, 'AUTO', _isAuto, () => setState(() => _isAuto = !_isAuto))),
                const SizedBox(width: 14),
                Expanded(child: _ctrlBtn(Icons.timer_rounded, 'TIMER', false, null)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String label, bool isActive, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: isActive ? AppColors.accentDim : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: isActive ? AppColors.accentLight.withOpacity(0.3) : Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? AppColors.accentLight : Colors.white54, size: 26),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(color: isActive ? AppColors.accentLight : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    ),
  );

  Widget _buildColorCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.palette_rounded, color: AppColors.info, size: 18),
                SizedBox(width: 8),
                Text('Mood Lighting', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: GestureDetector(
                onPanUpdate: (details) {
                  if (!_isOn) return;
                  final center = const Offset(110, 110);
                  final pos = details.localPosition;
                  final angle = atan2(pos.dy - center.dy, pos.dx - center.dx);
                  final newColor = HSVColor.fromAHSV(1, (angle / (2 * pi) * 360 + 360) % 360, 0.8, 1).toColor();
                  setState(() { _colorWheelAngle = angle; _selectedColor = newColor; });
                  _publishColor(newColor);
                },
                child: SizedBox(
                  width: 220, height: 220,
                  child: CustomPaint(painter: ColorWheelPainter(thumbAngle: _colorWheelAngle)),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _colorPresets.map((p) => _colorChip(p)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorChip(_ColorPreset p) {
    final isSelected = _selectedColor.value == p.color.value;
    return GestureDetector(
      onTap: () { setState(() => _selectedColor = p.color); _publishColor(p.color); },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: p.color,
              shape: BoxShape.circle,
              border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
              boxShadow: isSelected ? [BoxShadow(color: p.color.withOpacity(0.6), blurRadius: 12, spreadRadius: 2)] : [],
            ),
          ),
          const SizedBox(height: 8),
          Text(p.name, style: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildScenesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Scenes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12, mainAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: _scenes.map((s) => _sceneCard(s)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _sceneCard(_Scene s) {
    final isSelected = _selectedScene == s.name;
    return GestureDetector(
      onTap: () => _applyScene(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isSelected ? s.color.withOpacity(0.5) : Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Icon(s.icon, color: isSelected ? s.color : Colors.white38, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(s.subtitle, style: TextStyle(color: isSelected ? s.color : AppColors.textDim, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _statCard(Icons.bolt_rounded, AppColors.lightColor, '${(_brightness * 15).round()}W', 'Power')),
          const SizedBox(width: 14),
          Expanded(child: _statCard(Icons.thermostat_rounded, AppColors.info, '2700K', 'Color Temp')),
          const SizedBox(width: 14),
          Expanded(child: _statCard(Icons.schedule_rounded, AppColors.climateColor, '4h 32m', 'On Time')),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    ),
  );
}

class _Scene {
  final String name, subtitle;
  final IconData icon;
  final Color color;
  const _Scene(this.name, this.subtitle, this.icon, this.color);
}

class _ColorPreset {
  final Color color;
  final String name;
  const _ColorPreset(this.color, this.name);
}
