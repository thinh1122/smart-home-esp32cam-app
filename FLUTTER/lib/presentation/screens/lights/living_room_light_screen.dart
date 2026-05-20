import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/mqtt_service.dart';
import '../../widgets/painters/brightness_ring_painter.dart';

class LivingRoomLightScreen extends StatefulWidget {
  final String room;
  const LivingRoomLightScreen({super.key, this.room = 'living_room'});

  @override
  State<LivingRoomLightScreen> createState() => _LivingRoomLightScreenState();
}

class _LivingRoomLightScreenState extends State<LivingRoomLightScreen> {
  bool   _isOn       = false;
  double _brightness = 0.82;
  Timer? _brightnessDebounce;

  // Timer tắt đèn
  Timer?    _countdownTimer;
  Duration? _timerDuration;
  Duration  _remaining = Duration.zero;
  bool      _timerActive = false;

  @override
  void dispose() {
    _brightnessDebounce?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _toggleLight(bool v) {
    setState(() => _isOn = v);
    MQTTService().controlLight(widget.room, v);
    if (!v) _cancelTimer();
  }

  void _publishBrightness(double value) {
    _brightnessDebounce?.cancel();
    _brightnessDebounce = Timer(const Duration(milliseconds: 300), () {
      MQTTService().publish('home/devices/light/${widget.room}/brightness', {
        'brightness': (value * 100).round(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  // ── Timer logic ──────────────────────────────────────────────
  void _startTimer(Duration duration) {
    _countdownTimer?.cancel();
    setState(() {
      _timerDuration = duration;
      _remaining     = duration;
      _timerActive   = true;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final newRemaining = _remaining - const Duration(seconds: 1);
      if (newRemaining <= Duration.zero) {
        t.cancel();
        _toggleLight(false);
        setState(() { _timerActive = false; _remaining = Duration.zero; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đèn đã tắt theo hẹn giờ'),
          backgroundColor: Colors.blueGrey,
        ));
      } else {
        setState(() => _remaining = newRemaining);
      }
    });
  }

  void _cancelTimer() {
    _countdownTimer?.cancel();
    setState(() { _timerActive = false; _remaining = Duration.zero; _timerDuration = null; });
  }

  void _showTimerPicker() {
    final options = [
      _TimerOption('15 phút',  const Duration(minutes: 15),  Icons.alarm_rounded),
      _TimerOption('30 phút',  const Duration(minutes: 30),  Icons.alarm_rounded),
      _TimerOption('1 giờ',    const Duration(hours: 1),     Icons.alarm_rounded),
      _TimerOption('2 giờ',    const Duration(hours: 2),     Icons.alarm_rounded),
      _TimerOption('4 giờ',    const Duration(hours: 4),     Icons.alarm_rounded),
      _TimerOption('8 giờ',    const Duration(hours: 8),     Icons.alarm_rounded),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TimerPickerSheet(
        onSelected: (duration) {
          Navigator.pop(ctx);
          _startTimer(duration);
        },
        presets: options,
      ),
    );
  }

  String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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
            if (_timerActive) ...[
              SliverToBoxAdapter(child: _buildTimerCard()),
              SliverToBoxAdapter(child: const SizedBox(height: 20)),
            ],
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
          Row(
            children: [
              if (Navigator.canPop(context))
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_roomLabel(widget.room),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text('Điều khiển đèn',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
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
                      decoration: BoxDecoration(
                          color: _isOn ? AppColors.success : AppColors.textDim,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(_isOn ? 'ON' : 'OFF',
                      style: TextStyle(
                          color: _isOn ? AppColors.accentLight : AppColors.textSecondary,
                          fontSize: 12, fontWeight: FontWeight.bold),
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
                const center = Offset(120, 120);
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
                        style: TextStyle(
                            color: _isOn ? AppColors.textSecondary : AppColors.textDim,
                            fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isOn ? '${(_brightness * 100).round()}%' : 'OFF',
                        style: TextStyle(
                          color: _isOn ? Colors.white : AppColors.textSecondary,
                          fontSize: 52, fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wb_sunny_rounded,
                              color: _isOn ? AppColors.lightColor : Colors.white24, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            _isOn ? 'Đang bật' : 'Đang tắt',
                            style: TextStyle(
                                color: _isOn ? AppColors.lightColor : AppColors.textDim,
                                fontSize: 13, fontWeight: FontWeight.w600),
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
                Expanded(child: _ctrlBtn(
                  Icons.power_settings_new_rounded, 'BẬT/TẮT', !_isOn,
                  () => _toggleLight(!_isOn),
                )),
                const SizedBox(width: 14),
                Expanded(child: _ctrlBtn(
                  Icons.timer_rounded, 'HẸN GIỜ', _timerActive,
                  _isOn ? _showTimerPicker : null,
                )),
                const SizedBox(width: 14),
                Expanded(child: _ctrlBtn(
                  Icons.brightness_auto_rounded, '100%', false,
                  _isOn ? () {
                    setState(() => _brightness = 1.0);
                    _publishBrightness(1.0);
                  } : null,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.accentDim.withOpacity(0.3),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.accentLight.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.timer_rounded, color: AppColors.accentLight, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hẹn giờ tắt đèn',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Còn lại: ${_formatRemaining(_remaining)}',
                    style: const TextStyle(color: AppColors.accentLight, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _cancelTimer,
              icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 28),
              tooltip: 'Huỷ hẹn giờ',
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String label, bool isActive, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accentDim : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
                color: isActive ? AppColors.accentLight.withOpacity(0.3) : Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isActive ? AppColors.accentLight : Colors.white54, size: 26),
              const SizedBox(height: 10),
              Text(label,
                  style: TextStyle(
                      color: isActive ? AppColors.accentLight : Colors.white38,
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  String _roomLabel(String key) {
    const map = {
      'living_room': 'Phòng khách', 'bedroom': 'Phòng ngủ',
      'kitchen': 'Nhà bếp', 'bathroom': 'Nhà vệ sinh',
      'bedroom2': 'Phòng ngủ 2', 'garage': 'Nhà xe',
    };
    return map[key] ?? key;
  }
}

class _TimerOption {
  final String label;
  final Duration duration;
  final IconData icon;
  const _TimerOption(this.label, this.duration, this.icon);
}

class _TimerPickerSheet extends StatefulWidget {
  final void Function(Duration) onSelected;
  final List<_TimerOption> presets;
  const _TimerPickerSheet({required this.onSelected, required this.presets});

  @override
  State<_TimerPickerSheet> createState() => _TimerPickerSheetState();
}

class _TimerPickerSheetState extends State<_TimerPickerSheet> {
  bool _showCustom = false;
  int _customHour = 0;
  int _customMin  = 30;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Hẹn giờ tắt đèn',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Đèn sẽ tự động tắt sau thời gian chọn',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),

            // Preset options
            ...widget.presets.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => widget.onSelected(o.duration),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accentDim.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accentLight.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(o.icon, color: AppColors.accentLight, size: 20),
                        const SizedBox(width: 14),
                        Text(o.label,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            )),

            // Custom time option
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _showCustom = !_showCustom),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: _showCustom ? AppColors.accentDim.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _showCustom ? AppColors.accentLight.withOpacity(0.4) : Colors.white12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          color: _showCustom ? AppColors.accentLight : Colors.white54, size: 20),
                      const SizedBox(width: 14),
                      Text('Tuỳ chỉnh thời gian',
                          style: TextStyle(
                            color: _showCustom ? Colors.white : Colors.white70,
                            fontSize: 15, fontWeight: FontWeight.w600,
                          )),
                      const Spacer(),
                      Icon(_showCustom ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: AppColors.textSecondary, size: 20),
                    ],
                  ),
                ),
              ),
            ),

            if (_showCustom) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Giờ
                        Expanded(
                          child: Column(
                            children: [
                              const Text('Giờ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _numBtn(Icons.remove_rounded, () {
                                    if (_customHour > 0) setState(() => _customHour--);
                                  }),
                                  const SizedBox(width: 16),
                                  Text('$_customHour',
                                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 16),
                                  _numBtn(Icons.add_rounded, () {
                                    if (_customHour < 23) setState(() => _customHour++);
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Text(':', style: TextStyle(color: Colors.white54, fontSize: 28, fontWeight: FontWeight.bold)),
                        // Phút
                        Expanded(
                          child: Column(
                            children: [
                              const Text('Phút', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _numBtn(Icons.remove_rounded, () {
                                    if (_customMin > 0) setState(() => _customMin--);
                                  }),
                                  const SizedBox(width: 16),
                                  Text('${_customMin.toString().padLeft(2, '0')}',
                                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 16),
                                  _numBtn(Icons.add_rounded, () {
                                    if (_customMin < 59) setState(() => _customMin++);
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_customHour == 0 && _customMin == 0) ? null : () {
                          final duration = Duration(hours: _customHour, minutes: _customMin);
                          widget.onSelected(duration);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentDim,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          'Đặt hẹn giờ ${_customHour}h ${_customMin.toString().padLeft(2,'0')}m',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white70, size: 18),
    ),
  );
}
