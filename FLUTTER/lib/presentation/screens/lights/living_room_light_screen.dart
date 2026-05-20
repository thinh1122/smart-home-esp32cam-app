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

  // Timer
  Timer?    _countdownTimer;
  Duration  _remaining   = Duration.zero;
  bool      _timerActive = false;
  bool      _timerTurnOn = false; // false = hẹn tắt, true = hẹn bật

  @override
  void dispose() {
    _brightnessDebounce?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _toggleLight(bool v) {
    setState(() => _isOn = v);
    MQTTService().controlLight(widget.room, v);
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
  void _startTimer(Duration duration, bool turnOn) {
    _countdownTimer?.cancel();
    setState(() {
      _remaining   = duration;
      _timerActive = true;
      _timerTurnOn = turnOn;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final next = _remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        t.cancel();
        final action = turnOn ? true : false;
        _toggleLight(action);
        setState(() { _timerActive = false; _remaining = Duration.zero; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(turnOn ? 'Đèn đã bật theo hẹn giờ' : 'Đèn đã tắt theo hẹn giờ'),
          backgroundColor: turnOn ? Colors.green : Colors.blueGrey,
        ));
      } else {
        setState(() => _remaining = next);
      }
    });
  }

  void _cancelTimer() {
    _countdownTimer?.cancel();
    setState(() { _timerActive = false; _remaining = Duration.zero; });
  }

  void _showTimerPicker() {
    final options = [
      _TimerOption('15 phút', const Duration(minutes: 15), Icons.alarm_rounded),
      _TimerOption('30 phút', const Duration(minutes: 30), Icons.alarm_rounded),
      _TimerOption('1 giờ',   const Duration(hours: 1),    Icons.alarm_rounded),
      _TimerOption('2 giờ',   const Duration(hours: 2),    Icons.alarm_rounded),
      _TimerOption('4 giờ',   const Duration(hours: 4),    Icons.alarm_rounded),
      _TimerOption('8 giờ',   const Duration(hours: 8),    Icons.alarm_rounded),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TimerPickerSheet(
        currentlyOn: _isOn,
        onSelected: (duration, turnOn) {
          Navigator.pop(ctx);
          _startTimer(duration, turnOn);
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
                  _showTimerPicker,
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
                  Text(_timerTurnOn ? 'Hẹn giờ bật đèn' : 'Hẹn giờ tắt đèn',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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
  final void Function(Duration, bool turnOn) onSelected;
  final List<_TimerOption> presets;
  final bool currentlyOn;
  const _TimerPickerSheet({required this.onSelected, required this.presets, required this.currentlyOn});

  @override
  State<_TimerPickerSheet> createState() => _TimerPickerSheetState();
}

class _TimerPickerSheetState extends State<_TimerPickerSheet> {
  late bool _turnOn;
  // 0 = Nhanh, 1 = Đếm ngược, 2 = Giờ cụ thể
  int _tab = 0;

  // Tab đếm ngược
  int _cdHour = 0;
  int _cdMin  = 30;

  // Tab giờ cụ thể
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;
  int _targetHour = 0;
  int _targetMin  = 0;

  @override
  void initState() {
    super.initState();
    _turnOn = !widget.currentlyOn;
    final now = DateTime.now();
    _targetHour = now.hour;
    _targetMin  = now.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _targetHour);
    _minCtrl  = FixedExtentScrollController(initialItem: _targetMin);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  // Tính duration từ giờ cụ thể đến hiện tại
  Duration _durationUntil(int h, int m) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, h, m);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }

  void _confirm(Duration d) => widget.onSelected(d, _turnOn);

  @override
  Widget build(BuildContext context) {
    final accentColor = _turnOn ? AppColors.accentLight : Colors.blueGrey.shade300;
    final accentDim   = _turnOn ? AppColors.accentDim   : Colors.blueGrey.withOpacity(0.3);

    return Padding(
      padding: EdgeInsets.only(
        left: 0, right: 0, top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: accentDim, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.timer_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_turnOn ? 'Hẹn giờ bật đèn' : 'Hẹn giờ tắt đèn',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(_turnOn ? 'Đèn tự bật đúng giờ bạn chọn' : 'Đèn tự tắt đúng giờ bạn chọn',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bật / Tắt toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _modeBtn('Hẹn tắt', Icons.power_off_rounded, !_turnOn,
                      Colors.blueGrey.shade300, () => setState(() => _turnOn = false)),
                  _modeBtn('Hẹn bật', Icons.power_rounded, _turnOn,
                      AppColors.accentLight, () => setState(() => _turnOn = true)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tab selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _tabBtn('Nhanh',      Icons.bolt_rounded,         0, accentColor),
                  _tabBtn('Đếm ngược', Icons.hourglass_top_rounded, 1, accentColor),
                  _tabBtn('Giờ cụ thể', Icons.schedule_rounded,     2, accentColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Tab content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: _tab == 0 ? _buildQuickTab(accentColor, accentDim)
                   : _tab == 1 ? _buildCountdownTab(accentColor, accentDim)
                   :             _buildTargetTimeTab(accentColor, accentDim),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Quick presets tab ──
  Widget _buildQuickTab(Color accent, Color dim) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: widget.presets.map((o) => Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _confirm(o.duration),
                child: Container(
                  decoration: BoxDecoration(
                    color: dim.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withOpacity(0.25)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(o.icon, color: accent, size: 18),
                      const SizedBox(height: 6),
                      Text(o.label,
                          style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── Countdown tab ──
  Widget _buildCountdownTab(Color accent, Color dim) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(child: _spinnerCol('Giờ', _cdHour, 23,
                    (v) => setState(() => _cdHour = v), accent)),
                Text(':', style: TextStyle(color: accent, fontSize: 36, fontWeight: FontWeight.bold)),
                Expanded(child: _spinnerCol('Phút', _cdMin, 59,
                    (v) => setState(() => _cdMin = v), accent)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _confirmBtn(
            label: '${_turnOn ? 'Bật' : 'Tắt'} sau ${_cdHour}h ${_cdMin.toString().padLeft(2,'0')}m',
            enabled: _cdHour > 0 || _cdMin > 0,
            accent: accent, dim: dim,
            onTap: () => _confirm(Duration(hours: _cdHour, minutes: _cdMin)),
          ),
        ],
      ),
    );
  }

  // ── Target time tab ──
  Widget _buildTargetTimeTab(Color accent, Color dim) {
    final dur = _durationUntil(_targetHour, _targetMin);
    final durText = dur.inHours > 0
        ? 'sau ${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
        : 'sau ${dur.inMinutes}m';
    final isNextDay = dur.inHours >= 22;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(child: _wheelCol('Giờ', _hourCtrl, 24,
                    (v) => setState(() => _targetHour = v), accent)),
                Text(':', style: TextStyle(color: accent, fontSize: 40, fontWeight: FontWeight.bold)),
                Expanded(child: _wheelCol('Phút', _minCtrl, 60,
                    (v) => setState(() => _targetMin = v), accent)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Info chip
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, color: accent.withOpacity(0.6), size: 14),
              const SizedBox(width: 6),
              Text(
                isNextDay
                  ? 'Hẹn lúc ${_targetHour.toString().padLeft(2,'0')}:${_targetMin.toString().padLeft(2,'0')} ngày mai ($durText)'
                  : 'Hẹn lúc ${_targetHour.toString().padLeft(2,'0')}:${_targetMin.toString().padLeft(2,'0')} hôm nay ($durText)',
                style: TextStyle(color: accent.withOpacity(0.8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _confirmBtn(
            label: '${_turnOn ? 'Bật' : 'Tắt'} lúc ${_targetHour.toString().padLeft(2,'0')}:${_targetMin.toString().padLeft(2,'0')}',
            enabled: true,
            accent: accent, dim: dim,
            onTap: () => _confirm(dur),
          ),
        ],
      ),
    );
  }

  Widget _spinnerCol(String label, int value, int max, ValueChanged<int> onChange, Color accent) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _numBtn(Icons.remove_rounded, () { if (value > 0) onChange(value - 1); }),
            const SizedBox(width: 14),
            SizedBox(
              width: 48,
              child: Text(value.toString().padLeft(2,'0'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accent, fontSize: 34, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 14),
            _numBtn(Icons.add_rounded, () { if (value < max) onChange(value + 1); }),
          ],
        ),
      ],
    );
  }

  Widget _wheelCol(String label, FixedExtentScrollController ctrl, int count, ValueChanged<int> onChange, Color accent) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 4),
        SizedBox(
          height: 150,
          child: ListWheelScrollView.useDelegate(
            controller: ctrl,
            itemExtent: 50,
            physics: const FixedExtentScrollPhysics(),
            perspective: 0.003,
            overAndUnderCenterOpacity: 0.3,
            onSelectedItemChanged: onChange,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count,
              builder: (ctx, i) => Center(
                child: Text(i.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: accent,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeBtn(String label, IconData icon, bool active, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color.withOpacity(0.5) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? color : Colors.white38, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: active ? color : Colors.white38,
                fontWeight: FontWeight.bold, fontSize: 13,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(String label, IconData icon, int idx, Color accent) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? accent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? accent : Colors.white38, size: 16),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                color: active ? accent : Colors.white38,
                fontSize: 10, fontWeight: FontWeight.bold,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmBtn({
    required String label,
    required bool enabled,
    required Color accent,
    required Color dim,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent.withOpacity(0.2),
          foregroundColor: accent,
          disabledBackgroundColor: Colors.white10,
          disabledForegroundColor: Colors.white30,
          padding: const EdgeInsets.symmetric(vertical: 15),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: enabled ? accent.withOpacity(0.4) : Colors.transparent),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _numBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white70, size: 18),
    ),
  );
}
